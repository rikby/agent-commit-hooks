#!/usr/bin/env bun
/**
 * Self-check for the pi extension: drive the real tool_result handler against
 * a temp "opted-in" project (oxfmt/oxlint symlinked into node_modules/.bin).
 * Exits 0 when all assertions pass.
 *
 * Run: bun plugins/oxc-format/pi-extension/selfcheck.ts
 */

import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..", "..", "..");
const BIN = join(REPO, "node_modules", ".bin");

// Minimal ExtensionAPI mock that captures the tool_result handler.
let handler: ((event: any, ctx: any) => Promise<any>) | null = null;
const fakePi = { on: (event: string, h: any) => { if (event === "tool_result") handler = h; } };
const mod = await import("./index.ts");
mod.default(fakePi as any);
if (!handler) {
  console.error("❌ extension did not register a tool_result handler");
  process.exit(1);
}

// Temp opted-in project: both bins in node_modules/.bin, git repo (clean-at-HEAD: no commit → clean).
const proj = mkdtempSync(join(tmpdir(), "oxc-pi-selfcheck-"));
const fs = await import("node:fs");
fs.mkdirSync(join(proj, "node_modules", ".bin"), { recursive: true });
symlinkSync(join(BIN, "oxfmt"), join(proj, "node_modules", ".bin", "oxfmt"));
symlinkSync(join(BIN, "oxlint"), join(proj, "node_modules", ".bin", "oxlint"));
writeFileSync(join(proj, "bug.ts"), "debugger\n");
writeFileSync(join(proj, "clean.ts"), "const a = 1;\nexport const b = a;\n");

const ctx = { cwd: proj };
const call = (file: string) =>
  handler!(
    {
      toolName: "edit",
      toolCallId: "t1",
      input: { path: file },
      content: [{ type: "text", text: "ok" }],
      isError: false,
    },
    ctx,
  );

let failed = 0;
const assert = (name: string, cond: boolean) => {
  console.log(cond ? `✅ PASS ${name}` : `❌ FAIL ${name}`);
  if (!cond) failed++;
};

// 1. Findings are appended to the tool result content.
const r1 = await call("bug.ts");
assert(
  "findings appended as extra text content",
  Array.isArray(r1?.content) &&
    r1.content.length === 2 &&
    r1.content[1].text.includes("oxlint findings in bug.ts"),
);

// 2. Clean file → no findings → handler returns undefined (result untouched).
const r2 = await call("clean.ts");
assert("clean file leaves result untouched", r2 === undefined);

// 3. Non-edit/write tools are ignored.
const r3 = await handler!(
  { toolName: "bash", toolCallId: "t2", input: {}, content: [], isError: false },
  ctx,
);
assert("non-edit tools ignored", r3 === undefined);

rmSync(proj, { recursive: true, force: true });
process.exit(failed ? 1 : 0);
