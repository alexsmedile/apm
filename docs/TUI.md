# TUI: Human Terminal UX for `apm`

This document describes how `apm` should look and feel when used by a human in a terminal.

It is not a low-level implementation spec.
It defines the intended user journey, interaction patterns, and terminal UX principles.

See also:
- [PLAN.md](/Users/alex/code/tools/apm/PLAN.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_IMPORT.md](/Users/alex/code/tools/apm/SPEC_IMPORT.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)

## 1. UX Goals

`apm` should feel:
- safe
- fast
- legible
- local-first
- calm rather than flashy

The CLI should help users answer three questions quickly:

1. What exists?
2. What is out of sync?
3. What action should I take next?

The interface should guide action without hiding filesystem realities.

## 2. User Journey

The common human journey is:

```text
setup
-> inspect status
-> install or import
-> diff if needed
-> sync to GitHub
-> repeat
```

Typical loop:

```text
edit in local database
-> apm status
-> apm diff <id>
-> apm install <id>
-> apm github push <id>
```

Claude-first loop:

```text
create or edit agent in ~/.claude/agents
-> apm status
-> apm import <id>
-> review staged draft
-> apply
-> apm install <id>
-> apm github push <id>
```

## 3. General Terminal Feel

The terminal UX should follow these rules:

- one screen should answer one question
- actionable states should be obvious
- dangerous actions should be explicit
- noise should stay low
- file paths should be shown when they matter
- resolved platform and GitHub mode should be visible during relevant actions

The CLI should not feel like:
- a chat bot
- a dashboard full of decorative noise
- a hidden-state wizard with unclear side effects

## 4. Output Style Principles

Use:
- short headers
- aligned columns when listing states
- short labels like `ready`, `outdated`, `unmanaged`
- concrete paths when mutating files
- one next-step hint when useful

Avoid:
- long paragraphs in normal command output
- over-explaining obvious actions
- multiple simultaneous warnings unless truly necessary
- forcing the user through decorative full-screen UI when subcommands are enough

## 5. Command Modes

`apm` should support two human-facing modes:

### A. Direct Command Mode

For users who know what they want:

```text
apm status
apm diff git-mentor
apm install git-mentor
apm github push git-mentor
```

This is the primary interface.

### B. Interactive Mode

For users exploring the current state:

```text
apm
```

Interactive mode is a thin action layer over the same subcommands.

It should never introduce hidden behaviors unavailable from subcommands.

## 6. First-Run Experience

When no config exists, `apm` should feel like a focused setup assistant.

Example:

```text
$ apm

No config found at ~/.config/apm/config.sh

Local database path:
> ~/vault/data/agents_db

Default platform [claude-code/cursor/generic]:
> claude-code

Enable GitHub sync? [y/N]
> y

GitHub mode [monorepo/per-agent]:
> monorepo

GitHub owner or org:
> alexsmedile

GitHub monorepo:
> agents

Default branch:
> main

Config saved to ~/.config/apm/config.sh
```

After setup, `apm` should transition directly into discovery:

```text
Scanning local database...
Scanning Claude runtime...
Found 4 untracked runtime agents.

Import any now? [y/N]
```

## 7. Main States Humans Need To See

Humans primarily care about these states:

- `ready`
- `outdated`
- `in-sync`
- `unmanaged`
- `collision`
- `local only`
- `remote differs`

These should be surfaced consistently in:
- `status`
- `list`
- interactive mode
- GitHub status

## 8. `apm status` UX

`apm status` should answer:

```text
What needs attention right now?
```

Example:

```text
$ apm status

Platform    : claude-code
Library     : ~/vault/data/agents_db
GitHub mode : monorepo

  ready              8
  outdated           3
  in-sync           12
  unmanaged  4
  collision          1

Next:
  Run 'apm list' for details
```

Behavior:
- summary first
- no long explanations
- next-step hint only when helpful

## 9. `apm list` UX

`apm list` should answer:

```text
Which agents are in which state?
```

Example:

```text
$ apm list

Platform    : claude-code
GitHub mode : monorepo

  ~  git-mentor         outdated           remote: in-sync
  ○  north              ready              github: local only
  ✓  reviewer           in-sync            github: in-sync
  !  scratch-agent      unmanaged
  x  repo-coach         collision
```

Behavior:
- actionable rows first
- stable ordering
- secondary badges for GitHub or warnings

Suggested order:
1. collisions
2. unmanaged
3. outdated
4. ready
5. orphan
6. in-sync
7. no-deploy

## 10. `apm diff` UX

`apm diff` should answer:

```text
What exactly changed?
```

Example:

```text
$ apm diff git-mentor

git-mentor
Platform: claude-code

  alias        : in-sync
  description  : changed
  model        : in-sync
  tools        : changed
  body         : 12 lines differ

Next:
  Run 'apm install git-mentor' to update runtime
```

