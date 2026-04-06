# SPEC_IMPORT: Claude-First Workflow and Import Modes

This file is authoritative for import behavior.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_LIBRARY.md](/Users/alex/code/tools/apm/SPEC_LIBRARY.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_SAFETY.md](/Users/alex/code/tools/apm/SPEC_SAFETY.md)

## Conflict Principle

Library wins by default.

Imports must not overwrite canonical content silently.

## Claude-First Workflow

Sometimes the real first release lives in:

```text
~/.claude/agents/
```

This is a supported primary workflow, not an anomaly.

During `apm setup` or the first normal `apm` run:
1. scan Claude runtime dir
2. detect files not linked to canonical IDs
3. show them as import candidates
4. allow:
   - import now
   - skip for now
   - ignore permanently

Imported Claude-first agents should:
- preserve prompt body
- capture runtime frontmatter into `deploy.claude-code`
- create canonical library files
- add `apm.id` on the next install
- prefer the effective latest Claude body as the staged candidate when Claude is clearly newer
- still show a diff before replacing existing canonical content

## Import Modes

### `import-new`

Use when runtime should become a new canonical entry.

Behavior:
1. read runtime file
2. build draft library entry in staging
3. confirm canonical ID
4. write canonical folder only after confirmation

### `import-merge`

Use when runtime appears to be a candidate update for an existing canonical ID.

Behavior:
1. read runtime file
2. stage candidate library update
3. show diff against canonical library
4. on apply:
   - back up canonical folder first
   - then replace canonical files

### `link-existing`

Use when runtime should be associated with an existing canonical ID without changing canonical library content.

Behavior:
1. select existing canonical ID
2. confirm mismatch summary if alias/body differ
3. reinstall from library so runtime becomes managed by `apm`

## Match Heuristics

Conservative deterministic order:
1. exact existing `apm.id`
2. exact runtime filename equals canonical ID
3. exact runtime filename equals deploy alias
4. body hash match

If none match unambiguously, treat as a new import candidate.

## Staging Paths

Import staging:

```text
<AGENTS_DB>/_imports/<candidate-id>-<timestamp>/
```

Optional snapshot target for merge/apply:

```text
<agent>/versions/import-YYYY-MM-DD-HHMM/
```

## Output Contract

`apm import <id|path>` human output should include:
- source runtime path
- staging path
- detected or suggested import mode
- match summary when relevant
- apply/cancel guidance

