# Handoff — apm as the multi-harness install manager

## Goal

Make `apm` the single tool that installs a skill or agent into whichever agent
harness the user runs, choosing the right **install mode** per harness, and
repairing installs that have broken.

Today the user does this by hand, differently per harness, and it silently
rots. This document is the evidence base and the target design.

## Why this is needed — observed failures

All of these were found on this machine in one session, each invisible until
someone looked directly at it:

| Failure | Detail |
|---|---|
| Stale marketplace clones | `git-stack` installed 1.7.2 while the repo was on 1.13.1; `skizl` 1.7.0 vs 1.9.0; `ponytail` 4.7.0 vs 4.9.0; `yamlification` 1.2.0 vs 1.2.1. Marketplace clones never auto-refresh, and no CLI surfaces the gap. |
| Local-source marketplace | Codex `skizl` was pinned at 1.7.0 because its marketplace was added from a **local path**. `codex plugin marketplace upgrade` refreshes Git snapshots only, so it could never update — with no warning. |
| Broken user-scope symlinks | 13 dead links in `~/.claude/skills/` → `~/.agents/skills/` after a source dir moved. Skills silently never load. |
| Wrong-depth symlinks | Antigravity `tidy-project` had 7 dangling links including `SKILL.md`, pointing at `~/skills/tidy-project/<x>` instead of `~/skills/tidy-project/skills/tidy-project/<x>`. Broken since July. |
| Escaping `source.path` | `scrapekit`'s marketplace manifest declared `"../../plugins/scrapekit"`, escaping the marketplace root. Installs failed with the misleading `plugin scrapekit was not found in marketplace scrapekit`. |
| Static copies | Antigravity `apm` and `caveman` are copied dirs, not links — they drift from source with nothing to detect it. |

Every one is mechanically detectable, and most are mechanically fixable.

## Harness matrix (verified on this machine)

| Harness | Install dir | Mechanism | Notes |
|---|---|---|---|
| **Claude Code** | `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/output-styles/` | marketplace CLI **or** symlink | `claude plugin marketplace add <owner>/<repo>` + `claude plugin install <p>@<m>`. Scopes: user / project / local. Project scope declared in committed `.claude/settings.json`. |
| **Codex** | `~/.codex/plugins/cache/<name>/<name>/<version>/` | marketplace CLI | `codex plugin marketplace add <owner>/<repo>` + `codex plugin add <p>@<m>`. **Prefer Git over local** — `marketplace upgrade` skips local-path marketplaces entirely. |
| **Antigravity** | `~/.gemini/antigravity-cli/plugins/` (global), `.agents/plugins/` (workspace) | directory scan | No marketplace. A **symlink** to the library tracks source and cannot go stale; a copy drifts. Preferred mode: symlink. |
| **opencode** | `~/.config/opencode/skills/` (also `agents/`, `commands/`, `plugins/`) | directory scan + `opencode plugin <module>` | Currently real dirs, not links. |
| **Cursor** | none persistent | per-run flag | `cursor-agent --plugin-dir <path>`. No install concept; `generate-rule` is unrelated to plugins. |

Shared library: `~/.agents/skills/` (Claude symlinks into it; Codex reads
`~/.agents/plugins/marketplace.json`, an implicit local marketplace rooted at
`$HOME`, discovered by convention rather than declared in `config.toml`).

Source of truth for the user's library: `~/vault/data/skills_db/`, also
reachable as `~/skills` (a symlink), migration target per `skills_db/AGENTS.md`.

## Target design

### 1. Install matrix

```
apm install <skill> --harness claude,codex,antigravity --mode auto|plugin|symlink
```

- `auto` picks per harness: marketplace where one exists (Claude, Codex),
  symlink where the harness scans a dir (Antigravity, opencode, Claude
  user-scope), and print the `--plugin-dir` invocation for Cursor.
- `plugin` forces the marketplace path, failing loudly where unsupported.
- `symlink` forces relative symlinks into the library (portable; survives the
  project moving).

Config should let the user declare defaults per harness rather than passing
flags each time.

### 2. Doctor / repair

```
apm doctor [--fix]
```

Checks, all proven necessary above:

- dangling symlinks in every harness install dir (**including inside a plugin's
  own `skills/`** — that is how `tidy-project` broke)
- wrong-depth links: target missing but `<target>/skills/<name>` exists → this
  is a mechanical, safe auto-fix
- static copies where a symlink is possible → warn, offer to relink
- installed version vs marketplace clone version → stale install
- Codex marketplaces added from a local path → can never update
- marketplace manifests whose `source.path` escapes the marketplace root
- orphaned flat plugin dirs superseded by a versioned cache install

Prior art to port, do not rewrite from scratch:
`~/code/utils/dotagents/scripts/refresh-marketplaces.sh` already implements the
Claude/Codex/`~/.agents`/Antigravity/Cursor sweep and the version diff.
`skizl`'s `skills/skill-manager/references/doctor.md` has runnable
implementations of the plugin-layer checks.

### 3. Refresh

```
apm refresh [--harness ...]
```

Refresh marketplace clones before any version comparison, or every version read
is from a stale copy. Claude needs a per-marketplace `marketplace update`;
Codex has a single `marketplace upgrade` for all Git marketplaces.

## Constraints

- **Never install or symlink without an explicit request.** The user's standing
  rule: creating a skill and deploying it are separate actions. `apm doctor`
  must be read-only unless `--fix` is passed.
- Prefer **relative** symlinks — they survive the library being moved or cloned.
- Prefer a **Git** marketplace over a local path on Codex; local ones are
  invisible to `marketplace upgrade`.
- Do not rewrite git history on repos whose plugins are already installed —
  it re-mints every SHA that marketplace clones point at.
- `_archive/` and `_backups/` are gitignored by convention.

## Current state of apm

- Repo: `~/code/tools/apm` (`github.com/alexsmedile/apm`), version 0.2.0.
- `skills/apm/SKILL.md` is the skill; `~/vault/data/skills_db/apm` is a symlink
  to it, and `~/.claude/skills/apm` symlinks to that. Chain is healthy.
- **Plugin manifests were just added** (`.claude-plugin/{plugin,marketplace}.json`,
  `.codex-plugin/plugin.json`), so apm now installs as a real plugin on both
  Claude and Codex. Verified with `claude plugin validate .` and by adding the
  repo as a Codex marketplace.
- There is uncommitted work in the `apm` script itself (Python interpreter
  resolution, ~68 lines) — **do not discard it**; it is the user's in-progress
  change.
- Antigravity's `apm` entry is a hand-built wrapper copy (minimal `plugin.json`
  + a copy of `skills/apm/`). Content currently matches source but will drift;
  it should become a symlink once apm can manage that itself.

## First tasks

1. Read `~/code/utils/dotagents/scripts/refresh-marketplaces.sh` end to end —
   it is the working prototype of the detection half.
2. Implement `apm doctor` (read-only) covering the checks above; verify it
   reproduces the real findings listed in the failure table.
3. Implement `apm doctor --fix` for the two safe, mechanical repairs:
   dangling link removal and wrong-depth relink.
4. Then `apm install --harness/--mode`, starting with symlink mode (fully under
   apm's control) before marketplace mode (shells out to each CLI).
