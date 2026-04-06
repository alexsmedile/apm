#!/usr/bin/env bash
# test_runtime.sh — integration tests for install, remove, diff
# Follows SPEC_RUNTIME.md rules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

source "$SCRIPT_DIR/helpers/test_helpers.sh"

# Isolate apm config/lock/state from the real HOME so tests work in any environment.
_APM_TEST_CONFIG_DIR=$(mktemp -d)
export APM_CONFIG_DIR="$_APM_TEST_CONFIG_DIR"
trap 'rm -rf "$_APM_TEST_CONFIG_DIR"' EXIT

ERRORS=0

run_test() {
    local name="$1"
    shift
    if "$@" 2>/dev/null; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Runtime Tests (install / remove / diff) ==="

# --- generate-runtime ---

test_generate_runtime_content() {
    local out
    out=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" generate-runtime \
        --id git-mentor \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    # Must contain apm.id
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['content']
assert 'apm:' in c, 'missing apm block'
assert \"id: git-mentor\" in c, 'missing apm.id'
assert 'platform: claude-code' in c, 'missing apm.platform'
assert 'installed-from:' in c, 'missing installed-from'
assert 'installed-at:' in c, 'missing installed-at'
"
}
run_test "generate-runtime: produces runtime file contract fields" test_generate_runtime_content

test_generate_runtime_uses_latest() {
    local out
    out=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" generate-runtime \
        --id git-mentor \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    # Body should use @latest.md content (not root body)
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['content']
assert 'commit message quality' in c, 'body should be from @latest.md'
"
}
run_test "generate-runtime: uses @latest.md as active body" test_generate_runtime_uses_latest

test_generate_runtime_platform_specific_body() {
    # Set up a tmpdb with a platform-specific instruction file for claude-code
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    mkdir -p "$tmpdb/git-mentor/instructions"
    echo "This is the claude-code specific body." > "$tmpdb/git-mentor/instructions/git-mentor.cc@latest.md"

    local out
    out=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" generate-runtime \
        --id git-mentor \
        --db "$tmpdb" \
        --platform claude-code)
    rm -rf "$tmpdb"
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['content']
assert 'claude-code specific body' in c, 'platform-specific body not used'
assert 'commit message quality' not in c, 'generic body should not be used when platform-specific exists'
"
}
run_test "generate-runtime: platform-specific body takes priority over @latest.md" test_generate_runtime_platform_specific_body

test_generate_runtime_tools_sorted() {
    local out
    out=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" generate-runtime \
        --id git-mentor \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    # tools list should be sorted: Bash, Glob, Read, Write
    echo "$out" | python3 -c "
import json,sys,re
d=json.load(sys.stdin)
c=d['content']
# Extract tools section
import yaml
lines=c.split('---\n')
fm=yaml.safe_load(lines[1])
tools=fm['tools']
assert tools == sorted(tools), f'tools not sorted: {tools}'
"
}
run_test "generate-runtime: tools list is sorted" test_generate_runtime_tools_sorted

test_generate_runtime_no_deploy_fails() {
    python3 "$PROJECT_ROOT/lib/py/apm_python.py" generate-runtime \
        --id git-mentor \
        --db "$FIXTURES/library-basic" \
        --platform cursor > /dev/null 2>&1
    local exit_code=$?
    [ $exit_code -ne 0 ]
}
run_test "generate-runtime: no deploy config exits non-zero" test_generate_runtime_no_deploy_fails

# --- install ---

test_install_creates_file() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local result=$?
    local exists=0
    [ -f "$tmprt/git-mentor.md" ] && exists=1
    rm -rf "$tmprt"
    [ $result -eq 0 ] && [ $exists -eq 1 ]
}
run_test "install: creates runtime file" test_install_creates_file

test_install_runtime_contract() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local result
    # Check runtime file has apm.id
    result=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" parse-runtime "$tmprt/git-mentor.md")
    local ok=0
    echo "$result" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('managed') == True, 'not managed'
assert d.get('apm_id') == 'git-mentor', f'wrong id: {d.get(\"apm_id\")}'
" 2>/dev/null && ok=1
    rm -rf "$tmprt"
    [ $ok -eq 1 ]
}
run_test "install: runtime file has apm.id (managed)" test_install_runtime_contract

test_install_dry_run_no_file() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run install git-mentor > /dev/null 2>&1
    local missing=0
    [ ! -f "$tmprt/git-mentor.md" ] && missing=1
    rm -rf "$tmprt"
    [ $missing -eq 1 ]
}
run_test "install: --dry-run does not write file" test_install_dry_run_no_file

# --- diff ---

test_diff_after_install_in_sync() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local diff_exit
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code diff git-mentor > /dev/null 2>&1
    diff_exit=$?
    rm -rf "$tmprt"
    [ $diff_exit -eq 0 ]
}
run_test "diff: exits 0 when in-sync after install" test_diff_after_install_in_sync

test_diff_not_installed_exits_1() {
    local tmprt
    tmprt=$(mktemp -d)
    local diff_exit
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code diff git-mentor > /dev/null 2>&1
    diff_exit=$?
    rm -rf "$tmprt"
    [ $diff_exit -eq 1 ]
}
run_test "diff: exits 1 when not installed" test_diff_not_installed_exits_1

test_diff_managed_runtime_outdated() {
    # runtime-managed fixture has truncated description vs library — should be outdated
    local diff_exit
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-managed")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code diff git-mentor > /dev/null 2>&1
    diff_exit=$?
    # description differs → exit 1
    [ $diff_exit -eq 1 ]
}
run_test "diff: managed runtime with changed description is outdated" test_diff_managed_runtime_outdated

# --- remove ---

test_remove_deletes_runtime() {
    local tmprt
    tmprt=$(mktemp -d)
    # Install first
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    # Remove
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force remove git-mentor > /dev/null 2>&1
    local gone=0
    [ ! -f "$tmprt/git-mentor.md" ] && gone=1
    rm -rf "$tmprt"
    [ $gone -eq 1 ]
}
run_test "remove: removes runtime file" test_remove_deletes_runtime

test_remove_preserves_library() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force remove git-mentor > /dev/null 2>&1
    local lib_ok=0
    [ -f "$FIXTURES/library-basic/git-mentor/git-mentor.md" ] && lib_ok=1
    rm -rf "$tmprt"
    [ $lib_ok -eq 1 ]
}
run_test "remove: canonical library file is untouched" test_remove_preserves_library

test_remove_dry_run_keeps_file() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run remove git-mentor > /dev/null 2>&1
    local still_there=0
    [ -f "$tmprt/git-mentor.md" ] && still_there=1
    rm -rf "$tmprt"
    [ $still_there -eq 1 ]
}
run_test "remove: --dry-run keeps runtime file" test_remove_dry_run_keeps_file

# --- state engine ---

test_status_shows_in_sync() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local out
    out=$(AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --json status 2>/dev/null)
    local in_sync_count
    in_sync_count=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(sum(1 for a in d.get('agents',[]) if a.get('state',{}).get('sync')=='in-sync'))
" 2>/dev/null)
    rm -rf "$tmprt"
    [ "$in_sync_count" = "1" ]
}
run_test "status: shows in-sync after install" test_status_shows_in_sync

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS runtime test(s) failed"
    exit 1
else
    echo "PASSED: all runtime tests"
fi
