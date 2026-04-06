# SPEC_SAFETY: Atomic Writes, Locks, Exit Codes

This file is authoritative for safety guarantees.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_IMPORT.md](/Users/alex/code/tools/apm/SPEC_IMPORT.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)

## Atomic Write Pattern

For single-file writes:
1. write temp file in same filesystem
2. fsync if practical
3. rename into place

For directory updates:
1. write new content to staging dir
2. validate staged content
3. back up current target dir if it exists
4. replace target contents in a controlled step
5. remove staging only after success

v1 does not promise cross-filesystem atomic directory replacement.
It does promise:
- no partial canonical overwrite without backup
- no partial runtime file writes
- recoverability after interrupted apply

## Rollback Rules

- failed install must not leave truncated runtime files
- failed config write must not corrupt config
- failed pull/apply must leave canonical library untouched
- failed import must leave only staging artifacts

## Backups

Before destructive replacement of a canonical folder, create:

```text
<agent>/versions/apm-backup-YYYY-MM-DD-HHMM/
```

## Locking

Lock files live under:

```text
~/.config/apm/locks/
```

Required lock categories:
- `config.lock`
- `runtime-<platform>.lock`
- `library.lock`
- `github.lock`

Rules:
- mutating commands must acquire relevant lock
- read-only commands may run without locks
- stale lock detection should include pid and timestamp metadata

## Exit Codes

- `0`: success
- `1`: user-actionable diff/conflict/validation failure
- `2`: operational error
- `3`: dependency missing
- `4`: lock acquisition failed

## JSON Output

Commands supporting `--json` should emit one machine-readable object containing:
- command
- canonical ID when relevant
- platform
- primary state
- secondary warnings or states
- touched paths
- diff summary when relevant
- success boolean

Human output remains default.

