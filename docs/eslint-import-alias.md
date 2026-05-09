# ESLint Import Alias Plugin

Installation guide for [`@dword-design/eslint-plugin-import-alias`](https://github.com/dword-design/eslint-plugin-import-alias) — enforces import aliases and auto-fixes relative paths like `../../model/foo` → `@/model/foo`.

## 1. Install

```sh
bun add -D @dword-design/eslint-plugin-import-alias
```

> npm also works: `npm install -D @dword-design/eslint-plugin-import-alias`

Requires an existing ESLint setup (flat config / `eslint.config.ts`).

## 2. Configure ESLint

Add the plugin to your ESLint config:

```ts
// eslint.config.ts

import { defineConfig } from 'eslint/config';
import importAlias from '@dword-design/eslint-plugin-import-alias';

export default defineConfig([
  importAlias.configs.recommended,
]);
```

## 3. Define aliases

Pick **one** source for alias definitions (the plugin loads them automatically).

### Option A: `tsconfig.json` `paths` (recommended for TS projects)

```jsonc
// tsconfig.json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"],
      "@components/*": ["./src/components/*"]
    }
  }
}
```

No extra config needed — the plugin reads `tsconfig.json` automatically. To disable: set `shouldReadTsConfig: false` in rule options.

### Option B: Plugin `alias` option (no tsconfig needed)

```ts
// eslint.config.ts
import { defineConfig } from 'eslint/config';
import importAlias from '@dword-design/eslint-plugin-import-alias';

export default defineConfig([
  importAlias.configs.recommended,
  {
    rules: {
      '@dword-design/import-alias/prefer-alias': [
        'error',
        {
          alias: {
            '@': './src',
            '@components': './src/components',
          },
        },
      ],
    },
  },
]);
```

### Option C: babel-plugin-module-resolver

If you use [`babel-plugin-module-resolver`](https://www.npmjs.com/package/babel-plugin-module-resolver), the plugin loads its `alias` and `resolvePath` options automatically. To disable: set `shouldReadBabelConfig: false`.

## 4. Subpath aliasing (optional)

By default, only parent paths (`../model/foo`) are converted to aliases. Subpath imports stay relative. To also convert subpaths:

```ts
rules: {
  '@dword-design/import-alias/prefer-alias': ['error', { aliasForSubpaths: true }],
}
```

## 5. Alias priority

Inner (more specific) aliases are preferred over outer ones. With:

```ts
{ alias: { '@': './app', '@@': '.' } }
```

A file inside `app/` gets `@/...` (not `@@/...`). This lets you define specific aliases (`@components`, `@utils`) that win over a generic root alias.

## 6. Verify

```sh
npx eslint --fix src/
```

Relative imports matching your aliases should be auto-fixed.
