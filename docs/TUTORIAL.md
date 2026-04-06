# apm Tutorial

`apm` is a local-first CLI for managing AI agent prompt files.

For normal users, the mental model is simple:

1. Your local agent database is the master copy.
2. `apm` installs agents from that database into tools like Claude Code.
3. `apm` can also import unmanaged runtime agents back into your database.
4. GitHub sync is optional and acts as backup/distribution, not the source of truth.

> **Terminology Note:** In the context of most AI CLI tools (like Claude Code), the word "agent" often refers to the **primary agent** — the default persona you interact with when you start the tool. The individual files managed by `apm` (and stored in the `agents/` directory of those tools) are technically **subagents** that you call upon for specific tasks. When we say "installing an agent" in `apm`, we are typically installing one of these specialized subagents.

This tutorial walks through the normal user journey.

## 1. Install `apm`

From the repo root:

```bash
bash install.sh
```

This:
- checks required dependencies
- links `apm` into `~/.local/bin/apm` or `~/bin/apm`
- tells you if your PATH needs updating

If needed, check dependencies only:

```bash
bash install.sh --check
```

Requirements:
- `bash`
- `python3`
- `PyYAML`
- `git` only if you want GitHub sync

## 2. Run First-Time Setup

Start the tool:

```bash
apm setup
```

The setup wizard walks through:

**1. Database path** — where your local agent library lives (default: `~/agents_db`).

**2. Default platform** — choose from a numbered menu:
```
  1) claude-code (default)
  2) cursor
  3) codex
  4) gemini
  5) generic
```

**3. GitHub sync** (optional) — if you enable it:
```
  1) monorepo  — all agents in one repo, each in a subdirectory (default)
  2) per-agent — each agent has its own repo
```
Then provide: GitHub owner/org, repo name (monorepo mode), default branch.

The config is saved to:

```text
~/.config/apm/config.sh
```

If you run `apm` with no config, it will guide you into setup automatically.

## 3. Understand the Database Layout

Your local database is a folder with one subfolder per agent:

```text
agents_db/
  git-mentor/
    git-mentor.md                  # root file: frontmatter + deploy config + body
    instructions/                  # optional — only needed for platform-specific bodies
      git-mentor@latest.md         # generic active body
      git-mentor.cc@latest.md      # claude-code-specific body (overrides generic)
    versions/                      # backups/snapshots created by apm
```

Key points:
- `git-mentor/` — the folder name is the canonical agent ID
- `git-mentor.md` — the root file doubles as database entry and deploy source; for most agents this is the only file you need
- `instructions/` — optional; use when you need different instruction bodies per platform
- `versions/` — apm writes backups here before destructive changes

This database is your source of truth.

## 4. See What You Have

Use:

```bash
apm status
apm list
```

`status` shows counts by state (color-coded in terminal).
`list` shows every agent with its sync state and category (if set).

Sync states:

| Symbol | State | Meaning |
|--------|-------|---------|
| `✓` | in-sync | Runtime matches library |
| `~` | outdated | Runtime installed but behind library |
| `○` | ready | In library, not yet installed |
| `!` | unmanaged | In runtime but not in library — importable |
| `?` | orphan | Has apm.id but library entry missing |
| `-` | no-deploy | No deploy config for current platform |
| `x` | collision | Canonical ID conflict |

To see agents you can import from your Claude runtime:

```bash
apm list
```

Any `!` (unmanaged) entry is in your Claude runtime but not yet in your library.

## 5. Install Agents

Install one agent:

```bash
apm install git-mentor
```

Install several at once:

```bash
apm install git-mentor code-reviewer sql-pro
```

Install all ready or outdated agents:

```bash
apm install --all
```

Install all agents in a category (requires `category:` in frontmatter):

```bash
apm install --cat devtools
```

Preview any install without writing files:

```bash
apm --dry-run install git-mentor
apm --dry-run install --all
apm --dry-run install --cat devtools
```

Installed files go to the platform runtime dir, e.g. `~/.claude/agents/` for claude-code.

## 6. Check Whether Runtime Matches the Library

After installation:

```bash
apm diff git-mentor
```

If the runtime file matches the canonical library entry, it will report `in-sync`.

If you edited the runtime file manually, `apm diff` will show drift. The library still remains canonical.

## 7. Update Runtime from the Library

If you changed the canonical agent in the database and want runtime to catch up:

```bash
apm update
```

That reinstalls all `outdated` or `ready` agents.

To update one agent:

```bash
apm update git-mentor
```

To preview:

```bash
apm --dry-run update
```

## 8. Remove an Installed Runtime Agent

To remove only the runtime file, without touching the library:

```bash
apm remove git-mentor
```

This deletes the installed Claude runtime file but keeps the canonical database entry.

## 9. Import Existing Claude Agents into the Database

If you already have agents in `~/.claude/agents/` that are not managed by `apm`, you can import them.

