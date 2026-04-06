# Agent Entry Schema: Library Metadata and Deploy

> **Note on terminology:** In most AI tools, "agent" refers to the tool's primary/default AI persona. The `agents/` directories (`~/.claude/agents/`, `~/.cursor/agents/`, etc.) hold **subagents** — specialized, named agents invoked for specific tasks. `apm` manages subagents only. Throughout this document, "agent" means a subagent entry in your library.

This document defines the recommended root frontmatter schema for agent entries in the local database.

Purpose:
- support Obsidian or similar database/preview tools
- preserve rich metadata about each agent
- separate local database metadata from platform-specific deploy metadata
- make agent entries easier to archive, browse, filter, and review over time

The root file is:

```text
<AGENTS_DB>/<id>/<id>.md
```

The root frontmatter is for the database.
The `deploy:` block inside it controls runtime installation output.

Important:
- most top-level fields in this document are suggestions for the database item/entity
- they are useful for archivability, filtering, categorization, history, and local review
- `apm` should preserve them, but should not use them to decide runtime install behavior
- the `deploy:` block is the part `apm` uses for platform-specific installation behavior

---

## 1. Principles

1. Root frontmatter is user-owned metadata first.
2. `apm` should preserve unknown fields.
3. Platform installation must depend on `deploy:` fields, not on general metadata fields.
4. Metadata should support local review of lifecycle, history, and sync status.
5. Treat most non-`deploy` fields as library metadata suggestions, not runtime control fields.

---

## 2. Recommended Frontmatter

```yaml
---
id: git-mentor
name: GIT MENTOR - Git Workflow Coach
description: Helps manage git workflows, branches, rebases, and review flows.
tags: [git, devtools, workflow]
category: devtools

status: Published
ver-stat: Stable
ver-num: 4.1
platform: claude-code
lang: en

avatar: "[[git-mentor.png]]"
created: 2026-04-04
updated: 2026-04-04
origin: claude-import

github:
  enabled: true
  repo: git-mentor
  branch: main
  visibility: private

deploy:
  agents-dir:
    name: git-mentor
    description: Use for git workflows, branch strategy, rebases, merges, and PR hygiene.
    tags: [git, devtools]
    applyTo: ["**/*.md", ".github/**"]
  claude-code:
    name: git-mentor
    description: Use for git workflows, branch strategy, rebases, merges, and PR hygiene.
    model: claude-sonnet-4-6
    tools: [Read, Write, Bash, Glob]
  cursor:
    enabled: false
---
```

---

## 3. Field Reference

### Core Identity

| Field | Required | Type | Notes |
|------|----------|------|------|
| `id` | recommended | string | should match folder name |
| `name` | yes | string | display name for humans |
| `description` | yes | string | concise summary |
| `tags` | no | list | used for browsing/filtering |
| `category` | no | string | group name for `apm install --cat <name>` (alias: `group`) |

### Lifecycle

| Field | Required | Type | Notes |
|------|----------|------|------|
| `status` | recommended | string | workflow status such as `progress`, `Published`, `Archived` |
| `ver-stat` | recommended | string | lifecycle maturity such as `Prototype`, `Stable`, `Deprecated` |
| `ver-num` | recommended | string or number | current version number |
| `platform` | no | string | primary platform or current main target |
| `lang` | no | string | language such as `en`, `it`, `en/it` |

### Assets and History

| Field | Required | Type | Notes |
|------|----------|------|------|
| `avatar` | no | string | Obsidian-style asset reference |
| `created` | no | date | initial creation date |
| `updated` | no | date | latest significant update date |
| `origin` | no | string | e.g. `manual`, `claude-import`, `github-pull` |

### GitHub

| Field | Required | Type | Notes |
|------|----------|------|------|
| `github.enabled` | no | boolean | whether this agent should sync to GitHub |
| `github.repo` | no | string | repo name, defaults to canonical ID |
| `github.branch` | no | string | repo branch, defaults to global config |
| `github.visibility` | no | string | desired creation default like `private` or `public` |

