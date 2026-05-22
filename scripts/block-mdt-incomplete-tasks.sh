#!/bin/sh
# Block commits to MDT ticket .md files that have unchecked tasks [ ]
# when the ticket status is already "Implemented".
#
# Uses mdt-cli --json to discover the tickets directory and check status.
# Implemented tickets should have all tasks checked off [x].
#
# Requires: mdt-cli, python3 (for JSON parsing)
# Skips gracefully if no MDT project is found or no .md files are staged.
#
# Reads staged .md files from git index (Option C — no args from lefthook).

block_mdt_incomplete_tasks() {
  # Guard: check mdt-cli is available
  if ! command -v mdt-cli >/dev/null 2>&1; then
    echo "❌ ERROR: mdt-cli not found"
    echo ""
    echo "   This hook requires mdt-cli to check ticket status."
    echo "   Install: npm install -g mdt-cli"
    echo "   Or skip this hook with: LEFTHOOK=0 git commit ..."
    return 1
  fi

  # Get staged .md files from git index
  staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$' || true)

  if [ -z "$staged_files" ]; then
    return 0
  fi

  # Resolve project context via --json
  project_json=$(mdt-cli project current --json 2>/dev/null) || return 0

  project_path=$(echo "$project_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['project']['paths']['root'])" 2>/dev/null)
  tickets_path=$(echo "$project_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['project']['ticketsPath'])" 2>/dev/null)

  if [ -z "$project_path" ] || [ -z "$tickets_path" ]; then
    return 0
  fi

  tickets_root="$project_path/$tickets_path"
  violations=0

  for file in $staged_files; do
    # Resolve to absolute path
    file_abs=""
    if [ -f "$file" ]; then
      case "$file" in
        /*) file_abs="$file" ;;
        *) file_abs="$(pwd)/$file" ;;
      esac
    else
      continue
    fi

    # Must be under the tickets root
    case "$file_abs" in
      "$tickets_root"/*) ;;
      *) continue ;;
    esac

    # Extract ticket key from path relative to tickets_root
    # Ticket key: PROJECTCODE-NNN (e.g. MDT-158, HOOK-12, API-5)
    rel_path="${file_abs#"$tickets_root"/}"

    ticket_key=""
    case "$rel_path" in
      # Direct file: ABC-NNN-slug.md or ABC-NNN.md
      [A-Z]*-[0-9]*)
        ticket_key=$(echo "$rel_path" | sed 's/^\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*/\1/')
        ;;
      # Subdirectory file: ABC-NNN/anything.md
      */[A-Z]*-[0-9]*/*)
        ticket_key=$(echo "$rel_path" | sed 's/.*\/\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*/\1/')
        ;;
      # Nested: some/dir/ABC-NNN-slug.md
      */[A-Z]*-[0-9]*)
        ticket_key=$(echo "$rel_path" | sed 's/.*\/\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*/\1/')
        ;;
    esac

    if [ -z "$ticket_key" ]; then
      continue
    fi

    # Get ticket status via --json
    ticket_json=$(mdt-cli ticket get "$ticket_key" --json 2>/dev/null) || continue

    status=$(echo "$ticket_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket']['status']['value'])" 2>/dev/null)

    if [ "$status" != "Implemented" ]; then
      continue
    fi

    # Check for unchecked tasks [ ]
    if grep -q '\[ \]' "$file" 2>/dev/null; then
      unchecked_count=$(grep -c '\[ \]' "$file" 2>/dev/null)
      echo "❌ ERROR: $file has $unchecked_count unchecked task(s) [ ] but ticket $ticket_key is Implemented"
      violations=$((violations + 1))
    fi
  done

  if [ "$violations" -gt 0 ]; then
    echo ""
    echo "   Implemented tickets must have all tasks checked off [x]."
    echo "   Either check the remaining tasks or update the ticket status."
    return 1
  fi

  return 0
}

block_mdt_incomplete_tasks