**Find importable agents:**

```bash
apm list
```

Any entry marked `!` (unmanaged) is in your runtime but not in your library.

**Pick interactively** (numbered menu of all untracked agents):

```bash
apm import
```

**Import a specific agent by ID:**

```bash
apm import my-agent
```

**Import everything untracked at once:**

```bash
apm import --all
```

**Import flow for each agent:**
1. `apm` analyzes the runtime file and detects the best mode:
   - `import-new` — no library entry exists, create one
   - `import-merge` — library entry exists, merge runtime content in
   - `link-existing` — library entry exists, keep library canonical and reinstall from it
2. A draft is staged under `_imports/`
3. A diff is shown when relevant
4. You confirm before anything is written to the library
5. If a library entry already exists, a backup is created before it is replaced

To skip all confirmations:

```bash
apm --force import --all
```

## 10. Use GitHub as Backup or Distribution

GitHub sync is optional. The local library is always the source of truth — GitHub is backup/distribution.

**Connect GitHub:**

```bash
apm github connect
```

The wizard asks for:
- **Mode**: `monorepo` (all agents in one repo, each in a subdirectory) or `per-agent` (each agent gets its own repo)
- **Owner/org**: your GitHub username or org
- **Repo name**: monorepo name (monorepo mode only)
- **Default branch**: defaults to `main`

**Check sync state:**

```bash
apm github status
```

States: `✓` in-sync, `~` out-of-sync, `○` not-pushed yet.

**Push to GitHub:**

```bash
apm github push git-mentor      # push one agent
apm github push --all           # push everything
```

**Pull from GitHub** (staged — shows diff, asks before applying):

```bash
apm github pull git-mentor      # pull one agent
apm github pull --all           # pull all
```

**Diff library vs GitHub:**

```bash
apm github diff git-mentor
```

The normal flow is always local → GitHub. Pull is for recovery or multi-machine workflows.

## 11. Use Global Flags When Needed

You can override config for one command:

```bash
apm --db ~/my-agents status
apm --platform claude-code list
apm --dry-run install git-mentor
apm --json status
apm --force install --all
```

Useful flags:
- `--db <path>`
- `--platform <name>`
- `--dry-run`
- `--json`
- `--force`

## 12. Use Interactive Mode

Run `apm` with no command:

```bash
apm
```

That opens a minimal terminal dashboard and REPL-style prompt.

Useful interactive commands:
- `list`
- `status`
- `diff <id>`
- `install <id>`, `install --all`, `install --cat <name>`
- `remove <id>`
- `update [id]`
- `import [id]`
- `validate [id]`
- `github <subcommand>`
- `setup`
- `quit`

## 13. Safe Daily Workflow

A good normal-user routine looks like this:

```bash
apm status                       # see counts by state
apm list                         # see per-agent state + category
apm diff git-mentor              # check what changed
apm install git-mentor           # install one agent
apm install --cat devtools       # install a whole category
apm update                       # catch up all outdated agents
apm github push --all            # back up to GitHub
```

If you have pre-existing Claude agents not yet in your library:

```bash
apm list                         # spot the ! (unmanaged) entries
apm import                       # interactive picker
apm import --all                 # import everything at once
apm validate                     # verify library is clean
apm install --all                # install everything ready
```

## 14. Safe Playground Workflow

This repo includes a throwaway example database:

```text
tests/fakeagents-db/
```

You can test `apm` against it without risking your real database.

Example (run from the repo root):

```bash
mkdir -p /tmp/fake-claude-agents

CLAUDE_AGENTS=/tmp/fake-claude-agents \
apm --db "$(pwd)/tests/fakeagents-db" --platform claude-code list

CLAUDE_AGENTS=/tmp/fake-claude-agents \
apm --db "$(pwd)/tests/fakeagents-db" --platform claude-code install gino

CLAUDE_AGENTS=/tmp/fake-claude-agents \
apm --db "$(pwd)/tests/fakeagents-db" --platform claude-code diff gino
```

That is the safest way to learn the tool before pointing it at your real database or real Claude runtime.

## 15. When Something Goes Wrong

Useful checks:

```bash
apm validate
apm status
apm diff <id>
bash install.sh --check
```

Common issues:
- missing `python3`
- missing `PyYAML`
- wrong database path
- wrong platform
- runtime file manually edited
- GitHub not configured

## 16. Related Docs

- [../README.md](../README.md) — quick overview
- [WORKFLOWS.md](WORKFLOWS.md) — usability Q&A and edge cases
- [ARCHITECTURE.md](ARCHITECTURE.md) — module boundaries and data flow
- [AGENT_ENTRY_SCHEMA.md](AGENT_ENTRY_SCHEMA.md) — library metadata and deploy schema reference
- [DATABASE_LIBRARY.md](DATABASE_LIBRARY.md) — canonical database layout guide
- [../_archive/](../_archive/) — design specs and historical documents
