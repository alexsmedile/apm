---
schema: make-a-change/todo/v1
extensions:
  - "octopus:all"
---

# TODO

## Next Up

- [ ] Multi-harness install manager: `apm doctor` (read-only) → `doctor --fix` → `install --harness/--mode` → `refresh` ~next %feat
  > Design, evidence and first tasks in `docs/HANDOFF-multi-harness-install.md`. Port `dotagents/scripts/refresh-marketplaces.sh` and skizl's doctor reference rather than rewriting.

- [x] `apm --mode skills scan autofix` — auto-fix managed-copy entries by converting to symlinks %feat

- [x] `apm install` should print resolved scope %feat
  > Shipped in 0.2.0 (docs/CHANGELOG.md: "Skills install output now shows a `Scope` line").
  - [x] Add `Scope:` line to install output
    > When `apm -s install <id>` runs, scope is silently auto-detected. If `.claude/` is present → project-local, otherwise global. Invisible to user. Add e.g. `Scope: project → ./claude/skills/` or `Scope: global → ~/.claude/skills/`.

- [x] `apm --mode skills --platform codex` installs to wrong directory %bug

- [ ] Opencode subagents support ~backlog %feat
  > Docs: https://opencode.ai/docs/agents/#subagents — skills.sh opencode: `.agents/skills/` / `~/.config/opencode/skills/`

- [ ] OpenClaw agents investigation ~backlog %feat
  > Docs: https://docs.openclaw.ai/concepts/multi-agent — skills.sh openclaw: `skills/` / `~/.openclaw/skills/`

- [ ] Antigravity support ~backlog %feat
  > From skills.sh: antigravity `.agents/skills/` / `~/.gemini/antigravity/skills/`

- [ ] gpts-cli build gpt agents from terminal ~backlog %feat

- [ ] teamflow (appsumo) integration ~backlog %feat

- [ ] Replace Bash TUI with Ratatui rewrite ~backlog %feat
  > v1 bash TUI documented in `docs/bash_tui.md`. Track progress in Ratatui roadmap issue; mark Python TUI deprecated and remove once Rust UI ships.
  ```yaml
  energy: high
  ```

- [ ] Skill list: indicate runtime state from `.agents/skills` ~next %feat
  > List canonical skills from SKILLS_DB but add status flags (present/absent, diffed, not synced) for skills in `.agents/skills`.

- [ ] `apm -s --cwd . repair` — fix project-local relative symlinks ~backlog %feat
  > Detects and repairs broken/stale symlinks inside `.claude/skills/` (or `.agents/skills/`). Scan for dangling symlinks, match by name against skills_db, rewrite to correct relative path. Support `--dry-run`.

- [ ] Audit agents/skills for a project against canonical library ~backlog %feat
  > List agents and skills from a selected runtime and compare against AGENTS_DB/SKILLS_DB. Detect drift, show when updates available. Add `version` field to skill frontmatter for upgrade visibility.

- [x] Resolve symlinks in `skill_dir` / `paths` when skills_db entry is itself a symlink %feat

## Plugin install mode

- [ ] `apm --mode plugins list` — show installed plugins and component sync state ~backlog %feat

  - [ ] `apm --mode plugins install <owner>/<repo>` — full install: skills + agents + hooks

  - [ ] `apm --mode plugins install --platform all` — install to all runtimes

  - [ ] `apm --mode plugins status` — check which components installed, outdated, or missing

  - [ ] `apm --mode plugins update <name>` — pull latest and reinstall all components

  - [ ] `apm --mode plugins remove <name>` — clean removal of all installed components

> Full plugin install abstracting `npx skills add`, `/plugin marketplace add`, `npx codex-marketplace add --plugin`. One command: `apm plugin install <owner>/<repo> [--platform claude|codex|all]`. See plugin scaffold in TODO notes.

## MCP mode

- [ ] Research config paths + JSON schemas for Claude Code, Codex, Gemini, Cursor ~next %spec

- [ ] Design MCP_DB layout ~backlog %spec

- [ ] `apm -m list` / `status` / `install` / `remove` (parity with skills mode) ~backlog %feat

- [ ] `apm -m import` and `--all` ~backlog %feat

- [ ] Preset support: `apply` / `remove` / `save` / `list` ~backlog %feat

- [ ] `apm -m watch` for drift detection ~backlog %feat

- [ ] Per-platform adapters: cc, cdx, gmn, crs ~backlog %feat

- [ ] Reconcile with `mcp-manager` skill once apm covers same surface ~backlog %chore

## Multi-platform agents support

- [ ] Add Codex, Gemini, Cursor, OpenClaw, Opencode support for agents import/sync/check ~backlog %feat
  > Research correct paths and docs for each platform. Add sync commands (not just agents).
  ```yaml
  energy: high
  ```

- [ ] Add update check on startup ~backlog %feat
  ```yaml
  energy: low
  ```

- [ ] Agents/skills hub repositories ~backlog %feat

## Ideas

<!-- New items here are low priority by default: write them with !low (ported from .octopus/config.toml section_map). -->
- Add more items here as they come up.

## Notes

<!-- Items here are low priority by default: write them with !low (ported from .octopus/config.toml section_map). -->
- Capture links, constraints, and implementation details under each task.
