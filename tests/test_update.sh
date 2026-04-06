#!/usr/bin/env bash
# test_update.sh — tests for apm update and apm interactive (non-interactive path)

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
    local name="$1"; shift
    if "$@" 2>/dev/null; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Update + Interactive Tests ==="

# ---------------------------------------------------------------------------
# Helpers: build a tmpdb with one agent installed (in-sync) and one outdated
# ---------------------------------------------------------------------------

# Sets up: tmpdb (library-basic), tmprt with all agents installed (in-sync).
# Caller must rm -rf both dirs.
_setup_insync() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install reviewer > /dev/null 2>&1
    echo "$tmpdb $tmprt"
}

# Sets up: tmpdb (library-basic), tmprt with a manually written outdated git-mentor.
# Outdated = installed but description differs from library.
_setup_outdated() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # Write a runtime file that has apm.id but stale description
    cat > "$tmprt/git-mentor.md" <<'EOF'
---
name: git-mentor
description: Old stale description.
model: claude-sonnet-4-6
tools: [Bash, Glob, Read, Write]
apm:
  id: git-mentor
  platform: claude-code
  installed-from: /fake/path
  installed-at: 2026-01-01T00:00:00Z
---
Old body content.
EOF
    echo "$tmpdb $tmprt"
}

# ---------------------------------------------------------------------------
# update: nothing to update when all in-sync
# ---------------------------------------------------------------------------

test_update_all_in_sync() {
    local dirs
    dirs=$(_setup_insync)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    local out
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force update 2>/dev/null)
    local ec=$?
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && echo "$out" | grep -q "in-sync"
}
run_test "update: reports all in-sync when nothing to update" test_update_all_in_sync

# ---------------------------------------------------------------------------
# update: reinstalls outdated agent
# ---------------------------------------------------------------------------

test_update_reinstalls_outdated() {
    local dirs
    dirs=$(_setup_outdated)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force update > /dev/null 2>&1
    local ec=$?

    # After update the runtime file should be managed (has valid apm.id)
    # and its description should no longer be the stale "Old stale description."
    local rt_desc
    rt_desc=$(python3 -c "
import sys, yaml, re
content = open('$tmprt/git-mentor.md').read()
fm = yaml.safe_load(re.match(r'^---\n(.*?)\n---', content, re.DOTALL).group(1))
print(fm.get('description',''))
" 2>/dev/null)

    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && [ "$rt_desc" != "Old stale description." ]
}
run_test "update: outdated agent is reinstalled with library content" test_update_reinstalls_outdated

# ---------------------------------------------------------------------------
# update: single agent by id
# ---------------------------------------------------------------------------

test_update_single_agent() {
    local dirs
    dirs=$(_setup_outdated)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force update git-mentor > /dev/null 2>&1
    local ec=$?

    # Runtime file should now be up to date
    local rt_apm_installed
    rt_apm_installed=$(python3 "$PROJECT_ROOT/lib/py/apm_python.py" parse-runtime \
        "$tmprt/git-mentor.md" 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin).get('managed'))" 2>/dev/null)

    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && [ "$rt_apm_installed" = "True" ]
}
run_test "update: single agent updated by id" test_update_single_agent

# ---------------------------------------------------------------------------
# update: single agent already in-sync exits 0 with message
# ---------------------------------------------------------------------------

test_update_single_already_insync() {
    local dirs
    dirs=$(_setup_insync)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    local out
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force update git-mentor 2>/dev/null)
    local ec=$?
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && echo "$out" | grep -q "in-sync"
}
run_test "update: single agent already in-sync exits 0" test_update_single_already_insync

# ---------------------------------------------------------------------------
# update: --dry-run writes nothing
# ---------------------------------------------------------------------------

test_update_dry_run() {
    local dirs
    dirs=$(_setup_outdated)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    local before_mtime
    before_mtime=$(stat -f "%m" "$tmprt/git-mentor.md" 2>/dev/null || stat -c "%Y" "$tmprt/git-mentor.md" 2>/dev/null)

    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run update > /dev/null 2>&1

    local after_mtime
    after_mtime=$(stat -f "%m" "$tmprt/git-mentor.md" 2>/dev/null || stat -c "%Y" "$tmprt/git-mentor.md" 2>/dev/null)

    rm -rf "$tmpdb" "$tmprt"
    [ "$before_mtime" = "$after_mtime" ]
}
run_test "update: --dry-run does not write files" test_update_dry_run

# ---------------------------------------------------------------------------
# update: nonexistent id exits 2
# ---------------------------------------------------------------------------

test_update_nonexistent_id() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"

    local ec
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code update no-such-agent > /dev/null 2>&1
    ec=$?
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 2 ]
}
run_test "update: nonexistent agent id exits 2" test_update_nonexistent_id

# ---------------------------------------------------------------------------
# update: declining confirmation does not write
# ---------------------------------------------------------------------------

