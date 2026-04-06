# SPEC_CONFIG: Setup, Config, Overrides

This file is authoritative for configuration and startup behavior.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_LIBRARY.md](/Users/alex/code/tools/apm/SPEC_LIBRARY.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)

## Config Path

```text
~/.config/apm/config.sh
```

## First-Run Setup

If config does not exist, `apm` must start an interactive setup wizard before normal operations.

Minimum setup questions:
- local database path
- default platform
- whether GitHub sync is enabled
- GitHub mode
- GitHub owner or org
- default monorepo name if using monorepo mode
- default branch

Example:

```text
$ apm

No config found at ~/.config/apm/config.sh

Local database path:
> ~/vault/data/agents_db

Default platform [claude-code/cursor/generic]:
> claude-code

Enable GitHub sync? [y/N]
> y

GitHub mode [monorepo/per-agent]:
> monorepo

GitHub owner or org:
> alexsmedile

GitHub monorepo:
> agents

Default branch:
> main

Config saved to ~/.config/apm/config.sh
```

## Config Variables

Example:

```bash
AGENTS_DB="$HOME/vault/data/agents_db"
PLATFORM="claude-code"
CLAUDE_AGENTS="$HOME/.claude/agents"
CURSOR_RULES="$HOME/.cursor/rules"
GENERIC_EXPORT="$HOME/Desktop/agents-export"
GITHUB_MODE="monorepo"
GITHUB_OWNER="your-username-or-org"
GITHUB_MONOREPO="agents"
GITHUB_BRANCH="main"
```

## Runtime Overrides

Priority:

```text
CLI flag > env var > config file > built-in default
```

Examples:

```bash
apm list --db ~/other/agents_db
apm install git-mentor --platform cursor
AGENTS_DB=~/other/agents_db apm status
GITHUB_MODE=per-agent apm github status
```

## Platform Targets

| Platform | Default runtime directory | Notes |
|------|------|------|
| `claude-code` | `~/.claude/agents` | primary v1 target |
| `cursor` | `~/.cursor/rules` | supported in config/schema, not primary interactive flow |
| `generic` | `~/Desktop/agents-export` | manual export target |

Rules:
- each platform directory is configurable
- commands operate on the selected platform
- install/remove/diff must resolve runtime paths through platform config, not hardcoded defaults

