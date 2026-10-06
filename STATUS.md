---
schema: make-a-change/status/v1
updated: 2026-10-06
summary: "v0.2.0 released; plugin manifests shipped; multi-harness install manager (apm doctor) is designed and in progress locally."
next: "Implement read-only `apm doctor` per docs/HANDOFF-multi-harness-install.md, then `--fix` for dangling and wrong-depth links."
branch: main
version: 0.2.0
mission: docs/HANDOFF-multi-harness-install.md
---

# apm — Status

## Current state

- Latest release: **0.2.0** (2026-05-06) — see `docs/CHANGELOG.md`.
- `main` @ `99d9abe` (2026-08-15): Claude Code + Codex plugin manifests (`.claude-plugin/`,
  `.codex-plugin/`) and the multi-harness install handoff (`docs/HANDOFF-multi-harness-install.md`).
- In-progress, **uncommitted** local work in the main local checkout: edits to `apm`,
  `lib/`, `tests/`, docs, plus new `lib/harnesses.toml` and `tests/test_doctor.sh`. Do not discard it.
- Tasks moved from the Octopus v1 bucket files into `TODO.md` (OPF default layout, 2026-10-06).

## Next

Make `apm` the single multi-harness install manager: a read-only `apm doctor` that reproduces the
failure table in the handoff, then `apm doctor --fix` for the two safe repairs (dangling-link removal,
wrong-depth relink), then `apm install --harness … --mode auto|plugin|symlink` and `apm refresh`.
Source: [docs/HANDOFF-multi-harness-install.md](docs/HANDOFF-multi-harness-install.md) → "First tasks".

## Resume here

1. Check the working tree (local work is in progress — keep it):

   ```bash
   git status --short --branch
   git diff --stat
   ```

2. Read the prototype the handoff says to port, not rewrite:

   ```bash
   less ../../utils/dotagents/scripts/refresh-marketplaces.sh   # sibling dotagents checkout
   ```

3. Implement `apm doctor` (read-only) and run the suite:

   ```bash
   make lint && make test
   bash tests/test_doctor.sh
   ```

## Constraints

- Never install or symlink without an explicit request; `apm doctor` is read-only unless `--fix`.
- Prefer relative symlinks and Git (not local-path) marketplaces on Codex.
- Do not rewrite git history on repos whose plugins are already installed.
