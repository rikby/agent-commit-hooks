# Changelog

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
