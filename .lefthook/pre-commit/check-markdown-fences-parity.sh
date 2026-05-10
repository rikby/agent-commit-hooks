#!/bin/sh
# Check markdown fence parity — unclosed fences cause rendering breakage
# that markdownlint cannot catch.
#
# Counts fence markers (``` or ~~~). Odd count = unclosed fence.
# Skips dirs configurable via MD_SKIP_DIRS env var (colon-separated).
#
# Receives staged files as arguments ($@) — lefthook resolves {staged_files}
# in the YAML run: directive and passes them as args.

check_markdown_fences_parity() {
  skip_dirs="${MD_SKIP_DIRS:-}"

  violations=0

  for file in "$@"; do
    # Skip non-existent files (deleted but still in staged list)
    if [ ! -f "$file" ]; then
      continue
    fi

    # Skip configured directories
    if [ -n "$skip_dirs" ]; then
      skip=0
      # Parse colon-separated skip dirs
      old_ifs="$IFS"
    IFS=':'
    for skip_dir in $skip_dirs; do
      case "$file" in
        ${skip_dir}/*)
          skip=1
          break
          ;;
      esac
    done
    IFS="$old_ifs"
    if [ "$skip" -eq 1 ]; then
      continue
    fi
    fi

    # Count lines starting with 3+ backticks or tildes (fence openers/closers)
    # Use awk to avoid sh arithmetic issues with empty/multiline grep -c output
    fence_count=$(awk '/^```|^~~~/{count++} END{print count+0}' "$file" 2>/dev/null || echo 0)

    if [ "$(expr "$fence_count" % 2)" -ne 0 ]; then
      echo "❌ ERROR: Unclosed code fence in: $file"
      echo "   Found $fence_count fence marker(s) — must be even (open + close)."
      echo "   Fix: add missing closing \`\`\` or remove stray opening \`\`\`"
      echo ""
      grep -nE '^```|^~~~' "$file" | sed 's/^/   /'
      echo ""
      violations=$((violations + 1))
    fi
  done

  if [ "$violations" -gt 0 ]; then
    echo "❌ Commit blocked: $violations file(s) with unclosed code fences."
    echo "   Fix the issues above and try again."
    return 1
  fi

  return 0
}

check_markdown_fences_parity "$@"
