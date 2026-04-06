#!/usr/bin/env bash
# test_import.sh — integration tests for import subsystem
# Follows SPEC_IMPORT.md rules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"
PY="$PROJECT_ROOT/lib/py/apm_python.py"

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

echo "=== Import Tests ==="

# ---------------------------------------------------------------------------
# analyze-import: match heuristics
# ---------------------------------------------------------------------------

test_analyze_new_untracked() {
    local out
    out=$(python3 "$PY" analyze-import \
        "$FIXTURES/runtime-untracked/scratch-agent.md" \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    assert_json_field "$out" "mode" "import-new"
    assert_json_field "$out" "match_type" "new"
    assert_json_field "$out" "library_exists" "False"
}
run_test "analyze-import: untracked file → import-new mode" test_analyze_new_untracked

test_analyze_apm_id_match() {
    local out
    out=$(python3 "$PY" analyze-import \
        "$FIXTURES/runtime-managed/git-mentor.md" \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    assert_json_field "$out" "match_type" "apm_id"
    assert_json_field "$out" "candidate_id" "git-mentor"
    assert_json_field "$out" "library_exists" "True"
}
run_test "analyze-import: file with apm.id → apm_id match" test_analyze_apm_id_match

test_analyze_link_existing_mode() {
    # apm_id match → link-existing (not import-merge)
    local out
    out=$(python3 "$PY" analyze-import \
        "$FIXTURES/runtime-managed/git-mentor.md" \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    assert_json_field "$out" "mode" "link-existing"
}
run_test "analyze-import: apm_id match → link-existing mode" test_analyze_link_existing_mode

test_analyze_filename_match() {
    # Create a runtime file matching library ID by filename, no apm.id
    local tmprt
    tmprt=$(mktemp -d)
    cat > "$tmprt/reviewer.md" <<'EOF'
---
name: reviewer
description: Modified reviewer for test.
model: claude-sonnet-4-6
tools: [Read]
---
Modified body.
EOF
    local out
    out=$(python3 "$PY" analyze-import \
        "$tmprt/reviewer.md" \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    local candidate
    candidate=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['candidate_id'])" "$out")
    local match
    match=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['match_type'])" "$out")
    rm -rf "$tmprt"
    [ "$candidate" = "reviewer" ] && [ "$match" = "filename_id" ]
}
run_test "analyze-import: filename matches canonical ID → filename_id match" test_analyze_filename_match

test_analyze_import_merge_mode() {
    # filename match with library_exists → import-merge
    local tmprt
    tmprt=$(mktemp -d)
    cat > "$tmprt/reviewer.md" <<'EOF'
---
name: reviewer
description: Modified reviewer.
model: claude-sonnet-4-6
tools: [Read]
---
Modified body.
EOF
    local out
    out=$(python3 "$PY" analyze-import \
        "$tmprt/reviewer.md" \
        --db "$FIXTURES/library-basic" \
        --platform claude-code)
    local mode
    mode=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['mode'])" "$out")
    rm -rf "$tmprt"
    [ "$mode" = "import-merge" ]
}
run_test "analyze-import: filename match + library exists → import-merge mode" test_analyze_import_merge_mode

# ---------------------------------------------------------------------------
# build-import-draft
# ---------------------------------------------------------------------------

test_draft_has_required_fields() {
    local out
    out=$(python3 "$PY" build-import-draft \
        "$FIXTURES/runtime-untracked/scratch-agent.md" \
        --id scratch-agent \
        --db "$FIXTURES/library-basic" \
        --platform claude-code \
        --timestamp 2026-04-04-1200)
    # stage_dir, root_file_path, latest_file_path must exist
    python3 -c "
import json,sys
d=json.loads(sys.argv[1])
assert d.get('stage_dir'), 'missing stage_dir'
assert d.get('root_file_path'), 'missing root_file_path'
assert d.get('latest_file_path'), 'missing latest_file_path'
assert d.get('root_file_content'), 'missing root_file_content'
assert d.get('latest_file_content'), 'missing latest_file_content'
" "$out"
}
run_test "build-import-draft: returns all required fields" test_draft_has_required_fields

test_draft_sets_origin_claude_import() {
    local out
    out=$(python3 "$PY" build-import-draft \
        "$FIXTURES/runtime-untracked/scratch-agent.md" \
        --id scratch-agent \
        --db "$FIXTURES/library-basic" \
        --platform claude-code \
        --timestamp 2026-04-04-1200)
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
content=d['root_file_content']
assert 'origin: claude-import' in content, 'missing origin field'
assert 'ver-stat: Imported' in content, 'missing ver-stat'
"
}
run_test "build-import-draft: root file has import metadata (origin, ver-stat)" test_draft_sets_origin_claude_import

test_draft_derives_deploy_block() {
    local out
    out=$(python3 "$PY" build-import-draft \
        "$FIXTURES/runtime-untracked/scratch-agent.md" \
        --id scratch-agent \
        --db "$FIXTURES/library-basic" \
        --platform claude-code \
        --timestamp 2026-04-04-1200)
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
content=d['root_file_content']
assert 'deploy:' in content, 'missing deploy block'
assert 'claude-code:' in content, 'missing claude-code deploy'
"
}
run_test "build-import-draft: derives deploy block from runtime frontmatter" test_draft_derives_deploy_block

test_draft_body_in_latest_file() {
    local out
    out=$(python3 "$PY" build-import-draft \
        "$FIXTURES/runtime-untracked/scratch-agent.md" \
        --id scratch-agent \
        --db "$FIXTURES/library-basic" \
        --platform claude-code \
        --timestamp 2026-04-04-1200)
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
body=d['latest_file_content']
assert 'Scratch Agent' in body, 'body content missing from latest file'
"
}
run_test "build-import-draft: body goes into latest_file_content" test_draft_body_in_latest_file

# ---------------------------------------------------------------------------
# scan-unmanaged
# ---------------------------------------------------------------------------

test_scan_finds_untracked() {
    local out
    out=$(python3 "$PY" scan-unmanaged \
        --runtime-dir "$FIXTURES/runtime-untracked" \
        --db "$FIXTURES/library-basic")
    local count
    count=$(python3 -c "
import json,sys; d=json.loads(sys.argv[1]); print(len(d.get('unmanaged',[])))
" "$out")
    [ "$count" -gt 0 ]
}
run_test "scan-unmanaged: detects untracked files" test_scan_finds_untracked

test_scan_finds_managed() {
    local out
    out=$(python3 "$PY" scan-unmanaged \
        --runtime-dir "$FIXTURES/runtime-managed" \
        --db "$FIXTURES/library-basic")
    local count
    count=$(python3 -c "
import json,sys; d=json.loads(sys.argv[1]); print(len(d.get('managed',[])))
" "$out")
    [ "$count" -gt 0 ]
}
run_test "scan-unmanaged: recognizes managed files (have apm.id in library)" test_scan_finds_managed

test_scan_respects_ignore_file() {
    local tmpign
    tmpign=$(mktemp)
    local fpath
    fpath="$(realpath "$FIXTURES/runtime-untracked/scratch-agent.md")"
    echo "claude-code:${fpath}" > "$tmpign"
    local out
    out=$(python3 "$PY" scan-unmanaged \
        --runtime-dir "$FIXTURES/runtime-untracked" \
        --db "$FIXTURES/library-basic" \
        --ignore-file "$tmpign")
    local unmanaged_count ignored_count
    unmanaged_count=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(len(d.get('unmanaged',[])))" "$out")
    ignored_count=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(len(d.get('ignored',[])))" "$out")
    rm -f "$tmpign"
    [ "$unmanaged_count" = "0" ] && [ "$ignored_count" = "1" ]
}
run_test "scan-unmanaged: ignored files are excluded from unmanaged list" test_scan_respects_ignore_file

# ---------------------------------------------------------------------------
# Full import flow (shell command)
# ---------------------------------------------------------------------------

test_import_new_creates_library_entry() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import scratch-agent > /dev/null 2>&1
    local ok=0
    [ -f "$tmpdb/scratch-agent/scratch-agent.md" ] && \
    [ -f "$tmpdb/scratch-agent/instructions/scratch-agent@latest.md" ] && \
    ok=1
    rm -rf "$tmpdb"
    [ $ok -eq 1 ]
}
run_test "import: import-new creates canonical library entry" test_import_new_creates_library_entry

test_import_new_validates_cleanly() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import scratch-agent > /dev/null 2>&1
    local result
    AGENTS_DB="$tmpdb" bash "$PROJECT_ROOT/apm" validate scratch-agent 2>/dev/null
    result=$?
    rm -rf "$tmpdb"
    [ $result -eq 0 ]
}
run_test "import: imported entry passes validate" test_import_new_validates_cleanly

test_import_new_dry_run_no_library_change() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --dry-run import scratch-agent > /dev/null 2>&1
    local missing=0
    [ ! -d "$tmpdb/scratch-agent" ] && missing=1
    rm -rf "$tmpdb"
    [ $missing -eq 1 ]
}
run_test "import: --dry-run does not create library entry" test_import_new_dry_run_no_library_change

