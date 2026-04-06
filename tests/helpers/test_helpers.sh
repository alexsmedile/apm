#!/usr/bin/env bash
# test_helpers.sh — shared test utilities for apm test suite

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$HELPERS_DIR")"
PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"  # tests/ -> root

setup_test_env() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    export APM_AGENTS_DB="$tmpdir"
    export APM_PLATFORM="claude-code"
    echo "$tmpdir"
}

teardown_test_env() {
    local tmpdir="$1"
    rm -rf "$tmpdir"
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-exit code check}"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL [$msg]: expected exit $expected, got $actual"
        return 1
    fi
    return 0
}

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    parts = sys.argv[2].split('.')
    val = d
    for p in parts:
        val = val[p]
    print(str(val))
except Exception as e:
    print('ERROR: ' + str(e))
    sys.exit(1)
" "$json" "$field" 2>&1)
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "FAIL: json field '$field' expected '$expected', got '$actual'"
        return 1
    fi
}

assert_file_exists() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "FAIL: expected file to exist: $path"
        return 1
    fi
    return 0
}

assert_file_missing() {
    local path="$1"
    if [ -f "$path" ]; then
        echo "FAIL: expected file NOT to exist: $path"
        return 1
    fi
    return 0
}

run_apm() {
    bash "$PROJECT_ROOT/apm" "$@"
}
