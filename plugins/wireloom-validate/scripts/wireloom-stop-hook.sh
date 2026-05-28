#!/bin/sh
# Codex Stop hook: validate Wireloom blocks in changed markdown files.
#
# Configure in the target project or environment:
#   WIRELOOM_INDEX_PATH=/path/to/Wireloom/dist/index.js
#   WIRELOOM_RUNTIME=auto|node|bun

run_wireloom_stop_hook() {
  runtime="${WIRELOOM_RUNTIME:-auto}"
  input_file=$(mktemp "${TMPDIR:-/tmp}/codex-wireloom-input.XXXXXX.json")
  script_file=$(mktemp "${TMPDIR:-/tmp}/codex-wireloom-stop.XXXXXX.mjs")

  cleanup() {
    rm -f "$input_file" "$script_file"
  }
  trap cleanup EXIT HUP INT TERM

  cat > "$input_file"

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

  cat > "$script_file" <<'JS'
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const inputPath = process.env.CODEX_WIRELOOM_INPUT;
const indexPathInput = process.env.WIRELOOM_INDEX_PATH || '';

function readHookInput() {
  try {
    const raw = fs.readFileSync(inputPath, 'utf8').trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function wireloomBlocks(cwd, files) {
  const blocks = [];

  for (const file of files) {
    const absolute = path.resolve(cwd, file);
    const text = fs.readFileSync(absolute, 'utf8');
    if (!/^[ \t]*```wireloom[ \t]*$/m.test(text)) {
      continue;
    }

    const matches = text.matchAll(/(?:^|\n)[ \t]*```wireloom[ \t]*\n([\s\S]*?)\n[ \t]*```[ \t]*(?=\n|$)/g);
    let number = 0;
    for (const match of matches) {
      number += 1;
      blocks.push({ file, number, source: match[1] });
    }
  }

  return blocks;
}

function statePath(input, cwd) {
  const stateRoot = process.env.CODEX_WIRELOOM_STATE_DIR
    || path.join(os.homedir(), '.local', 'state', 'codex-wireloom-validate');
  const rawId = input.session_id || input.turn_id || cwd;
  const safeId = Buffer.from(String(rawId)).toString('base64url');
  return path.join(stateRoot, `${safeId}.files`);
}

function touchedMarkdownFiles(input, cwd) {
  const filePath = statePath(input, cwd);
  if (!fs.existsSync(filePath)) {
    return [];
  }

  return fs.readFileSync(filePath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .filter((file) => /\.(md|markdown)$/i.test(file))
    .filter((file) => {
      const absolute = path.resolve(cwd, file);
      const relative = path.relative(cwd, absolute);
      return relative && !relative.startsWith('..') && !path.isAbsolute(relative)
        && fs.existsSync(absolute) && fs.statSync(absolute).isFile();
    });
}

function clearTouchedFiles(input, cwd) {
  try {
    fs.rmSync(statePath(input, cwd), { force: true });
  } catch {
    // Best effort cleanup only.
  }
}

function blockStop(reason) {
  process.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`);
  process.exit(0);
}

const input = readHookInput();
const cwd = typeof input.cwd === 'string' && input.cwd ? input.cwd : process.cwd();
if (input.stop_hook_active === true) {
  clearTouchedFiles(input, cwd);
  process.exit(0);
}

const markdownFiles = touchedMarkdownFiles(input, cwd);
const blocks = wireloomBlocks(cwd, markdownFiles);

if (blocks.length === 0) {
  clearTouchedFiles(input, cwd);
  process.exit(0);
}

if (!indexPathInput) {
  blockStop([
    'Wireloom parser path is not configured.',
    '',
    'Markdown files touched by this Codex session contain ```wireloom blocks.',
    'Set WIRELOOM_INDEX_PATH to this project\'s Wireloom dist index.js path.',
    'Example: WIRELOOM_INDEX_PATH=./node_modules/wireloom/dist/index.js',
    '',
    'Wireloom source: https://github.com/StardockCorp/Wireloom',
    'Build parser: git clone https://github.com/StardockCorp/Wireloom.git && cd Wireloom && npm install && npm run build',
  ].join('\n'));
}

const indexPath = path.isAbsolute(indexPathInput)
  ? indexPathInput
  : path.resolve(cwd, indexPathInput);

if (!fs.existsSync(indexPath)) {
  blockStop([
    `Wireloom parser not found: ${indexPath}`,
    '',
    'Update WIRELOOM_INDEX_PATH for this project/environment.',
    '',
    'Wireloom source: https://github.com/StardockCorp/Wireloom',
    'Build parser: git clone https://github.com/StardockCorp/Wireloom.git && cd Wireloom && npm install && npm run build',
  ].join('\n'));
}

let wireloom;
try {
  const mod = await import(pathToFileURL(indexPath).href);
  wireloom = mod.default ?? mod;
} catch (error) {
  blockStop(`Failed to load Wireloom parser: ${error.message}`);
}

if (!wireloom || typeof wireloom.parse !== 'function') {
  blockStop('Failed to load Wireloom parser: expected a parse(source) function.');
}

const failures = [];
for (const block of blocks) {
  try {
    wireloom.parse(block.source);
  } catch (error) {
    failures.push(`❌ FAIL ${block.file}\nblock ${block.number}: ${error.message}`);
  }
}

if (failures.length > 0) {
  blockStop([
    'Wireloom validation failed.',
    '',
    ...failures,
    '',
    'Fix the Wireloom block(s), then stop again. If you cannot fix them, explain the blocker to the user.',
  ].join('\n'));
}

if (process.env.CODEX_WIRELOOM_VERBOSE === '1') {
  console.error(`Wireloom validation passed (${blocks.length} block(s)).`);
}
clearTouchedFiles(input, cwd);
JS

  CODEX_WIRELOOM_INPUT="$input_file" "$runner" "$script_file"
  rc=$?
  cleanup
  return "$rc"
}

run_wireloom_stop_hook "$@"
