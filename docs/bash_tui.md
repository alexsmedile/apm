# Bash TUI (v1)

This document records the v1 Bash-based interactive UI that ships with `apm`.

## Status

- **Working:** default `apm` interactive path when `APM_EXPERIMENTAL_TUI` is not set.
- **Scope:** dashboard-style output only; includes agents/skills tabs, filter, expand/hide toggles, and command mode.
- **Direct actions:** remain handled through the standard CLI commands (`install`, `update`, `link`, `github`, etc.) rather than via single-key shortcuts.
- **Documentation:** this page should be referenced when describing the official/ship state of the Bash TUI.

## Behavior

1. Tabs
   - Keys: `Tab`, `1`, `2`, `S` toggle between `agents`, `skills`, and `settings`.
   - The header shows the selected tab plus a primitive separator line.
2. Content
   - Each tab renders its metadata (Mode/Platform/Scope/Runtime/Library/GitHub).
   - Summary line lists total/current/actionable/invalid counts.
   - Agents are shown in compact mode (limit 12) sorted by status then name, color-coded via ANSI.
   - Skills resolve their own runtime context when switching tabs; the skills tab should reflect the selected platform's skill runtime rather than reusing the agents runtime.
   - In the skills tab, direct skills are shown as flat entries and pack-based skills may be grouped by repo folder with indentation.
   - Grouped skills are ordered alphabetically by repo and then by skill id within each repo.
   - `e` toggles between compact and expanded (`--all`) list.
   - `d` toggles visibility of `no-deploy` entries.
   - `/` prompts for a text filter applied to id/name/description fields.
3. Footer
   - Key reminder line includes `Tab`, expand/hide/filter, `: commands`, and `q` to quit.
4. Command mode
   - Entering `:` opens the existing CLI-style interface; fallbacks (list/status/check/interact) unchanged.
   - The command prompt remains the path for install/update/remove/link/unlink/github, keeping the Bash commands authoritative.

## Roadmap

1. **Documented v1 is stable.** No further UI innovation occurs in this Bash TUI, except bug fixes or refinements that keep this view readable.
2. **Next iteration:** implement a terminal UI using a proper framework (Ratatui, Ink, etc.) as a separate command or the eventual default (`apm tui` / `APM_EXPERIMENTAL_TUI`), replacing the Python experiment. See the roadmap issue for the new Ratatui work.
   Requirements for the replacement TUI:
   - Users must be able to filter and inspect entries per platform, not just by the currently resolved platform.
   - Users must be able to switch the active mode/platform from the settings UI while visualizing the TUI.
   - The UI should support a clear per-platform view for skills so linked vs ready state is visible for each target runtime.
   - Settings changes made in the TUI should be persistable to the `apm` config, not view-only.
3. **Python TUI:** tagged experimental; consider deprecating in favor of the upcoming Rust/other UI once the new TUI ships.

## Testing & Verification

- `bash tests/test_update.sh` already validates the Bash TUI summary output.
- `bash tests/run_tests.sh` ensures no regression across the command suite.

## Notes

- Keep `apm tui` as an experimental entrypoint until the Ratatui rewrite is ready.
- The Bash TUI is intentionally simple; do not add new single-key mutations here.
