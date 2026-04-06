#!/usr/bin/env bash
# test_python_parse.sh — tests for Python parser/validator output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"
PY="$PROJECT_ROOT/lib/py/apm_python.py"

if [ ! -f "$PY" ]; then
    echo "SKIP: apm_python.py not yet created — skipping all Python parse tests"
    exit 0
fi

# shellcheck source=tests/helpers/test_helpers.sh
source "$SCRIPT_DIR/helpers/test_helpers.sh"

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

echo "=== Python Parse Tests ==="

# --- parse-root ---

test_parse_root_valid() {
    local out
    out=$(python3 "$PY" parse-root "$FIXTURES/library-basic/git-mentor/git-mentor.md")
    assert_json_field "$out" "frontmatter.id" "git-mentor"
}
run_test "parse-root: valid agent has correct id" test_parse_root_valid

test_parse_root_name() {
    local out
    out=$(python3 "$PY" parse-root "$FIXTURES/library-basic/git-mentor/git-mentor.md")
    # name field contains "GIT MENTOR"
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
name = d['frontmatter'].get('name','')
assert 'GIT MENTOR' in name, f'Expected GIT MENTOR in name, got: {name}'
"
}
run_test "parse-root: name field present" test_parse_root_name

test_parse_root_bad_returns_json() {
    local out
    out=$(python3 "$PY" parse-root "$FIXTURES/bad-frontmatter/broken/broken.md" 2>&1) || true
    # Must return JSON (not a raw Python traceback)
    echo "$out" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null
}
run_test "parse-root: bad frontmatter returns JSON (not traceback)" test_parse_root_bad_returns_json

# --- validate-agent ---

test_validate_valid_exits_0() {
    python3 "$PY" validate-agent --id git-mentor --db "$FIXTURES/library-basic" > /dev/null
}
run_test "validate-agent: valid agent exits 0" test_validate_valid_exits_0

test_validate_valid_json() {
    local out
    out=$(python3 "$PY" validate-agent --id git-mentor --db "$FIXTURES/library-basic")
    assert_json_field "$out" "valid" "True"
}
run_test "validate-agent: valid agent returns valid=true" test_validate_valid_json

test_validate_bad_exits_1() {
    python3 "$PY" validate-agent --id broken --db "$FIXTURES/bad-frontmatter" > /dev/null 2>&1
    [ $? -eq 1 ]
}
run_test "validate-agent: bad frontmatter exits 1" test_validate_bad_exits_1

test_validate_bad_json() {
    local out
    out=$(python3 "$PY" validate-agent --id broken --db "$FIXTURES/bad-frontmatter" 2>/dev/null || true)
    assert_json_field "$out" "valid" "False"
}
run_test "validate-agent: bad frontmatter returns valid=false" test_validate_bad_json

# --- list-agents ---

test_list_agents_count() {
    local out
    out=$(python3 "$PY" list-agents --db "$FIXTURES/library-basic")
    local count
    count=$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
print(len(d.get('agents',[])))
" "$out")
    [ "$count" = "2" ]
}
run_test "list-agents: finds 2 agents in library-basic" test_list_agents_count

# --- validate-all ---

test_validate_all_basic_valid() {
    local out
    out=$(python3 "$PY" validate-all --db "$FIXTURES/library-basic")
    assert_json_field "$out" "valid" "True"
}
run_test "validate-all: library-basic is fully valid" test_validate_all_basic_valid

test_validate_all_collision() {
    local out
    out=$(python3 "$PY" validate-all --db "$FIXTURES/library-collision" 2>/dev/null || true)
    local ncoll
    ncoll=$(python3 -c "
import json,sys
d=json.loads(sys.argv[1])
print(len(d.get('collisions',[])))
" "$out")
    [ "$ncoll" -gt 0 ]
}
run_test "validate-all: library-collision detects collision" test_validate_all_collision

# --- parse-runtime ---

test_parse_runtime_managed() {
    local out
    out=$(python3 "$PY" parse-runtime "$FIXTURES/runtime-managed/git-mentor.md")
    assert_json_field "$out" "managed" "True"
}
run_test "parse-runtime: managed file has managed=true" test_parse_runtime_managed

test_parse_runtime_untracked() {
    local out
    out=$(python3 "$PY" parse-runtime "$FIXTURES/runtime-untracked/scratch-agent.md")
    assert_json_field "$out" "managed" "False"
}
run_test "parse-runtime: untracked file has managed=false" test_parse_runtime_untracked

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS Python parse test(s) failed"
    exit 1
else
    echo "PASSED: all Python parse tests"
fi
