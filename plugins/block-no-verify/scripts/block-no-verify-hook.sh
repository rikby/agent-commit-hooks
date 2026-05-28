#!/bin/sh
# Codex PreToolUse bridge for block-no-verify.
#
# Codex sends hook input as JSON on stdin. block-no-verify understands the
# Codex/Claude-style fields: tool_name and tool_input.command.

run_block_no_verify() {
  if [ -x "./node_modules/.bin/block-no-verify" ]; then
    exec ./node_modules/.bin/block-no-verify
  fi

  if command -v block-no-verify >/dev/null 2>&1; then
    exec block-no-verify
  fi

  if command -v bunx >/dev/null 2>&1; then
    exec bunx block-no-verify
  fi

  if command -v pnpm >/dev/null 2>&1; then
    exec pnpm exec block-no-verify
  fi

  if command -v npm >/dev/null 2>&1; then
    exec npm exec --yes block-no-verify
  fi

  echo "block-no-verify is not available" >&2
  echo "Install it with: bun add -D block-no-verify" >&2
  return 1
}

run_block_no_verify "$@"
