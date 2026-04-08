# Contributing to apm

Thanks for your interest in contributing.

## Getting started

```bash
git clone https://github.com/alexsmedile/apm.git
cd apm
bash install.sh --check   # verify dependencies
```

## Running tests

```bash
make test    # full suite (~127 tests)
make lint    # static checks only (fast)
```

Tests are plain bash — no external test framework required. Each suite isolates state via `APM_CONFIG_DIR=$(mktemp -d)`.

## Making changes

- **Shell logic** lives in `apm` and `lib/shell/`. Keep it focused on orchestration, prompts, and filesystem operations.
- **Parsing and validation** belongs in `lib/py/apm_python.py`. All frontmatter parsing goes through Python — no ad hoc YAML in shell.
- **Tests** live in `tests/`. Every new feature or bug fix should include a test case.

After any change, run:

```bash
bash -n apm
python3 -m py_compile lib/py/apm_python.py
```

## Submitting a PR

1. Fork the repo and create a branch: `git switch -c feat/your-feature`
2. Make your changes and add tests
3. Run `make lint && make test` — all tests must pass
4. Open a pull request with a clear description of what and why

## Reporting bugs

Use [GitHub Issues](https://github.com/alexsmedile/apm/issues). Include your OS, bash version, and the exact command that failed.
