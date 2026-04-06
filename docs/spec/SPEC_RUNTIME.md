# SPEC_RUNTIME: Install, Remove, Diff, Interactive Mode

This file is authoritative for runtime-facing operations.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_LIBRARY.md](/Users/alex/code/tools/apm/SPEC_LIBRARY.md)
- [SPEC_STATE.md](/Users/alex/code/tools/apm/SPEC_STATE.md)
- [SPEC_SAFETY.md](/Users/alex/code/tools/apm/SPEC_SAFETY.md)

## Runtime Alias Model

- canonical ID is the command input
- `deploy.<platform>.name` is the runtime alias
- runtime filename is usually `<alias>.md`

Runtime path resolution order:
1. existing installed file with matching `apm.id`
2. current deploy alias for selected platform
3. error if ambiguous

## Runtime File Contract

For Claude Code, `apm install` writes:

```yaml
---
name: <deploy.<platform>.name>
description: <deploy.<platform>.description>
model: <deploy.<platform>.model>
tools: <normalized tools list>
apm:
  id: <canonical-id>
  platform: <platform>
  installed-from: <absolute library path>
  installed-at: <UTC timestamp>
---
```

Managed body source (resolution order):
1. `instructions/<id>.<platform-alias>@latest.md` — platform-specific (e.g. `git-mentor.cc@latest.md`)
2. `instructions/<id>@latest.md` — generic latest
3. `instructions/<id>_latest.md` — legacy fallback
4. `<id>.md` body — root file, frontmatter stripped

Platform aliases: `claude-code→cc`, `cursor→crs`, `gemini→gmn`, `codex→cdx`, `generic→gen`

Managed file rules:
- reinstall may rewrite the whole file
- unknown runtime frontmatter fields are not preserved by default
- manual edits are allowed, but `diff` must report drift
- files without `apm.id` are unmanaged until imported or linked explicitly

## Install

`apm install` is one-way:

```text
library -> runtime
```

It never treats runtime as authoritative.

If two canonical IDs resolve to the same alias for a platform, install must fail.

## Remove

`apm remove <id>` removes the installed runtime artifact for the selected platform.

Rules:
- remove runtime only
- never delete canonical library
- show exact resolved path before deletion
- warn if runtime differs from library
- support `--dry-run`

## Diff

`apm diff <id>` compares normalized representations.

Compared fields:
- canonical ID
- deploy alias
- description
- model
- tools
- body

Ignored:
- user-facing Obsidian metadata not used at runtime
- timestamps
- `apm.installed-at`

Normalization:
- trim trailing whitespace
- ignore final newline differences
- compare `tools` as normalized set-like values, but preserve normalized sorted output

## Minimal Interactive Mode

Running `apm` with no subcommand should enter a minimal interactive mode.

Minimum behavior:
- show effective platform
- show summary counts
- list actionable agents first
- support selecting one agent at a time
- offer a small action menu based on state

Suggested actions:
- `ready` or `outdated` -> install
- `unmanaged` -> import
- `in-sync` -> diff or github status
- `collision` -> validate details

Fallback:
- use `fzf` if available
- otherwise a simple numbered shell menu

## Output Contracts

### `apm diff <id>`

Human output should include:
- header with canonical ID and result
- changed vs in-sync fields
- body diff summary or exact diff
- suggested next action

### `apm install <id>`

Human output should include:
- canonical ID
- platform
- source body path
- resolved runtime path
- success or failure result

