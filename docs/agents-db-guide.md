# agents_db — Full Reference Guide

Complete documentation for the agents_db system: folder structure, frontmatter standard, versioning workflow, and GitHub sync.

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Folder Structure](#2-folder-structure)
3. [Frontmatter Standard](#3-frontmatter-standard)
4. [Instruction File Standard](#4-instruction-file-standard)
5. [Versioning Workflow](#5-versioning-workflow)
6. [Knowledge Files](#6-knowledge-files)
7. [Avatars](#7-avatars)
8. [Starters](#8-starters)
9. [GitHub Sync](#9-github-sync)
10. [Platform-Specific Notes](#10-platform-specific-notes)

---

## 1. Design Principles

**One folder, one agent.** The folder is the agent's canonical identity. Everything it needs — instructions, knowledge, history, avatar — lives inside.

**The root `.md` file is the index.** For most agents it holds the full instructions directly — this is the preferred pattern. For complex agents with platform-specific bodies, it holds only frontmatter and a pointer comment, with the body in `instructions/agent-name@latest.md` or `instructions/agent-name.<platform>@latest.md`. Either way, the root file is what Obsidian's database view reads.

**The template is the standard.** `_template/agent-name/` defines the structure every agent follows. When the template changes, existing agents are not retroactively updated — but new agents start from the new template.

**Version before you edit.** Never overwrite a version in place. Snapshot first, then change. The history is the value.

---

## 2. Folder Structure

### Complete scaffold

```
agent-name/
├── agent-name.md              ← ROOT: frontmatter + full instructions, or pointer to latest
├── avatar/
│   └── agent-name.png         ← Square PNG, min 256×256px
├── knowledge/
│   ├── topic.md               ← Reference docs the agent uses
│   └── knowledge-index.md     ← Optional: index of what's in this folder and why
├── starters/
│   └── starters.md            ← Cold-start prompts organized by use case
├── instructions/
│   ├── agent-name_v1.md            ← Archived version (read-only after saving)
│   ├── agent-name_v1.1.md          ← Minor revision
│   ├── agent-name@latest.md        ← Generic active body (optional)
│   └── agent-name.cc@latest.md     ← Platform-specific body, e.g. claude-code (optional)
└── versions/
    └── v1.0.0/
        ├── agent.md           ← Full snapshot at this milestone
        └── CHANGELOG.md       ← What changed, why, known limits
```

### What each folder is for

**`instructions/`** — rolling file-based version history. Every named version file (`_v1.md`, `_v1.1.md`) is a snapshot. `@latest.md` holds the current generic body; `.<platform-alias>@latest.md` holds a platform-specific override (e.g. `.cc@latest.md` for claude-code). Both are optional — most agents keep the full body in the root file.

**`versions/`** — explicit milestone snapshots. Use this for significant releases (first stable, major rewrites, platform launches). Each version gets a subfolder with a full `agent.md` snapshot and a `CHANGELOG.md` explaining the changes.

You don't need both for every agent. Simple agents: use just `instructions/`. Complex or evolving agents: use both.

**`knowledge/`** — supporting documents the agent references. Not deployed to the LLM automatically — they're uploaded manually (OpenAI file uploads) or referenced in the instructions (Claude documents tool). Include a `knowledge-index.md` if there are more than 3 files.

**`starters/`** — pre-written prompts that cold-start the agent. Write these for users who don't know what to type.

### Files that don't belong in root

Only `agent-name.md` and `avatar/` go in the root. Everything else in a subfolder. If you have extra `.md` files accumulating in root (old drafts, backup copies, experiments) — move them to `instructions/` with a version label, or delete.

---

## 3. Frontmatter Standard

Every root `agent-name.md` must have this frontmatter block. Instructions files (`@latest.md`, platform-specific variants) contain only the body — no frontmatter needed unless tracking version metadata:

```yaml
---
avatar: "[[agent-name.png]]"
name: AGENT NAME – Role Title
description: One-line tagline. What it does and for whom. Max 120 chars.
tags: [tag1, tag2, tag3]
platform: claude-code
ver-stat: Prototype
ver-num: 1
status: progress
lang: en
---
```

### Field reference

**`avatar`** — Obsidian wikilink to the PNG file. Must match the filename exactly.

**`name`** — Display name in format `PERSONA – Short Role Title`. Keep under 60 chars. Use UPPERCASE for the persona name.

**`description`** — One sentence. What it does and for whom. This appears in Obsidian's database card view — make it scannable. Max 120 chars.

**`tags`** — 2–5 lowercase tags. Use consistent vocabulary: prefer `scraping` over `web-scraping`, `copywriting` over `copy`.

**`platform`** — where this agent runs:
| Value | Platform |
|-------|----------|
| `claude-code` | Claude Code subagent (`~/.claude/agents/`) |
| `openai-gpt` | OpenAI Custom GPT |
| `claude-api` | Anthropic API system prompt |
| `n8n` | n8n workflow node |
| `generic` | platform-agnostic |

**`ver-stat`** — lifecycle state:
| Value | Meaning |
|-------|---------|
| `Prototype` | First draft, untested |
| `Experimental` | Being tested, may change |
| `Stable` | Tested and reliable |
| `Release Candidate` | Final checks before shipping |
| `Deprecated` | Retired, kept for reference |
| `Shell` | Placeholder, no instructions yet |

**`ver-num`** — version number. Use integers (`1`, `2`) for simple agents; semver (`1.0`, `1.1`, `2.0`) for agents with tracked minor revisions. The filename suffix must match: `agent-name_v1.md` → `ver-num: 1`.

**`status`** — workflow state:
| Value | Meaning |
|-------|---------|
| `progress` | Actively being built |
| `Published` | Live and in use |
| `On Hold` | Paused |
| `Archived` | Retired |
| `Shell` | Placeholder only |

**`lang`** — primary instruction language: `en`, `it`, `en/it` for bilingual.

### Version snapshot frontmatter

Archived versions in `instructions/` and `versions/` get additional fields:

```yaml
---
ver-num: 1
ver-stat: Stable
date: 2026-04-04
status: Archived
changelog: What this version introduced or changed. Why it was created.
name: AGENT NAME – Role Title
...
---
```

---

## 4. Instruction File Standard

### Section order

Use this order consistently. Omit sections that don't apply, but never reorder the ones you include.

```
# Agent Name — Role Title

[Opening: role + task + context. 2–4 sentences.]

## ROLE & MISSION
## SCOPE & BOUNDARIES
## TONE & VOICE
## CORE SKILLS
## INTERACTION RULES
## OUTPUT RULES
## FORMAT PREFERENCES
## BEHAVIOR EXTENSIONS     (optional: named modes)
## INPUTS REQUIRED         (optional: structured input specs)
## PROCESS                 (optional: step-by-step workflow)
## ANTI-PATTERNS
## SAFEGUARDS
## EXAMPLE OUTPUT
```

### Non-negotiable sections

These must exist in every agent that reaches `Stable`:

- **SCOPE & BOUNDARIES** — explicit in-scope / out-of-scope list + fallback for missing input
- **INTERACTION RULES** — if/then rules for vague input, missing input, off-scope requests
- **OUTPUT RULES** — Always / Never / Default format
- **ANTI-PATTERNS** — named wrong behaviors the agent must avoid
- **EXAMPLE OUTPUT** — at least one real example

### Writing rules summary

- Write to the agent, not about it. Use second person: "You are...", "Always...", "Never..."
- Tone rules must be behavioral, not adjectival. "Direct" → "One question per response. No filler phrases."
- Every required input needs a fallback. Define what the agent does when input is missing.
- Use `If [condition] → [action]` for all edge case rules.
- No emojis in section headers.

Full writing guide: `_template/agent-name/AGENTS.md`

---

## 5. Versioning Workflow

### When to version

| Change type | Action |
|-------------|--------|
| Typo fix, wording tweak, frontmatter update | Edit in place — no new version |
| New mode, new section, clarified rule | Bump `ver-num` minor (1.0 → 1.1) — edit `@latest` in place |
| Scope change, tone rewrite, structural overhaul | Bump major (1 → 2) — snapshot current first |
| Complete rewrite or platform migration | New major version — archive previous `@latest` as `_vX` |

### Step-by-step: minor update

1. Edit the active body (root file, `instructions/agent-name@latest.md`, or platform-specific variant) directly
2. Bump `ver-num` in the frontmatter (e.g., `1` → `1.1`)
3. Sync the root `agent-name.md` to match (or update its `ver-num` if it's a pointer file)

### Step-by-step: major update

1. Rename `instructions/agent-name@latest.md` → `instructions/agent-name_v1.md`
   - Add `status: Archived` and `changelog: [what this version was]` to its frontmatter
2. Create a new `instructions/agent-name@latest.md` with the new content
3. Set `ver-num: 2`, `ver-stat: Experimental` (update to `Stable` after testing)
4. Sync the root `agent-name.md`

### Step-by-step: milestone snapshot (versions/)

Use this for significant releases — first stable, major rewrites, platform launches.

1. Create `versions/vX.Y.Z/`
2. Copy the current active body into `versions/vX.Y.Z/agent.md`
3. Write `versions/vX.Y.Z/CHANGELOG.md`:
   - What changed
   - Why (the motivation — not just what, but why)
   - Known limitations at this version
   - What triggered the next iteration (fill in retroactively when you know)
4. Update `ver-stat` in the active body to `Stable` if not already done

### Example: evolved agent history

```
scrape-architect/
└── instructions/
    ├── scrape-architect_v1.md            ← ver-num: 1, status: Archived
    ├── scrape-architect_v1.1.md          ← ver-num: 1.1, status: Archived
    └── scrape-architect@latest.md        ← ver-num: 2, status: Published
versions/
    ├── v1.0.0/   ← first stable release
    └── v2.0.0/   ← major rewrite
```

### Rules

- `@latest.md` is always an exact copy of the current active instructions — never a stub or pointer
- Platform-specific variants (e.g. `.cc@latest.md`) override `@latest.md` for that platform
- Archived version files (`_v1.md`, `_v2.md`) are read-only after saving
- The root `agent-name.md` either holds the full instructions, or contains only frontmatter + a comment: `<!-- Active instructions: see instructions/agent-name@latest.md -->`
- Never delete old versions. Use `ver-stat: Deprecated` if an agent is retired.

---

## 6. Knowledge Files

Files in `knowledge/` are reference documents the agent uses. They are not automatically injected — they're uploaded manually (OpenAI) or provided via tool calls (Claude).

**Naming:** lowercase, hyphen-separated. Prefix with agent name if the filename might be ambiguous across agents.

**Formats:**
| Use case | Format |
|----------|--------|
| Guides, references, structured notes | `.md` |
| Raw source material | `.txt` |
| Structured data | `.json` or `.csv` |
| External research, examples | `.pdf` |

**Organization:** Keep flat unless there are more than 8 files. Then use subfolders: `md/`, `txt/`, `raw/`, `examples/`.

Always include a `knowledge-index.md` when there are 3 or more files — it tells the agent what each file is for and when to reference it.

---

## 7. Avatars

- Format: PNG, square (1:1), minimum 256×256px, preferred 512×512px
- Filename: `agent-name.png` — must match the folder name and the frontmatter `avatar` field
- One canonical avatar per agent. Alternates go in `avatar/` with suffix: `agent-name-2.png`
- The `avatar/` folder is excluded from Obsidian's database view by the `.base` config — don't put anything else in there

---

## 8. Starters

`starters/starters.md` contains pre-written prompts that cold-start the agent without requiring the user to know its capabilities.

**Format:**
```markdown
# Starters — Agent Name

## [Category]
**Starter 1:** "[Complete prompt, copy-paste ready]"
**Starter 2:** "[Another prompt for a common variant]"
```

**What makes a good starter:**
- Written as something a real user would actually send — no `[insert X]` placeholders
- Each starter triggers a meaningfully different path through the agent
- Cover at minimum: the core use case, an edge case, and a troubleshooting/diagnostic prompt
- Keep each prompt under 2 sentences

---

## 9. GitHub Sync

The `agents_db` folder can be maintained as a Git repository for backup, version control independent of Obsidian, and sharing across machines or collaborators.

### Initial setup

```bash
cd /path/to/vault/data/agents_db

# Initialize git repo
git init
git branch -M main

# Create .gitignore
cat > .gitignore << 'EOF'
.DS_Store
agents_db.base
*.tmp
.trash/
EOF

# Initial commit
git add .
git commit -m "init: agents_db initial snapshot"

# Connect to GitHub (create repo on GitHub first — private recommended)
git remote add origin https://github.com/your-username/agents-db.git
git push -u origin main
```

### What to include / exclude

**Include:**
- All `agent-name.md` root files (frontmatter + instructions)
- All `instructions/` version files
- All `versions/` snapshots and changelogs
- All `knowledge/` files
- All `starters/` files
- `_template/` and `_docs/`
- `README.md`

**Exclude (add to `.gitignore`):**
- `agents_db.base` — Obsidian-specific config, not useful on GitHub
- `.DS_Store`
- `avatar/` — binary files, add only if you want visual identity tracked
- Any file with private API keys, credentials, or sensitive data in knowledge files

### Push workflow

After creating or updating an agent:

```bash
cd /path/to/vault/data/agents_db

# See what changed
git status
git diff

# Stage and commit
git add agent-name/
git commit -m "feat(agent-name): add v1 stable release"

# Push
git push origin main
```

### Commit message convention

Use this format for clean history:

```
<type>(<agent-name>): <short description>

Types:
  feat      → new agent or major new capability
  update    → instruction improvement, new mode, revised scope
  fix       → corrected wrong behavior, patched gap
  docs      → README, starters, knowledge files only
  archive   → versioning / snapshotting only
  chore     → frontmatter, naming, structural cleanup
```

Examples:
```
feat(scrape-architect): add v1 stable release with 6-phase workflow
update(landino): add Quick Mode and Debug Mode behavior extensions
fix(god-cli): close scope gap — agent was handling off-topic requests
archive(aiden): snapshot v1.1 before major rewrite
docs(carobella): add starters and knowledge index
```

### Branch strategy (if collaborating)

For solo use, push directly to `main`. If multiple people are contributing:

```
main          ← stable, deployed agents only
dev           ← work in progress
agent/<name>  ← per-agent feature branches
```

Merge to `main` only when an agent reaches `ver-stat: Stable`.

### Keeping Obsidian and GitHub in sync

GitHub is the source of truth for version history. Obsidian is the working environment.

- Edit agents in Obsidian as normal
- Push to GitHub when you reach a meaningful checkpoint (new version, new agent, significant update)
- Pull on other machines before editing: `git pull origin main`
- Never edit directly on GitHub — always edit in Obsidian, push from terminal

---

## 10. Platform-Specific Notes

### Claude Code (`platform: claude-code`)

The production file lives at `~/.claude/agents/agent-name.md` (global) or `.claude/agents/agent-name.md` (project-scoped). The `agents_db` entry is the source of truth — keep them in sync manually or via a script.

Required frontmatter fields for Claude Code (different from vault frontmatter):
```yaml
---
name: agent-name
description: "Trigger description for Claude Code..."
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet
---
```

The vault root file uses vault frontmatter. Use `instructions/agent-name.cc@latest.md` for the Claude Code-specific body, or keep the full body in the root file and let `apm` install it directly. When pushing a new version, run `apm install <id>` or `apm update`.

### OpenAI Custom GPTs (`platform: openai-gpt`)

- Instruction field limit: ~32,000 characters
- Knowledge files are uploaded via the GPT builder UI
- Test cold-start behavior with your starters before publishing

### Claude API (`platform: claude-api`)

- Used as the `system` parameter in API calls
- Knowledge must be embedded inline or retrieved via tool calls — no file uploads
- Stay within model context limits (~200K tokens for Claude 3+)

### n8n (`platform: n8n`)

- Document expected input/output JSON schema in the agent file
- Use `knowledge/` to track external API dependencies
- Store node-specific prompt versions in `instructions/`

### Generic (`platform: generic`)

- Should work pasted into any LLM chat interface
- Avoid platform-specific references
- Test across at least 2 different models before marking `Stable`
