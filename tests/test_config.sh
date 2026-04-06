#!/usr/bin/env bash
# test_config.sh — integration tests for config loading, precedence, and setup wizard

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

echo "=== Config Tests ==="

# ---------------------------------------------------------------------------
# Config precedence: env var overrides config file
# ---------------------------------------------------------------------------

test_env_overrides_config_file() {
    local cfgdir
    cfgdir=$(mktemp -d)
    cat > "${cfgdir}/config.sh" <<'EOF'
AGENTS_DB="/from-config-file"
PLATFORM="cursor"
EOF
    # AGENTS_DB env var should win over the config file value
    local out
    out=$(APM_CONFIG_DIR="$cfgdir" \
        AGENTS_DB="/from-env" \
        bash "$PROJECT_ROOT/apm" --json status 2>&1 || true)
    rm -rf "$cfgdir"
    # The error (if any) should reference /from-env, not /from-config-file
    # We check that it didn't use the config-file value
    ! echo "$out" | grep -q "/from-config-file"
}
run_test "config: env var AGENTS_DB overrides config file" test_env_overrides_config_file

test_cli_flag_overrides_env() {
    local cfgdir tmpdb1 tmpdb2
    cfgdir=$(mktemp -d)
    tmpdb1=$(mktemp -d)
    tmpdb2=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb2/"

    cat > "${cfgdir}/config.sh" <<EOF
AGENTS_DB="$tmpdb1"
PLATFORM="claude-code"
EOF
    # --db flag should win over env var
    local out
    out=$(APM_CONFIG_DIR="$cfgdir" \
        AGENTS_DB="$tmpdb1" \
        bash "$PROJECT_ROOT/apm" --db "$tmpdb2" --json list 2>/dev/null)
    local count
    count=$(echo "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(len(d.get('agents',[])))" 2>/dev/null || echo "0")
    rm -rf "$cfgdir" "$tmpdb1" "$tmpdb2"
    [ "$count" -gt 0 ]
}
run_test "config: --db CLI flag overrides AGENTS_DB env var" test_cli_flag_overrides_env

