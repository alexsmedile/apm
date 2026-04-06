# ARCHITECTURE: `apm` Development Design

This document defines the implementation architecture for `apm`.

It is not the product spec.
The product rules live in:
- [PLAN.md](/Users/alex/code/tools/apm/PLAN.md)
- [SPEC_CONFIG.md](/Users/alex/code/tools/apm/SPEC_CONFIG.md)
- [SPEC_LIBRARY.md](/Users/alex/code/tools/apm/SPEC_LIBRARY.md)
- [SPEC_STATE.md](/Users/alex/code/tools/apm/SPEC_STATE.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_IMPORT.md](/Users/alex/code/tools/apm/SPEC_IMPORT.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)
- [SPEC_SAFETY.md](/Users/alex/code/tools/apm/SPEC_SAFETY.md)
- [SPEC_TESTS.md](/Users/alex/code/tools/apm/SPEC_TESTS.md)

This file explains how to build the system so it is:
- modular
- testable
- safe for destructive operations
- easy to extend later

## 1. Architecture Goals

The implementation should optimize for:

1. **Spec fidelity**
   Behavior should come from the spec set, not ad hoc shell logic.

2. **Single source of structured truth**
   Commands should operate on one normalized internal manifest format.

3. **Thin shell, structured helpers**
   Shell is best for orchestration; Python is best for parsing, normalization, and diff/validation support.

4. **Backend replaceability**
   GitHub sync mode and future platform support must be swappable without rewriting core logic.

5. **Safety-first mutations**
   All destructive actions must pass through locking, staging, backup, and validation layers.

## 2. High-Level System

`apm` should be implemented as a hybrid CLI:

```text
shell entrypoint
  -> config + command parsing
  -> calls structured helpers
  -> orchestrates file operations / prompts / git commands

python helper layer
  -> parse frontmatter
  -> validate schema
  -> normalize deploy/runtime/library structures
  -> generate manifests and diffs
```

Recommended shape:

```text
apm
lib/
  shell/
  py/
tests/
```

## 3. Recommended Module Layout

The exact filenames can vary, but the responsibilities should stay separated.

```text
apm
lib/
  shell/
    config.shlib
    locks.shlib
    fs.shlib
    runtime.shlib
    import.shlib
    github.shlib
    ui.shlib
  py/
    apm_model.py
    apm_parse.py
    apm_validate.py
    apm_manifest.py
    apm_diff.py
tests/
  fixtures/
  helpers/
  test_*.sh
```

### Shell Layer

Owns:
- CLI argument parsing
- setup wizard prompts
- config loading
- lock acquisition
- staging directory orchestration
- file copy / move / backup operations
- git subprocess orchestration
- human output formatting

### Python Layer

Owns:
- YAML/frontmatter parsing
- schema validation
- normalization
- manifest generation
- structured diff generation
- machine-readable JSON responses for shell to consume

## 4. Core Design Principle: Manifest-Centered Commands

All commands should operate on the same normalized manifest model.

This is the most important architectural rule.

Without it, each command will rediscover:
- where the body lives
- how aliases resolve
- how runtime files link back to canonical IDs
- how state is computed

That creates drift and bugs.

### Manifest Shape

The manifest should represent one agent in one selected platform context.

Suggested shape:

```json
{
  "id": "git-mentor",
  "paths": {
    "agent_dir": "...",
    "root_file": "...",
    "active_body_file": "...",
    "runtime_file": "...",
    "import_stage_dir": "...",
    "github_stage_dir": "..."
  },
  "root_meta": {},
  "deploy": {
    "platform": "claude-code",
    "enabled": true,
    "alias": "git-mentor",
    "description": "...",
    "model": "...",
    "tools": ["Read", "Write"]
  },
  "runtime_meta": {},
  "github": {
    "mode": "monorepo",
    "owner": "alexsmedile",
    "repo": "agents",
    "branch": "main",
    "repo_path": "git-mentor/"
  },
  "state": {
    "sync": "outdated",
    "github": "in-sync",
    "eligibility": "enabled"
  },
  "warnings": []
}
```

### Manifest Rules

- manifest is read-only once built for a command execution
- manifest generation must not mutate the filesystem
- state calculation belongs to manifest generation, not to each command
- shell commands should consume manifest fields rather than reparsing files directly

## 5. Main Subsystems

### A. Config Subsystem

Responsibilities:
- load config file
- apply env and CLI overrides
- resolve effective platform directories
- expose one normalized config object

Inputs:
- config file
- env vars
- CLI flags

Outputs:
- effective config JSON or shell variables

Key rule:
- commands should not read raw config sources independently

### B. Parsing and Validation Subsystem

Responsibilities:
- parse root frontmatter
- parse runtime frontmatter
- normalize deploy blocks
- validate schema and naming rules
- build canonical manifest inputs

Inputs:
- root file path
- runtime file path
- selected platform

Outputs:
- normalized structured data
- validation errors
- manifest fragments

Key rule:
- no regex-only YAML parsing in shell

### C. State Engine

Responsibilities:
- enumerate agents in library
- discover runtime files
- discover ignored unmanaged runtime files
- compute state dimensions
- detect collisions

Inputs:
- effective config
- library paths
- runtime paths
- parser outputs

Outputs:
- manifests for `list`, `status`, `diff`, `install`, `remove`, `import`, GitHub commands

Key rule:
- state logic lives in one place

### D. Runtime Operations Subsystem

Responsibilities:
- install
- remove
- diff
- minimal interactive actions

Inputs:
- manifest
- normalized body and runtime content

