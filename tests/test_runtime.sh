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

test_install_project_dir_creates_project_runtime_file() {
    local project_root base_dir
    base_dir=$(mktemp -d)
    project_root="$base_dir/project-alpha"

    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --project-dir "$project_root" install git-mentor > /dev/null 2>&1
    local result=$?
    local exists=0
    [ -f "$project_root/.claude/agents/git-mentor.md" ] && exists=1
    rm -rf "$base_dir"
    [ $result -eq 0 ] && [ $exists -eq 1 ]
}
run_test "install: --project-dir writes into the target project runtime" test_install_project_dir_creates_project_runtime_file

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
run_test "diff: exits 0 when installed after install" test_diff_after_install_in_sync

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

# --- skills runtime ---

test_skill_install_creates_symlink() {
    local tmphome
    tmphome=$(mktemp -d)
    HOME="$tmphome" \
        SKILLS_DB="$(realpath "$FIXTURES/skills-basic")" \
        bash "$PROJECT_ROOT/apm" --mode skills --platform claude-code install browser-use > /dev/null 2>&1
    local result=$?
    local target="$tmphome/.claude/skills/browser-use"
    local ok=0
    [ -L "$target" ] && [ "$(readlink "$target")" = "$(realpath "$FIXTURES/skills-basic/browser-use")" ] && ok=1
    rm -rf "$tmphome"
    [ $result -eq 0 ] && [ $ok -eq 1 ]
}
run_test "skills install: creates runtime symlink for supported platform" test_skill_install_creates_symlink

test_skill_status_reports_linked() {
    local tmphome out state
    tmphome=$(mktemp -d)
    HOME="$tmphome" \
        SKILLS_DB="$(realpath "$FIXTURES/skills-basic")" \
        bash "$PROJECT_ROOT/apm" --mode skills --platform claude-code install browser-use > /dev/null 2>&1
    out=$(HOME="$tmphome" \
        SKILLS_DB="$(realpath "$FIXTURES/skills-basic")" \
        bash "$PROJECT_ROOT/apm" --mode skills --platform claude-code --json status 2>/dev/null)
    state=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get('skills', []):
    if s.get('id') == 'browser-use':
        print(s.get('state', {}).get('sync', ''))
        break
" 2>/dev/null)
    rm -rf "$tmphome"
    [ "$state" = "linked" ]
}
run_test "skills status: reports linked after install" test_skill_status_reports_linked

test_skill_remove_deletes_symlink() {
    local tmphome target
    tmphome=$(mktemp -d)
    target="$tmphome/.claude/skills/browser-use"
    HOME="$tmphome" \
        SKILLS_DB="$(realpath "$FIXTURES/skills-basic")" \
        bash "$PROJECT_ROOT/apm" --mode skills --platform claude-code install browser-use > /dev/null 2>&1
    HOME="$tmphome" \
        SKILLS_DB="$(realpath "$FIXTURES/skills-basic")" \
        bash "$PROJECT_ROOT/apm" --mode skills --platform claude-code --force remove browser-use > /dev/null 2>&1
    local removed=0
    [ ! -e "$target" ] && [ ! -L "$target" ] && removed=1
    rm -rf "$tmphome"
    [ $removed -eq 1 ]
}
run_test "skills remove: removes runtime symlink" test_skill_remove_deletes_symlink

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
print(sum(1 for a in d.get('agents',[]) if a.get('state',{}).get('sync')=='installed'))
" 2>/dev/null)
    rm -rf "$tmprt"
    [ "$in_sync_count" = "1" ]
}
run_test "status: shows installed after install" test_status_shows_in_sync

test_status_symlink_install_mode_not_linked_outdated() {
    local tmprt tmpagents out state
    tmprt=$(mktemp -d)
    tmpagents=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        AGENTS_DIR="$tmpagents" \
        INSTALL_MODE="symlink" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    out=$(AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        AGENTS_DIR="$tmpagents" \
        INSTALL_MODE="symlink" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --json status 2>/dev/null)
    state=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('agents', []):
    if a.get('id') == 'git-mentor':
        print(a.get('state', {}).get('sync', ''))
        break
" 2>/dev/null)
    rm -rf "$tmprt" "$tmpagents"
    [ "$state" = "installed" ]
}
run_test "status: symlink install mode remains installed" test_status_symlink_install_mode_not_linked_outdated

test_status_direct_link_reports_linked_then_linked_outdated() {
    local tmprt tmpdb out state linked_path
    tmprt=$(mktemp -d)
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor > /dev/null 2>&1
    out=$(AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --json status 2>/dev/null)
    state=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('agents', []):
    if a.get('id') == 'git-mentor':
        print(a.get('state', {}).get('sync', ''))
        break
" 2>/dev/null)
    [ "$state" = "linked" ] || { rm -rf "$tmprt"; return 1; }

    linked_path="$tmprt/git-mentor.md"
    rm -f "$linked_path"
    ln -s "$tmpdb/git-mentor/git-mentor.md" "$linked_path"

    out=$(AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --json status 2>/dev/null)
    state=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('agents', []):
    if a.get('id') == 'git-mentor':
        print(a.get('state', {}).get('sync', ''))
        break
" 2>/dev/null)
    rm -rf "$tmprt" "$tmpdb"
    [ "$state" = "outdated" ]
}
run_test "status: direct links report linked and outdated correctly" test_status_direct_link_reports_linked_then_linked_outdated

