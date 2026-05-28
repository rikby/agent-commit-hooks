# Block No Verify Plugin

Codex plugin that blocks attempts to bypass local git hooks.

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
