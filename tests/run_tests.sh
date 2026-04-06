#!/usr/bin/env bash
# run_tests.sh — master test runner for apm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PASS=0
FAIL=0

run_suite() {
    local file="$1"
    echo ""
    echo "--- $file ---"
    if bash "$file"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

run_suite tests/test_static.sh
run_suite tests/test_python_parse.sh
run_suite tests/test_config.sh
run_suite tests/test_runtime.sh
run_suite tests/test_import.sh
run_suite tests/test_safety.sh
run_suite tests/test_github.sh
run_suite tests/test_update.sh
run_suite tests/test_install.sh

echo ""
echo "================================"
echo "Results: $PASS suite(s) passed, $FAIL suite(s) failed"
[ "$FAIL" -eq 0 ]
