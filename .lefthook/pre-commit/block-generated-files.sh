#!/bin/sh
# Block auto-generated artifacts from being committed
#
# Configurable via BLOCK_PATTERNS env var (comma-separated glob patterns).
# Default: common build/tool artifacts + OS metadata.
#
# Receives staged files as arguments ($@) — lefthook resolves {staged_files}
# in the YAML run: directive and passes them as args.

block_generated_files() {
  patterns="${BLOCK_PATTERNS:-*.trace.md,*.min.js,*.min.css,*.generated.ts,*.map,*.log,.DS_Store,Thumbs.db}"

  violations=0
  for file in "$@"; do
    for pattern in $(echo "$patterns" | tr ',' '\n'); do
      case "$file" in
        *$pattern*)
          echo "❌ ERROR: Generated artifact cannot be committed: $file"
          violations=$((violations + 1))
          break
          ;;
      esac
    done
  done

  if [ "$violations" -gt 0 ]; then
    echo ""
    echo "   These files appear to be auto-generated."
    echo "   Pattern(s) blocked: $patterns"
    echo "   If this is incorrect, adjust BLOCK_PATTERNS in your lefthook.yml"
    return 1
  fi

  return 0
}

block_generated_files "$@"
