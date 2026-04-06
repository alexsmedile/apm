#!/usr/bin/env bash
# test_safety.sh — failure-path and safety guarantee tests
# Covers: lock release, atomic write, tmpfile cleanup, exit codes

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

echo "=== Safety Tests ==="

# ---------------------------------------------------------------------------
# Lock release: lock must not be held after a successful install
# ---------------------------------------------------------------------------

test_install_releases_lock() {
    local tmprt
    tmprt=$(mktemp -d)
    # Run install; then check that no runtime lock file remains
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local lock_gone=0
    [ ! -f "${APM_CONFIG_DIR}/locks/runtime-claude-code.lock" ] && lock_gone=1
    rm -rf "$tmprt"
    [ $lock_gone -eq 1 ]
}
run_test "install: runtime lock released after success" test_install_releases_lock

# ---------------------------------------------------------------------------
# Lock release: lock must not be held after a failed install (bad agent id)
# ---------------------------------------------------------------------------

test_install_releases_lock_on_failure() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install nonexistent-agent-xyz > /dev/null 2>&1 || true
    # Lock must be gone regardless of install failure
    local lock_gone=0
    [ ! -f "${APM_CONFIG_DIR}/locks/runtime-claude-code.lock" ] && lock_gone=1
    rm -rf "$tmprt"
    [ $lock_gone -eq 1 ]
}
run_test "install: runtime lock released after failure" test_install_releases_lock_on_failure

# ---------------------------------------------------------------------------
# No tmpfile left after install (success path)
# ---------------------------------------------------------------------------

test_install_no_tmpfile_after_success() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local tmpfiles
    tmpfiles=$(find "$tmprt" -name "*.apm.tmp.*" 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmprt"
    [ "$tmpfiles" = "0" ]
}
run_test "install: no tmpfile left after successful install" test_install_no_tmpfile_after_success

# ---------------------------------------------------------------------------
# Atomic write: installed file is valid YAML frontmatter (not truncated)
# ---------------------------------------------------------------------------

test_install_produces_valid_file() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    local valid=0
    # File must start with --- and contain closing ---
    local content
    content=$(cat "$tmprt/git-mentor.md" 2>/dev/null)
    echo "$content" | grep -q '^---' && echo "$content" | grep -c '^---' | grep -qE '^[2-9]' && valid=1
    rm -rf "$tmprt"
    [ $valid -eq 1 ]
}
run_test "install: installed file has complete frontmatter (not truncated)" test_install_produces_valid_file

# ---------------------------------------------------------------------------
# Lock release: library lock must not be held after _apm_apply_draft succeeds
# ---------------------------------------------------------------------------

test_import_releases_library_lock() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import scratch-agent > /dev/null 2>&1
    local lock_gone=0
    [ ! -f "${APM_CONFIG_DIR}/locks/library.lock" ] && lock_gone=1
    rm -rf "$tmpdb"
    [ $lock_gone -eq 1 ]
}
run_test "import: library lock released after successful apply" test_import_releases_library_lock

# ---------------------------------------------------------------------------
# Exit codes per SPEC_SAFETY.md
# ---------------------------------------------------------------------------

test_exit_code_validate_failure() {
    # validate-agent on a bad agent should exit 1 (validation failure)
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/bad-frontmatter/." "$tmpdb/"
    local ec
    AGENTS_DB="$tmpdb" \
        bash "$PROJECT_ROOT/apm" validate broken > /dev/null 2>&1
    ec=$?
    rm -rf "$tmpdb"
    [ "$ec" = "1" ]
}
run_test "exit code: validate failure exits 1" test_exit_code_validate_failure

test_exit_code_remove_not_found() {
    # remove on non-installed agent should exit 2 (operational error)
    local tmprt
    tmprt=$(mktemp -d)
    local ec
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force remove git-mentor > /dev/null 2>&1
    ec=$?
    rm -rf "$tmprt"
    [ "$ec" = "2" ]
}
run_test "exit code: remove non-installed agent exits 2" test_exit_code_remove_not_found

