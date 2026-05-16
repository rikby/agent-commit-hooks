#!/bin/sh
# Block relative imports to shared module (enforce path alias)
#
# Generalized from markdown-ticket. Scans staged .ts files for
# disallowed imports and suggests correct alias usage.
#
# Configurable via env vars:
#   BLOCKED_IMPORT_PATTERN — regex for disallowed imports (default: from ['"](\.\./)+shared/)
#   ALIAS — the path alias to suggest (default: @mdt/shared)
#
# Uses git diff --cached directly (Option C) because it scans file content.

block_shared_imports() {
  if [ -n "$BLOCKED_IMPORT_PATTERN" ]; then
    blocked_pattern="$BLOCKED_IMPORT_PATTERN"
  else
    blocked_pattern="from ['\"]+(\\.\\./)+shared/"
  fi
  alias="${ALIAS:-@mdt/shared}"

  # Get list of staged .ts files (excluding .d.ts files)
  staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.ts$' | grep -v -E '\.d\.ts$' || true)

  if [ -z "$staged_files" ]; then
    return 0
  fi

  violations=0

  for file in $staged_files; do
    if [ ! -f "$file" ]; then
      continue
    fi

    # Check for disallowed imports (case insensitive)
    if grep -iE "$blocked_pattern" "$file" > /dev/null 2>&1; then
      echo "❌ ERROR: Disallowed relative import to shared module in: $file"
      echo ""
      echo "   Found import using '../shared/' which breaks TypeScript project references."
      echo ""
      echo "   Please use the '$alias' path alias instead:"
      echo "   Bad:  from '../../../shared/test-lib/...'"
      echo "   Good: from '$alias/test-lib/...'"
      echo ""

      # Show the offending lines
      grep -n -iE "$blocked_pattern" "$file" | sed 's/^/   /'
      echo ""
      violations=$((violations + 1))
    fi
  done

  if [ "$violations" -gt 0 ]; then
    echo "❌ Commit blocked: $violations file(s) with disallowed relative imports to shared module."
    echo "   Fix the imports and try again."
    return 1
  fi

  return 0
}

block_shared_imports
