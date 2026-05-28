# agent-commit-hooks

Shared git hooks for Lefthook — declarative YAML configs + shell scripts in a single repo.

Centralized hook definitions that any project can opt into via Lefthook remotes. No package install, no duplication.

<img width="1024" alt="git commit hooks" src="https://github.com/user-attachments/assets/a47fc2c1-e679-46e6-b39e-b679103151d6" />


## How it works

```
┌─────────────────────────┐        remotes:          ┌──────────────────────────────┐
│  Your Project           │ ── https://github.com ─→ │  agent-commit-hooks          │
│                         │        configs:          │  └─ configs/general/         │
│  lefthook.yml           │   ┌──────────────────┐   │     block-env-files.yml      │
│  ┌─────────────────┐    │   │ pick which       │   │     ...                      │
│  │ remotes:        │    │   │ configs you want │   │  └─ configs/typescript/      │
│  │   - git_url: .. │    │   └──────────────────┘   │     check-markdown-          │
│  │     configs:    │    │                          │       fences.yml             │
│  │       - general/│    │                          │  └─ .lefthook/                │
│  │       - typesc..│    │                          │    pre-commit/               │
│  └─────────────────┘    │                          │      block-home-paths-       │
└─────────────────────────┘                          │        code.sh  ...          │
                                                       └──────────────────────────────┘

⚠️ --no-verify guardrail is mandatory for AI agents
   (see INSTALL.md §4)
```

**Single repo, two layers:**

| Layer | What | Where | How |
|---|---|---|---|
| **YAML configs** | Declarative hook definitions | `configs/` | Lefthook fetches at `lefthook install` |
| **Shell scripts** | Complex logic (awk, grep, multi-step) | `.lefthook/<hook>/` | Lefthook resolves via `source_dir` (works with `ref:` pinning) |

## Install

```sh
bun add -D @evilmartians/lefthook
```

Other options: `brew install lefthook`, `npm install -D @evilmartians/lefthook`, or see
[lefthook guides](https://github.com/evilmartians/lefthook#guides) for more.

See [INSTALL.md](INSTALL.md) for full setup. **⚠️ Blocking `--no-verify` for AI agents is mandatory** — see INSTALL.md §4.
See [docs/eslint-import-alias.md](docs/eslint-import-alias.md) for ESLint import alias plugin setup.

## Available Hooks

### General (every project)

| Hook | Priority | What it blocks | Dependencies |
|---|---|---|---|
| `block-env-files` | P0 | `.env`, `.env.local`, etc. (allows `.env.sample`, `.env.example`) | None |
| `block-credential-files` | P0 | `*.pem`, `*.key`, `id_rsa`, SSH keys, certificates | None |
| `block-home-paths-code` | P0 | Absolute `/Users/...` or `/home/...` paths in staged code | None |
| `block-home-paths-commit-msg` | P1 | Absolute paths in commit messages | None |
| `block-generated-files` | P1 | Build artifacts, minified files, source maps, OS metadata | None |
| `block-co-authored-by` | P1 | `Co-Authored-By` lines in commit messages | None |
| `block-mdt-incomplete-tasks` | P1 | Unchecked `[ ]` tasks in [markdown-ticket](https://github.com/andkirby/markdown-ticket) files when ticket status is Implemented | `mdt-cli`, `python3` |
| `check-wireloom-blocks` | P1 | Validates staged markdown `wireloom` fenced blocks | `node` or `bun`, Wireloom parser path |

### TypeScript / Node

| Hook | Priority | What it does | Dependencies |
|---|---|---|---|
| `check-markdown-fences-parity` | P1 | Detects unclosed fences, closing fences with info strings, bare opening fences; autofix with `--fix` / `--fix-staged` | None |
| `check-markdown-fences-style` | P1 | Runs `markdownlint-cli2` for MD031/040/046/048 | `markdownlint-cli2` |
| `run-knip` | P1 | Dead code detection | `knip` |
| `run-eslint-staged` | P1 | Lints staged `.ts`/`.tsx` files, auto-fixes ([import alias plugin](docs/eslint-import-alias.md)) | `eslint` |

### Specialized

| Hook | Category | What it does | Dependencies |
|---|---|---|---|
| `block-shared-imports` | monorepo | Blocks relative `../shared/` imports, enforces path aliases | None |

## Configuration

### Override defaults per-project

```yaml
# lefthook.yml (project-level overrides merge with remote config)
pre-commit:
  scripts:
    "block-generated-files.sh":
      env:
        # Narrow/extend blocked patterns
        BLOCK_PATTERNS: "*.trace.md,*.generated.ts"
    "check-markdown-fences-parity.sh":
      env:
        # Skip nested markdown directories
        MD_SKIP_DIRS: "prompts,templates"
    "check-wireloom-blocks.sh":
      env:
        # Use the parser path for this project/environment
        WIRELOOM_INDEX_PATH: "./node_modules/wireloom/dist/index.js"
        WIRELOOM_RUNTIME: "auto" # auto, node, or bun
    "block-shared-imports.sh":
      env:
        BLOCKED_IMPORT_PATTERN: 'from ["\x27](\.\./)+shared/'
        ALIAS: "@myorg/shared"
```

### Skip hooks temporarily

```sh
LEFTHOOK=0 git commit -m "wip: bypass hooks"
```

## Upgrading

```sh
# Re-fetch configs
bunx lefthook install
```

## Repository Structure

```
agent-commit-hooks/
├── configs/                          # YAML hook definitions (git remote)
│   ├── general/                      # Every project
│   ├── typescript/                   # TS/Node projects
│   └── monorepo/                     # Multi-package projects
├── .lefthook/                        # Scripts resolved by lefthook source_dir
│   ├── pre-commit/                   # pre-commit hook scripts
│   └── commit-msg/                   # commit-msg hook scripts
├── scripts/                          # Legacy scripts (kept for backward compat)
├── tests/                            # Shell script tests
├── docs/                             # Installation guides & hook reference
│   └── eslint-import-alias.md       # ESLint import alias plugin setup
└── INSTALL.md                        # Installation guide
```

## License

MIT
