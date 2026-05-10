#!/bin/sh
# Run markdownlint-cli2 on staged markdown files.
# Hard-fails if markdownlint-cli2 is not installed.
#
# Receives staged files as arguments ($@) — lefthook resolves {staged_files}
# in the YAML run: directive and passes them as args.

check_markdown_fences_style() {
  # Guard: hard-fail if markdownlint-cli2 is not installed
  if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
    echo "❌ markdownlint-cli2 not found"
    echo "   Install: npm i -D markdownlint-cli2"
    return 1
  fi

  if [ $# -eq 0 ]; then
    return 0
  fi

  if ! markdownlint-cli2 "$@" 2>&1; then
    echo ""
    echo "  Fix guide:"
    echo "    MD031  Add blank line before/after fenced code block"
    echo "    MD040  Add language to fence: \`\`\` → \`\`\`bash / \`\`\`typescript / \`\`\`text"
    echo "    MD046  Use consistent fence style (all backticks or all tildes)"
    echo "    MD048  Use consistent fence character (backtick or tilde, not mixed)"
    echo ""
    echo "  Autofix MD031/MD046/MD048:  markdownlint-cli2 --fix \"**/*.md\""
    return 1
  fi

  return 0
}

check_markdown_fences_style "$@"