Outputs:
- runtime files
- diff summaries
- human-readable command results

Key rule:
- runtime writes must always use the runtime contract from spec

### E. Import Subsystem

Responsibilities:
- discover unmanaged Claude runtime agents
- match to canonical IDs conservatively
- build staged import drafts
- support `import-new`, `import-merge`, `link-existing`

Inputs:
- runtime files
- existing library manifests

Outputs:
- staged drafts
- backup snapshots when applying to canonical agents

Key rule:
- import never silently overwrites canonical content

### F. GitHub Subsystem

Responsibilities:
- resolve GitHub backend target
- connect
- status
- diff
- push
- pull

Inputs:
- manifest
- GitHub config
- staged or canonical content

Outputs:
- temp clone operations
- staged remote snapshots
- commit/push results

Key rule:
- backend resolution must be abstract

### G. Safety Subsystem

Responsibilities:
- acquire and release locks
- build staging paths
- build backups
- ensure safe file replacement
- standardize exit codes

Inputs:
- command type
- target paths

Outputs:
- safe mutation guards

Key rule:
- every mutating command must go through this layer

## 6. Command Architecture

Every command should follow the same execution pattern where possible.

### Standard Flow

```text
parse CLI
-> load effective config
-> acquire lock if mutating
-> build manifest(s)
-> validate preconditions
-> perform command-specific action
-> validate outputs if needed
-> print result / emit JSON
```

### Example: `apm install <id>`

```text
resolve config
-> build manifest for <id>
-> validate deploy is enabled
-> resolve active body source
-> generate runtime content
-> stage runtime file
-> atomically replace runtime file
-> print result
```

### Example: `apm import <id>`

```text
resolve config
-> discover runtime source
-> build runtime-derived manifest
-> determine import mode
-> create staged draft
-> show diff or summary
-> apply only on confirmation or force
```

### Example: `apm github pull <id>`

```text
resolve config
-> build manifest
-> resolve backend target
-> clone/fetch temp repo
-> stage remote content locally
-> diff against canonical library
-> apply only after confirmation or force
```

## 7. Backend Abstractions

Two areas need abstraction from the start.

### A. Platform Backend

Current platforms:
- `claude-code`
- `cursor`
- `generic`

Backend interface should answer:
- runtime directory
- runtime filename convention
- runtime frontmatter generation rules
- platform-specific defaults

v1 may only fully implement Claude behavior, but the code should not bake Claude assumptions into unrelated modules.

### B. GitHub Backend

Current modes:
- `monorepo`
- `per-agent`

Backend interface should answer:
- which repo to use
- which path in that repo maps to the canonical ID
- how to push canonical content
- how to stage remote content for pull

v1 implementation target:
- monorepo backend first

Future upgrade:
- add per-agent backend behind the same interface

## 8. Data Flow

### Local Read Flow

```text
config
-> library scan
-> runtime scan
-> parser
-> manifest builder
-> state engine
-> command result
```

### Local Write Flow

```text
manifest
-> validation
-> staging
-> backup if needed
-> atomic replace
-> post-write verification
```

### GitHub Flow

```text
manifest
-> backend resolution
-> temp clone
-> stage local or remote content
-> diff / commit
-> apply or push
```

## 9. Suggested Internal Interfaces

The shell should not parse raw file content itself.

Suggested shell-to-python entrypoints:

```text
python ... parse-root <file>
python ... parse-runtime <file>
python ... build-manifest --id <id> --platform <platform>
python ... validate-agent --id <id>
python ... diff-manifest --id <id>
```

Output should be JSON.

This keeps:
- shell simple
- parser logic centralized
- tests easier to write

## 10. Filesystem Layout During Development

Recommended repository layout:

```text
.
├── apm
├── lib/
│   ├── shell/
│   └── py/
├── tests/
│   ├── fixtures/
│   ├── helpers/
│   └── test_*.sh
├── PLAN.md
├── SPEC_*.md
├── AGENT_FRONTMATTER.md
├── AGENT-PLAN.md
├── TEST.md
└── ARCHITECTURE.md
```

## 11. Upgrade Paths

The architecture should support these upgrades without major rewrites.

### A. GitHub `per-agent` Mode

Required seam:
- isolated GitHub backend resolution

Should not require:
- changing local state engine
- changing runtime install logic
- changing import logic

### B. Richer Platform Support

Required seam:
- platform backend layer

Should not require:
- changing canonical library rules
- changing manifest shape

### C. Additional Validation Rules

Required seam:
- validation module isolated from shell orchestration

Should not require:
- touching install/remove code directly

### D. Rich Interactive UI

Required seam:
- commands remain usable without TUI
- UI wraps command capabilities rather than replacing them

Should not require:
- special hidden logic available only in the UI

## 12. Anti-Patterns To Avoid

Do not:
- parse YAML frontmatter in multiple places
- compute state differently per command
- let GitHub code bypass staging and backup rules
- let import code write directly into canonical library without shared safety helpers
- bury platform-specific logic inside generic filesystem code
- couple shell output formatting to validation logic

## 13. Development Sequence

Recommended order:

1. shell entrypoint and config module
2. Python parser/validator/manifest modules
3. state engine and manifest wiring
4. local runtime commands
5. import flows
6. safety hardening
7. GitHub monorepo backend
8. test suite expansion
9. early per-agent backend planning branch

## 14. Completion Standard

The architecture is successful if:
- each subsystem maps clearly to a spec file
- commands share one manifest model
- destructive flows go through one safety path
- GitHub monorepo works without hardcoding away future per-agent support
- implementation agents can work in parallel with low conflict

