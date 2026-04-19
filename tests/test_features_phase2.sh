#!/usr/bin/env bash
# test_features_phase2.sh — tests for init, platform filtering, and dry-run output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers/test_helpers.sh"

# Isolate apm config from the real HOME
_APM_TEST_CONFIG_DIR=$(mktemp -d)
export APM_CONFIG_DIR="$_APM_TEST_CONFIG_DIR"
trap 'rm -rf "$_APM_TEST_CONFIG_DIR"' EXIT

ERRORS=0

run_test() {
    local name="$1"; shift
    if "$@"; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Roadmap Phase 2 Feature Tests ==="

# ---------------------------------------------------------------------------
# apm init
# ---------------------------------------------------------------------------

test_init_claude_code() {
    local workdir
    workdir=$(mktemp -d)
    local old_pwd=$(pwd)
    cd "$workdir" || return 1
    
    # Run init with force to skip confirmation
    APM_FORCE=1 bash "$PROJECT_ROOT/apm" --platform claude-code init >/dev/null
    
    local ok=0
    # echo "DEBUG: PWD: $(pwd)"
    # ls -la .claude/agents 2>/dev/null
    if [ -d ".claude/agents" ]; then
        # Verify config now reports project scope
        local out
        out=$(bash "$PROJECT_ROOT/apm" --platform claude-code --json config)
        # echo "DEBUG: CONFIG OUT: $out"
        if assert_json_field "$out" "scope" "project" && assert_json_field "$out" "runtime_dir" "./.claude/agents"; then
            ok=1
        fi
    fi
    
    cd "$old_pwd" || return 1
    rm -rf "$workdir"
    [ "$ok" -eq 1 ] || return 1
}
run_test "init: creates .claude/agents and detects project scope" test_init_claude_code

test_init_gemini_agents() {
    local workdir
    workdir=$(mktemp -d)
    local old_pwd=$(pwd)
    cd "$workdir" || return 1

    APM_FORCE=1 bash "$PROJECT_ROOT/apm" --platform gemini init >/dev/null

    local ok=0
    if [ -d ".gemini/agents" ]; then
        local out
        out=$(bash "$PROJECT_ROOT/apm" --platform gemini --json config)
        if assert_json_field "$out" "scope" "project" && assert_json_field "$out" "runtime_dir" "./.gemini/agents"; then
            ok=1
        fi
    fi

    cd "$old_pwd" || return 1
    rm -rf "$workdir"
    [ "$ok" -eq 1 ] || return 1
}
run_test "init: creates .gemini/agents and detects project scope" test_init_gemini_agents

# ---------------------------------------------------------------------------
# ls -a (platform filtering)
# ---------------------------------------------------------------------------

test_ls_platform_filter() {
    local db
    db=$(mktemp -d)
    
    # Create an agent that only has 'cursor' deploy config
    mkdir -p "$db/cursor-only"
    cat > "$db/cursor-only/cursor-only.md" <<EOF
---
id: cursor-only
deploy:
  cursor:
    name: cursor-only
    description: Only for cursor
---
# Cursor Only
EOF

    # Create an agent that has 'claude-code' deploy config
    mkdir -p "$db/claude-agent"
    cat > "$db/claude-agent/claude-agent.md" <<EOF
---
id: claude-agent
deploy:
  claude-code:
    name: claude-agent
    description: Only for claude
---
# Claude Agent
EOF

    local out
    local ok=1
    # Filter for cursor
    out=$(bash "$PROJECT_ROOT/apm" --db "$db" ls -a cursor)
    echo "$out" | grep -q "cursor-only" || { echo "FAIL: cursor-only missing from filter"; ok=0; }
    echo "$out" | grep -q "claude-agent" && { echo "FAIL: claude-agent should be filtered out"; ok=0; }

    # Filter for claude-code
    out=$(bash "$PROJECT_ROOT/apm" --db "$db" ls -a claude-code)
    echo "$out" | grep -q "claude-agent" || { echo "FAIL: claude-agent missing from filter"; ok=0; }
    echo "$out" | grep -q "cursor-only" && { echo "FAIL: cursor-only should be filtered out"; ok=0; }

    rm -rf "$db"
    [ "$ok" -eq 1 ]
}
run_test "ls -a: filters agents by platform compatibility" test_ls_platform_filter

# ---------------------------------------------------------------------------
# install --dry-run
# ---------------------------------------------------------------------------

test_install_dry_run_output() {
    local db
    db=$(mktemp -d)
    mkdir -p "$db/test-agent"
    cat > "$db/test-agent/test-agent.md" <<EOF
---
id: test-agent
deploy:
  claude-code:
    name: test-agent
    description: Test agent
    tools: [Read]
---
# Test Body
EOF

    local out
    out=$(bash "$PROJECT_ROOT/apm" --db "$db" --platform claude-code install --dry-run test-agent)
    
    local ok=1
    echo "$out" | grep -q "\-\-\- Generated Content (Dry Run) \-\-\-" || { echo "FAIL: Dry run header missing"; ok=0; }
    echo "$out" | grep -q "name: test-agent" || { echo "FAIL: Generated frontmatter missing"; ok=0; }
    echo "$out" | grep -q "tools:" || { echo "FAIL: Generated tools missing"; ok=0; }
    echo "$out" | grep -q "# Test Body" || { echo "FAIL: Generated body missing"; ok=0; }
    
    rm -rf "$db"
    [ "$ok" -eq 1 ]
}
run_test "install --dry-run: shows generated content" test_install_dry_run_output

if [ $ERRORS -gt 0 ]; then
    echo "Total errors: $ERRORS"
    exit 1
fi
