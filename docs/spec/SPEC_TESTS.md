# SPEC_TESTS: Build Order, Tests, Workflow Examples

This file is authoritative for implementation sequencing and verification.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_CONFIG.md](/Users/alex/code/tools/apm/SPEC_CONFIG.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)

## Recommended Build Order

1. config loader and env/flag resolution
2. parser/normalizer/validator helpers
3. internal manifest builder
4. library/runtime state engine for Claude
5. `validate`, `list`, `status`
6. `diff`, `install`
7. `remove`
8. import staging and Claude-first discovery
9. locking, backups, and failure hardening
10. GitHub connect/status/diff
11. GitHub pull
12. GitHub push
13. GitHub `per-agent` backend
14. simple interactive mode

## Automated Test Strategy

Test layers:

1. unit-like shell tests
   For state detection, parsing, path resolution, collision detection

2. fixture integration tests
   Simulate:
   - agent library
   - Claude runtime
   - GitHub clone

3. golden output tests
   Verify:
   - `list`
   - `status`
   - `diff`
   - `validate`

4. failure-path tests
   Verify:
   - partial writes do not escape staging
   - collisions fail cleanly
   - missing dependencies are reported

Suggested harness:
- `bats` if acceptable
- otherwise plain shell tests under `tests/`

Minimum v1 coverage:
- install happy path
- import staging path
- remove path
- validate failures
- collision detection
- GitHub staged pull

## Manual Smoke Test Checklist

1. Run `apm setup` on a clean config path.
2. Confirm config file contents and override behavior.
3. Run `apm validate` on a fixture database.
4. Run `apm list` and `apm status`.
5. Install one agent to Claude runtime.
6. Diff the installed agent after a local edit.
7. Remove the installed agent.
8. Import one unmanaged Claude agent into staging.
9. Apply one staged import into the canonical library.
10. Run monorepo GitHub status, diff, push, and staged pull.

## Example User Flows

### Fresh machine, Claude already has agents

```text
$ apm

No config found. Running setup...
Library path: ~/vault/data/agents_db
Platform: claude-code
Config saved to ~/.config/apm/config.sh

Scanning Claude runtime...
Found 4 untracked runtime agents:
  - git-mentor
  - reviewer
  - north
  - scratch-agent

Import any into your local library now? [y/N]
```

### Monorepo GitHub setup

```text
$ apm setup

Library path: ~/vault/data/agents_db
Platform: claude-code
GitHub mode: monorepo
GitHub owner: alexsmedile
GitHub monorepo: agents
GitHub branch: main

Config saved to ~/.config/apm/config.sh
```

### Monorepo GitHub status

```text
$ apm github status

GitHub mode : monorepo
Remote repo : alexsmedile/agents
Branch      : main

  ↑  git-mentor         synced
  ↑  reviewer           synced
  !  north              local only
  ~  scrape-architect   remote differs
```

### Safe import

```text
$ apm import git-mentor

Source: ~/.claude/agents/git-mentor.md
Draft : ~/vault/data/agents_db/_imports/git-mentor-2026-04-04-1030/

Match check:
  runtime filename matches canonical id
  body differs from current library

Suggested mode: import-merge
Review draft and apply? [y/N]
```

### Safe pull

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

