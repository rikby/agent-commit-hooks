# OXC Format Plugin

PostToolUse hook (Claude-schema `hooks/hooks.json`, consumed by ZCode and
Claude Code) that formats and lints the file the agent just touched, using
the oxc stack (`oxfmt` + `oxlint`).

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

## Packaging notes (why so few files)

One manifest + one hooks file serve both ZCode and Claude Code: ZCode's
plugin discovery probes `.claude-plugin/plugin.json` when no
`.zcode-plugin/` exists, and its hook runner expands `${CLAUDE_PLUGIN_ROOT}`.
The `.zcode-plugin/` + `.zcode-hooks.json` pair older plugins here carry is
redundant for new work. Codex is deliberately **not** packaged: its
`apply_patch` tool input is a patch blob without a `file_path` field, so the
script's stdin parsing cannot find the touched file there.

The matcher is `^(Edit|Write)$` — `Write|Edit` absorb `ApplyPatch` via
ZCode's tool-name alias.

## Wiring it up

Two ways; pick one:

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