test_import_merge_creates_backup() {
    # Create a runtime file that matches by filename (no apm.id) → import-merge
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
Updated reviewer body.
EOF
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$tmprt" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import reviewer > /dev/null 2>&1
    local backup_exists=0
    ls "$tmpdb/reviewer/versions/" 2>/dev/null | grep -q "apm-backup" && backup_exists=1
    rm -rf "$tmpdb" "$tmprt"
    [ $backup_exists -eq 1 ]
}
run_test "import: import-merge creates backup of existing canonical entry" test_import_merge_creates_backup

test_import_all_discovers_unmanaged() {
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code --force import --all > /dev/null 2>&1
    local ok=0
    [ -f "$tmpdb/scratch-agent/scratch-agent.md" ] && ok=1
    rm -rf "$tmpdb"
    [ $ok -eq 1 ]
}
run_test "import --all: imports all unmanaged runtime files" test_import_all_discovers_unmanaged

test_import_does_not_touch_library_without_confirm() {
    # Without --force, import should stage but not apply
    # We simulate non-interactive by piping empty string as input
    local tmpdb
    tmpdb=$(mktemp -d)
    cp -r "$FIXTURES/library-basic/." "$tmpdb/"
    # Pipe 'n' as answer to the confirm prompt
    AGENTS_DB="$tmpdb" \
        CLAUDE_AGENTS="$(realpath "$FIXTURES/runtime-untracked")" \
        bash "$PROJECT_ROOT/apm" --platform claude-code import scratch-agent <<< "n" > /dev/null 2>&1
    local not_applied=0
    [ ! -d "$tmpdb/scratch-agent" ] && not_applied=1
    rm -rf "$tmpdb"
    [ $not_applied -eq 1 ]
}
run_test "import: declining confirmation does not write to library" test_import_does_not_touch_library_without_confirm

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS import test(s) failed"
    exit 1
else
    echo "PASSED: all import tests"
fi
