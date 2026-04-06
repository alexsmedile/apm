# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

`apm` is a local-first CLI package manager for AI agent prompt files. It manages three representations of an agent:
- **library**: canonical local database (`AGENTS_DB`, e.g. `~/vault/data/agents_db`)
- **runtime**: installed platform-specific agent files (e.g. `~/.claude/agents/`)
- **remote**: optional GitHub sync backend (monorepo and per-agent modes)

The CLI is a hybrid: a shell entrypoint (`apm`) handles orchestration and user interaction, while a Python helper (`lib/py/apm_python.py`) handles YAML parsing, normalization, validation, manifest generation, and structured JSON output.

## Project Status

**Fully implemented.** The spec files describe the design; the implementation is complete and tested.

Spec files for reference:
- `docs/spec/SPEC_CONFIG.md`, `SPEC_LIBRARY.md`, `SPEC_STATE.md`, `SPEC_RUNTIME.md`
- `docs/spec/SPEC_IMPORT.md`, `SPEC_GITHUB.md`, `SPEC_SAFETY.md`, `SPEC_TESTS.md`
- `docs/ARCHITECTURE.md`, `docs/AGENT_ENTRY_SCHEMA.md`, `docs/TUI.md`, `docs/WORKFLOWS.md`

## File Layout

```
apm                        # main shell entrypoint
lib/
  shell/
    config.shlib           # APM_CONFIG_DIR, config loading, setup wizard
    locks.shlib            # lock acquire/release (keyed by name)
    fs.shlib               # atomic write, backup, staging helpers
    ui.shlib               # apm_header, apm_info, apm_warn, apm_die
  py/
    apm_python.py          # all Python commands (parse, validate, diff, generate, import, github)
tests/
  fixtures/
    library-basic/         # canonical test library (git-mentor, reviewer)
    runtime-managed/       # runtime files with apm.id
    runtime-untracked/     # runtime files without apm.id
    bad-frontmatter/       # invalid agent for validation tests
  helpers/
    test_helpers.sh        # assert_json_field and other helpers
  test_static.sh           # bash -n + py_compile
  test_python_parse.sh     # Python layer unit tests
  test_config.sh           # config loading, precedence, setup wizard
  test_runtime.sh          # install, remove, diff, status
  test_import.sh           # analyze-import, build-import-draft, scan-unmanaged, full import flows
  test_safety.sh           # lock release, atomic write, exit codes, dry-run
  test_github.sh           # github-diff, push/pull round-trips, per-agent mode
  run_tests.sh             # master runner (runs all 7 suites)
```

## Static Validation

After any code change:

```bash
bash -n apm
python3 -m py_compile lib/py/apm_python.py
```

## Running Tests

```bash
# All suites (7 total, ~86 tests)
bash tests/run_tests.sh

# Single suite
bash tests/test_config.sh
bash tests/test_runtime.sh
# etc.
```

Tests use plain bash — no bats required. Each suite is self-contained and isolates all state via `APM_CONFIG_DIR=$(mktemp -d)`.

## Key Behavioral Rules

**Canonical ID** = agent folder name (`^[a-z0-9][a-z0-9-]*$`). Never the platform alias.

**Active body** resolution order (platform-aware):
1. `instructions/<id>.<platform-alias>@latest.md` — platform-specific (e.g. `git-mentor.cc@latest.md` for `claude-code`)
2. `instructions/<id>@latest.md` — generic latest
3. `instructions/<id>_latest.md` — legacy fallback
4. root `<id>.md` body — most common; file doubles as both DB entry and deploy source

Platform aliases: `claude-code→cc`, `cursor→crs`, `gemini→gmn`, `codex→cdx`, `generic→gen`

**Runtime file contract**: Installed files must include `apm.id`, `apm.platform`, `apm.installed-from`, `apm.installed-at` in frontmatter.

**Config precedence**: `CLI flag > env var > config file > built-in default`

**Config isolation**: All config/lock/ignore paths derive from `APM_CONFIG_DIR` (defaults to `~/.config/apm`). Tests set `APM_CONFIG_DIR=$(mktemp -d)` to avoid touching the real home.

**Lock files**: `${APM_CONFIG_DIR}/locks/` — required for all mutating commands.

**Backups**: Created at `<agent>/versions/apm-backup-YYYY-MM-DD-HHMM/` before destructive replacement.

**Exit codes**: `0` success, `1` diff/validation failure, `2` operational error, `3` dependency missing, `4` lock failure.

**Staging rule**: Pulls and imports must stage first; `--force` skips confirmation but not staging.

**Library wins**: Install is one-way (library → runtime). Never treat runtime as authoritative.

## Shell/Python Boundary

- **Shell owns**: CLI dispatch, prompts, config loading, lock acquisition, filesystem operations, git subprocess calls
- **Python owns**: YAML/frontmatter parsing, schema validation, normalization, manifest generation, structured diff output (as JSON)
- **No ad hoc YAML in shell**: All frontmatter parsing goes through the Python layer via JSON.

## Implemented Commands

| Command | Description |
|---------|-------------|
| `setup` | Interactive config wizard |
| `config` | Show resolved configuration |
| `validate [id]` | Validate agent(s) in library |
| `list` | List agents with sync state symbols |
| `status` | Count summary by sync state |
| `diff <id>` | Library vs runtime field diff |
| `install <id>` | Install agent to runtime |
| `remove <id>` | Remove agent from runtime |
| `update [id]` | Reinstall all outdated agents (or one) |
| `import [id\|--all]` | Import runtime agent into library |
| `github connect\|status\|diff\|push\|pull` | GitHub sync (monorepo + per-agent) |
| _(no args)_ | Interactive REPL with dashboard |

## GitHub Backend

Two modes: `monorepo` (all agents in one repo, each in a subdirectory) and `per-agent` (each agent gets its own repo). Key helpers:
- `_apm_github_repo_url(agent_id)` — mode-aware URL resolution
- `_apm_github_agent_dir(clone_dir, agent_id)` — monorepo: `clone/<id>/`; per-agent: `clone/` root
- Python `github-diff` / `github-status` commands handle the comparison logic