test_update_decline_confirmation() {
    local dirs
    dirs=$(_setup_outdated)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"

    # Single-agent update so only git-mentor is targeted (avoids reviewer=ready noise)
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code update git-mentor <<< "n" > /dev/null 2>&1

    local after_desc
    after_desc=$(python3 -c "
import sys, yaml, re
content = open('$tmprt/git-mentor.md').read()
fm = yaml.safe_load(re.match(r'^---\n(.*?)\n---', content, re.DOTALL).group(1))
print(fm.get('description',''))
" 2>/dev/null)

    rm -rf "$tmpdb" "$tmprt"
    # Description should still be the stale one (not updated)
    [ "$after_desc" = "Old stale description." ]
}
run_test "update: declining confirmation does not update runtime" test_update_decline_confirmation

# ---------------------------------------------------------------------------
# link-existing: import of managed runtime reinstalls from library
# ---------------------------------------------------------------------------

test_import_link_existing_reinstalls() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # Use runtime-managed fixture: has apm.id, description "Use for git workflows."
    cp "$FIXTURES/runtime-managed/git-mentor.md" "$tmprt/"

    local before_desc
    before_desc=$(python3 -c "
import yaml, re
content = open('$tmprt/git-mentor.md').read()
fm = yaml.safe_load(re.match(r'^---\n(.*?)\n---', content, re.DOTALL).group(1))
print(fm.get('description',''))
" 2>/dev/null)

    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import git-mentor > /dev/null 2>&1
    local ec=$?

    # After link-existing, runtime should have been reinstalled (apm.installed-at updated)
    local after_installed_at
    after_installed_at=$(python3 -c "
import yaml, re
content = open('$tmprt/git-mentor.md').read()
fm = yaml.safe_load(re.match(r'^---\n(.*?)\n---', content, re.DOTALL).group(1))
print(fm.get('apm',{}).get('installed-at',''))
" 2>/dev/null)

    rm -rf "$tmpdb" "$tmprt"
    # Must succeed and installed-at must have been updated (not the fake 2026-04-01 value)
    [ $ec -eq 0 ] && [ "$after_installed_at" != "2026-04-01T12:00:00Z" ]
}
run_test "import link-existing: reinstalls library content to runtime" test_import_link_existing_reinstalls

# ---------------------------------------------------------------------------
# install --all
# ---------------------------------------------------------------------------

test_install_all_installs_ready() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # Neither agent is installed yet — both are "ready"
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force install --all > /dev/null 2>&1
    local ec=$?
    local count
    count=$(find "$tmprt" -name "*.md" | wc -l | tr -d ' ')
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && [ "$count" -ge 2 ]
}
run_test "install --all: installs all ready agents" test_install_all_installs_ready

test_install_all_dry_run_no_write() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run install --all > /dev/null 2>&1
    local count
    count=$(find "$tmprt" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmpdb" "$tmprt"
    [ "$count" = "0" ]
}
run_test "install --all: --dry-run writes nothing" test_install_all_dry_run_no_write

test_install_all_nothing_to_do() {
    local dirs
    dirs=$(_setup_insync)
    local tmpdb tmprt
    read -r tmpdb tmprt <<< "$dirs"
    local out
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force install --all 2>/dev/null)
    local ec=$?
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ] && echo "$out" | grep -q "in-sync\|already"
}
run_test "install --all: reports nothing to do when all in-sync" test_install_all_nothing_to_do

test_install_multiple_ids() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force install git-mentor reviewer > /dev/null 2>&1
    local count
    count=$(find "$tmprt" -name "*.md" | wc -l | tr -d ' ')
    rm -rf "$tmpdb" "$tmprt"
    [ "$count" -eq 2 ]
}
run_test "install: multiple IDs installs each agent" test_install_multiple_ids

test_install_cat() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # Inject category into both fixture agents
    sed -i.bak "s/^tags:/category: devtools\ntags:/" "$tmpdb/git-mentor/git-mentor.md"
    sed -i.bak "s/^tags:/category: devtools\ntags:/" "$tmpdb/reviewer/reviewer.md"
    AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force install --cat devtools > /dev/null 2>&1
    local count
    count=$(find "$tmprt" -name "*.md" | wc -l | tr -d ' ')
    rm -rf "$tmpdb" "$tmprt"
    [ "$count" -eq 2 ]
}
run_test "install --cat: installs all agents in category" test_install_cat

test_install_cat_unknown() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    local out
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install --cat nonexistent 2>&1)
    local count
    count=$(find "$tmprt" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmpdb" "$tmprt"
    [ "$count" -eq 0 ] && echo "$out" | grep -qi "no agents"
}
run_test "install --cat: unknown category installs nothing" test_install_cat_unknown

# ---------------------------------------------------------------------------
# interactive: non-interactive (piped) path prints dashboard and exits 0
# ---------------------------------------------------------------------------

test_interactive_noninteractive_exits_0() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"

    local out ec
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code <<< "" 2>/dev/null)
    ec=$?
    rm -rf "$tmpdb" "$tmprt"
    [ $ec -eq 0 ]
}
run_test "interactive: piped stdin exits 0 (non-interactive dashboard)" test_interactive_noninteractive_exits_0

test_interactive_shows_agent_counts() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"

    local out
    out=$(AGENTS_DB="$tmpdb" CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code <<< "" 2>/dev/null)
    rm -rf "$tmpdb" "$tmprt"
    echo "$out" | grep -qi "agents:"
}
run_test "interactive: dashboard shows agent summary line" test_interactive_shows_agent_counts

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS update/interactive test(s) failed"
    exit 1
else
    echo "PASSED: all update/interactive tests"
fi
