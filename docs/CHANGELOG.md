# Changelog

All notable changes to this project will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.2.0] — 2026-05-06

### Added
- Skills install output now shows a `Scope` line (global vs project-local) and the resolved runtime directory, so installs are always traceable without a follow-up `apm config` check.
- Skills runtime paths for `claude-code`, `codex`, and `windsurf` are now configurable variables (`CLAUDE_SKILLS`, `CODEX_SKILLS`, `WINDSURF_SKILLS`) in `~/.config/apm/config.sh`, following the same override pattern as agent paths.
- Agent onboarding steps added to `AGENTS.md` / `CLAUDE.md` so agents bootstrapping the repo self-configure correctly.
- Multi-platform skills install: `-p cc,agt install <id>` installs to each platform in a single command.

### Fixed
- Codex skills runtime corrected to `~/.agents/skills/` (global) and `.agents/skills/` (project-local). The previous target (`~/.codex/skills/`) is not where Codex reads skills from.

---

## [0.1.0] — 2026-04-08

Initial public release.

### Added
- Library management: canonical local database of agent definitions
- Install, remove, update, diff commands for runtime sync
- Import command to bring unmanaged runtime agents into the library
- Sync state tracking: in-sync, outdated, ready, unmanaged, orphan, no-deploy, collision
- Category support: tag agents and install whole groups with `--cat`
- GitHub sync: monorepo and per-agent modes (push, pull, diff, status)
- Interactive REPL dashboard (no-args mode)
- Platform support: Claude Code, Codex, Cursor, Gemini, generic
- Platform-specific body resolution with aliases (`cc`, `crs`, `gmn`, `cdx`, `gen`)
- Atomic writes, file locking, and automatic backups before destructive operations
- Python layer for YAML parsing, validation, normalization, and structured diff output
- `apm setup` interactive config wizard
- `apm version` / `--version` / `-V`
- Full shell-based test suite (9 suites, ~127 tests)
