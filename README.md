# apm — Agent Package Manager
_Write an agent once. Install it everywhere._

**A CLI package manager for AI agent prompt files.**

`apm` syncs your library of agent definitions and manages their installation into agentic coding tools (e.g. Claude Code, Codex, Gemini, etc.).

It handles: `install`, `diff`, `update`, `import`, and optional **GitHub sync** — all with atomic writes, locking, and backups.

<div align="center">

| **Works with** | <img src="https://img.shields.io/badge/Claude_Code-cc6b39?style=flat-square&logo=anthropic&logoColor=white" alt="Claude Code" /> | <img src="https://img.shields.io/badge/Codex-412991?style=flat-square&logo=openai&logoColor=white" alt="Codex" /> | <img src="https://img.shields.io/badge/Cursor-000000?style=flat-square&logo=cursor&logoColor=white" alt="Cursor" /> | <img src="https://img.shields.io/badge/Gemini-4285F4?style=flat-square&logo=google&logoColor=white" alt="Gemini" /> | <img src="https://img.shields.io/badge/Generic-6c757d?style=flat-square&logo=terminal&logoColor=white" alt="Generic" /> |
|---|:---:|:---:|:---:|:---:|:---:|

</div>

> This tool is under active development. It may contain bugs. Always back up your data.

## Features

<table>
<tr>
<td align="center" width="33%">
<h3>📚 One Library, All Tools</h3>
Define an agent once in your library. Install it to Claude Code, Codex, Cursor, or Gemini — with the right format for each.
</td>
<td align="center" width="33%">
<h3>🔄 Sync State Tracking</h3>
Always know what's installed, what's outdated, and what's drifted. <code>apm list</code> gives you a full picture at a glance.
</td>
<td align="center" width="33%">
<h3>📥 Import Agents</h3>
Already have agents scattered across tool directories? <code>apm import</code> brings them into your library with a single command.
</td>
</tr>
<tr>
<td align="center">
<h3>☁️ GitHub Sync</h3>
Back up and share your library via GitHub. Monorepo or per-agent mode. Push, pull, and diff from the CLI.
</td>
<td align="center">
<h3>🛡️ Safe by Default</h3>
Atomic writes, file locking, and automatic backups before every destructive operation. No silent overwrites.
</td>
<td align="center">
<h3>🗂️ Categories</h3>
Tag agents with a category and install entire groups at once. Keep your library organized as it grows.
</td>
</tr>
</table>

## Problems apm solves

| Without apm | With apm |
|---|---|
| ❌ You copy-paste the same agent prompt into Claude Code, Cursor, and Codex separately — and they drift apart over time. | ✅ One source of truth in your library. Install to any tool with one command. |
| ❌ You edit an agent directly in `~/.claude/agents/` and forget which version is canonical. | ✅ Library always wins. Runtime is treated as a deploy target, never the source. |
| ❌ You have no idea which installed agents are outdated or missing after switching machines. | ✅ `apm list` shows sync state for every agent — in-sync, outdated, ready, or unmanaged. |
| ❌ You accumulate random `.md` files in your agents directories with no record of where they came from. | ✅ Every installed file is stamped with `apm.id`, platform, and install timestamp. |
| ❌ Updating an agent means manually finding and overwriting files across multiple tools. | ✅ `apm update` reinstalls every outdated agent in one shot, with backups. |

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
apm link git-mentor      # symlink runtime file directly to split instructions
apm diff git-mentor      # compare library vs runtime
apm update               # reinstall all outdated agents
apm import               # import unmanaged runtime agents into library
```

## Library layout

`apm` supports different canonical layouts for agents and skills.

Agents:

```text
agents_db/
  agent-mentor/
    agent-mentor.md                  # required root file
    instructions/                    # optional
      agent-mentor@latest.md         # optional generic active body
      agent-mentor.cc@latest.md      # optional platform-specific body
    versions/                        # optional snapshots/backups/history
```

Agent rules:
- The canonical ID is the folder name.
- The required root file is `<id>/<id>.md`.
- `instructions/` is optional and keeps the current body split out of the root file.
- Body resolution order is `<id>.<platform-alias>@latest.md` → `<id>@latest.md` → `<id>_latest.md` (legacy) → root file body.

Skills:

Preferred monorepo-style layout:

```text
skills_db/
  repo-name/
    skills/
      browser-use/
        SKILL.md
      shadcn/
        SKILL.md
```

Fallback direct layout:

```text
skills_db/
  browser-use/
    SKILL.md
  shadcn/
    SKILL.md