### Deploy

`deploy:` is the platform-specific install contract.

Each platform block may include:

| Field | Platforms | Type | Notes |
|-------|-----------|------|-------|
| `name` | all | string | runtime filename and slash-command name |
| `description` | all | string | shown to the AI for auto-trigger decisions |
| `model` | all | string | e.g. `claude-sonnet-4-6`; `inherit` for Cursor/agents-dir |
| `tools` | claude-code, codex, gemini | list | tool permissions e.g. `[Read, Write, Bash]` |
| `applyTo` | agents-dir, codex, gemini | list | file glob scoping e.g. `["**/*.py"]` (alias: `paths`) |
| `tags` | agents-dir, codex | list | categorization / indexing |
| `readonly` | cursor | boolean | restrict write permissions (default: `false`) |
| `is_background` | cursor | boolean | run without blocking parent agent (default: `false`) |
| `enabled` | all | boolean | set `false` to disable this platform without deleting the block |

`applyTo` / `paths` and `tags` are part of the cross-tool generic frontmatter subset (see §5).

---

## 5. Generic Cross-Tool Frontmatter (agents-dir)

When deploying to `agents-dir` (`~/.agents/`), agents are read by multiple tools (Codex, Gemini, Cursor, VS Code Copilot). Use the minimal cross-tool subset for broadest compatibility:

```yaml
---
name: test-runner
description: Runs unit tests and reports failures with fix suggestions.
tags: [testing, python]
applyTo: ["**/*.py", "tests/**"]
model: auto
---
```

This subset maps across tools as follows:

| Field | Claude Code | Codex | Gemini | Cursor | Windsurf |
|-------|-------------|-------|--------|--------|----------|
| `name` | slash-command | identifier | identifier | slash-command | identifier |
| `description` | auto-trigger | indexing | indexing | auto-trigger | auto-trigger |
| `applyTo` | `paths` glob | `applyTo` glob | `applyTo` glob | glob match | glob match |
| `tags` | — | indexing | — | — | — |
| `model` | optional | optional | preferred | optional | optional |

For agents targeting a specific platform only, use the full `deploy.<platform>` block instead.

**agents-dir fallback behavior:** when `apm install --platform agents-dir` is run and no `deploy.agents-dir` block exists, apm falls back to the first enabled deploy block found. To explicitly define agents-dir output, add:

```yaml
deploy:
  agents-dir:
    name: test-runner
    description: Runs unit tests.
    applyTo: ["**/*.py"]
    tags: [testing]
  claude-code:
    name: test-runner
    description: Runs unit tests and reports failures with fix suggestions.
    model: claude-sonnet-4-6
    tools: [Read, Bash]
```

---

## 4. Ownership Rules

### User-Owned Fields

These should be preserved exactly when possible:
- `name`
- `description`
- `tags`
- `status`
- `ver-stat`
- `ver-num`
- `platform`
- `lang`
- `avatar`
- `created`
- `updated`
- `origin`
- `github`
- unknown custom fields

### `apm`-Managed or `apm`-Assisted Fields

`apm` may set or update these during import/sync flows:
- `id`
- `updated`
- `origin`
- `github` defaults when creating repo-linked entries
- `deploy` block derived from runtime import or preserved during sync

`apm` should never drop unrelated custom fields just because it does not understand them.

---

## 5. Import Guidance

When importing from Claude runtime:
- copy runtime body into `instructions/<id>@latest.md`
- derive `deploy.claude-code` from runtime frontmatter
- create minimal root metadata
- set `origin: claude-import`
- set `updated` to import date

Suggested import defaults:

```yaml
status: progress
ver-stat: Imported
ver-num: 1
platform: claude-code
origin: claude-import
```

---

## 6. Notes

- This document is the metadata reference, not the full tool behavior spec.
- If the metadata model evolves, update this document first, then align `../CLAUDE.md` and `WORKFLOWS.md`.
