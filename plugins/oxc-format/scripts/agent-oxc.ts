#!/usr/bin/env bun
/**
 * ZCode/Claude/Codex PostToolUse hook: format + lint the file(s) the agent
 * just touched (oxc stack: oxfmt + oxlint).
 *
 * stdin  : hook JSON.
 *          - Claude/ZCode: { tool_name, tool_input: { file_path } }
 *          - Codex:       { tool_name: "apply_patch", cwd,
 *                           tool_input: { command: "<patch blob>" } }
 *          Touched files come from file_path — or, for apply_patch, from
 *          the patch's `*** Add File:` / `*** Update File:` headers.
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
import { homedir, tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";

interface HookInput {
  tool_name?: string;
  cwd?: string;
  tool_input?: { file_path?: string; path?: string; command?: string };
}

const EXT = /\.(ts|tsx|js|mjs|cjs|jsx|json|jsonc)$/;
const SKIP_DIR =
  /^(data|seeds|de-books|legacy|dist|node_modules|\.wrangler|\.zcode|\.tickets|poc|coverage)\//;
const MAX_FINDINGS_CHARS = 2000;

let input: HookInput;
try {
  input = JSON.parse(await Bun.stdin.text()) as HookInput;
} catch {
  process.exit(0);
}

// Codex sets no project env var — fall back to the hook input's cwd.
const root =
  process.env.ZCODE_PROJECT_DIR ?? process.env.CLAUDE_PROJECT_DIR ?? input.cwd;
if (!root) process.exit(0);

// Claude/ZCode name the file directly; Codex apply_patch carries a patch
// blob whose `*** Add/Update File:` headers name the touched files.
const rawFiles =
  input.tool_name === "apply_patch"
    ? [
        ...new Set(
          [
            ...(input.tool_input?.command ?? "").matchAll(
              /^\*\*\* (?:Add File|Update File):\s+(.+)$/gm,
            ),
          ].map((m) => m[1].trim()),
        ),
      ]
    : [input.tool_input?.file_path ?? input.tool_input?.path ?? ""].filter(Boolean);
if (rawFiles.length === 0) process.exit(0);

// Project pin first, then the distribution repo's pin (walk up from here;
// when installed as a plugin the script runs from an app cache dir with no
// node_modules ancestor, so fall back to the repo's documented home).
async function resolveBin(name: string): Promise<string | null> {
  const projectBin = join(root!, "node_modules", ".bin", name);
  if (await Bun.file(projectBin).exists()) return projectBin;
  let dir = import.meta.dir;
  for (;;) {
    const p = join(dir, "node_modules", ".bin", name);
    if (await Bun.file(p).exists()) return p;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const homeRepoBin = join(homedir(), "home", "commithooks", "node_modules", ".bin", name);
  if (await Bun.file(homeRepoBin).exists()) return homeRepoBin;
  return null;
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

// Returns the report text for one touched file, or "" when nothing to say.
async function findingsFor(raw: string): Promise<string> {
  const file = raw.startsWith("/") ? raw : join(root, raw);
  if (!file.startsWith(`${root}/`)) return "";
  if (!EXT.test(file)) return "";
  const rel = file.slice(root.length + 1);
  if (SKIP_DIR.test(rel)) return "";
  if (!(await Bun.file(file).exists())) return "";

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

  // oxlint exits 0 even with warnings, and its piped output (1.86) carries
  // no "Found N warnings" summary — detect findings from the lines themselves.
  const text = new TextDecoder().decode(lint.stdout).trim();
  if (/^\S+:\d+:\d+: (?:warning|error)\b/m.test(text)) {
    const body =
      text.length > MAX_FINDINGS_CHARS ? `${text.slice(0, MAX_FINDINGS_CHARS)}\n… (truncated)` : text;
    const prefix =
      mode === "fixed"
        ? `oxlint findings in ${rel} (auto-fixable ones already applied):`
        : mode === "legacy"
          ? `oxlint findings in ${rel} (report only — file not oxfmt-baselined, no fixes applied):`
          : `oxlint findings in ${rel} (report only — project not opted in to oxfmt formatting, no fixes applied):`;
    return `${prefix}\n${body.replaceAll(`${root}/`, "")}`;
  }
  return "";
}

const reports: string[] = [];
for (const raw of rawFiles) reports.push(await findingsFor(raw));
const joined = reports.filter(Boolean).join("\n\n");
if (joined) {
  console.log(
    JSON.stringify({ hookEventName: "PostToolUse", additionalContext: joined }),
  );
}
process.exit(0);
