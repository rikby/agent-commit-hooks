# Wireloom Validate Plugin

Codex plugin that validates changed markdown `wireloom` fenced blocks when the agent stops.

## Configure

Set Wireloom variables in Codex config, not shell profile exports. Edit
`~/.codex/config.toml`:

```toml
[shell_environment_policy]
inherit = "core"

[shell_environment_policy.set]
WIRELOOM_INDEX_PATH = "/absolute/path/to/Wireloom/dist/index.js"
WIRELOOM_RUNTIME = "auto"
```

`WIRELOOM_INDEX_PATH` can be absolute or relative to the project cwd, but
absolute paths are best for Codex Desktop. Restart Codex after changing config.
Do not store secrets in this file; values are plain text.

If the parser is not available, build it from source:

```sh
git clone https://github.com/StardockCorp/Wireloom.git
cd Wireloom
npm install
npm run build
```

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
