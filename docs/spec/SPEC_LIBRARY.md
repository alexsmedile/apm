# SPEC_LIBRARY: Canonical Library and Metadata

This file is authoritative for the local agent database layout.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [AGENT_FRONTMATTER.md](/Users/alex/code/tools/apm/AGENT_FRONTMATTER.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_IMPORT.md](/Users/alex/code/tools/apm/SPEC_IMPORT.md)

## Canonical Identity

The canonical ID is the folder name:

```text
<agent folder name>
```

Example:

```text
~/vault/data/agents_db/git-mentor/
```

Canonical ID:

```text
git-mentor
```

Rules:
- commands accept canonical IDs
- platform alias is not used as the primary identifier
- canonical ID regex: `^[a-z0-9][a-z0-9-]*$`

## Standard Structure

```text
<AGENTS_DB>/
  .obsidian/
  _imports/
  _staging/
  git-mentor/
    git-mentor.md
    instructions/
      git-mentor_latest.md
    avatar/
    knowledge/
    starters/
    versions/
```

Rules:
- top-level support folders such as `.obsidian/`, `_imports/`, and `_staging/` are allowed
- support folders must be ignored during agent scans

## Root File Rules

Required root path:

```text
<id>/<id>.md
```

Rules:
- root file always exists
- root frontmatter is required
- root file is canonical for metadata and deploy config

## Active Body Rules

Body resolution order (platform-aware):

```text
instructions/<id>.<platform-alias>@latest.md   # platform-specific (preferred)
instructions/<id>@latest.md                    # generic latest
instructions/<id>_latest.md                    # legacy fallback
<id>.md                                        # root file body (most common)
```

Platform aliases: `claude-code→cc`, `cursor→crs`, `gemini→gmn`, `codex→cdx`, `generic→gen`

Rules:
- platform-specific file wins when present for the active platform
- `@latest.md` is the preferred generic active body file
- `_latest.md` is accepted as a legacy fallback (rename to `@latest.md` when editing)
- if no instructions file exists, root file body is used
- runtime generation is always platform-aware

## Root Body Policy

The root file body may be:
- a full copy of active instructions (most common — file doubles as DB entry and deploy source)
- a short pointer/comment for Obsidian users when an instructions file is used

`apm` must not require root body to mirror the instructions file.

## Root Frontmatter Policy

Root frontmatter is user-facing local database metadata.

`apm` must:
- preserve unknown root frontmatter fields
- preserve field order when practical
- only manage fields it explicitly owns during import/update flows

Recommended metadata reference:
- [AGENT_FRONTMATTER.md](/Users/alex/code/tools/apm/AGENT_FRONTMATTER.md)

