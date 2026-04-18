# WORKFLOWS: Usability Questions, Answers, and Edge Cases

This document captures the kinds of questions a human user will ask while using `apm`.

It serves two purposes:
- clarify intended behavior before implementation
- provide a practical operator reference later

## 1. Setup and Orientation

### How does `apm` work at a high level?

`apm` treats your local agent database as the source of truth.
It compares that library against:
- installed runtime files, such as Claude Code agents
- optional GitHub sync targets

Then it lets you:
- inspect state
- install to runtime
- import from runtime
- diff changes
- sync to GitHub

### How do I start using it on a new machine?

Run:

```text
apm
```

If config does not exist, `apm` should start setup automatically.
After setup, it should scan both your local database and Claude runtime.

### How do I point `apm` to my own local database?

Use one of:

```text
apm setup
apm list --db ~/my/agents_db
AGENTS_DB=~/my/agents_db apm status
```

The database you choose is your master source of truth.

### How do I know what `apm` thinks my current config is?

Run:

```text
apm setup
```

Re-running setup shows current config and lets you update any values.

## 2. Daily Local Use

### How do I see what needs attention?

```text
apm status
```

Shows counts by state (color-coded): `ready`, `outdated`, `in-sync`, `unmanaged`, `collision`.

### How do I see everything, not just counts?

```text
apm list
```

Shows each agent with its sync symbol, ID, category (if set), and state name.

Direct runtime links show up as:
- `linked` — the runtime symlink points at the expected active body
- `linked-outdated` — the runtime symlink exists, but points at the wrong target

### How do I install one agent to Claude Code?

```text
apm install git-mentor
```

`apm` resolves: canonical ID → platform → runtime alias → target file path.

### How do I install one skill?

Use skills mode on a platform that supports skill directories:

```text
apm --mode skills --platform claude-code install browser-use
```

Current skill-install platforms:
- `claude-code`
- `codex`
- `gemini`
- `windsurf`
- `agents-dir`

This creates a symlink from the platform skill target directory back to the canonical skill folder in `SKILLS_DB`.

### Can installs use symlinks instead of copying the runtime file?

Yes.

```text
INSTALL_MODE=symlink apm install git-mentor
```

In this mode, `apm` still generates a normal managed runtime file in `~/.agents/`, then creates a tool-specific symlink back to it.
This preserves `apm.id` metadata and keeps `diff` / `update` behavior the same as a normal install.

### What is the difference between `install` symlink mode and `apm link`?

They solve different problems:

- `INSTALL_MODE=symlink apm install ...`
  creates a symlink to a generated runtime file in `~/.agents/`
- `apm link <id>`
  creates a symlink that points directly at the active instruction body in the library

Use `install` symlink mode when you still want a managed runtime wrapper file.
Use `link` when you want runtime to mirror the split instruction body directly.

### How do I create a direct runtime symlink to the library body?

```text
apm link git-mentor
apm link git-mentor --as review-helper
apm links
```

If the platform-specific split file does not exist yet, `apm link` can generate it from the root body.

### How do I remove a direct symlink later?

```text
apm unlink git-mentor
apm unlink git-mentor --project
apm unlink git-mentor --global
apm unlink git-mentor --all
```

`unlink` removes only tracked symlinks and refuses to delete regular files.
Without a scope flag, it removes links only in the current resolved scope.

### How do I install multiple agents at once?

```text
apm install git-mentor code-reviewer sql-pro
```

### How do I install everything that is ready or outdated?

```text
apm install --all
```

### How do I install all agents in a category?

Add `category: <name>` (or `group: <name>`) to the agent's root frontmatter:

```yaml
category: devtools
```

Then:

```text
apm install --cat devtools
```

### How do I preview what would happen without writing files?

```text
apm --dry-run install git-mentor
apm --dry-run install --all
apm --dry-run install --cat devtools
apm --dry-run remove git-mentor
```

## 3. Diff and Inspection

### How do I see what changed between my library and runtime?

Run:

```text
apm diff git-mentor
```

### What exactly should `apm diff` compare?

It should compare normalized runtime-relevant fields:
- alias
- description
- model
- tools
- body

It should ignore:
- timestamps
- unrelated Obsidian metadata

### What if I edited the runtime file manually?

