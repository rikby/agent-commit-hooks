# Contributing

## Quick Start

```sh
# Clone
git clone https://github.com/rikby/agent-commit-hooks.git
cd agent-commit-hooks

# Run tests
sh tests/run-tests.sh
```

No build step. No install step. Just shell scripts and YAML files.

## What You Can Contribute

| Type | Examples | Effort |
|---|---|---|
| **Bug fix** | False positive, wrong error message, POSIX incompatibility | Small |
| **New hook** | New block rule, new lint check, new project category | Medium |
| **New category** | New `configs/python/` or `configs/rust/` folder | Medium |
| **Test coverage** | Add tests for untested hooks (env-files, credential-files, etc.) | Small |
| **Docs** | Fix docs, add examples, improve error messages | Small |

## Before You Start

1. **Read `AGENTS.md`** — architecture rules, shell script conventions, how hooks work
3. **Check existing hooks** — look at `configs/` and `scripts/` for patterns to follow

## Making Changes

### Fix a bug

1. Write a failing test in `tests/run-tests.sh` that reproduces the bug
2. Fix the script or YAML config
3. Run `sh tests/run-tests.sh` — all tests must pass
4. Open a PR

### Add a new hook

See `AGENTS.md` → "Adding a New Hook" — full step-by-step.

### Add a new project category

1. Create `configs/<category>/` directory
2. Write YAML configs following existing patterns
3. Add any new shell scripts to `scripts/`
4. Add tests in `tests/run-tests.sh`
5. Update `README.md` (hook reference table + project templates)
6. Update `AGENTS.md` (category table + key files)

## Shell Script Rules

These are non-negotiable. PRs violating these will be asked to fix:

- **`#!/bin/sh`** — POSIX sh, not bash
- **Function wrapper** with `return 1`/`return 0` — never bare `exit 1`
- **No bashisms** — no `[[ ]]`, no arrays, no `read -a`
- **Detailed error messages** — `❌` prefix, what's wrong, how to fix
- **Defensive guards** — null checks, empty input, missing files
- **Executable** — `chmod +x` on all scripts

## Testing

```sh
sh tests/run-tests.sh
```

Tests create a temp git repo, stage files, run each script, and verify pass/fail.

**Current coverage:**

| Script | Tested? |
|---|---|
| `block-generated-files.sh` | ✅ 6 tests |
| `check-markdown-fences-parity.sh` | ✅ 4 tests |
| `block-home-paths-commit-msg.sh` | ✅ 4 tests |
| `block-home-paths-code.sh` | ✅ 2 tests |
| `check-markdown-fences-style.sh` | ✅ 1 test |
| `check-deps` | ✅ 2 tests |
| `block-env-files` | ❌ inline YAML |
| `block-credential-files` | ❌ inline YAML |
| `block-co-authored-by` | ❌ inline YAML |
| `block-shared-imports.sh` | ❌ needs git diff context |

## Versioning

Breaking changes are noted in CHANGELOG.md.

### What's a breaking change?

- Removing or renaming an env var that consumers override
- Changing a script's argument signature
- Removing a config file
- Tightening a block pattern (starts blocking files that were previously allowed)

### What's backward compatible?

- Adding a new env var with a default
- Adding a new config file
- Loosening a block pattern (allowing previously blocked files)
- Improving error messages
- Adding new skip rules

## PR Checklist

- [ ] Tests pass (`sh tests/run-tests.sh`)
- [ ] New hooks have test coverage
- [ ] Shell scripts follow conventions (see AGENTS.md)
- [ ] README.md updated (hook reference table)
- [ ] AGENTS.md updated if conventions changed
- [ ] Breaking changes documented in CHANGELOG.md

## Questions?

- Agent instructions → `AGENTS.md`
- User docs → `README.md`
