# Wireloom Validate Plugin

Codex plugin that validates changed markdown `wireloom` fenced blocks when the agent stops.

## Configure

Set these in the project environment where Codex runs:

```sh
export WIRELOOM_INDEX_PATH="./node_modules/wireloom/dist/index.js"
export WIRELOOM_RUNTIME="auto" # auto, node, or bun
```

`WIRELOOM_INDEX_PATH` can be absolute or relative to the project cwd.

## Install From This Repo

Add this repository as a local plugin marketplace:

```sh
codex plugin marketplace add /Users/kirby/home/commithooks
```

Then install:

```sh
codex plugin add wireloom-validate@agent-commit-hooks
```

## Behavior

- Skips quickly when changed markdown files have no `wireloom` blocks.
- Validates only markdown files touched by the current Codex session.
- Returns structured Codex `Stop` feedback on the first validation failure.
- Allows later `stop_hook_active=true` attempts so the agent is not trapped in a loop.
