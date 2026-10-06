---
schema: make-a-change/project/v1
type: project
id: apm-6006
title: apm
status: active
created: 2026-04-06
updated: 2026-10-06
description: Agent Package Manager — a local-first CLI that installs one library of agent and skill files into every supported AI harness.
kind: code
area: dev
owner: alex
repo: alexsmedile/apm
---

# apm

`apm` (Agent Package Manager) keeps one canonical library of subagent and skill definitions
and installs, diffs, updates and imports them across agent runtimes (Claude Code, Codex,
Gemini CLI, Windsurf, `~/.agents`), with optional GitHub sync, atomic writes, locking and backups.

## Links
- Status → [STATUS.md](STATUS.md) · Tasks → [TODO.md](TODO.md) · Releases → [docs/CHANGELOG.md](docs/CHANGELOG.md)
- Architecture → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Current plan → [docs/HANDOFF-multi-harness-install.md](docs/HANDOFF-multi-harness-install.md)
- Usage → [README.md](README.md) · Agent guide → [AGENTS.md](AGENTS.md)
