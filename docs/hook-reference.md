# Hook Reference

All hooks are configured as remote YAML configs in the `agent-commit-hooks` repository.

## General Hooks

| Hook | Type | Priority | External Deps | Description |
|---|---|---|---|---|
| `block-env-files` | pre-commit | P0 | None | Blocks `.env` files (allows `.env.sample`, `.env.example`) |
| `block-credential-files` | pre-commit | P0 | None | Blocks private keys, certificates, SSH keys |
| `block-co-authored-by` | commit-msg | P1 | None | Blocks `Co-Authored-By` in commit messages |
| `block-home-paths-code` | pre-commit | P0 | None | Blocks absolute `/Users/...`, `/home/...` paths in staged diffs |
| `block-home-paths-commit-msg` | commit-msg | P1 | None | Blocks absolute home paths in commit messages |
| `block-generated-files` | pre-commit | P1 | None | Blocks auto-generated artifacts (configurable via `BLOCK_PATTERNS`) |

## TypeScript Hooks

| Hook | Type | Priority | External Deps | Description |
|---|---|---|---|---|
| `check-markdown-fences-parity` | pre-commit | P1 | None | Checks for unclosed code fences (odd fence count) |
| `check-markdown-fences-style` | pre-commit | P1 | `markdownlint-cli2` | Runs markdownlint style checks (MD031/040/046/048) |
| `run-knip` | pre-commit | P1 | `knip` | Dead code detection |
| `run-eslint-staged` | pre-commit | P1 | `eslint` | Lints staged `.ts`/`.tsx` files with auto-fix |

## Monorepo Hooks

| Hook | Type | Priority | External Deps | Description |
|---|---|---|---|---|
| `block-shared-imports` | pre-commit | P1 | None | Blocks relative `../shared/` imports, enforces path alias |

## Script Details

All scripts live in `scripts/` and are referenced via the remote checkout path:
```
.git/info/lefthook-remotes/agent-commit-hooks/scripts/<script>
```

### `block-home-paths-code.sh`
- **Method**: Parses `git diff --cached` with awk, extracts line numbers
- **Skips**: Comments (`//`, `#`, `*`), example lines, URLs, `.husky/` directory

### `block-home-paths-commit-msg.sh`
- **Receives**: Commit message file path as `$1` (lefthook `{1}`)
- **Skips**: Lines containing `username`, `pattern`, `description`, `example`

### `block-generated-files.sh`
- **Receives**: Staged files as `$@` (lefthook `{staged_files}`)
- **Configurable**: `BLOCK_PATTERNS` env var (comma-separated globs)

### `check-markdown-fences-parity.sh`
- **Receives**: Staged files as `$@` (lefthook `{staged_files}`)
- **Configurable**: `MD_SKIP_DIRS` env var (colon-separated directories)

### `check-markdown-fences-style.sh`
- **Receives**: Staged files as `$@` (lefthook `{staged_files}`)
- **Hard-fails** if `markdownlint-cli2` not installed

### `block-shared-imports.sh`
- **Configurable**: `BLOCKED_IMPORT_PATTERN` (regex), `ALIAS` (suggested alias)
- **Method**: Scans staged `.ts` files for disallowed import patterns

### `check-deps` (CLI)
- **Purpose**: Proactive dependency check
- **Method**: Reads `lefthook.yml`, determines enabled configs, checks PATH
- **Run**: `sh .git/info/lefthook-remotes/agent-commit-hooks/scripts/check-deps`