test_alias_link_is_accounted_for_not_unmanaged() {
    local tmprt tmpdb out state unmanaged_count
    tmprt=$(mktemp -d)
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor --as mentor > /dev/null 2>&1
    out=$(AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --json status 2>/dev/null)
    state=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('agents', []):
    if a.get('id') == 'git-mentor':
        print(a.get('state', {}).get('sync', ''))
        break
" 2>/dev/null)
    unmanaged_count=$(echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(sum(1 for a in d.get('agents', [])
          if a.get('state', {}).get('sync') == 'unmanaged' and a.get('id') == 'mentor'))
" 2>/dev/null)
    rm -rf "$tmprt" "$tmpdb"
    [ "$state" = "linked" ] && [ "$unmanaged_count" = "0" ]
}
run_test "status: alias links are tracked and not shown as unmanaged" test_alias_link_is_accounted_for_not_unmanaged

test_unlink_current_scope_only_removes_matching_link() {
    local global_rt project_root project_rt tmpdb links_json
    global_rt=$(mktemp -d)
    project_root=$(mktemp -d)
    project_rt="$project_root/.claude/agents"
    tmpdb=$(mktemp -d)
    mkdir -p "$project_rt"
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"

    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$global_rt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor --global --as global-mentor > /dev/null 2>&1

    (
        cd "$project_root" || exit 1
        AGENTS_DB="$tmpdb" \
            CLAUDE_AGENTS="$global_rt" \
            bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor > /dev/null 2>&1
    ) || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }

    (
        cd "$project_root" || exit 1
        AGENTS_DB="$tmpdb" \
            CLAUDE_AGENTS="$global_rt" \
            APM_FORCE=1 \
            bash "$PROJECT_ROOT/apm" --platform claude-code unlink git-mentor > /dev/null 2>&1
    ) || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }

    [ ! -L "$project_rt/git-mentor.md" ] || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }
    [ -L "$global_rt/global-mentor.md" ] || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }

    links_json=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" read-links \
        --id git-mentor \
        --db "$tmpdb")
    rm -rf "$global_rt" "$project_root" "$tmpdb"
    echo "$links_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
links=d.get('links', [])
assert len(links) == 1, links
assert links[0]['scope'] == 'global', links
assert links[0]['alias'] == 'global-mentor', links
" 2>/dev/null
}
run_test "unlink: plain unlink removes only the current-scope link" test_unlink_current_scope_only_removes_matching_link

test_unlink_without_matching_scope_fails_when_multiple_links_exist() {
    local global_rt project_root project_rt tmpdb status
    global_rt=$(mktemp -d)
    project_root=$(mktemp -d)
    project_rt="$project_root/.claude/agents"
    tmpdb=$(mktemp -d)
    mkdir -p "$project_rt"
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"

    (
        cd "$project_root" || exit 1
        AGENTS_DB="$tmpdb" \
            CLAUDE_AGENTS="$global_rt" \
            bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor > /dev/null 2>&1
        AGENTS_DB="$tmpdb" \
            CLAUDE_AGENTS="$global_rt" \
            bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor --as mentor-alias > /dev/null 2>&1
    ) || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }

    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$global_rt" \
        APM_FORCE=1 \
        bash "$PROJECT_ROOT/apm" --platform claude-code unlink git-mentor > /dev/null 2>&1
    status=$?

    [ -L "$project_rt/git-mentor.md" ] || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }
    [ -L "$project_rt/mentor-alias.md" ] || { rm -rf "$global_rt" "$project_root" "$tmpdb"; return 1; }
    rm -rf "$global_rt" "$project_root" "$tmpdb"
    [ "$status" -ne 0 ]
}
run_test "unlink: plain unlink fails when current scope has no match and multiple links exist" test_unlink_without_matching_scope_fails_when_multiple_links_exist

test_link_bookkeeping_handles_apostrophe_in_runtime_path() {
    local tmpbase tmprt tmpdb out
    tmpbase=$(mktemp -d)
    tmprt="$tmpbase/runtime's"
    tmpdb=$(mktemp -d)
    mkdir -p "$tmprt"
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code link git-mentor --as mentor > /dev/null 2>&1
    out=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" read-links \
        --id git-mentor \
        --db "$tmpdb")
    rm -rf "$tmpbase" "$tmpdb"
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
links=d.get('links', [])
assert len(links) == 1, links
assert links[0]['path'].endswith(\"runtime's/mentor.md\"), links
" 2>/dev/null
}
run_test "link: bookkeeping handles apostrophes in runtime paths" test_link_bookkeeping_handles_apostrophe_in_runtime_path

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS runtime test(s) failed"
    exit 1
else
    echo "PASSED: all runtime tests"
fi
