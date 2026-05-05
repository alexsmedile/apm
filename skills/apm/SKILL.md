---
name: apm
description: |
  Use apm to manage AI agents and skills. Trigger on: "install skill X", "install agent X",
  "remove skill X", "uninstall agent X", "list skills", "list agents", "import agent",
  "update agent", "check agent status", "scan skills", "find duplicate skills",
  "what skills are installed", "sync agent to GitHub", "add the X skill", "enable skill X",
  "add the X agent", or any request to install, remove, update, scan, or manage agents/skills.
  Also use to repair broken symlinks, register tool-embedded skills, or run apm commands.
allowed-tools:
  - Bash(~/.local/bin/apm *)
  - Bash(ls *)
  - Bash(find *)
  - Bash(ln *)
  - Bash(pwd)
  - Read
---

# apm

`apm` is a local-first package manager for AI agents and skills.
CLI path: `~/.local/bin/apm`

## Quick reference — flag syntax

```
apm [flags] <command> [args]

Key flags:
  -s / --skills          Skills mode
  -a / --agents          Agents mode
  -p / --platform <x>    Platform: claude-code (cc), cursor (crs), codex (cdx),
                         gemini (gmn), windsurf (wds), continue (cnt),
                         agents-dir (agt), generic (gen)
  -j / --json            JSON output
  -f / --force           Skip confirmations
  --dry-run              Preview without writing
  --db <path>            Override library path (skills_db in -s mode, agents_db in -a mode)
  --cwd <path>           Project-scoped install rooted here

Positional shortcuts:
  apm skills <cmd>       same as apm -s <cmd>
  apm agents <cmd>       same as apm -a <cmd>
```

## Determine intent

Identify three things from the user's request:
1. **Mode**: skill or agent?
2. **Action**: install, remove, list, status, import, update, scan, find, validate, github?
3. **Scope**: global or project-local? (skills installs only)

If the user says "skill" or "skills" → use `-s` flag throughout.
If the user says "agent" or "agents" → use `-a` flag throughout.
If ambiguous → ask once, then proceed.

**Scope detection for skills installs:**

`apm` scope-detects from cwd — if a `.claude/` dir is present it installs project-local, otherwise global. This matches user intent *most* of the time, but not always. Before running install, resolve scope explicitly:

| Context | Expected scope | Flag to use |
|---|---|---|
| User is in a project dir and says "install for this project" | project-local | *(none, let apm detect)* |
| User is in a project dir but says "install globally" or "for all projects" | global | `--global` |
| User is in home dir / no project context | global | *(none, let apm detect)* |
| Ambiguous — in a project dir, intent unclear | **ask** | — |

When the user is inside a project directory and their intent isn't explicit, ask: *"Install globally (available in all projects) or just for this project?"* Then apply `--global` or omit it accordingly.

---

## SKILLS

### List / discover

```bash
# See what's installed
apm -s -p cc list

# Search library
apm -s find <query>

# Status overview
apm -s status
```

### Install a skill

**Step 1 — check if skill is in the library:**
```bash
apm -s find <name>
```

- If found (state: `ready`, `outdated`, `linked`) → install directly (Step 2).
- If NOT found → resolve tool-embedded skill first (Step 3).

**Step 2 — install:**
```bash
# Global (explicit — use when in a project dir to avoid project-scoped install):
apm -s --global install <skill-id>

# Project-local (explicit):
apm -s --cwd /absolute/path install <skill-id>
apm -s --cwd . install <skill-id>

# Scope auto-detected from cwd (safe only when intent is unambiguous):
apm -s install <skill-id>

# Multiple at once:
apm -s install <id1> <id2> <id3>

# All ready/outdated:
apm -s install --all
```

**Step 3 — register tool-embedded skill first:**

First check if the repo is already in skills_db with a `skills/` subfolder — if so, sub-skills are auto-discovered and you can install directly by ID without any extra steps:
```bash
apm -s find <skill-name>
```

If found, go straight to Step 2. Only proceed below if the skill is genuinely not in skills_db yet.

