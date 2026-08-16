# Pre-commit Scripts

Canonical script sources for the pre-commit hooks. YAML configs live in
`configs/<category>/`; what each script checks and which env vars it reads is
documented in [docs/hook-reference.md](../../docs/hook-reference.md).

`scripts/` at the repo root is a synced copy — edit here, then sync there
(tests run against the copy).

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

```text
❌ docs/CRs/MDT-165/architecture.md — closing fence has language tag (line 37,50,68,86,149)
⚠️  docs/CRs/MDT-127/architecture.md — bare opening fence (line 27,145)

Fix: sh .lefthook/pre-commit/check-markdown-fences-parity.sh --fix-staged
```

Fix mode prints one line per fixed file:

```text
✅ Fixed docs/CRs/MDT-165/architecture.md (5 fence(s))
   Re-staged: docs/CRs/MDT-165/architecture.md

Fixed 5 fence(s) total.
Fixed files are staged. Ready to commit.
```