If the runtime file is managed by `apm`, `diff` should show drift.
Manual edits are allowed, but the library remains canonical.

## 4. Import from Claude Runtime

### How do I find agents in my Claude runtime that are not in my library?

Run `apm list`. Any agent marked `!` (unmanaged) is in your Claude runtime but not in your library.

### How does import work?

Import is staged first.
`apm` reads a Claude runtime file, builds a draft library entry, and asks before applying it.

### How do I import an agent that only exists in `~/.claude/agents`?

Run with no args for an interactive numbered picker:

```text
apm import
```

Or import a specific agent by ID:

```text
apm import git-mentor
```

If it is unmanaged, `apm` stages a draft under `_imports/`.

### What if the agent already exists in my local database?

`apm` should not overwrite silently.
It should:
- detect the match
- suggest `import-merge` or `link-existing`
- show the diff
- require confirmation before applying

### What is `link-existing` for?

Use it when the runtime file corresponds to an existing canonical agent, but you do not want to update the library from runtime content.

In that case, `apm` should keep the library unchanged and reinstall from canonical content so runtime becomes managed.

### How does `apm` decide whether something is a match?

Conservative order:
1. existing `apm.id`
2. runtime filename equals canonical ID
3. runtime filename equals deploy alias
4. body hash match

If the match is unclear, `apm` should treat it as a new candidate instead of guessing.

### What if Claude is actually the latest source?

That is a supported workflow.
If Claude runtime clearly has the newer effective body, `apm` should stage it as the candidate source for import or merge.
It should still show a diff before applying it to the canonical library.

### How do I ignore a runtime file I do not want to import?

The tool should support:
- skip for now
- ignore permanently

Ignored files should stay out of repeated prompts unless explicitly reviewed later.

## 5. GitHub Sync

### How does GitHub sync work?

GitHub is a backup/distribution channel, not the source of truth.
Push is the normal direction.
Pull exists for remote recovery or shared-project cases.

### What GitHub modes are supported?

**monorepo** — one GitHub repo contains all agents, each in its own subdirectory:
```
<repo>/git-mentor/
<repo>/code-reviewer/
```

**per-agent** — each agent gets its own GitHub repository.

### How do I connect GitHub?

Run:

```text
apm github connect
```

The wizard asks:
- **Mode** (numbered menu): `1) monorepo` or `2) per-agent`
- **Owner/org**: GitHub username or organization
- **Repo name**: monorepo repo name (monorepo mode only)
- **Default branch**: defaults to `main`

### How do I push one agent?

Run:

```text
apm github push git-mentor
```

In monorepo mode, that should update:

```text
<repo>/git-mentor/
```

### How do I push all agents?

Run:

```text
apm github push --all
```

In monorepo mode, this should result in one repo push containing multiple changed agent folders.

### How do I see which agents are local only vs synced vs remote-different?

Run:

```text
apm github status
```

### How do I pull updates from GitHub when another machine changed something?

Run:

```text
apm github pull git-mentor
```

`apm` should:
- clone/fetch temp repo
- stage the remote content locally
- show the diff against canonical library
- ask before applying unless forced

### What if I only want GitHub as backup and never want pull to override my library silently?

That is the default behavior.
Pull stages first and asks before applying.

### What if the remote changed since my last fetch and I try to push?

Push should abort instead of silently overwriting remote work.

## 6. Identity and Naming

### What is the real identity of an agent?

The canonical ID is the folder name in the local database.

### What if the deployed Claude filename is different from the canonical ID?

That is allowed.
`deploy.<platform>.name` is the runtime alias.

Example:

```text
canonical id: repo-coach
runtime alias: git-helper
runtime file : ~/.claude/agents/git-helper.md
```

### How does `apm` know which runtime file belongs to which agent?

Managed runtime files include:

```yaml
apm:
  id: <canonical-id>
```

That metadata is the primary reverse mapping.

## 7. Database Structure and Metadata

### Why do we keep one folder per agent?

So each agent can store:
- root metadata
- active instructions
- versions
- avatar
- starters
- knowledge

### Why is the root frontmatter customizable?

Because the local database may also be viewed in Obsidian or another metadata-driven tool.
You may want fields like:
- version
- status
- platform
- origin
- avatar
- github

### Where are those metadata rules documented?

See:

- [AGENT_ENTRY_SCHEMA.md](AGENT_ENTRY_SCHEMA.md)

