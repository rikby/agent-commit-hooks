#!/bin/sh
# Validate staged markdown ```wireloom blocks with a configured Wireloom parser.
#
# Configure:
#   WIRELOOM_INDEX_PATH=/path/to/Wireloom/dist/index.js
#   WIRELOOM_RUNTIME=auto|node|bun

check_wireloom_blocks() {
  runtime="${WIRELOOM_RUNTIME:-auto}"
  index_path="${WIRELOOM_INDEX_PATH:-}"
  tmp_files=$(mktemp "${TMPDIR:-/tmp}/check-wireloom-files.XXXXXX")
  tmp_js=$(mktemp "${TMPDIR:-/tmp}/check-wireloom-blocks.XXXXXX.mjs")

  cleanup() {
    rm -f "$tmp_files" "$tmp_js"
  }
  trap cleanup EXIT HUP INT TERM

  if [ $# -gt 0 ]; then
    for file in "$@"; do
      case "$file" in
        *.md|*.markdown)
          if [ -f "$file" ]; then
            printf '%s\n' "$file" >> "$tmp_files"
          fi
          ;;
      esac
    done
  else
    git diff --cached --name-only --diff-filter=ACM | while IFS= read -r file; do
      case "$file" in
        *.md|*.markdown)
          if [ -f "$file" ]; then
            printf '%s\n' "$file"
          fi
          ;;
      esac
    done > "$tmp_files"
  fi

  if [ ! -s "$tmp_files" ]; then
    cleanup
    return 0
  fi

  has_blocks=0
  while IFS= read -r file; do
    if grep -q '^[[:space:]]*```wireloom[[:space:]]*$' "$file"; then
      has_blocks=1
      break
    fi
  done < "$tmp_files"

  if [ "$has_blocks" -eq 0 ]; then
    cleanup
    return 0
  fi

  if [ -z "$index_path" ]; then
    echo "❌ Wireloom parser path is not configured"
    echo ""
    echo "   Set WIRELOOM_INDEX_PATH to your Wireloom dist index.js path."
    echo "   Example: WIRELOOM_INDEX_PATH=./node_modules/wireloom/dist/index.js"
    cleanup
    return 1
  fi

  if [ ! -f "$index_path" ]; then
    echo "❌ Wireloom parser not found: $index_path"
    echo ""
    echo "   Update WIRELOOM_INDEX_PATH in your lefthook.yml."
    cleanup
    return 1
  fi

  case "$runtime" in
    auto)
      if command -v bun >/dev/null 2>&1; then
        runner="bun"
      elif command -v node >/dev/null 2>&1; then
        runner="node"
      else
        echo "❌ Neither bun nor node was found"
        echo "   Install Bun or Node, or set WIRELOOM_RUNTIME to an available runtime."
        cleanup
        return 1
      fi
      ;;
    bun|node)
      if command -v "$runtime" >/dev/null 2>&1; then
        runner="$runtime"
      else
        echo "❌ $runtime not found"
        echo "   Install $runtime or set WIRELOOM_RUNTIME=auto."
        cleanup
        return 1
      fi
      ;;
    *)
      echo "❌ Invalid WIRELOOM_RUNTIME: $runtime"
      echo "   Use auto, node, or bun."
      cleanup
      return 1
      ;;
  esac

  cat > "$tmp_js" <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const fileListPath = process.env.WIRELOOM_FILE_LIST;
const indexPathInput = process.env.WIRELOOM_INDEX_PATH;
const files = fs.readFileSync(fileListPath, 'utf8').split('\n').filter(Boolean);
const blocks = [];

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  const matches = text.matchAll(/(?:^|\n)[ \t]*```wireloom[ \t]*\n([\s\S]*?)\n[ \t]*```[ \t]*(?=\n|$)/g);
  let number = 0;

  for (const match of matches) {
    number += 1;
    blocks.push({ file, number, source: match[1] });
  }
}

if (blocks.length === 0) {
  process.exit(0);
}

const indexPath = path.isAbsolute(indexPathInput)
  ? indexPathInput
  : path.resolve(process.cwd(), indexPathInput);

let wireloom;
try {
  const mod = await import(pathToFileURL(indexPath).href);
  wireloom = mod.default ?? mod;
} catch (error) {
  console.error(`❌ FAIL loading Wireloom parser: ${error.message}`);
  process.exit(1);
}

if (!wireloom || typeof wireloom.parse !== 'function') {
  console.error('❌ FAIL loading Wireloom parser: expected a parse(source) function');
  process.exit(1);
}

let failed = false;
for (const block of blocks) {
  try {
    wireloom.parse(block.source);
    console.log(`OK ${block.file} block ${block.number}`);
  } catch (error) {
    failed = true;
    console.error(`❌ FAIL ${block.file}`);
    console.error(`block ${block.number}: ${error.message}`);
  }
}

process.exit(failed ? 1 : 0);
JS

  WIRELOOM_FILE_LIST="$tmp_files" WIRELOOM_INDEX_PATH="$index_path" "$runner" "$tmp_js"
  rc=$?
  cleanup
  return "$rc"
}

check_wireloom_blocks "$@"
