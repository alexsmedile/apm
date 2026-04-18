#!/usr/bin/env bash
# test_static.sh — syntax checks for all shell and Python files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ERRORS=0

check_shell() {
    if bash -n "$1" 2>/dev/null; then
        echo "PASS: bash -n $(basename "$1")"
    else
        echo "FAIL: bash -n $1"
        bash -n "$1" 2>&1 || true
        ERRORS=$((ERRORS + 1))
    fi
}

check_python() {
    if python3 -m py_compile "$1" 2>/dev/null; then
        echo "PASS: py_compile $(basename "$1")"
    else
        echo "FAIL: py_compile $1"
        python3 -m py_compile "$1" 2>&1 || true
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Static Validation ==="

[ -f "$PROJECT_ROOT/apm" ]                         && check_shell "$PROJECT_ROOT/apm"                        || echo "SKIP: apm"
[ -f "$PROJECT_ROOT/lib/shell/config.shlib" ]      && check_shell "$PROJECT_ROOT/lib/shell/config.shlib"     || echo "SKIP: config.shlib"
[ -f "$PROJECT_ROOT/lib/shell/locks.shlib" ]       && check_shell "$PROJECT_ROOT/lib/shell/locks.shlib"      || echo "SKIP: locks.shlib"
[ -f "$PROJECT_ROOT/lib/shell/ui.shlib" ]          && check_shell "$PROJECT_ROOT/lib/shell/ui.shlib"         || echo "SKIP: ui.shlib"
[ -f "$PROJECT_ROOT/lib/shell/fs.shlib" ]          && check_shell "$PROJECT_ROOT/lib/shell/fs.shlib"         || echo "SKIP: fs.shlib"
[ -f "$PROJECT_ROOT/lib/py/apm_python.py" ]        && check_python "$PROJECT_ROOT/lib/py/apm_python.py"      || echo "SKIP: apm_python.py"
[ -f "$PROJECT_ROOT/lib/py/apm_tui.py" ]           && check_python "$PROJECT_ROOT/lib/py/apm_tui.py"         || echo "SKIP: apm_tui.py"

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS static check(s) failed"
    exit 1
else
    echo "PASSED: all static checks"
fi
