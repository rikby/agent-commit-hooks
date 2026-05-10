#!/bin/sh
# Block absolute home paths in commit messages
#
# Blocks commit messages containing absolute paths like:
#   - /Users/kirby/...
#   - /home/user/...
#
# Receives commit message file path as $1 (from lefthook {1}).

block_home_paths_commit_msg() {
  commit_msg_file="$1"

  # Defensive: fallback to default commit message file if not provided
  if [ -z "$commit_msg_file" ]; then
    commit_msg_file=$(git rev-parse --git-dir)/COMMIT_EDITMSG
  fi

  # Defensive: skip if file doesn't exist
  if [ ! -f "$commit_msg_file" ]; then
    return 0
  fi

  COMMIT_MSG=$(cat "$commit_msg_file")

  # Pattern for absolute home paths (macOS/Linux)
  HOME_PATH_PATTERN='/(Users|home)/[a-zA-Z0-9_-]+/'

  # Check for home paths in commit message
  # Skip example placeholders and common documentation terms
  if echo "$COMMIT_MSG" | grep -v "username" | grep -v "pattern" | \
    grep -v "description" | grep -v "example" | \
    grep -E "$HOME_PATH_PATTERN" > /dev/null; then
    echo "❌ ERROR: Absolute home paths detected in commit message"
    echo ""
    echo "   Please remove absolute paths from your commit message."
    echo "   Use relative paths or project identifiers instead."
    echo ""
    echo "   Found in:"
    echo "$COMMIT_MSG" | grep -E "$HOME_PATH_PATTERN" | sed 's/^/     /'
    return 1
  fi

  return 0
}

block_home_paths_commit_msg "$1"