test_exit_code_missing_dep() {
    # Shadow python3 with a fake that exits 1 for everything (simulates missing PyYAML)
    # command -v succeeds (file exists), but `python3 -c "import yaml"` fails → exit 3
    local fakedir ec
    fakedir=$(mktemp -d)
    printf '#!/bin/sh\nexit 1\n' > "$fakedir/python3"
    chmod +x "$fakedir/python3"
    PATH="${fakedir}:${PATH}" \
        bash "$PROJECT_ROOT/apm" list > /dev/null 2>&1
    ec=$?
    rm -rf "$fakedir"
    [ "$ec" = "3" ]
}
run_test "exit code: missing python3 exits 3" test_exit_code_missing_dep

test_exit_code_lock_conflict() {
    # Manually place a live-pid lock, then try to install
    local tmprt lockdir
    tmprt=$(mktemp -d)
    lockdir=$(mktemp -d)
    mkdir -p "${lockdir}/locks"
    # Use current shell PID (always live)
    printf 'pid=%s\ntimestamp=2026-04-04T00:00:00Z\n' "$$" \
        > "${lockdir}/locks/runtime-claude-code.lock"
    local ec
    APM_CONFIG_DIR="$lockdir" \
        AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    ec=$?
    rm -rf "$tmprt" "$lockdir"
    [ "$ec" = "4" ]
}
run_test "exit code: live lock conflict exits 4" test_exit_code_lock_conflict

# ---------------------------------------------------------------------------
# Stale lock detection: stale lock (dead pid) is cleaned up and cmd succeeds
# ---------------------------------------------------------------------------

test_stale_lock_auto_cleared() {
    local tmprt lockdir
    tmprt=$(mktemp -d)
    lockdir=$(mktemp -d)
    mkdir -p "${lockdir}/locks"
    # PID 99999999 is almost certainly not a live process
    printf 'pid=99999999\ntimestamp=2020-01-01T00:00:00Z\n' \
        > "${lockdir}/locks/runtime-claude-code.lock"
    local ec
    APM_CONFIG_DIR="$lockdir" \
        AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code install git-mentor > /dev/null 2>&1
    ec=$?
    rm -rf "$tmprt" "$lockdir"
    [ "$ec" = "0" ]
}
run_test "locks: stale lock (dead pid) is cleared and install succeeds" test_stale_lock_auto_cleared

# ---------------------------------------------------------------------------
# Backup created before import-merge overwrites canonical entry
# ---------------------------------------------------------------------------

test_import_merge_backup_exists() {
    local tmpdb tmprt
    tmpdb=$(mktemp -d)
    tmprt=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    cat > "$tmprt/reviewer.md" <<'EOF'
---
name: reviewer
description: Updated reviewer from runtime.
model: claude-sonnet-4-6
tools: [Read, Grep]
---
Updated reviewer body from safety test.
EOF
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import reviewer > /dev/null 2>&1
    local backup_found=0
    ls "$tmpdb/reviewer/versions/" 2>/dev/null | grep -q "apm-backup" && backup_found=1
    rm -rf "$tmpdb" "$tmprt"
    [ $backup_found -eq 1 ]
}
run_test "safety: import-merge creates backup before overwriting canonical" test_import_merge_backup_exists

# ---------------------------------------------------------------------------
# --dry-run must never write files
# ---------------------------------------------------------------------------

test_dry_run_install_no_write() {
    local tmprt
    tmprt=$(mktemp -d)
    AGENTS_DB="$(realpath "$FIXTURES/library-basic")" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run install git-mentor > /dev/null 2>&1
    local file_count
    file_count=$(find "$tmprt" -type f 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmprt"
    [ "$file_count" = "0" ]
}
run_test "dry-run: install writes no files" test_dry_run_install_no_write

test_dry_run_import_no_library_write() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    local before_count after_count
    before_count=$(find "$tmpdb" -type f | wc -l | tr -d ' ')
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run import scratch-agent > /dev/null 2>&1
    after_count=$(find "$tmpdb" -type f | wc -l | tr -d ' ')
    rm -rf "$tmpdb"
    [ "$before_count" = "$after_count" ]
}
run_test "dry-run: import writes no library files" test_dry_run_import_no_library_write

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS safety test(s) failed"
    exit 1
else
    echo "PASSED: all safety tests"
fi
