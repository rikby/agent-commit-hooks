# Getting Started

## Quick Start

### 1. Install lefthook

```sh
bun add -D @evilmartians/lefthook
```

> npm also works: `npm install -D @evilmartians/lefthook`

### 2. Create `lefthook.yml`

Choose the template that matches your project type:

**TypeScript project:**

```yaml
min_version: 1.13.0

remotes:
  - git_url: https://github.com/rikby/agent-commit-hooks.git
    configs:
      - configs/general/block-env-files.yml
      - configs/general/block-credential-files.yml
      - configs/general/block-home-paths-code.yml
      - configs/general/block-home-paths-commit-msg.yml
      - configs/general/block-generated-files.yml
      - configs/general/block-co-authored-by.yml
      - configs/typescript/check-markdown-fences.yml
      - configs/typescript/run-knip.yml
      - configs/typescript/run-eslint-staged.yml
```

**Monorepo** — add `configs/monorepo/block-shared-imports.yml`

### 3. Install hooks

```sh
bunx lefthook install
```

> npm also works: `npx lefthook install`

### 4. Check dependencies

```sh
sh .git/info/lefthook-remotes/agent-commit-hooks/scripts/check-deps
```

## Configuration

Each config can be customized via env vars in your `lefthook.yml`:

| Env Var | Hook | Default | Description |
|---|---|---|---|
| `BLOCK_PATTERNS` | block-generated-files | `*.trace.md,*.min.js,...` | Comma-separated glob patterns to block |
| `MD_SKIP_DIRS` | check-markdown-fences | `""` | Colon-separated dirs to skip for parity check |
| `WIRELOOM_INDEX_PATH` | check-wireloom-blocks | `""` | Path to this project's Wireloom `dist/index.js` parser |
| `WIRELOOM_RUNTIME` | check-wireloom-blocks | `auto` | Runtime for validation: `auto`, `node`, or `bun` |
| `BLOCKED_IMPORT_PATTERN` | block-shared-imports | `from ['"](\.\./)+shared/` | Regex for disallowed imports |
| `ALIAS` | block-shared-imports | `@mdt/shared` | Path alias to suggest |

## Upgrading

```sh
# Re-fetch configs (picks up latest from main branch)
bunx lefthook install
```
