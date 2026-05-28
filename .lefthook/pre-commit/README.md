# Pre-commit Hooks

Scripts in this directory run as Lefthook pre-commit hooks.
YAML configs live in `configs/<category>/`.

## Hook Reference

| Script | What it checks | Config |
|--------|---------------|--------|
| `check-markdown-fences-parity.sh` | Unclosed fences, closing fences with language tags, bare opening fences | `MD_SKIP_DIRS` env var |
| `check-markdown-fences-style.sh` | MD031/MD040/MD046/MD048 via markdownlint-cli2 | — |
| `check-wireloom-blocks.sh` | Wireloom fenced blocks in staged markdown files | `WIRELOOM_INDEX_PATH`, `WIRELOOM_RUNTIME` |
| `block-generated-files.sh` | Staged files matching `BLOCK_PATTERNS` | `BLOCK_PATTERNS` env var |
| `block-home-paths-code.sh` | Hardcoded home paths in staged code diffs | — |
| `block-shared-imports.sh` | Cross-package imports in monorepo | — |

## check-markdown-fences-parity.sh

Three checks that markdownlint cannot catch:

| Check | Example | Autofix? |
|-------|---------|----------|
| **Closing fence has language tag** | ` ```text ` used as closer | ✅ strips to bare ` ``` ` |
| **Bare opening fence** | ` ``` ` with no language | ✅ adds `text` |
| **Unclosed fence** | odd fence count | ❌ manual fix |

### Usage

```bash
# Check mode (hook runs this automatically)
sh check-markdown-fences-parity.sh file.md

# Fix staged files + re-stage (copy-paste from hook output)
sh check-markdown-fences-parity.sh --fix-staged

# Fix specific files
sh check-markdown-fences-parity.sh --fix file1.md file2.md

# Scan all docs in project
find ./docs -name '*.md' -exec sh check-markdown-fences-parity.sh {} +

# Fix all docs in project
find ./docs -name '*.md' -exec sh check-markdown-fences-parity.sh --fix {} +
```

### Output format

Check mode prints one line per issue, fix command at the end:

```
❌ docs/CRs/MDT-165/architecture.md — closing fence has language tag (line 37,50,68,86,149)
⚠️  docs/CRs/MDT-127/architecture.md — bare opening fence (line 27,145)

Fix: sh .lefthook/pre-commit/check-markdown-fences-parity.sh --fix-staged
```

Fix mode prints one line per fixed file:

```
✅ Fixed docs/CRs/MDT-165/architecture.md (5 fence(s))
   Re-staged: docs/CRs/MDT-165/architecture.md

Fixed 5 fence(s) total.
Fixed files are staged. Ready to commit.
```
