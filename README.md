# apm — Agent Package Manager

A local-first CLI package manager for AI agent prompt files.

`apm` keeps a canonical library of agent definitions and manages their installation into agentic coding CLI tools (e.g. Claude Code, Codex, Gemini, etc.). It handles install, diff, update, import, and optional GitHub sync — all with atomic writes, locking, and backups.

## Install

```bash
git clone https://github.com/alexsmedile/apm.git
cd apm
bash install.sh          # links apm into ~/.local/bin
apm setup                # configure library path, platform, optional GitHub
```

**Requirements:**
- bash 4+
- python3 + PyYAML (`pip3 install pyyaml`)
- git (optional, for GitHub sync)

## Quickstart

```bash
apm list                 # show all agents and sync state
apm install git-mentor   # install agent to runtime (~/.claude/agents/)
apm diff git-mentor      # compare library vs runtime
apm update               # reinstall all outdated agents
apm import               # import unmanaged runtime agents into library
```

## Library layout

```
agents_db/
  agent-mentor/
    agent-mentor.md
    # root file (personal frontmatter + standard deploy config + body with instructions)
    instructions/                     # default deploy directory
      agent-mentor@latest.md          # generic active body (optional)
      agent-mentor.cc@latest.md       # claude-code-specific body (optional)
    versions/                         # snapshots, backups and history
```

Body resolution order: `<id>.<platform-alias>@latest.md` → `<id>@latest.md` → `<id>_latest.md` (legacy) → root file body. Most agents use the root file only.

Platform aliases: `claude-code→cc`, `cursor→crs`, `gemini→gmn`, `codex→cdx`, `generic→gen`

### Categories

Add `category: <name>` (or `group: <name>`) to any agent's frontmatter to group it:

```yaml
category: devtools
```

Then install the whole group at once:

```bash
apm install --cat devtools
```

`apm list` shows the category column when any agents have one set.

## GitHub sync

Two modes:
- **monorepo** — all agents in one repo, each in a subdirectory
- **per-agent** — each agent has its own repo

```bash
apm github connect           # configure mode, owner, repo
apm github push --all        # push everything
apm github pull git-mentor   # pull one agent (staged by default)
```

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Interactive config wizard |
| `config` | Show resolved configuration |
| `list` | List agents with sync state and category |
| `status` | Count summary by state |
| `validate [id]` | Validate agent(s) in library |
| `diff <id>` | Show library vs runtime diff |
| `install <id> [id…]` | Install one or more agents by ID |
| `install --all` | Install every ready/outdated agent |
| `install --cat <name>` | Install all agents in a category |
| `remove <id>` | Remove agent from runtime |
| `update [id]` | Reinstall outdated agent(s) — omit for all |
| `import` | Pick from unmanaged runtime agents (interactive) |
| `import [id]` | Import specific agent, or `--all` for everything |
| `github connect` | Configure GitHub sync |
| `github status` | Show library vs GitHub sync state |
| `github push <id>` | Push agent to GitHub, or `--all` for everything |
| `github pull <id>` | Pull agent from GitHub, or `--all` for everything |
| `github diff <id>` | Diff library vs GitHub |
| _(no args)_ | Interactive REPL dashboard |

### Global flags

```
--db <path>        Override library path
--platform <name>  Override platform (claude-code, cursor, codex, gemini, generic)
--json             Machine-readable JSON output
--dry-run          Preview without writing
--force            Skip confirmation prompts
```

## Sync states

| Symbol | State | Meaning |
|--------|-------|---------|
| `✓` | in-sync | Runtime matches library |
| `~` | outdated | Runtime installed but behind library |
| `○` | ready | In library, not yet installed |
| `!` | unmanaged | Runtime file with no library entry |
| `?` | orphan | Has apm.id but library entry missing |
| `-` | no-deploy | No deploy config for current platform |
| `x` | collision | Canonical ID conflict |

## Docs

- [`docs/TUTORIAL.md`](docs/TUTORIAL.md) — practical getting-started guide for normal users
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module boundaries and data flow
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md) — usability Q&A and edge cases
- [`docs/AGENT_FRONTMATTER.md`](docs/AGENT_FRONTMATTER.md) — frontmatter schema reference
- [`docs/DATABASE_LIBRARY.md`](docs/DATABASE_LIBRARY.md) — canonical database layout guide
- [`_archive/`](_archive/) — design specs and historical documents

## Playground

A safe, resettable test database lives in `tests/fakeagents-db/` with two fake agents (`gino`, `pino`) synced to a private GitHub monorepo at `<user>/fakeagents-db`.

```bash
# One-time config setup (recreate after reboot)
mkdir -p /tmp/apm-fake-config && cat > /tmp/apm-fake-config/config.sh <<EOF
AGENTS_DB="$(pwd)/tests/fakeagents-db"
APM_PLATFORM="claude-code"
APM_GITHUB_MODE="monorepo"
APM_GITHUB_OWNER="<user>"
APM_GITHUB_MONOREPO="fakeagents-db"
APM_GITHUB_BRANCH="main"
EOF

# Session env
export AGENTS_DB="$(pwd)/tests/fakeagents-db"
export APM_CONFIG_DIR=/tmp/apm-fake-config
export CLAUDE_AGENTS=/tmp/fake-rt && mkdir -p \$CLAUDE_AGENTS

# Try it out
bash apm --platform claude-code list
bash apm --platform claude-code install gino
bash apm --platform claude-code github status

# Reset library to committed state
git checkout tests/fakeagents-db/
```

## Development

```bash
make test       # run all 9 test suites (~127 tests)
make lint       # static checks (bash -n, py_compile)
make install    # install to ~/.local/bin
make uninstall  # remove symlink
```

