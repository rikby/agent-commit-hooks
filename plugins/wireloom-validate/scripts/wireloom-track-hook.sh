#!/bin/sh
# Codex PostToolUse hook: record markdown files touched during this session.

run_wireloom_track_hook() {
  runtime="${WIRELOOM_RUNTIME:-auto}"
  input_file=$(mktemp "${TMPDIR:-/tmp}/codex-wireloom-track-input.XXXXXX.json")
  script_file=$(mktemp "${TMPDIR:-/tmp}/codex-wireloom-track.XXXXXX.mjs")

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
        cleanup
        return 0
      fi
      ;;
    bun|node)
      if command -v "$runtime" >/dev/null 2>&1; then
        runner="$runtime"
      else
        cleanup
        return 0
      fi
      ;;
    *)
      cleanup
      return 0
      ;;
  esac

  cat > "$script_file" <<'JS'
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const inputPath = process.env.CODEX_WIRELOOM_TRACK_INPUT;

function readHookInput() {
  try {
    const raw = fs.readFileSync(inputPath, 'utf8').trim();
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function statePath(input, cwd) {
  const stateRoot = process.env.CODEX_WIRELOOM_STATE_DIR
    || path.join(os.homedir(), '.local', 'state', 'codex-wireloom-validate');
  const rawId = input.session_id || input.turn_id || cwd;
  const safeId = Buffer.from(String(rawId)).toString('base64url');
  return path.join(stateRoot, `${safeId}.files`);
}

function normalizeMarkdownPath(cwd, rawPath) {
  if (typeof rawPath !== 'string' || !/\.(md|markdown)$/i.test(rawPath)) {
    return null;
  }

  const cleaned = rawPath.trim().replace(/^["']|["']$/g, '');
  if (!cleaned || !/\.(md|markdown)$/i.test(cleaned)) {
    return null;
  }

  const absolute = path.isAbsolute(cleaned) ? cleaned : path.resolve(cwd, cleaned);
  const relative = path.relative(cwd, absolute);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    return null;
  }
  return relative;
}

function pathsFromApplyPatch(command) {
  const paths = [];
  const re = /^\*\*\* (?:Add File|Update File|Delete File|Move to):\s+(.+)$/gm;
  for (const match of command.matchAll(re)) {
    paths.push(match[1].trim());
  }
  return paths;
}

function pathsFromBash(command) {
  const paths = [];
  const re = /(?:^|[\s"'=])((?:\.{1,2}\/|\/)?[A-Za-z0-9_@%+=:,./-]+\.(?:md|markdown))(?:$|[\s"'])/gi;
  for (const match of command.matchAll(re)) {
    paths.push(match[1]);
  }
  return paths;
}

const input = readHookInput();
const cwd = typeof input.cwd === 'string' && input.cwd ? input.cwd : process.cwd();
const toolName = input.tool_name || '';
const command = input.tool_input && typeof input.tool_input.command === 'string'
  ? input.tool_input.command
  : '';

let rawPaths = [];
if (toolName === 'apply_patch') {
  rawPaths = pathsFromApplyPatch(command);
} else if (toolName === 'Bash') {
  rawPaths = pathsFromBash(command);
}

const markdownPaths = [...new Set(rawPaths
  .map((file) => normalizeMarkdownPath(cwd, file))
  .filter(Boolean))];

if (markdownPaths.length === 0) {
  process.exit(0);
}

const filePath = statePath(input, cwd);
fs.mkdirSync(path.dirname(filePath), { recursive: true });
const existing = fs.existsSync(filePath)
  ? fs.readFileSync(filePath, 'utf8').split('\n').filter(Boolean)
  : [];
const next = [...new Set([...existing, ...markdownPaths])].sort();
fs.writeFileSync(filePath, `${next.join('\n')}\n`);
JS

  CODEX_WIRELOOM_TRACK_INPUT="$input_file" "$runner" "$script_file" >/dev/null 2>&1
  cleanup
  return 0
}

run_wireloom_track_hook "$@"
