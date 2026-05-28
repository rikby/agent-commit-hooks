# Install Wireloom Validate

From this repository checkout:

```sh
codex plugin marketplace add /Users/kirby/home/commithooks
```

Then install:

```sh
codex plugin add wireloom-validate@agent-commit-hooks
```

Configure projects that use Wireloom blocks:

```sh
export WIRELOOM_INDEX_PATH="./node_modules/wireloom/dist/index.js"
export WIRELOOM_RUNTIME="auto"
```

If missing, build the parser from:

```sh
git clone https://github.com/StardockCorp/Wireloom.git
cd Wireloom
npm install
npm run build
```
