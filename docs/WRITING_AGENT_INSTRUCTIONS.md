# Writing Agent Instructions

This guide explains how to author an agent in an `apm` library, with emphasis on:

- the root `<id>.md` file
- the `deploy:` field
- the optional `instructions/` folder
- how `apm` decides which instruction body is active

## The Short Version

For most agents, one file is enough:

```text
agents_db/
  git-mentor/
    git-mentor.md
```

That root file usually contains:

1. frontmatter for metadata
2. a `deploy:` block for runtime-specific install settings
3. the default instruction body

If you need different instruction bodies per platform, add an `instructions/` folder.

## Recommended Agent Layout

```text
agents_db/
  git-mentor/
    git-mentor.md
    instructions/
      git-mentor@latest.md
      git-mentor.cc@latest.md
    versions/
```

Meaning:

- `git-mentor/` is the canonical agent ID
- `git-mentor.md` is the main database entry
- `instructions/` is optional and only needed for body overrides
- `versions/` is managed by `apm` for backups and snapshots

## The Root File

The root file lives at:

```text
<AGENTS_DB>/<id>/<id>.md
```

Example:

```md
---
id: git-mentor
name: GIT MENTOR
description: Helps manage git workflows and PR hygiene.
tags: [git, workflow]
category: devtools

deploy:
  agents-dir:
    name: git-mentor
    description: Use for git workflows and review hygiene.
    tags: [git, devtools]
    applyTo: ["**/*.md", ".github/**"]
  claude-code:
    name: git-mentor
    description: Use for git workflows and review hygiene.
    model: claude-sonnet-4-6
    tools: [Read, Write, Bash, Glob]
---

You are a git workflow specialist.
Help with branches, rebases, merges, and PR cleanup.
```

The important distinction is:

- top-level frontmatter is library metadata
- `deploy:` is the install contract for runtimes
- the markdown body is the instruction text

## What `deploy:` Does

`deploy:` tells `apm` how to materialize the agent for each target platform.

Example:

```yaml
deploy:
  claude-code:
    name: git-mentor
    description: Use for git workflows, rebases, merges, and PR hygiene.
    model: claude-sonnet-4-6
    tools: [Read, Write, Bash, Glob]
  codex:
    name: git-mentor
    description: Use for git workflows and repository cleanup.
    tools: [Read, Write, Bash]
    applyTo: ["**/*"]
  cursor:
    name: git-mentor
    description: Use for git workflows and repository cleanup.
    readonly: false
    is_background: false
```

Common fields inside each platform block:

- `name`: runtime-visible agent name
- `description`: short routing summary used by tools
- `model`: optional model hint
- `tools`: tool permissions for platforms that support them
- `applyTo`: path globs for platforms that support scoping
- `tags`: categorization/indexing metadata
- `enabled: false`: disables deploy for that platform

Platform-specific fields also exist, such as:

- `readonly` for Cursor
- `is_background` for Cursor

## The Special Case: `agents-dir`

`agents-dir` is treated as a generic cross-tool output target.

If you define it explicitly:

```yaml
deploy:
  agents-dir:
    name: git-mentor
    description: Use for git workflows and PR hygiene.
    tags: [git, devtools]
    applyTo: ["**/*.md", ".github/**"]
```

`apm` uses that block when installing to `agents-dir`.

If you do not define `deploy.agents-dir`, `apm` falls back to the first enabled deploy block it finds.

That fallback only applies to `agents-dir`. For other platforms, no block means no deploy for that platform.

## When To Use `instructions/`

Use `instructions/` when the instruction body itself must differ by platform.

Examples:

- Claude Code version needs different tool-use wording
- Codex version needs different execution constraints
- Cursor version should be shorter and more routing-oriented

Do not create `instructions/` just to store the main prompt separately unless there is a real need. The root file body is the default body and is the simplest setup.

## Active Body Resolution

When `apm` installs an agent, it resolves the active instruction body in this order:

1. `instructions/<id>.<platform-alias>@latest.md`
2. `instructions/<id>@latest.md`
3. `instructions/<id>_latest.md`
4. the body of `<id>.md`

Platform aliases currently used by `apm`:

- `claude-code` -> `cc`
- `cursor` -> `crs`
- `gemini` -> `gmn`
- `codex` -> `cdx`
- `generic` -> `gen`

Example for `git-mentor` on Claude Code:

1. `instructions/git-mentor.cc@latest.md`
2. `instructions/git-mentor@latest.md`
3. `instructions/git-mentor_latest.md`
4. body inside `git-mentor.md`

This means:

- platform-specific body wins
- generic `@latest` body is the normal shared override
- `_latest` is only a legacy fallback
- root body remains the final fallback

## Naming Rules

The canonical agent ID is the folder name.

Use:

```text
<AGENTS_DB>/<id>/<id>.md
```

Do not use the platform alias as the canonical ID.

Good:

```text
git-mentor/git-mentor.md
git-mentor/instructions/git-mentor.cc@latest.md
```

Bad:

```text
git-mentor-cc/git-mentor-cc.md
```

## Practical Authoring Patterns

### Pattern 1: Single-file agent

Best for most agents.

```text
reviewer/
  reviewer.md
```

Use this when one body works everywhere.

### Pattern 2: Shared body override

Use this when you want the root file to stay metadata-heavy, but still have one shared instruction body.

```text
reviewer/
  reviewer.md
  instructions/
    reviewer@latest.md
```

### Pattern 3: Platform-specific overrides

Use this when the prompt needs real runtime-specific differences.

```text
reviewer/
  reviewer.md
  instructions/
    reviewer@latest.md
    reviewer.cc@latest.md
    reviewer.cdx@latest.md
```

## Suggested Workflow

1. Start with a single `<id>.md` file.
2. Put metadata and `deploy:` in frontmatter.
3. Write the default instructions in the root body.
4. Only add `instructions/` when you need shared or platform-specific overrides.
5. Add explicit `deploy.agents-dir` if you care about generic multi-tool output instead of fallback behavior.

## Authoring Advice

- Keep metadata at the top level and runtime behavior inside `deploy:`.
- Keep `description` short and routing-oriented.
- Keep `name` stable once users rely on it.
- Prefer one canonical body unless platform differences are real.
- Treat `instructions/*.@latest.md` as active working copies.
- Use the root body as the safest fallback, not as dead content.

## Related Docs

- `docs/AGENT_ENTRY_SCHEMA.md`
- `docs/TUTORIAL.md`
- `docs/DATABASE_LIBRARY.md`
