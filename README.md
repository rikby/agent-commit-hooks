# agent-commit-hooks

Shared git hooks for Lefthook — declarative YAML configs + shell scripts in a single repo.

Centralized hook definitions that any project can opt into via Lefthook remotes. No package install, no duplication.

<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/3df9da19-1974-43d7-bc69-0c6ad797f190" />


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
│  │       - general/│    │                          │  └─ scripts/                 │
│  │       - typesc..│    │                          │    block-home-paths-code.sh  │
│  └─────────────────┘    │                          │    ...                       │
└─────────────────────────┘                          └──────────────────────────────┘
```

**Single repo, two layers:**

| Layer | What | Where | How |
|---|---|---|---|
| **YAML configs** | Declarative hook definitions | `configs/` | Lefthook fetches at `lefthook install` |
| **Shell scripts** | Complex logic (awk, grep, multi-step) | `scripts/` | Referenced via `.git/info/lefthook-remotes/agent-commit-hooks/scripts/` |

## Install

```sh
bun add -D @evilmartians/lefthook
```

Other options: `brew install lefthook`, `npm install -D @evilmartians/lefthook`, or see
[lefthook guides](https://github.com/evilmartians/lefthook#guides) for more.

See [INSTALL.md](INSTALL.md) for full setup and agent hook-bypass protection.

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

### TypeScript / Node

| Hook | Priority | What it does | Dependencies |
|---|---|---|---|
| `check-markdown-fences-parity` | P1 | Detects unclosed code fences (`` ``` ``/`~~~`) in `.md` files | None |
| `check-markdown-fences-style` | P1 | Runs `markdownlint-cli2` for MD031/040/046/048 | `markdownlint-cli2` |
| `run-knip` | P1 | Dead code detection | `knip` |
| `run-eslint-staged` | P1 | Lints staged `.ts`/`.tsx` files, auto-fixes | `eslint` |

### Specialized

| Hook | Category | What it does | Dependencies |
|---|---|---|---|
| `block-shared-imports` | monorepo | Blocks relative `../shared/` imports, enforces path aliases | None |

## Configuration

### Override defaults per-project

```yaml
# lefthook.yml (project-level overrides merge with remote config)
pre-commit:
  commands:
    block-generated-files:
      env:
        # Narrow/extend blocked patterns
        BLOCK_PATTERNS: "*.trace.md,*.generated.ts"
    check-markdown-fences-parity:
      env:
        # Skip nested markdown directories
        MD_SKIP_DIRS: "prompts,templates"
    block-shared-imports:
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
├── scripts/                          # Shell scripts executed by hook configs
├── tests/                            # Shell script tests
├── docs/                             # Design docs, hook reference
└── INSTALL.md                        # Installation guide
```

## License

MIT
