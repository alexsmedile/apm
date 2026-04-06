# GEMINI.md - `apm` Project Context

## Project Overview
`apm` (AI Prompt Manager) is a local-first CLI tool for managing AI agent prompt files (e.g., for Claude Code, Cursor, and other AI platforms). It maintains a canonical library of agent definitions and manages their installation, updates, and synchronization with both local runtimes and remote GitHub repositories.

- **Architecture:** Hybrid CLI using Bash (v4+) for orchestration/UI and Python 3 (PyYAML) for parsing, validation, and manifest generation.
- **Core Principles:** Local-first, atomic writes, manifest-centered commands, and safety-first mutations (locking and backups).
- **Project Structure:**
    - `apm`: Main entry point (Bash script).
    - `lib/shell/`: Bash libraries (`config.shlib`, `fs.shlib`, `locks.shlib`, `ui.shlib`).
    - `lib/py/`: Python logic (`apm_python.py` handles parsing, validation, and diffs).
    - `docs/`: Comprehensive specifications and architectural guides.
    - `tests/`: Extensive shell-based test suite.

## Building and Running
### Core Commands
- **Install:** `bash install.sh` (links `apm` to `~/.local/bin`).
- **Setup:** `apm setup` (interactive configuration wizard).
- **Manage Agents:**
    - `apm list`: Show agents and their sync status.
    - `apm install <id>`: Install an agent to the configured runtime.
    - `apm update`: Reinstall all outdated agents.
    - `apm import`: Import unmanaged runtime agents into the library.
- **GitHub Sync:** `apm github connect/status/push/pull`.

### Development & CI
- **Test:** `make test` (runs the full suite via `tests/run_tests.sh`).
- **Lint:** `make lint` (performs `bash -n` checks and Python compilation).
- **Check Dependencies:** `make check`.

## Development Conventions
### Architectural Mandates
- **Thin Shell, Structured Helpers:** Keep shell logic focused on orchestration. Use `_apm_py` to delegate complex parsing, normalization, and validation to the Python layer.
- **JSON-Only Python Output:** Python helpers must always return JSON for the shell to consume.
- **Manifest-Centered:** Commands should operate on a normalized manifest model provided by the Python layer to ensure consistency in state calculation.
- **Safety First:** 
    - Always use `apm_acquire_lock` and `apm_release_lock` (from `locks.shlib`) before mutating configurations or the agents database.
    - Use staging directories for downloads and imports to avoid direct mutation of the canonical library.
- **Shell Standards:**
    - Use `set -uo pipefail` in all shell scripts.
    - Source library files from `lib/shell/`.
    - Follow the UI patterns defined in `ui.shlib` (e.g., `apm_log`, `apm_warn`, `apm_die`).

### Testing & Validation
- **Regression Testing:** Every new feature or bug fix must be accompanied by a test case in `tests/`.
- **Validation Engine:** Use `cmd_validate` (or `_apm_py validate-agent`) to ensure agents conform to the schema defined in `docs/AGENT_ENTRY_SCHEMA.md`.
- **Playground:** Use `tests/fakeagents-db/` for manual testing and verification of GitHub sync logic.

### Documentation Reference
- `ARCHITECTURE.md`: High-level system design and module boundaries.
- `SPEC_*.md` (in `docs/spec/`): Detailed implementation rules for each subsystem.
- `AGENT_ENTRY_SCHEMA.md`: Schema reference for agent library metadata and deploy fields.
