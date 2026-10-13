# OXC Format Plugin

PostToolUse hook (Claude-schema, consumed by ZCode and Claude Code via
`.claude-plugin/hooks.json`, and by Codex via the conventional
`hooks/hooks.json`) that formats and lints the file(s) the agent just
touched, using the oxc stack (`oxfmt` + `oxlint`).

Behavior:

- Runs `oxfmt --check` → `oxfmt --write` → `oxlint --fix` on the edited file,
  then reports remaining findings back to the agent via `additionalContext`
  (truncated at 2000 chars).
- **Always exits 0**; PostToolUse cannot undo an edit, so this hook never
  blocks.
- File filter: `.ts .tsx .js .mjs .cjs .jsx .json .jsonc`, skipping `data/`,
  `seeds/`, `de-books/`, `legacy/`, `dist/`, `node_modules/`, `.wrangler/`,
  `.zcode/`, `.tickets/`, `poc/`, `coverage/`.

## Two safety gates

**1. Opt-in for rewrites.** Files are only ever *rewritten* in projects that
depend on the tools themselves (both `oxfmt` and `oxlint` in the project's
`node_modules/.bin`). Everywhere else the hook is observe-only: findings are
reported, never fixed — a Prettier-formatted repo is never churned by a
foreign formatter.

**2. Clean-at-HEAD guard** (within opted-in projects). Whole-file
reformatting only happens on files that were already oxfmt-clean before the
edit — new/untracked files, or tracked files whose HEAD content passes
`oxfmt --check`. Legacy files are lint-reported only, protecting blame and
per-hunk staging until that project's one-time oxfmt baseline lands.

## Tool resolution (pinned, no registry floats)

A file-rewriting hook must not float on latest-of-registry tools. Resolution
order:

1. the project's own `node_modules/.bin/oxfmt` / `oxlint` (the project's pin
   wins),
2. this repo's root `node_modules/.bin` (exact-pinned in `package.json`:
   `oxfmt 0.71.0`, `oxlint 1.86.0`).

If neither resolves, the hook exits silently. To opt a project in:

```sh
bun add -d oxfmt oxlint
```

## Packaging notes

Two manifest+hooks pairs serve three platforms:

| Platform | Manifest | Hooks file | Matcher | Root var |
|---|---|---|---|---|
| Codex | `.codex-plugin/plugin.json` | `hooks/hooks.json` (conventional path) | `^(apply_patch)$` | `${PLUGIN_ROOT}` |
| ZCode | probes `.claude-plugin/plugin.json` | `.claude-plugin/hooks.json` (via its `hooks:` pointer) | `^(Edit\|Write)$` | `${CLAUDE_PLUGIN_ROOT}` |
| Claude Code | `.claude-plugin/plugin.json` | `.claude-plugin/hooks.json` (via its `hooks:` pointer) | `^(Edit\|Write)$` | `${CLAUDE_PLUGIN_ROOT}` |
| pi | — (TypeScript extension) | `pi-extension/index.ts` (`tool_result` handler on `edit`/`write`) | pi tools `edit`, `write` | n/a — uses hook input `cwd` |

Codex support: its `apply_patch` tool input is a patch blob without a
`file_path` field, so the script extracts touched paths from the blob's
`*** Add File:` / `*** Update File:` headers (same technique as
wireloom-validate's Codex hook) and formats/lints every touched file,
joining findings into one `additionalContext` report. Codex sets no project
env var, so the script also falls back to the hook input's `cwd` for the
project root. The older `.zcode-plugin/` + `.zcode-hooks.json` pair carried
by other plugins here is redundant for new work.

pi support: a TypeScript extension (`pi-extension/index.ts`) listens on pi's
`tool_result` event for `edit`/`write` calls, spawns this same script with
the Claude-style stdin payload, and appends the `additionalContext` report
to the tool result so the model sees the findings. All hook logic stays in
`scripts/agent-oxc.ts`; the extension only bridges the input/output shapes.
Self-check: `bun plugins/oxc-format/pi-extension/selfcheck.ts`.

The ZCode/Claude matcher is `^(Edit|Write)$` — `Write|Edit` absorb
`ApplyPatch` via ZCode's tool-name alias.

## Wiring it up

Four ways; pick one per platform.

**pi** — symlink the extension into pi's user extensions directory:

```sh
ln -sf "$PWD/plugins/oxc-format/pi-extension/index.ts" \
  ~/.pi/agent/extensions/oxc-format.ts
```

New pi sessions pick it up; a running session needs `/reload`.

**Codex** — the repo is already a Codex marketplace
(`codex plugin marketplace add /Users/kirby/home/commithooks`), so:

```sh
codex plugin add oxc-format@agent-commit-hooks
```

Codex prompts to trust the hook on first use; a running session picks the
plugin up on restart.

- **Configuration hook (no plugin install, recommended for personal
  machines)** — one stanza in `~/.zcode/cli/config.json` covers every
  workspace:

  ```json
  "PostToolUse": [
    {
      "matcher": "^(Edit|Write)$",
      "hooks": [
        {
          "type": "command",
          "command": "bun /Users/kirby/home/commithooks/plugins/oxc-format/scripts/agent-oxc.ts",
          "timeout": 20
        }
      ]
    }
  ]
  ```

  Configuration hooks need `"enabled": true` on the `hooks` object (the
  block-no-verify stanza usually already set it). New sessions pick the
  stanza up; a running session does not hot-reload.

- **Marketplace install** — add `/Users/kirby/home/commithooks/plugins` as a
  local marketplace (see [block-no-verify's
  README](../block-no-verify/README.md)) and install `oxc-format`. DSH can
  consume the same `hooks/hooks.json` via its
  `@deepseek-ai/dsh-hooks-claude-code` bridge (`configPath`).
