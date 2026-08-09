#!/bin/sh
# Enforce semantic class names — block CSS-framework utility classes
# (Tailwind/WindiCSS/UnoCSS) in component markup.
#
# Wraps enforce-semantic-classes.mjs so lefthook can invoke it with `runner: sh`
# (matches the block-shared-imports.sh / check-wireloom-blocks.sh convention).
#
# Runtime: node OR bun — whichever is available. No npm dependencies.
#
# Receives staged files as arguments ($@) — lefthook resolves {staged_files} in
# the YAML run: directive and passes them as args. When invoked with no args
# (e.g. manual run), falls back to git staged files.
#
# Configurable via env vars (passed through by lefthook `env:`):
#   SEMANTIC_ALLOW    regex; tokens matching it are never flagged
#                     (e.g. '^(ticket-card|vword)')
#   UTILITY_ALLOW     regex; tokens matching it are always treated as a utility
#   CONTRACT_ONLY=1   only flag files that have a colocated @layer components CSS
#   SEMANTIC_QUIET=1  omit the explanatory footer

enforce_semantic_classes() {
  # Pick a JS runtime. Prefer node (universality), fall back to bun.
  runtime=""
  if command -v node >/dev/null 2>&1; then
    runtime="node"
  elif command -v bun >/dev/null 2>&1; then
    runtime="bun"
  else
    echo "❌ enforce-semantic-classes: neither node nor bun found"
    echo "   Install one of: node, bun"
    return 2
  fi

  # Resolve the .mjs next to this script (works under lefthook source_dir + remotes).
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  linter="$script_dir/enforce-semantic-classes.mjs"
  if [ ! -f "$linter" ]; then
    echo "❌ enforce-semantic-classes.mjs not found at: $linter"
    return 2
  fi

  # Files to lint: args if provided, else staged files from git.
  files=""
  if [ $# -gt 0 ]; then
    files="$*"
  else
    files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null \
            | grep -E '\.(jsx?|tsx?|mjs|cjs|svelte|vue|html?|php|astro|marko|liquid)$' \
            | tr '\n' ' ')
  fi

  if [ -z "$files" ]; then
    return 0
  fi

  $runtime "$linter" $files
}

enforce_semantic_classes "$@"