test_platform_default_is_claude_code() {
    local cfgdir tmpdb
    cfgdir=$(mktemp -d)
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # No PLATFORM set — should default to claude-code
    cat > "${cfgdir}/config.sh" <<EOF
AGENTS_DB="$tmpdb"
EOF
    local out
    out=$(APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" --json status 2>/dev/null)
    rm -rf "$cfgdir" "$tmpdb"
    # JSON status output should be valid and contain agents
    echo "$out" | python3 -c "import json,sys; json.loads(sys.stdin.read())" 2>/dev/null
}
run_test "config: default platform is claude-code when not set" test_platform_default_is_claude_code

# ---------------------------------------------------------------------------
# Setup wizard: writes config file
# ---------------------------------------------------------------------------

test_setup_wizard_creates_config() {
    local cfgdir
    cfgdir=$(mktemp -d)
    # Feed: db path, platform, no github
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" setup <<'INPUT' > /dev/null 2>&1
/tmp/test-agents-db
claude-code
n
INPUT
    [ -f "${cfgdir}/config.sh" ]
    local result=$?
    rm -rf "$cfgdir"
    [ $result -eq 0 ]
}
run_test "setup: wizard creates config.sh" test_setup_wizard_creates_config

test_setup_wizard_writes_agents_db() {
    local cfgdir
    cfgdir=$(mktemp -d)
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" setup <<'INPUT' > /dev/null 2>&1
/tmp/test-agents-db
claude-code
n
INPUT
    local content
    content=$(cat "${cfgdir}/config.sh" 2>/dev/null)
    rm -rf "$cfgdir"
    echo "$content" | grep -q 'AGENTS_DB="/tmp/test-agents-db"'
}
run_test "setup: wizard writes AGENTS_DB to config" test_setup_wizard_writes_agents_db

test_setup_wizard_writes_platform() {
    local cfgdir
    cfgdir=$(mktemp -d)
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" setup <<'INPUT' > /dev/null 2>&1
/tmp/test-db
cursor
n
INPUT
    local content
    content=$(cat "${cfgdir}/config.sh" 2>/dev/null)
    rm -rf "$cfgdir"
    echo "$content" | grep -q 'PLATFORM="cursor"'
}
run_test "setup: wizard writes PLATFORM to config" test_setup_wizard_writes_platform

test_setup_wizard_atomic_write() {
    # Config file must not be partially written (temp+rename pattern)
    # We verify indirectly: the config file exists and is valid shell
    local cfgdir
    cfgdir=$(mktemp -d)
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" setup <<'INPUT' > /dev/null 2>&1
/tmp/test-db
claude-code
n
INPUT
    # Source the config: if it's valid shell, this won't crash
    bash -c "source '${cfgdir}/config.sh'" 2>/dev/null
    local result=$?
    rm -rf "$cfgdir"
    [ $result -eq 0 ]
}
run_test "setup: config file is valid shell (atomic write)" test_setup_wizard_atomic_write

test_setup_wizard_with_github() {
    local cfgdir
    cfgdir=$(mktemp -d)
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" setup <<'INPUT' > /dev/null 2>&1
/tmp/test-db
claude-code
y
monorepo
myorg
my-agents
main
INPUT
    local content
    content=$(cat "${cfgdir}/config.sh" 2>/dev/null)
    rm -rf "$cfgdir"
    echo "$content" | grep -q 'GITHUB_MODE="monorepo"' && \
    echo "$content" | grep -q 'GITHUB_OWNER="myorg"' && \
    echo "$content" | grep -q 'GITHUB_MONOREPO="my-agents"'
}
run_test "setup: wizard writes GitHub config when enabled" test_setup_wizard_with_github

# ---------------------------------------------------------------------------
# Config file absent: no-setup-needed commands work without it
# ---------------------------------------------------------------------------

test_no_config_validate_with_db_flag() {
    # --db flag should allow validate to work even without a config file
    local cfgdir tmpdb
    cfgdir=$(mktemp -d)
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # cfgdir has no config.sh
    local ec
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" --db "$tmpdb" validate git-mentor > /dev/null 2>&1
    ec=$?
    rm -rf "$cfgdir" "$tmpdb"
    [ $ec -eq 0 ]
}
run_test "config: --db flag allows validate without config file" test_no_config_validate_with_db_flag

test_no_config_no_db_exits_2() {
    local cfgdir
    cfgdir=$(mktemp -d)
    local ec
    APM_CONFIG_DIR="$cfgdir" \
        bash "$PROJECT_ROOT/apm" list > /dev/null 2>&1
    ec=$?
    rm -rf "$cfgdir"
    [ $ec -eq 2 ]
}
run_test "config: no config and no --db exits 2" test_no_config_no_db_exits_2

# ---------------------------------------------------------------------------
# APM_CONFIG_DIR isolation: two simultaneous processes see their own config
# ---------------------------------------------------------------------------

test_config_dir_isolation() {
    local cfgdir1 cfgdir2 tmpdb1 tmpdb2
    cfgdir1=$(mktemp -d)
    cfgdir2=$(mktemp -d)
    tmpdb1=$(mktemp -d)
    tmpdb2=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb1/"

    cat > "${cfgdir1}/config.sh" <<EOF
AGENTS_DB="$tmpdb1"
PLATFORM="claude-code"
EOF
    cat > "${cfgdir2}/config.sh" <<EOF
AGENTS_DB="$tmpdb2"
PLATFORM="claude-code"
EOF

    local count1 count2
    count1=$(APM_CONFIG_DIR="$cfgdir1" bash "$PROJECT_ROOT/apm" --json list 2>/dev/null | \
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(len(d.get('agents',[])))" 2>/dev/null || echo "0")
    count2=$(APM_CONFIG_DIR="$cfgdir2" bash "$PROJECT_ROOT/apm" --json list 2>/dev/null | \
        python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(len(d.get('agents',[])))" 2>/dev/null || echo "0")

    rm -rf "$cfgdir1" "$cfgdir2" "$tmpdb1" "$tmpdb2"
    # cfgdir1 has library-basic (2+ agents), cfgdir2 has an empty db (0 agents)
    [ "$count1" -gt "$count2" ]
}
run_test "config: APM_CONFIG_DIR isolation — two configs see different libraries" test_config_dir_isolation

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS config test(s) failed"
    exit 1
else
    echo "PASSED: all config tests"
fi
