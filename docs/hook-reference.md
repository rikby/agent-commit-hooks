# Hook Reference

Every hook, its config file, how it receives input, its env vars, and its
dependencies. For setup, see [INSTALL.md](../INSTALL.md); for per-project
overrides, see [README.md](../README.md#configuration).

Hooks are enabled by listing their config files under `remotes:` in your
`lefthook.yml`. Configs live in `configs/<category>/` in this repo.

## Invocation modes

Hooks use one of three patterns — this determines how they get their input:

| Mode | Config shape | How input arrives |
|---|---|---|
| **Inline command** | `commands:` + `run:` with `{staged_files}` / `{1}` | Lefthook expands the template into the command |
| **Script, diff-driven** | `scripts:` + `runner: sh` | Script calls `git diff --cached` itself — no args needed |
| **Script, commit-msg** | `commit-msg:` + `scripts:` | Lefthook passes the commit-message file path as `$1` |

The `scripts:` mechanism never passes staged files as arguments (see
[AGENTS.md](../AGENTS.md) → "How scripts receive staged files"). Scripts that
need the file list read `git diff --cached` directly, which also keeps them
runnable against the real staged diff.

## General hooks (`configs/general/`)

| Hook | Hook type | Priority | Depends on | Blocks / does |
|---|---|---|---|---|
| `block-env-files` | pre-commit (inline) | P0 | — | `.env*` files (allows `.env.sample`, `.env.example`) |
| `block-credential-files` | pre-commit (inline) | P0 | — | `*.pem`, `*.key`, `*.p12`, SSH keys by name, certificates |
| `block-home-paths-code` | pre-commit (script) | P0 | — | Absolute `/Users/...` / `/home/...` paths in staged diffs |
| `block-home-paths-commit-msg` | commit-msg (script) | P1 | — | Absolute home paths in commit messages |
| `block-generated-files` | pre-commit (script) | P1 | — | Build artifacts, minified files, source maps, OS metadata |
| `block-co-authored-by` | commit-msg (inline) | P1 | — | `Co-Authored-By` lines in commit messages |
| `check-markdown-fences-parity` | pre-commit (script) | P1 | — | Unclosed fences, closers with info strings, bare openers; autofix via `--fix` / `--fix-staged` |
| `check-markdown-fences-style` | pre-commit (script) | P1 | `markdownlint-cli2` | MD031/040/046/048 style checks |
| `check-wireloom-blocks` | pre-commit (script) | P1 | `node`/`bun` + Wireloom parser | Validates staged ` ```wireloom ` fenced blocks |
| `enforce-semantic-classes` | pre-commit (script) | P1 | `node`/`bun` | CSS utility classes in component markup — [design doc](semantic-classes.md) |

Both fence checks are defined together in `configs/general/check-markdown-fences.yml`.

## TypeScript hooks (`configs/typescript/`)

| Hook | Hook type | Priority | Depends on | Does |
|---|---|---|---|---|
| `run-knip` | pre-commit (inline) | P1 | `knip` | Dead-code detection on staged `.ts` files |
| `run-eslint-staged` | pre-commit (inline) | P1 | `eslint` | Lints staged `.ts`/`.tsx`, auto-fixes, re-stages fixes — [alias plugin guide](eslint-import-alias.md) |

## Specialized hooks

| Hook | Category | Hook type | Priority | Depends on | Does |
|---|---|---|---|---|---|
| `block-shared-imports` | monorepo | pre-commit (script) | P1 | — | Blocks relative `../shared/` imports, enforces path alias |
| `block-mdt-incomplete-tasks` | mdt | pre-commit (script) | P1 | `mdt-cli`, `python3` | Unchecked `[ ]` tasks in [markdown-ticket](https://github.com/andkirby/markdown-ticket) files whose ticket status is Implemented |

## Environment variables

Defaults come from the YAML configs; override them under the script's `env:`
in your project's `lefthook.yml`. See [README.md](../README.md#configuration)
for override examples.

| Variable | Hook | Default | Purpose |
|---|---|---|---|
| `BLOCK_PATTERNS` | block-generated-files | `*.trace.md,*.min.js,*.min.css,*.generated.ts,*.map,*.log,.DS_Store,Thumbs.db` | Comma-separated glob patterns to block |
| `MD_SKIP_DIRS` | check-markdown-fences-parity | *(empty)* | Colon-separated directories to skip |
| `WIRELOOM_INDEX_PATH` | check-wireloom-blocks | *(empty)* | Path to the project's Wireloom `dist/index.js` — required when `wireloom` blocks are staged |
| `WIRELOOM_RUNTIME` | check-wireloom-blocks | `auto` | `auto`, `node`, or `bun` |
| `BLOCKED_IMPORT_PATTERN` | block-shared-imports | `from ["'](\.\./)+shared/` | Regex for disallowed imports |
| `ALIAS` | block-shared-imports | `@mdt/shared` | Path alias to suggest in the error message |
| `CONTRACT_ONLY` | enforce-semantic-classes | `1` | `1` = only flag files with colocated `@layer components` CSS; `0` = lint every file |
| `SEMANTIC_ALLOW` | enforce-semantic-classes | *(empty)* | Regex; matching class tokens are never flagged |
| `UTILITY_ALLOW` | enforce-semantic-classes | *(empty)* | Regex; matching class tokens always count as utilities |
| `SEMANTIC_QUIET` | enforce-semantic-classes | `0` | `1` omits the explanatory footer |
| `SEMANTIC_FIX_TIP` | enforce-semantic-classes | `1` | `0` hides the allowlist suggestion |

## Script locations

Canonical script sources live in `.lefthook/<hook-name>/` in this repo;
Lefthook resolves them via `source_dir`, which works with `ref:` version
pinning. The `scripts/` directory at the repo root is a synced copy that
`tests/run-tests.sh` runs against — edit `.lefthook/`, then sync.

Manual use of the fence-parity fixer (`--fix`, `--fix-staged`) is documented
in [.lefthook/pre-commit/README.md](../.lefthook/pre-commit/README.md).

## `check-deps` (CLI helper)

Not a hook — a one-shot dependency checker. Reads your `lefthook.yml`,
determines which configs you enabled, and verifies the tools they need are on
`PATH`:

```sh
sh .git/info/lefthook-remotes/agent-commit-hooks/scripts/check-deps
```

## Known gaps

- `check-markdown-fences-style.sh` expects file arguments and returns `0`
  when invoked with none — under the `scripts:` mechanism Lefthook passes no
  args, so this check currently no-ops in the default wiring. Run it manually
  with files (`sh …/check-markdown-fences-style.sh docs/foo.md`) until wired
  otherwise.
