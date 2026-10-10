#!/usr/bin/env bun
/**
 * ZCode/Claude PostToolUse hook: format + lint the file the agent just
 * touched (oxc stack: oxfmt + oxlint).
 *
 * stdin  : hook JSON { tool_name, tool_input: { file_path } }
 * stdout : empty on success; on remaining oxlint findings exactly one
 *          strict-schema object:
 *          {"hookEventName":"PostToolUse","additionalContext":"..."}
 * exit   : always 0 (PostToolUse cannot undo an edit; never block here).
 *
 * Tool resolution (no registry floats in a file-rewriting hook): prefer the
 * project's own `node_modules/.bin` (the project's pin wins), then walk up
 * from this script to the distribution repo's `node_modules/.bin` (the
 * commithooks pin). If neither oxfmt nor oxlint resolves, exit silently.
 *
 * Opt-in gate: files are only ever REWRITTEN (oxfmt --write / oxlint --fix)
 * in projects that depend on the tools themselves (both bins in the
 * project's node_modules/.bin). Everywhere else the hook is observe-only —
 * a foreign-formatter repo gets findings reported, never reformatting.
 *
 * Clean-at-HEAD guard (within opted-in projects): whole-file reformatting is
 * only safe on files that were already oxfmt-clean before the agent touched
 * them — new/untracked files, or tracked files whose HEAD content passes
 * `oxfmt --check`. Legacy files are lint-reported only, protecting blame and
 * per-hunk staging until the one-time oxfmt baseline commit lands.
 */

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";

interface HookInput {
  tool_input?: { file_path?: string; path?: string };
}

const EXT = /\.(ts|tsx|js|mjs|cjs|jsx|json|jsonc)$/;
const SKIP_DIR =
  /^(data|seeds|de-books|legacy|dist|node_modules|\.wrangler|\.zcode|\.tickets|poc|coverage)\//;
const MAX_FINDINGS_CHARS = 2000;

const root = process.env.ZCODE_PROJECT_DIR ?? process.env.CLAUDE_PROJECT_DIR;
if (!root) process.exit(0);

let input: HookInput;
try {
  input = JSON.parse(await Bun.stdin.text()) as HookInput;
} catch {
  process.exit(0);
}
const raw = input.tool_input?.file_path ?? input.tool_input?.path;
if (!raw) process.exit(0);

const file = raw.startsWith("/") ? raw : join(root, raw);
if (!file.startsWith(`${root}/`)) process.exit(0);
if (!EXT.test(file)) process.exit(0);
const rel = file.slice(root.length + 1);
if (SKIP_DIR.test(rel)) process.exit(0);
if (!(await Bun.file(file).exists())) process.exit(0);

// Project pin first, then the distribution repo's pin (walk up from here).
async function resolveBin(name: string): Promise<string | null> {
  const projectBin = join(root!, "node_modules", ".bin", name);
  if (await Bun.file(projectBin).exists()) return projectBin;
  let dir = import.meta.dir;
  for (;;) {
    const p = join(dir, "node_modules", ".bin", name);
    if (await Bun.file(p).exists()) return p;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

const oxfmt = await resolveBin("oxfmt");
const oxlint = await resolveBin("oxlint");
if (!oxfmt && !oxlint) process.exit(0);

// Opt-in: only projects that install the tools themselves get rewritten.
const hasProjectBin = async (name: string) =>
  Bun.file(join(root!, "node_modules", ".bin", name)).exists();
const optedIn = (await hasProjectBin("oxfmt")) && (await hasProjectBin("oxlint"));

const sh = (args: string[]) =>
  Bun.spawnSync(args, { cwd: root!, stdout: "pipe", stderr: "pipe", stdin: "ignore" });

let lint;
// Which report-only/auto-fix path actually ran — the message must not claim
// fixes were applied when the guard skipped them.
let mode: "fixed" | "legacy" | "observe" = "observe";
if (optedIn && oxfmt && oxlint) {
  // Was the file oxfmt-clean before the agent touched it? Not in HEAD counts
  // as clean (new file, nothing to protect); tracked files must pass
  // oxfmt --check on their HEAD content, probed via a same-extension file.
  const head = Bun.spawnSync(["git", "show", `HEAD:${rel}`], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  let cleanAtHead: boolean;
  if (head.exitCode !== 0) {
    cleanAtHead = true; // new/untracked file
  } else {
    const probeDir = mkdtempSync(join(tmpdir(), "oxc-hook-"));
    const probe = join(probeDir, basename(file));
    writeFileSync(probe, head.stdout);
    cleanAtHead = sh([oxfmt, "--check", probe]).exitCode === 0;
    rmSync(probeDir, { recursive: true, force: true });
  }

  if (cleanAtHead) {
    if (sh([oxfmt, "--check", file]).exitCode !== 0) sh([oxfmt, "--write", file]);
    lint = sh([oxlint, "--fix", file]); // remaining unfixed issues are reported
    mode = "fixed";
  } else {
    lint = sh([oxlint, file]); // legacy file: report only, never rewrite
    mode = "legacy";
  }
} else {
  lint = sh([oxlint!, file]); // observe-only project: report, never rewrite
}

// oxlint exits 0 even with warnings, so detect findings from its summary line.
const text = new TextDecoder().decode(lint.stdout).trim();
const m = text.match(/^Found (\d+) warnings? and (\d+) errors?\./m);
if (m && (m[1] !== "0" || m[2] !== "0")) {
  const body =
    text.length > MAX_FINDINGS_CHARS ? `${text.slice(0, MAX_FINDINGS_CHARS)}\n… (truncated)` : text;
  const prefix =
    mode === "fixed"
      ? `oxlint findings in ${rel} (auto-fixable ones already applied):`
      : mode === "legacy"
        ? `oxlint findings in ${rel} (report only — file not oxfmt-baselined, no fixes applied):`
        : `oxlint findings in ${rel} (report only — project not opted in to oxfmt formatting, no fixes applied):`;
  console.log(
    JSON.stringify({
      hookEventName: "PostToolUse",
      additionalContext: `${prefix}\n${body}`,
    }),
  );
}
process.exit(0);
