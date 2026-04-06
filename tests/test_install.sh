#!/usr/bin/env bash
# test_install.sh — tests for install.sh: symlink creation, --check, --uninstall

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

echo "=== Install Tests ==="

# ---------------------------------------------------------------------------
# --check: exits 0 when all deps present
# ---------------------------------------------------------------------------

test_check_deps_exits_0() {
    bash "$PROJECT_ROOT/install.sh" --check > /dev/null 2>&1
}
run_test "--check: exits 0 when deps satisfied" test_check_deps_exits_0

# ---------------------------------------------------------------------------
# --check: output mentions python3 and PyYAML
# ---------------------------------------------------------------------------

test_check_deps_output() {
    local out
    out=$(bash "$PROJECT_ROOT/install.sh" --check 2>&1)
    echo "$out" | grep -q "python3" && echo "$out" | grep -q "PyYAML"
}
run_test "--check: output mentions python3 and PyYAML" test_check_deps_output

# ---------------------------------------------------------------------------
# install: creates symlink in custom dir
# ---------------------------------------------------------------------------

test_install_creates_symlink() {
    local tmpbin
    tmpbin=$(mktemp -d)
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" > /dev/null 2>&1
    local ec=$?
    local is_link=0
    [ -L "${tmpbin}/apm" ] && is_link=1
    rm -rf "$tmpbin"
    [ $ec -eq 0 ] && [ $is_link -eq 1 ]
}
run_test "install: creates symlink in custom directory" test_install_creates_symlink

# ---------------------------------------------------------------------------
# install: symlink resolves to the apm entrypoint
# ---------------------------------------------------------------------------

test_install_symlink_target() {
    local tmpbin
    tmpbin=$(mktemp -d)
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" > /dev/null 2>&1
    local target
    target=$(readlink "${tmpbin}/apm" 2>/dev/null)
    rm -rf "$tmpbin"
    [ "$target" = "$PROJECT_ROOT/apm" ]
}
run_test "install: symlink points to project apm entrypoint" test_install_symlink_target

# ---------------------------------------------------------------------------
# install: reinstall overwrites existing symlink (idempotent)
# ---------------------------------------------------------------------------

test_install_idempotent() {
    local tmpbin
    tmpbin=$(mktemp -d)
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" > /dev/null 2>&1
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" > /dev/null 2>&1
    local ec=$?
    local is_link=0
    [ -L "${tmpbin}/apm" ] && is_link=1
    rm -rf "$tmpbin"
    [ $ec -eq 0 ] && [ $is_link -eq 1 ]
}
run_test "install: reinstall is idempotent (overwrites existing symlink)" test_install_idempotent

# ---------------------------------------------------------------------------
# --uninstall: removes the symlink
# ---------------------------------------------------------------------------

test_uninstall_removes_symlink() {
    local tmpbin
    tmpbin=$(mktemp -d)
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" > /dev/null 2>&1
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" --uninstall > /dev/null 2>&1
    local ec=$?
    local still_exists=0
    [ -e "${tmpbin}/apm" ] && still_exists=1
    rm -rf "$tmpbin"
    [ $ec -eq 0 ] && [ $still_exists -eq 0 ]
}
run_test "--uninstall: removes the installed symlink" test_uninstall_removes_symlink

# ---------------------------------------------------------------------------
# --uninstall: exits 0 gracefully when nothing installed
# ---------------------------------------------------------------------------

test_uninstall_nothing_to_remove() {
    local tmpbin
    tmpbin=$(mktemp -d)
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" --uninstall > /dev/null 2>&1
    local ec=$?
    rm -rf "$tmpbin"
    [ $ec -eq 0 ]
}
run_test "--uninstall: exits 0 when nothing installed" test_uninstall_nothing_to_remove

# ---------------------------------------------------------------------------
# --uninstall: refuses to remove a non-symlink file
# ---------------------------------------------------------------------------

test_uninstall_refuses_regular_file() {
    local tmpbin
    tmpbin=$(mktemp -d)
    touch "${tmpbin}/apm"   # regular file, not a symlink
    bash "$PROJECT_ROOT/install.sh" "$tmpbin" --uninstall > /dev/null 2>&1
    local ec=$?
    local still_exists=0
    [ -f "${tmpbin}/apm" ] && still_exists=1
    rm -rf "$tmpbin"
    # Must exit non-zero and leave the file untouched
    [ $ec -ne 0 ] && [ $still_exists -eq 1 ]
}
run_test "--uninstall: refuses to remove a non-symlink file" test_uninstall_refuses_regular_file

# ---------------------------------------------------------------------------
# unknown flag exits non-zero
# ---------------------------------------------------------------------------

test_unknown_flag_exits_nonzero() {
    bash "$PROJECT_ROOT/install.sh" --bogus > /dev/null 2>&1
    local ec=$?
    [ $ec -ne 0 ]
}
run_test "unknown flag: exits non-zero with error" test_unknown_flag_exits_nonzero

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS install test(s) failed"
    exit 1
else
    echo "PASSED: all install tests"
fi
