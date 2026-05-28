# Install Block No Verify

From this repository checkout:

```sh
codex plugin marketplace add /Users/kirby/home/commithooks
```

Then install:

```sh
codex plugin add block-no-verify@agent-commit-hooks
```

For pinned runtime behavior, install the dependency in target projects:

```sh
bun add -D block-no-verify
```
