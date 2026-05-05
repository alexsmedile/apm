# AGENTS.md

This file is the canonical working guide for agents operating in this `apm` repository.

`apm` is a local-first package manager for AI agents and skills. Prefer this file over older tool-specific guidance files.

## What This Project Is

`apm` manages three representations:

- `library`: canonical local database
  - agents: `AGENTS_DB`
  - skills: `SKILLS_DB`
- `runtime`: installed platform-specific files or skill directories
- `remote`: optional GitHub sync backend

The implementation is hybrid:

- shell entrypoint: [`apm`](apm)
- shell helpers: [`lib/shell/`](lib/shell)
- Python helper: [`lib/py/apm_python.py`](lib/py/apm_python.py)

Shell owns orchestration, prompts, locking, filesystem operations, and git subprocesses.
Python owns YAML/frontmatter parsing, normalization, validation, manifest generation, and JSON output.

## Core Rules

- Prefer the CLI over the TUI for real work.
- Treat `AGENTS_DB` and `SKILLS_DB` as the source of truth.
- Never delete from `AGENTS_DB` or `SKILLS_DB` unless the user explicitly confirms.
- Library wins over runtime. Do not treat runtime as authoritative.
- Do not parse YAML in shell. Use the Python layer via `_apm_py`.
- Mutations must be safety-first: lock, stage if needed, backup if destructive, then apply.

## Important Local Paths

- Repo script: `<repo-root>/apm`
- Installed command: `~/.local/bin/apm`
- User config: `~/.config/apm/config.sh`
- Bash libs: `<repo-root>/lib/shell/`
- Python helper: `<repo-root>/lib/py/apm_python.py`

## Current User Preference

While the TUI is still work in progress, prefer explicit per-platform skill commands, especially:

```bash
apm --mode skills --platform claude-code status
apm --mode skills --platform claude-code list
apm --mode skills --platform agents-dir list
```

The user wants clear per-platform visibility.

## Agent Onboarding — Read This First

When an agent opens this repo, follow these steps in order.

### Step 1 — Check if apm is already installed

```bash
command -v apm && apm --version
```

- If found and working: skip to Step 3.
- If not found: go to Step 2.

### Step 2 — Install apm

```bash
bash install.sh
```

This links `apm` into `~/.local/bin/apm`. The installer will also offer to install the `apm` skill into `~/.claude/skills/` and `~/.agents/skills/` — accept it so agents can use apm commands going forward.

If `~/.local/bin` is not in `$PATH`, add it:

```bash
export PATH="$PATH:$HOME/.local/bin"
```

Verify:

```bash
apm --version
```

### Step 3 — Check if apm is configured

```bash
apm config
```

Look for `Library` and `Runtime dir` in the output. If they show valid paths, apm is configured — skip to Step 4.

If the library path is missing or wrong, run the setup wizard:

```bash
apm setup
```

The wizard asks for:
- `AGENTS_DB` path — your canonical agents library folder
- `SKILLS_DB` path — your canonical skills library folder
- default mode (`agents` or `skills`)
- default platform (`claude-code`, `codex`, `gemini`, `agents-dir`, etc.)

### Step 4 — Orient yourself

```bash
apm status          # count summary by state
apm list            # all agents with sync state
apm -s -p cc list   # skills for claude-code
apm -s -p agt list  # skills for agents-dir
```

This tells you what is installed, what is outdated, and what is ready to install.

### Step 5 — Install the apm skill (if not done by install.sh)

The `apm` skill teaches agents how to use this tool. Install it globally:

```bash
apm -s -p cc,agt install apm
```

Or project-locally from the repo root:

```bash
apm -s -p cc,agt --cwd . install apm
```

### Step 6 — Normal operation

You are now ready. Use apm commands for all agent and skill management — never edit runtime directories directly.

```bash
apm install <agent-id>               # install an agent
apm -s -p cc install <skill-id>      # install a skill
apm update                           # reinstall all outdated agents
apm -s -p cc install --all           # install all ready/outdated skills
apm diff <agent-id>                  # compare library vs runtime
apm import                           # import unmanaged runtime agents
```

## Config and Resolution Rules

- Precedence: `CLI flag > env var > config file > built-in default`
- Config and lock paths derive from `APM_CONFIG_DIR` and default to `~/.config/apm`
- Runtime scope may be global or project-local
- Current defaults are visible with `apm config`

Relevant config/runtime logic lives in:

- [`lib/shell/config.shlib`](lib/shell/config.shlib)
- [`lib/shell/locks.shlib`](lib/shell/locks.shlib)

## Safety Rules

- Always acquire locks before mutating config or canonical databases
- Use staging directories for imports and pull-style operations
- Back up before destructive replacement
- Never silently replace canonical data with runtime data

Lock files live under:

- `${APM_CONFIG_DIR}/locks/`

Backups for destructive replacement should be preserved rather than discarded.

## Exit Codes

- `0`: success
- `1`: diff or validation failure
- `2`: operational error
- `3`: dependency missing
- `4`: lock failure

## Dependencies

Required:

- `bash`
- `python3`
- `PyYAML`

If `apm` fails with:

```text
PyYAML is required but not installed
```

install it with:

```bash
pip3 install pyyaml
```

## Architectural Conventions

- Thin shell, structured Python helpers
- JSON-only Python output for shell consumption
- Manifest-centered state calculations
- No ad hoc YAML parsing in shell
- Use UI helpers from [`lib/shell/ui.shlib`](lib/shell/ui.shlib)

## Canonical Agent Rules

- Canonical agent ID is the folder name
- ID pattern: `^[a-z0-9][a-z0-9-]*$`
- Never use platform alias as canonical ID

Active body resolution order for agents:

