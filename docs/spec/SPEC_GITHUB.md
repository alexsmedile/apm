# SPEC_GITHUB: GitHub Sync Backends

This file is authoritative for GitHub sync behavior.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_CONFIG.md](/Users/alex/code/tools/apm/SPEC_CONFIG.md)
- [SPEC_STATE.md](/Users/alex/code/tools/apm/SPEC_STATE.md)
- [SPEC_SAFETY.md](/Users/alex/code/tools/apm/SPEC_SAFETY.md)

## Sync Modes

`apm` must support:
- `monorepo`
- `per-agent`

These are two backends for the same high-level GitHub commands.

## Initial Implementation Decision

First implementation target:

```text
github.mode = monorepo
```

Reason:
- simpler to build
- fits personal master-database backup well
- easier to harden before multi-repo orchestration

## Planned Early Follow-Up

`per-agent` is planned early, not indefinitely deferred.

Architecture must therefore:
- resolve repo targets abstractly
- avoid hardcoding monorepo assumptions into unrelated logic
- isolate backend-specific behavior in tests

## Mode Semantics

### `monorepo`

One repo contains many agent folders:

```text
<repo>/
  git-mentor/
  repo-coach/
  scrape-architect/
```

Canonical ID maps to a folder path inside the repo.

### `per-agent`

Each canonical ID maps to its own repo:

```text
canonical id: git-mentor
github repo : <owner>/git-mentor
```

Canonical ID maps to repo name by default, and repo root contains that agent's files directly.

## Config Model

Global config:

```bash
GITHUB_MODE="monorepo"
GITHUB_OWNER="your-username-or-org"
GITHUB_MONOREPO="agents"
GITHUB_BRANCH="main"
```

Per-agent root frontmatter may include:

```yaml
github:
  enabled: true
  repo: git-mentor
  branch: main
  visibility: private
```

Mode-specific interpretation:
- in `monorepo`, `github.repo` may be omitted and the global monorepo is used
- in `per-agent`, `github.repo` defaults to canonical ID

## Connect

`apm github connect` should configure:
- GitHub mode
- owner or org
- monorepo name when relevant
- default branch

## Operational Model

Use an ephemeral temp clone per GitHub command.

Rules:
- no persistent cache clone required
- each command starts from a clean checkout
- command fails clearly if auth is missing

Auth may come from:
- `gh auth`
- normal git credential helpers

## Push / Pull Rules

Push:
- `monorepo`: push canonical agent folder into `<repo>/<id>/`
- `per-agent`: push canonical agent folder contents into repo root

Pull:
- never write directly into canonical library without staging first

Staging path for GitHub pull:

```text
<AGENTS_DB>/_staging/github/<canonical-id>-<timestamp>/
```

## Git Safety Rules

- fetch before any push
- abort push if remote changed after fetch
- never push unrelated working tree changes
- commit only intended agent content
- in v1, GitHub features are implemented first for `monorepo`

## Output Contract

### `apm github status`

Human output should include:
- GitHub mode
- resolved repo target
- branch
- per-agent status lines

