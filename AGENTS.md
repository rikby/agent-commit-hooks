# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project Overview

Shared git hooks for [Lefthook](https://github.com/evilmartians/lefthook). Single-repo architecture:

| Layer | What | Where | Consumed via |
|---|---|---|---|
| **YAML configs** | Declarative hook definitions | `configs/` | Lefthook remotes (`remotes:` in `lefthook.yml`) |
| **Shell scripts** | Complex hook logic | `.lefthook/<hook>/` | Lefthook `source_dir` (auto-resolves, works with `ref:` pinning) |

Consuming projects pick configs in their `lefthook.yml`, run `lefthook install`, and hooks run on commit. No package install needed — scripts come from the same remote repo.

## Repository Structure

```
configs/
  general/          # 7 hooks — every project
  typescript/       # 2 hooks — TS/Node projects
  monorepo/         # 1 hook  — multi-package TS
  mdt/              # 1 hook  — MDT ticket manager
.lefthook/
  pre-commit/       # pre-commit hook scripts
  commit-msg/       # commit-msg hook scripts
scripts/            # Legacy — kept for backward compat, tests still run from here
tests/
  run-tests.sh      # Shell script unit tests (run with: sh tests/run-tests.sh)
README.md            # User-facing docs — quickstart, hook reference, templates
AGENTS.md            # Agent instructions — conventions, rules
CONTRIBUTING.md      # Contributor guide — how to contribute, versioning
```

## Architecture Rules

### How scripts are resolved

Scripts live in `.lefthook/<hook-name>/` and are referenced via lefthook's `scripts:` mechanism
in YAML configs. Lefthook resolves the path using its `source_dir` + `RemoteFolder()` logic,
which correctly handles `ref:` pinning — no hardcoded paths needed.

```yaml
# YAML config (no path hardcoding)
pre-commit:
  scripts:
    "block-generated-files.sh":
      runner: sh
      env:
        BLOCK_PATTERNS: "*.trace.md,*.min.js"
```

```
# Lefthook resolves to:
#   Without ref: .git/info/lefthook-remotes/agent-commit-hooks/.lefthook/pre-commit/block-generated-files.sh
#   With ref:    .git/info/lefthook-remotes/agent-commit-hooks-v0.1.0/.lefthook/pre-commit/block-generated-files.sh
```

### How scripts receive staged files

Two patterns — choose based on what the script needs:

**Option C (always for `scripts:`):** Script calls `git diff --cached` itself. Lefthook's `scripts:` mechanism does **not** pass staged files as arguments.
```yaml
# YAML — no args passed to scripts, script reads git diff directly
pre-commit:
  scripts:
    "block-home-paths-code.sh":
      runner: sh
```
```sh
# Script
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -v '\.husky/' || true)
for file in $staged_files; do ...
```

**Option D (only for `commands:` / `run:`):** Lefthook passes staged files via `{staged_files}` template. Use `$@` in the script.
```yaml
# YAML — {staged_files} expanded by lefthook in run: commands
pre-commit:
  commands:
    block-generated:
      run: sh scripts/block-generated-files.sh {staged_files}
```
```sh
# Script
for file in "$@"; do ...
```

### How env vars configure hooks

YAML configs define defaults. Consuming projects override in their `lefthook.yml`:
```yaml
# Remote config defines default
scripts:
  "block-generated-files.sh":
    env:
      BLOCK_PATTERNS: "*.trace.md,*.min.js"

# Project overrides
pre-commit:
  scripts:
    "block-generated-files.sh":
      env:
        BLOCK_PATTERNS: "*.trace.md,*.generated.ts"
```

### Inline vs script

Simple checks stay inline in YAML (no shell script file):
- `block-env-files` — simple grep/case on `{staged_files}`
- `block-credential-files` — simple grep/case on `{staged_files}`
- `block-co-authored-by` — simple grep on `{1}`

Complex checks get a script in `.lefthook/<hook>/`:
- Multi-line awk parsers, multiple rules, skip logic, fix suggestions

**IMPORTANT:** Do NOT use `run:` commands with hardcoded paths to `.git/info/lefthook-remotes/`.
The `run:` approach breaks when consumers pin to a version tag via `ref:` in their `lefthook.yml`.
Always use the `scripts:` mechanism instead.

## Shell Script Conventions

**Every script MUST:**

1. **`#!/bin/sh` shebang** — POSIX sh, not bash
2. **Function wrapper** with `return 1` / `return 0` — never bare `exit 1` (kills the hook runner)
3. **Defensive guards** — null checks, file existence checks, empty input early-return
4. **Detailed error messages** — what's wrong, why, and how to fix. Use `❌` prefix.
5. **No bashisms** — no `[[ ]]`, no arrays, no `read -a`. Use `case`, `grep`, `awk`, `expr`

```sh
#!/bin/sh
# One-line description of what this blocks/checks
#
# How it works, what env vars it reads, how to configure.

block_something() {
  # Guard: early return if nothing to check
  if [ -z "$1" ]; then
    return 0
  fi

  # ... logic ...

  if [ "$violations" -gt 0 ]; then
    echo "❌ ERROR: What went wrong"
    echo ""
    echo "   Why this matters."
    echo "   How to fix it."
    return 1
  fi
  return 0
}

block_something "$@"
```

## Modifying an Existing Hook

### Changing script logic

1. Edit `.lefthook/<hook>/<script>.sh`
2. Also update `scripts/<script>.sh` (kept in sync for tests)
3. Run `sh tests/run-tests.sh` — existing tests must still pass
4. Add new test cases if behavior changed (new violation type, new edge case)
5. If you changed the function signature or env vars it reads → update the YAML config too

### Changing YAML config (default env vars, glob patterns, tool guards)

1. Edit `configs/<category>/<hook>.yml`
2. Consumers override via their project `lefthook.yml` — your change only affects the **default**
3. If you remove or rename an env var → it's a **breaking change** (bump minor version)
4. If you add a new env var with a sensible default → it's backward compatible

### Adding a new env var to an existing hook

1. Add the var with a default in the YAML config's `env:` block
2. Use `$VAR` or `${VAR:-default}` in the shell script
3. Document it in the config's YAML comment header
4. Update README.md hook reference table

### Fixing a bug

1. Write a failing test first in `tests/run-tests.sh` that reproduces the bug
2. Fix the script or YAML config
3. Re-run tests — the new test must pass, existing tests must still pass
4. If the fix changes behavior consumers relied on (even buggy behavior) → note it in CHANGELOG.md

## Adding a New Hook

### Step 1: Decide category

| Category | Directory | When to use |
|---|---|---|
| `general/` | Every project | Secrets, hygiene, universal checks |
| `typescript/` | TS/Node | Needs `node`, `npx`, `.ts` files |
| `monorepo/` | Multi-package | Cross-package import rules |
| `mdt/` | MDT projects | Markdown ticket manager checks |

### Step 2: Decide inline vs script

- Simple pattern match on staged files or commit message → **inline in YAML**
- Needs awk/grep parsing, multiple rules, skip logic, diff content → **shell script**

### Step 3: Write the YAML config

Follow the pattern in existing configs. Key fields:
```yaml
pre-commit:              # or commit-msg
  scripts:
    "hook-name.sh":      # kebab-case, must match filename in .lefthook/<hook>/
      runner: sh
      glob: "*.ext"      # lefthook file filter (optional)
      exclude: "pattern" # lefthook exclude (optional)
      env:               # defaults, overridable by consumers
        YOUR_VAR: "default"
```

### Step 4: If script needed

1. Create `.lefthook/<hook>/hook-name.sh`
2. `chmod +x`
3. Follow shell script conventions above
4. Also copy to `scripts/hook-name.sh` (tests reference this path)
5. Add tests in `tests/run-tests.sh`

### Step 5: Update docs

- `README.md` — add to hook reference table
- `AGENTS.md` — update if conventions changed

### Step 6: Test

```sh
sh tests/run-tests.sh
```

## Tool-Dependent Hooks

Hooks that need external tools (markdownlint-cli2, knip, eslint) MUST:

1. Check `command -v` or `npx --help` before running
2. Hard-fail with install instructions if missing
3. Never silently skip

```yaml
run: |
  if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
    echo "❌ markdownlint-cli2 not found"
    echo "   Install: bun add -D markdownlint-cli2"
    exit 1
  fi
  markdownlint-cli2 {staged_files}
```

## Testing

```sh
# Run all tests
sh tests/run-tests.sh

# Tests create a temp git repo, stage files, run scripts, verify pass/fail
# Each test reports ✅ PASS or ❌ FAIL
```

## Key Files

| File | Purpose |
|---|---|
| `README.md` | User-facing — quickstart, hook reference, project templates |
| `INSTALL.md` | Installation guide for consumers |
| `configs/*/` | YAML hook definitions consumed via Lefthook remotes |
| `.lefthook/*/` | Scripts resolved by lefthook's `source_dir` mechanism |
| `scripts/` | Legacy script copies (kept for backward compat and tests) |

## Do NOT

- Use `bash` features — scripts must be POSIX sh
- Use bare `exit 1` inside function wrappers — use `return 1`
- Add tool dependencies without a `command -v` guard
- Hardcode file paths or patterns that should be configurable via env vars
- Use `run:` with hardcoded paths to `.git/info/lefthook-remotes/` — use `scripts:` instead
