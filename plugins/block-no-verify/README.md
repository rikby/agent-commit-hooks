# Block No Verify Plugin

Codex and ZCode plugin that blocks attempts to bypass local git hooks.

It catches:

- `git ... --no-verify`
- `git commit -n`
- `git -c core.hooksPath=...`
- GitHub MCP write tools such as `mcp__github__push_files`

## Install From This Repo

Add this repository as a local plugin marketplace:

```sh
codex plugin marketplace add /Users/kirby/home/commithooks
```

Then install:

```sh
codex plugin add block-no-verify@agent-commit-hooks
```

## ZCode

This plugin is listed in `../marketplace.json` (ZCode-shaped, lives in the
`plugins/` directory). The plugin folder carries `.zcode-plugin/plugin.json`
and `.zcode-hooks.json`; ZCode reads the latter (not Codex's `hooks/hooks.json`)
and uses `${CLAUDE_PLUGIN_ROOT}` to locate the runner script.

### Install (local directory)

In ZCode: **Settings → Plugin Management → Discover → `+`** → add as a
**local directory** — point at the **parent `plugins/` directory** (the one
containing `marketplace.json`), not this plugin folder:

```
/Users/kirby/home/commithooks/plugins
```

Then install `block-no-verify` from the resulting marketplace listing. The
plugin installs and enables automatically. The hook runner is enabled
automatically when any plugin contributes a hook — no `hooks.enabled: true`
needed.

### ZCode matcher

The ZCode hook matches `^(Bash|Write|Edit|mcp__github__.*)$` — broader than
the Codex matcher, so it also catches file-write attacks on hook files
(`.git/hooks/*`, `.husky/*`) in addition to `Bash` bypasses. `Write|Edit`
absorb `ApplyPatch` via ZCode's tool-name alias.

## Runtime Dependency

The plugin runner uses the first available option:

1. project-local `node_modules/.bin/block-no-verify`
2. `block-no-verify` on `PATH`
3. `bunx block-no-verify`
4. `pnpm exec block-no-verify`
5. `npm exec --yes block-no-verify`

For pinned behavior, install it in the target project:

```sh
bun add -D block-no-verify
```