Locate the SKILL.md in `~/code/tools/`:
```bash
find ~/code/tools -name "SKILL.md" | xargs grep -l "name:.*<skill-name>" 2>/dev/null
# or by tool name:
find ~/code/tools/<tool-name> -name "SKILL.md" 2>/dev/null
```

Decide what to register — the symlink target depends on the layout:

| Layout | Example | Symlink target | Notes |
|---|---|---|---|
| Root SKILL.md | `tools/browser-harness/SKILL.md` | `tools/browser-harness/` | single skill, register directly |
| Repo with sub-skills | `tools/caveman/skills/skill-a/SKILL.md` | `tools/caveman/` | register the whole repo; all sub-skills auto-discovered |
| Named subdir (one skill) | `tools/ghostlink/skills/ghostlink/SKILL.md` | `tools/ghostlink/skills/ghostlink/` | register just that skill if you don't want the others |

**Show the user the proposed registration before writing:**
> "Found SKILL.md at `<path>`. Will register as `skills_db/<skill-name>` → `<tool-path>`. Proceed?"

Then register:
```bash
ln -s /absolute/path/to/skill/dir ~/vault/data/skills_db/<skill-name>
```

Then install via `apm -s install <skill-id>`.

**Step 4 — verify:**
```bash
ls -la ~/.claude/skills/<skill-id>
```

Expected chain: `~/.claude/skills/<name>` → `skills_db/<name>` → `~/code/tools/<tool>/…`

### Remove a skill
```bash
apm -s remove <skill-id>
```

### Scan for unmanaged skills
```bash
# Scan default dirs (~/code/tools):
apm -s scan

# Scan specific dirs:
apm -s scan --dir ~/code/tools --dir ~/projects

# Convert managed-copy entries to symlinks (with backup):
apm -s scan autofix
apm -s scan autofix --dry-run   # preview first
apm -s scan autofix -f          # skip confirmations
```

States reported by scan: `unmanaged`, `managed-copy`, `managed-symlink`.

### Find duplicate skills
```bash
apm -s duplicates
```
Finds skills_db entries that are content-identical or copies of symlinked sources.

---

## AGENTS

### List / discover

```bash
# List all agents (default platform from config):
apm -a list

# List for a specific platform:
apm -a -p cc list

# Search library:
apm -a find <query>

# Status overview:
apm -a status
```

### Install an agent

```bash
# Install one agent (installs to default platforms from config):
apm -a install <agent-id>

# Override platform for this run:
apm -a -p cc install <agent-id>

# Multiple platforms:
apm -a -p cc,agt install <agent-id>

# Install all ready/outdated:
apm -a install --all

# Install a category:
apm -a install --cat <category-name>
```

### Remove an agent
```bash
apm -a -p cc remove <agent-id>
```

### Update agents
```bash
# Update all outdated:
apm -a update

# Update one:
apm -a update <agent-id>
```

### Import an unmanaged agent

Use when an agent file exists in the runtime dir but isn't tracked in agents_db:
```bash
apm -a import <agent-id>
apm -a import --all
```

### Validate
```bash
apm -a validate <agent-id>
apm -a validate           # validate all
```

### Diff (library vs runtime)
```bash
apm -a diff <agent-id>
```

### GitHub sync
```bash
apm -a github status
apm -a github push <agent-id>
apm -a github pull <agent-id>
apm -a github diff <agent-id>
```

---

## Config and setup

```bash
apm config          # show resolved config (mode, platform, paths, defaults)
apm setup           # interactive wizard to change defaults
```

---

## Edge cases

| Situation | Action |
|---|---|
| Skill already linked | Report already installed; show symlink chain |
| Broken/outdated symlink | `apm -s install <id>` repairs it |
| Not in skills_db, not in tools | Tell user; suggest `apm -s list` to browse |
| Vague name | Run `apm -s find <query>`, show options, confirm before installing |
| Exact ID known | Skip find, go straight to install |
| Multiple skills requested | Batch install: `apm -s install id1 id2 id3` |
| Tool-embedded skill | Register to skills_db first (symlink), then install |
| Ambiguous mode (skill or agent?) | Ask once, then proceed |
