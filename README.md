# agent-commit-hooks

Shared git hooks for Lefthook — declarative YAML configs + shell scripts in a single repo.

Centralized hook definitions that any project can opt into via Lefthook remotes. No package install, no duplication.

<img width="1024" alt="git commit hooks" src="https://github.com/user-attachments/assets/a47fc2c1-e679-46e6-b39e-b679103151d6" />


## How it works

```text
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

See [INSTALL.md](INSTALL.md) for full setup. **⚠️ Blocking `--no-verify` for AI agents is mandatory** — Codex and ZCode can install the [block-no-verify plugin](plugins/block-no-verify/README.md).
See [docs/eslint-import-alias.md](docs/eslint-import-alias.md) for ESLint import alias plugin setup.

## Available Hooks

Full reference — priorities, dependencies, invocation modes, env vars:
[docs/hook-reference.md](docs/hook-reference.md).

### General (`configs/general/`) — every project

- `block-env-files`, `block-credential-files` — secrets never reach git
- `block-home-paths-code`, `block-home-paths-commit-msg` — no absolute `/Users/...` paths
- `block-generated-files` — build artifacts, minified files, source maps
- `block-co-authored-by` — no AI attribution in commit messages
- `check-markdown-fences-parity` / `-style` — markdown fence checks (autofix built in)
- `check-wireloom-blocks` — validates ` ```wireloom ` fenced blocks
- `enforce-semantic-classes` — keeps CSS utilities out of component markup ([design](docs/semantic-classes.md))

### TypeScript (`configs/typescript/`)

- `run-knip` — dead code detection
- `run-eslint-staged` — lint staged `.ts`/`.tsx` with auto-fix ([import alias plugin](docs/eslint-import-alias.md))

### Specialized

- `block-shared-imports` (monorepo) — blocks relative `../shared/` imports, enforces aliases
- `block-mdt-incomplete-tasks` (mdt) — no unchecked tasks in Implemented tickets

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
    "enforce-semantic-classes.sh":
      env:
        CONTRACT_ONLY: "1"                       # only flag files with colocated @layer components CSS
        # SEMANTIC_ALLOW is rarely needed — the classifier recognizes semantic
        # names by shape automatically. Leave empty unless you hit an edge case.
```

All variables and defaults: [hook reference](docs/hook-reference.md#environment-variables).

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

```text
agent-commit-hooks/
├── configs/                          # YAML hook definitions (git remote)
│   ├── general/                      # Every project
│   ├── typescript/                   # TS/Node projects
│   ├── monorepo/                     # Multi-package projects
│   └── mdt/                          # Markdown-ticket projects
├── .lefthook/                        # Scripts resolved by lefthook source_dir
│   ├── pre-commit/                   # pre-commit hook scripts
│   └── commit-msg/                   # commit-msg hook scripts
├── scripts/                          # Synced copy of .lefthook/ that tests run
├── tests/                            # Shell script tests
├── plugins/                          # Codex/ZCode plugins (block-no-verify, wireloom-validate)
├── docs/
│   ├── hook-reference.md             # Every hook: deps, env vars, invocation modes
│   ├── eslint-import-alias.md        # ESLint import alias plugin setup
│   └── semantic-classes.md           # enforce-semantic-classes design doc
└── INSTALL.md                        # Installation guide (incl. --no-verify guardrails)
```

## License

MIT