```

Skill rules:
- `apm` prefers `skills_db/<repo>/skills/<skill>/SKILL.md`.
- If a top-level entry has no `skills/` folder, `apm` falls back to `skills_db/<skill>/SKILL.md`.
- The canonical skill ID is the skill folder name that directly contains `SKILL.md`.

Platform aliases: `claude-code→cc`, `cursor→crs`, `gemini→gmn`, `codex→cdx`, `generic→gen`

> **About the "agents".** In most AI tools, "agent" means the tool's primary AI persona, but the `agents/` directories (`~/.claude/agents/`, `~/.cursor/agents/`, etc.) actually hold **subagents** — specialized, named agents invoked for specific tasks. `apm` manages subagents only.

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

## Install target folders

Agents install targets:

| Platform | Global target | Project target |
|---|---|---|
| `claude-code` | `~/.claude/agents/` | `.claude/agents/` |
| `cursor` | `~/.cursor/agents/` | `.cursor/agents/` |
| `codex` | `~/.codex/agents/` | `.codex/agents/` |
| `gemini` | `~/.gemini/` | `.gemini/` |
| `windsurf` | `~/.windsurf/rules/` | `.windsurf/rules/` |
| `continue` | `~/.continue/rules/` | `.continue/rules/` |
| `agents-dir` | `~/.agents/` | `.agents/` |
| `generic` | `~/Desktop/agents-export/` | n/a |

Skills install targets:

| Platform | Global target | Project target | Behavior |
|---|---|---|---|
| `claude-code` | `~/.claude/skills/` | `.claude/skills/` | symlink skill dir |
| `codex` | `~/.codex/skills/` | `.codex/skills/` | symlink skill dir |
| `gemini` | `~/.gemini/skills/` | `.gemini/skills/` | symlink skill dir |
| `windsurf` | `~/.codeium/windsurf/skills/` | `.windsurf/skills/` | symlink skill dir |
| `agents-dir` | `~/.agents/skills/` | `.agents/skills/` | symlink skill dir |

Skills are not installable for `cursor`, `continue`, or `generic` in the current implementation.

## Install modes and direct symlinks

`apm` supports two different symlink-based workflows:

- `install` with `INSTALL_MODE=symlink`:
  `apm` writes the generated runtime file into `~/.agents/` and symlinks the tool-specific runtime path back to that managed file. This keeps frontmatter like `apm.id`, `installed-at`, and deploy metadata intact.
- `--mode skills install`:
  `apm` creates a directory symlink from the selected platform skill target back to the canonical skill folder in `SKILLS_DB`.
- `link` / `unlink`:
  `apm link <id>` creates a runtime symlink that points directly at the resolved split instruction body in your library. This is useful when you want runtime to follow the library body exactly without generating a runtime wrapper file.

Examples:

```bash
apm install git-mentor                     # normal copy install
INSTALL_MODE=symlink apm install git-mentor
apm --mode skills --platform claude-code install browser-use
apm link git-mentor
apm link git-mentor --as review-helper
apm links
apm unlink git-mentor --all
```

Notes:
- `link` resolves the active body using the normal platform precedence: `<id>.<platform>@latest.md`, then `<id>@latest.md`, then the root file body.
- If the split file does not exist yet, `apm link` can generate `instructions/<id>.<platform-alias>@latest.md` from the root body.
- `unlink` removes only tracked symlinks and refuses to delete regular files.
- Plain `unlink` targets the current scope. Use `--project`, `--global`, or `--all` to be explicit when needed.

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
| `install <id> [id…]` | Install agents, or in `--mode skills` create skill symlinks |
| `install --all` | Install every ready/outdated agent or skill |
| `install --cat <name>` | Install all agents in a category |
| `link <id>` | Symlink agent body directly into the runtime dir |
| `unlink <id>` | Remove tracked symlink(s) for an agent |
| `links [id]` | List tracked symlinks for one agent or all agents |
| `remove <id>` | Remove agent runtime file, or in `--mode skills` remove the skill symlink |
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
--install-mode     Override install mode (`copy` or `symlink`)
--json             Machine-readable JSON output
--dry-run          Preview without writing
--force            Skip confirmation prompts
```

## Sync states

| Symbol | State | Meaning |
|--------|-------|---------|
| `✓` | in-sync | Runtime matches library |
| `⤷` | linked | Runtime is a direct symlink to the active library body or skill dir |
| `⤸` | linked-outdated | Runtime is a symlink, but points to the wrong target |
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
- [`docs/AGENT_ENTRY_SCHEMA.md`](docs/AGENT_ENTRY_SCHEMA.md) — library metadata and deploy schema reference
- [`docs/DATABASE_LIBRARY.md`](docs/DATABASE_LIBRARY.md) — canonical database layout guide
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — version history
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — how to contribute

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
