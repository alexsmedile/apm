# SPEC_STATE: State Engine, Manifest, Collisions

This file is authoritative for state calculation and manifest structure.

See also:
- [PLAN5.md](/Users/alex/code/tools/apm/PLAN5.md)
- [SPEC_LIBRARY.md](/Users/alex/code/tools/apm/SPEC_LIBRARY.md)
- [SPEC_RUNTIME.md](/Users/alex/code/tools/apm/SPEC_RUNTIME.md)
- [SPEC_GITHUB.md](/Users/alex/code/tools/apm/SPEC_GITHUB.md)

## State Dimensions

### Library / Runtime Sync State

- `in-sync`
- `outdated`
- `ready`
- `no-deploy`
- `orphan`
- `unmanaged`
- `staged-import`
- `staged-pull`
- `ignored-runtime`
- `collision`

Definitions:
- `in-sync`: canonical library exists, deploy enabled, runtime exists, normalized content matches
- `outdated`: canonical library exists, deploy enabled, runtime exists, normalized content differs
- `ready`: canonical library exists, deploy enabled, runtime missing
- `no-deploy`: canonical library exists, deploy missing or disabled for current platform
- `orphan`: runtime claims an `apm.id`, but canonical library entry is missing
- `unmanaged`: runtime exists without `apm.id`
- `staged-import`: runtime-derived draft exists in `_imports/`
- `staged-pull`: GitHub-derived draft exists in staging
- `ignored-runtime`: unmanaged runtime file intentionally ignored
- `collision`: multiple entries map to the same alias/path unexpectedly

### GitHub State

- `not-configured`
- `unknown`
- `not-pushed`
- `in-sync`
- `outdated`

### Platform Eligibility

- `enabled`
- `disabled`
- `unsupported`

## Internal Manifest

Every command should normalize an agent into one internal manifest containing:
- canonical ID
- root path
- active body path
- deploy config for selected platform
- resolved runtime path
- runtime metadata if installed
- GitHub repo or monorepo target if configured
- detected states

This manifest should be shared across:
- `list`
- `status`
- `diff`
- `install`
- `remove`
- `import`
- GitHub commands

## Ignore Registry

Ignored unmanaged runtime files are stored in:

```text
~/.config/apm/ignored-runtime.txt
```

One entry per line:

```text
<platform>:<absolute-runtime-path>
```

## Collisions

Collision types:
1. alias collision
2. library path collision
3. runtime file collision
4. GitHub repo collision

Behavior:
- `validate` reports collisions
- `list` shows `collision`
- `install` refuses
- `import` stages under a disambiguated draft name
- `github push` refuses unless explicitly forced

