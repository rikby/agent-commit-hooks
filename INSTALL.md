# Installation

For AI coding agents.

## 1. Install lefthook

```sh
bun add -D @evilmartians/lefthook
```

Other options: `brew install lefthook`, `npm install -D @evilmartians/lefthook`, or see
[lefthook guides](https://github.com/evilmartians/lefthook#guides) for more.

## 2. Create `lefthook.yml`

Pick the configs your project needs. Scripts come from the remote repo automatically — no package install needed.

```yaml
min_version: 1.13.0

remotes:
  - git_url: https://github.com/rikby/agent-commit-hooks.git
    configs:
      # Secrets & hygiene — every project
      - configs/general/block-env-files.yml
      - configs/general/block-credential-files.yml
      - configs/general/block-home-paths-code.yml
      - configs/general/block-home-paths-commit-msg.yml
      - configs/general/block-generated-files.yml
      - configs/general/block-co-authored-by.yml
      # Markdown
      - configs/general/check-markdown-fences.yml
      # TypeScript projects
      - configs/typescript/run-knip.yml
      - configs/typescript/run-eslint-staged.yml
      # MDT (optional)
      # - configs/mdt/block-mdt-incomplete-tasks.yml
      # Monorepo (optional)
      # - configs/monorepo/block-shared-imports.yml
```

## 3. Install hooks

```sh
bunx lefthook install
```

> npm also works: `npx lefthook install`

## 4. Block `--no-verify` for AI agents

AI coding agents (Claude Code, Codex, OpenCode, Pi) can bypass git hooks with `--no-verify`, `git config core.hooksPath /dev/null`, or `git stash` manipulation. This defeats pre-commit checks.

Install `block-no-verify` and configure it for every agent you use:

```sh
bun add -D block-no-verify
```

> npm also works: `npm install -D block-no-verify`

### Claude Code

Create `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bunx block-no-verify"
          }
        ]
      }
    ]
  }
}
```

### Codex CLI

Add this repository as a local Codex plugin marketplace:

```sh
codex plugin marketplace add /path/to/agent-commit-hooks
```

Then install the plugin:

```sh
codex plugin add block-no-verify@agent-commit-hooks
```

Codex may ask you to review/trust the hook before it runs.

### OpenCode

Create `opencode.json`:

```json
{
  "permission": {
    "bash": {
      "git *": "ask",
      "*": "allow"
    }
  }
}
```

> **Note:** OpenCode has a known bug where `CI=true git commit` (inline env var prefix) bypasses permission rules ([anomalyco/opencode#16075](https://github.com/anomalyco/opencode/issues/16075)). There is no PreToolUse-style hard block available yet.

### Pi

```sh
pi install https://github.com/rikby/pi-block-no-verify
```

### Cursor

Create `.cursor/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": "bunx block-no-verify"
      }
    ]
  }
}
```

## What `block-no-verify` catches

| Command | Blocked |
|---|---|
| `git commit --no-verify` | Yes |
| `git commit -n` | Yes |
| `git push --no-verify` | Yes |
| `git merge --no-verify` | Yes |
| `git cherry-pick --no-verify` | Yes |
| `git rebase --no-verify` | Yes |
| `git am --no-verify` | Yes |
| `git config core.hooksPath /dev/null` | Yes |
| `git stash && git commit` | No — not covered |

## 5. Verify

```sh
sh .git/info/lefthook-remotes/agent-commit-hooks/scripts/check-deps
```

## Post-install automation

Add to `package.json`:

```json
{
  "scripts": {
    "postinstall": "lefthook install"
  }
}
```
