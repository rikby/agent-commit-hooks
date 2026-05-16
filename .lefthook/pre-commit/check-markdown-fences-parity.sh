#!/bin/sh
# Check (and optionally fix) markdown code fence violations.
#
# Detects problems markdownlint cannot catch:
#   1. Closing fences with info strings (e.g. ```text as closer)
#   2. Bare opening fences (``` with no language) — adds "text"
#   3. Unclosed fences (odd fence count) — manual fix only
#
# Handles indented fences (up to 3 spaces per CommonMark spec).
#
# Usage:
#   Check (hook mode):     sh check-markdown-fences-parity.sh file.md ...
#   Fix staged + re-add:   sh check-markdown-fences-parity.sh --fix-staged
#   Fix specific files:    sh check-markdown-fences-parity.sh --fix file.md ...
#
# --fix-staged: reads staged .md files from git, fixes them, re-stages them.
#   One command to copy-paste from the hook error output.
#
# Skips dirs configurable via MD_SKIP_DIRS env var (colon-separated).

check_markdown_fences_parity() {
  # ── Parse flags ──

  fix_mode=0
  fix_staged=0

  case "$1" in
    --fix-staged)
      fix_mode=1
      fix_staged=1
      set -- $(git diff --cached --name-only --diff-filter=ACM '*.md' 2>/dev/null | grep -v '\.husky/' || true)
      if [ $# -eq 0 ]; then
        echo "No staged markdown files to fix."
        return 0
      fi
      ;;
    --fix)
      fix_mode=1
      shift
      ;;
  esac

  # ── Config ──

  skip_dirs="${MD_SKIP_DIRS:-}"
  violations=0
  total_fixed=0
  fixed_files=""

  # ── Shared awk fence parser ──
  # Matches fences with up to 3 spaces of indentation (CommonMark spec).
  # Tracks open/close state. Reports:
  #   - BAD_CLOSERS: closing fences that carry an info string
  #   - BARE_OPENERS: opening fences without a language tag
  #   - count: total fence markers (for parity check)

  # ── Per-file checks ──

  for file in "$@"; do
    if [ ! -f "$file" ]; then
      continue
    fi

    # Skip configured directories
    if [ -n "$skip_dirs" ]; then
      skip=0
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

    result=$(awk '
      /^[ ]{0,3}(`{3,}|~{3,})/ {
        # Extract indent
        match($0, /^[ ]*/)
        indent = substr($0, RSTART, RLENGTH)
        # Extract fence chars from the rest
        rest_line = substr($0, RLENGTH + 1)
        match(rest_line, /^[`~]+/)
        fence_chars = substr(rest_line, RSTART, RLENGTH)
        # Info string = everything after fence chars, trimmed
        info = rest_line
        sub(/^[`~]+/, "", info)
        gsub(/^[ \t]+/, "", info)
        gsub(/[ \t]+$/, "", info)

        if (!in_code) {
          in_code = 1
          count++
          if (info == "") {
            bare_openers = bare_openers NR " "
          }
        } else {
          in_code = 0
          count++
          if (info != "") {
            bad_closers = bad_closers NR ":" info " "
          }
        }
      }
      END {
        print count+0
        if (bad_closers != "") print "BAD_CLOSERS " bad_closers
        if (bare_openers != "") print "BARE_OPENERS " bare_openers
      }
    ' "$file" 2>/dev/null)

    fence_count=$(echo "$result" | head -1)
    bad_closers=$(echo "$result" | grep '^BAD_CLOSERS' | sed 's/^BAD_CLOSERS //')
    bare_openers=$(echo "$result" | grep '^BARE_OPENERS' | sed 's/^BARE_OPENERS //')

    needs_fix=0

    # Check parity (can't autofix)
    if [ "$(expr "$fence_count" % 2)" -ne 0 ]; then
      echo "❌ $file — unclosed fence ($fence_count markers, expected even)"
      violations=$((violations + 1))
      continue
    fi

    # Collect line numbers for concise output
    closer_lines=""
    if [ -n "$bad_closers" ]; then
      needs_fix=1
      closer_lines=$(echo "$bad_closers" | tr ' ' '\n' | while IFS=: read -r lineno _; do
        [ -n "$lineno" ] && printf "%s%s" "${sep:-}" "$lineno"; sep=","
      done)
    fi

    opener_lines=""
    if [ -n "$bare_openers" ]; then
      needs_fix=1
      opener_lines=$(echo "$bare_openers" | tr ' ' '\n' | while read -r lineno; do
        [ -n "$lineno" ] && printf "%s%s" "${sep:-}" "$lineno"; sep=","
      done)
    fi

    # Report in check-only mode — one line per issue type per file
    if [ "$needs_fix" -eq 1 ] && [ "$fix_mode" -eq 0 ]; then
      [ -n "$closer_lines" ] && echo "❌ $file — closing fence has language tag (line $closer_lines)"
      [ -n "$opener_lines" ] && echo "⚠️  $file — bare opening fence (line $opener_lines)"
      violations=$((violations + 1))
      continue
    fi

    # Fix mode: apply fixes with awk — preserves indentation
    if [ "$needs_fix" -eq 1 ] && [ "$fix_mode" -eq 1 ]; then
      changed=$(awk '
        /^[ ]{0,3}(`{3,}|~{3,})/ {
          match($0, /^[ ]*/)
          indent = substr($0, RSTART, RLENGTH)
          rest_line = substr($0, RLENGTH + 1)
          match(rest_line, /^[`~]+/)
          fence_chars = substr(rest_line, RSTART, RLENGTH)
          info = rest_line
          sub(/^[`~]+/, "", info)
          gsub(/^[ \t]+/, "", info)
          gsub(/[ \t]+$/, "", info)

          if (!in_code) {
            in_code = 1
            if (info == "") {
              print indent fence_chars "text"
              changed++
              next
            }
          } else {
            in_code = 0
            if (info != "") {
              print indent fence_chars
              changed++
              next
            }
          }
        }
        { print }
        END { print changed+0 > "/dev/stderr" }
      ' "$file" 2>&1 1>"${file}.fixed")

      if [ "$changed" -gt 0 ]; then
        mv "${file}.fixed" "$file"
        echo "✅ Fixed $file ($changed fence(s))"
        total_fixed=$((total_fixed + changed))
        fixed_files="$fixed_files $file"
      else
        rm -f "${file}.fixed"
      fi
    fi
  done

  # ── Fix mode: summary + re-stage ──

  if [ "$fix_mode" -eq 1 ]; then
    if [ "$total_fixed" -gt 0 ]; then
      if [ "$fix_staged" -eq 1 ] && [ -n "$fixed_files" ]; then
        for f in $fixed_files; do
          git add "$f" 2>/dev/null && echo "   Re-staged: $f"
        done
      fi
      echo ""
      echo "Fixed $total_fixed fence(s) total."
      if [ "$fix_staged" -eq 0 ]; then
        echo "Review changes, then: git add -u && git commit"
      else
        echo "Fixed files are staged. Ready to commit."
      fi
    else
      echo "No fence violations found."
    fi
    return 0
  fi

  # ── Check mode: block with fix command ──

  if [ "$violations" -gt 0 ]; then
    echo ""
    echo "Fix: sh .lefthook/pre-commit/check-markdown-fences-parity.sh --fix-staged"
    return 1
  fi

  return 0
}

check_markdown_fences_parity "$@"