1. `instructions/<id>.<platform-alias>@latest.md`
2. `instructions/<id>@latest.md`
3. `instructions/<id>_latest.md`
4. root `<id>.md` body

Platform aliases:

- `claude-code -> cc`
- `cursor -> crs`
- `gemini -> gmn`
- `codex -> cdx`
- `generic -> gen`

Installed agent runtime files must include:

- `apm.id`
- `apm.platform`
- `apm.installed-from`
- `apm.installed-at`

## Canonical Skill Rules

- Canonical skill ID is the folder name that directly contains `SKILL.md`
- `apm` supports two layouts in `SKILLS_DB`:
  1. **Direct**: `skills_db/<skill-id>/SKILL.md` — single skill, registered directly
  2. **Repo**: `skills_db/<repo>/skills/<skill-id>/SKILL.md` — multiple skills under one repo entry; all sub-skills are auto-discovered and individually installable by ID
- When a repo has multiple sub-skills, register the repo once in `skills_db`; do not create individual symlinks for each sub-skill
- Runtime skill installs should normally be symlinks from platform runtime dir back to canonical `SKILLS_DB`

For skills:

- `ready`: canonical skill exists but is not linked for the selected runtime
- `linked`: runtime symlink correctly points to canonical skill dir
- `outdated`: runtime exists but is wrong, stale, or not a managed symlink
- `no-deploy`: not deployable for the selected platform

## Main Commands

### Setup and config

```bash
apm setup
apm init [--platform <name>]
apm config
apm version
```

Use `apm setup` to change defaults.
Use `apm config` to inspect resolved mode, platform, runtime dir, db paths, and scope.

### Discovery

```bash
apm list
apm list <query>
apm find <query>
apm status
apm check
```

Useful skill views:

```bash
apm --mode skills --platform claude-code list
apm --mode skills --platform claude-code status
apm --mode skills --platform agents-dir list
```

### Validation

```bash
apm validate
apm validate <id>
```

Validation is primarily for agents mode.

### Install, remove, update

Agents:

```bash
apm install <id>
apm install --all
apm install --cat <name>
apm remove <id>
apm update
apm update <id>
```

Skills:

```bash
apm --mode skills --platform claude-code install <id>
apm --mode skills --platform claude-code install --all
apm --mode skills --platform claude-code remove <id>

# Multi-platform (comma-separated): installs to both platforms in one command
apm -s -p cc,agt install <id>
```

For skills, install should create a symlink to canonical `SKILLS_DB`. Comma-separated platforms (`-p cc,agt`) install to each platform sequentially.

### Diff

```bash
apm diff <id>
```

Useful in agents mode for library vs runtime comparisons.

### Import

```bash
apm import
apm import <id>
apm import --all
```

Use import when a runtime agent exists outside the canonical database.

### Agent links

```bash
apm link <id>
apm link <id> --as <alias>
apm unlink <id>
apm unlink <id> --all
apm links
apm links <id>
```

These are for agent runtime symlink tracking and management.

### GitHub

```bash
apm github connect
apm github status
apm github diff <id>
apm github push <id>
apm github pull <id>
```

Two supported backends:

- `monorepo`
- `per-agent`

Only use GitHub commands when the local canonical database is already correct.

### TUI

```bash
apm
apm tui
```

Current TUI status:

- Bash TUI is the default interactive path
- Python TUI is experimental
- TUI is for visualization and lightweight filtering
- Do not rely on TUI settings to persist mode/platform changes yet
- Use CLI commands or `apm setup` for actual config changes

## Recommended Operator Workflows

### Check whether a skill is correctly managed

```bash
apm --mode skills --platform claude-code list
apm --mode skills --platform claude-code status
```

If the skill should be installed, expect `linked`, not `ready`.

### Fix a skill runtime manually

1. Find the canonical skill path in `SKILLS_DB`
2. Back up the current runtime folder
3. Replace the runtime folder with a symlink to the canonical skill dir
4. Re-run `apm --mode skills --platform <platform> list`
5. Confirm the state is `linked`

### Bring an unmanaged skill into `apm`

1. Preserve the runtime copy
2. Create or import the canonical copy into `SKILLS_DB`
3. Replace the runtime folder with a symlink to that canonical copy
4. Verify with `apm --mode skills --platform <platform> status`

### Fix the user’s default experience

If the user expects bare `apm` to open on a given mode/platform, update config via:

```bash
apm setup
```

or edit:

- `~/.config/apm/config.sh`

## Development and Verification

After code changes:

```bash
bash -n apm
python3 -m py_compile lib/py/apm_python.py
```

Test suites:

```bash
bash tests/run_tests.sh
bash tests/test_config.sh
bash tests/test_runtime.sh
bash tests/test_import.sh
bash tests/test_safety.sh
bash tests/test_github.sh
bash tests/test_python_parse.sh
```

Also available:

```bash
make test
make lint
make check
```

Use `tests/fakeagents-db/` for manual GitHub sync and playground-style verification.

## Important References

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md)
- [`docs/AGENT_ENTRY_SCHEMA.md`](docs/AGENT_ENTRY_SCHEMA.md)
- [`docs/DATABASE_LIBRARY.md`](docs/DATABASE_LIBRARY.md)
- [`docs/bash_tui.md`](docs/bash_tui.md)

## Practical Guidance For Agents Working Here

- If the user asks whether something is installed for a platform, check that exact platform explicitly
- For skills, do not infer `linked` from config alone; inspect the runtime path against canonical `SKILLS_DB`
- If the user reports the TUI is misleading, verify with CLI commands first
- If runtime and database disagree, preserve data before changing symlinks
- If moving old guidance files or consolidating docs, keep the resulting `AGENTS.md` as the single authoritative operator guide
