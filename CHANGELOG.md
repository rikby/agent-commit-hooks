# Changelog

## v0.2.0 (2026-05-16)

### Added

- `check-markdown-fences-parity` now detects closing fences with info strings (e.g. ` ```text ` used as closer) — a CommonMark violation that markdownlint misses
- `check-markdown-fences-parity` now detects bare opening fences (` ``` ` with no language) and adds `text` via autofix
- `--fix` flag: fix specific files in place
- `--fix-staged` flag: reads staged `.md` files from git, fixes them, re-stages them — one command to copy-paste from hook output
- Handles indented fences (up to 3 spaces per CommonMark spec), preserves indentation on fix
- Concise one-line-per-file error output with copy-paste fix command
- `.lefthook/pre-commit/README.md` — hook reference and usage patterns
- 7 new tests (27 total)

### Fixed

- `block-shared-imports` default `BLOCKED_IMPORT_PATTERN` had POSIX sh quoting error — syntax error on source

## v0.1.0 (2026-05-10)

### Fixed

- `ref:` pinning broke all script-referencing hooks. Migrated from hardcoded `run:` paths to lefthook's native `scripts:` mechanism so hooks resolve correctly with or without a version tag in `remotes:`.

### Changed

- YAML configs now use `scripts:` + `runner: sh` instead of `commands:` + `run:`. Consumers who override these hooks in their `lefthook.yml` should update from `commands:` to `scripts:` to match.
- Scripts now live in `.lefthook/<hook>/` alongside the legacy `scripts/` directory.

## v0.1.0 (2026-05-08)

Initial release. Shared lefthook configs + scripts in a single repo.

- `block-env-files` — blocks `.env` files (allows `.env.sample`, `.env.example`)
- `block-credential-files` — blocks private keys, certificates, SSH keys
- `block-home-paths-code` — blocks `/Users/...`/`/home/...` paths in staged diffs
- `block-home-paths-commit-msg` — blocks absolute home paths in commit messages
- `block-generated-files` — blocks build artifacts, minified files, source maps
- `block-co-authored-by` — blocks `Co-Authored-By` in commit messages
- `check-markdown-fences-parity` — detects unclosed code fences in `.md` files
- `check-markdown-fences-style` — runs `markdownlint-cli2` (MD031/040/046/048)
- `run-knip` — dead code detection
- `run-eslint-staged` — lints staged `.ts`/`.tsx` files with auto-fix
- `block-shared-imports` — blocks relative `../shared/` imports, enforces aliases
