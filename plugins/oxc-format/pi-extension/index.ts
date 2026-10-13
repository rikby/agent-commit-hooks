/**
 * pi extension: run the oxc-format hook (oxfmt + oxlint) after edit/write,
 * appending oxlint findings to the tool result so the model sees them.
 *
 * Reuses plugins/oxc-format/scripts/agent-oxc.ts (same stdin contract as the
 * ZCode/Claude/Codex hooks) — no formatting logic lives here.
 *
 * Never throws and never blocks: any failure (bun missing, script missing,
 * spawn error, bad JSON) leaves the tool result untouched. PostToolUse-class
 * hooks cannot undo an edit, so there is nothing to block with.
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const TIMEOUT_MS = 20_000;

function resolveScript(): string | null {
  const here = dirname(fileURLToPath(import.meta.url));
  for (const candidate of [
    join(here, "..", "scripts", "agent-oxc.ts"), // repo layout (also when symlink resolved)
    join(homedir(), "home", "commithooks", "plugins", "oxc-format", "scripts", "agent-oxc.ts"),
  ]) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

/** Run the hook script; resolve with stdout, or "" on any failure. */
function runHook(script: string, cwd: string, payload: string): Promise<string> {
  return new Promise((resolve) => {
    let child: ReturnType<typeof spawn>;
    try {
      child = spawn("bun", [script], { cwd, stdio: ["pipe", "pipe", "ignore"] });
    } catch {
      resolve("");
      return;
    }
    let out = "";
    const timer = setTimeout(() => child.kill("SIGKILL"), TIMEOUT_MS);
    child.stdout.on("data", (chunk: Buffer) => (out += chunk));
    child.on("error", () => {
      clearTimeout(timer);
      resolve("");
    });
    child.on("close", () => {
      clearTimeout(timer);
      resolve(out);
    });
    child.stdin.on("error", () => {}); // EPIPE if the script exits early
    child.stdin.end(payload);
  });
}

export default function oxcFormat(pi: ExtensionAPI) {
  const script = resolveScript();
  if (!script) return;

  pi.on("tool_result", async (event, ctx) => {
    if (event.isError || event.parentToolCallId) return;
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const path = event.input?.path;
    if (typeof path !== "string" || !path) return;

    const payload = JSON.stringify({
      tool_name: event.toolName,
      cwd: ctx.cwd,
      tool_input: { file_path: path },
    });
    const out = (await runHook(script, ctx.cwd, payload)).trim();
    if (!out) return;

    let additionalContext: unknown;
    try {
      additionalContext = JSON.parse(out)?.additionalContext;
    } catch {
      return;
    }
    if (typeof additionalContext !== "string" || !additionalContext) return;

    return {
      content: [
        ...event.content,
        { type: "text" as const, text: `\n\n${additionalContext}` },
      ],
    };
  });
}