### Why use `deploy:` inside the root frontmatter?

Because each AI tool may need a different install format.
The local root metadata is not the same thing as runtime frontmatter.

`deploy:` lets `apm` generate the exact runtime file shape needed for:
- Claude Code
- Cursor
- generic export

## 8. Interactive Mode

### What should happen when I just run `apm`?

It should enter a minimal interactive mode.

That mode should:
- show summary context
- list actionable agents first
- let you choose one agent
- offer state-appropriate actions

### Should interactive mode be fancy?

No, not in v1.

It should be:
- simple
- readable
- safe
- a thin wrapper around the same subcommands

### Should `fzf` be required?

No.

Use it when available.
Fall back to a plain shell menu otherwise.

## 9. Validation and Errors

### How do I check whether my database is valid?

Run:

```text
apm validate
```

### What kinds of problems should validation catch?

- malformed frontmatter
- missing root file
- invalid deploy config
- alias collisions
- invalid canonical IDs
- unsupported structure

### What happens if two agents map to the same deployed filename?

That is a collision.
Install must refuse to proceed until it is resolved.

### What happens if another `apm` process is already mutating files?

The second one should fail clearly because of lock contention.

### What if required dependencies are missing?

The tool should fail with a specific message and appropriate exit code.

Examples:
- missing `python3`
- missing `PyYAML`
- missing `git`
- missing GitHub auth

## 10. Upgrade and Future Questions

### How will per-agent GitHub mode fit later?

The same high-level commands should keep working:

```text
apm github status
apm github push <id>
apm github pull <id>
```

Only backend resolution should change.

### How will richer platform support fit later?

The platform backend should determine:
- runtime directory
- runtime filename
- frontmatter output format

The local library model should stay stable.

### Could we later add richer TUI previews and multi-select?

Yes.
But those should wrap the same command capabilities, not introduce special hidden logic.

## 11. Extra Human Questions and Edge Cases

### What if my local database has `.obsidian/` and other support folders?

That is allowed.
They should be ignored by agent scans.

### What if an agent has no `deploy` block?

It can still exist in the local database.
It just is not installable for that platform.

### What if no instructions file exists?

The root file body is used (frontmatter stripped). This is the most common case — the root file doubles as both database entry and deploy source.

### What if both root body and an instructions file exist and differ?

The instructions file takes precedence. Resolution order: `<id>.<platform-alias>@latest.md` → `<id>@latest.md` → `<id>_latest.md` → root body.
The root body may still be kept for preview or Obsidian compatibility.

### What is the preferred instructions filename format?

`instructions/<id>@latest.md` for a generic body, or `instructions/<id>.<platform-alias>@latest.md` for platform-specific content (e.g. `git-mentor.cc@latest.md` for claude-code). The old `_latest.md` naming is still accepted as a legacy fallback.

### What if I rename an agent folder?

That changes the canonical ID.
The tool should treat it carefully and not assume it is the same identity without explicit mapping.

### What if I want to script `apm` from CI or another tool?

Use:

```text
--json
```

and rely on exit codes.

### What if I never want to use GitHub?

That is supported.
The tool should remain fully useful for local database plus runtime workflows only.

### What if I only use GitHub for some agents?

That is supported.
Some agents can remain local only.

### What if I want to test without touching my real library?

Use:

```text
--db <temp-path>
```

or an `AGENTS_DB` override.

### What if the runtime file path is ambiguous?

The tool should stop and report the ambiguity rather than guessing.

### What if a staged import or pull already exists?

The tool should surface that clearly and avoid silently overwriting the staging area.

### What if my GitHub branch is not `main`?

That should be configurable globally, and overridable per agent later if supported.

## 12. Quick Reference

Daily local workflow:

```text
apm status
apm list
apm diff <id>
apm install <id>
apm install --cat <category>
apm update
```

Import from Claude runtime:

```text
apm list                    # spot ! (unmanaged) entries
apm import                  # interactive picker
apm import --all            # import everything untracked
```

GitHub backup workflow:

```text
apm github status
apm github push --all
```

Remote recovery workflow:

```text
apm github diff <id>
apm github pull <id>
```

Setup:

```text
apm setup                   # first-time or re-configure
apm github connect          # configure or update GitHub sync
```