Principles:
- lead with a short verdict
- show changed vs unchanged fields
- avoid flooding the screen unless an exact diff is requested later

## 11. `apm install` UX

`apm install` should feel like a clear deployment step.

Example:

```text
$ apm install git-mentor

Installing: git-mentor
Platform  : claude-code
Source    : ~/vault/data/agents_db/git-mentor/instructions/git-mentor.cc@latest.md
Target    : ~/.claude/agents/git-mentor.md

Done.
```

If alias differs:

```text
Installing: repo-coach
Platform  : claude-code
Alias     : git-helper
Target    : ~/.claude/agents/git-helper.md
```

The user should always be able to see:
- canonical ID
- selected platform
- resolved target file

## 12. `apm remove` UX

`apm remove` should feel safe and specific.

Example:

```text
$ apm remove git-mentor

Remove runtime file for: git-mentor
Platform: claude-code
Target  : ~/.claude/agents/git-mentor.md

Proceed? [y/N]
```

If drift exists:

```text
Warning:
  runtime differs from canonical library
  removal affects runtime only
```

## 13. Import UX

Import is the most important human-trust workflow.

It should always feel staged, inspectable, and reversible.

Example:

```text
$ apm import git-mentor

Source runtime file:
  ~/.claude/agents/git-mentor.md

Suggested mode:
  import-merge

Staging draft:
  ~/vault/data/agents_db/_imports/git-mentor-2026-04-04-1030/

Match check:
  runtime filename matches canonical id
  body differs from local canonical version

Apply staged draft? [y/N]
```

Key UX rules:
- never silently overwrite canonical content
- always show staging path
- always show suggested mode
- always show whether canonical content already exists

## 14. GitHub UX

GitHub commands should feel like backup/sync operations, not the primary source of truth.

The user should always know:
- GitHub mode
- target repo
- target branch
- whether the action is pull or push

### `apm github status`

Example:

```text
$ apm github status

GitHub mode : monorepo
Remote repo : alexsmedile/agents
Branch      : main

  ↑  git-mentor         synced
  ~  scrape-architect   remote differs
  !  north              local only
```

### `apm github push <id>`

Example:

```text
$ apm github push north

Mode   : monorepo
Remote : alexsmedile/agents
Path   : north/

Staging canonical folder...
Committed: agent(north): update v1
Pushed to origin/main
```

### `apm github pull <id>`

Example:

```text
$ apm github pull git-mentor

Mode   : monorepo
Remote : alexsmedile/agents
Path   : git-mentor/

Fetched remote copy to staging.
Diff against local library:
  description changed
  body: 18 lines differ

Apply to canonical library? [y/N]
```

## 15. Interactive Mode Layout

v1 should remain simple.

It does not need a complex full-screen application.

Suggested layout:

```text
$ apm

APM
Platform    : claude-code
Library     : ~/vault/data/agents_db
GitHub mode : monorepo

Actionable first:
  1. scratch-agent      unmanaged
  2. git-mentor         outdated
  3. north              ready
  4. repo-coach         collision

All agents:
  5. reviewer           in-sync
  6. ...

Select agent number, or [q] to quit:
```

After selecting one agent:

```text
Selected: git-mentor

Actions:
  1. diff
  2. install
  3. github status
  4. back
```

This is enough for v1.

## 16. Prompts and Confirmations

Prompt wording should be:
- short
- explicit
- path-aware when destructive

Good:

```text
Apply staged draft to canonical library? [y/N]
```

Bad:

```text
Continue?
```

For destructive or state-changing actions, show:
- what will change
- where it lives
- whether the change affects runtime, library, or GitHub

## 17. Error UX

Errors should be:
- specific
- actionable
- low-drama

Example:

```text
ERROR: alias collision on claude-code
  repo-coach  -> git-helper.md
  git-mentor  -> git-helper.md

Run 'apm validate' for details.
```

Example:

```text
ERROR: no config found
Run 'apm setup' to create ~/.config/apm/config.sh
```

Example:

```text
ERROR: cannot acquire github.lock
Another mutating command may still be running.
```

## 18. Dry-Run UX

`--dry-run` should be very readable.

Example:

```text
$ apm install git-mentor --dry-run

Would install:
  canonical id : git-mentor
  platform     : claude-code
  source       : ~/vault/data/agents_db/git-mentor/instructions/git-mentor.cc@latest.md
  target       : ~/.claude/agents/git-mentor.md
```

The user should never wonder whether a dry run wrote something.

## 19. JSON Mode UX

`--json` is for automation.

Rules:
- no decorative text
- one structured object per command
- stable keys
- still honor exit codes

Humans should not be pushed toward `--json` for normal terminal use.

## 20. Future UX Upgrades

Later, the CLI may grow:
- richer `fzf` integration
- inline preview panes
- exact diff previews
- multi-select batch actions

But the core human experience should remain:
- command-first
- inspectable
- safe
- understandable without learning a hidden UI framework

