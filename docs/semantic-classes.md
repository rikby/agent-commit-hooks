# Enforce Semantic Class Names — Linter Concept & Design

A pre-commit hook that blocks CSS-framework utility classes (Tailwind,
WindiCSS, UnoCSS, …) from being written directly into component markup, so a
project committed to **semantic class names** can keep utilities out of the
render layer and protect its `@layer components` CSS contract.

> **Status:** Proof of concept, shipped in this repo (`agent-commit-hooks`) as
> `scripts/enforce-semantic-classes.{sh,mjs}` + `configs/general/enforce-semantic-classes.yml`.
> Validated against two real projects:
> - a **React + Tailwind v3** codebase where the motivating incident occurred
> - a **Svelte 5 + SvelteKit** codebase (no Tailwind) used as the false-positive control

---

## 1. The problem this solves

### 1.1 The cascade-layer hazard

Modern CSS uses cascade layers to order rule priority. Tailwind (v3 and v4)
emits its utilities into `@layer utilities`, and most semantic design systems
put their component rules into `@layer components`. The cascade resolves
layers in **declaration order**, and Tailwind declares `components` *before*
`utilities`:

```css
@layer base, components, utilities;   /* ← Tailwind's order */
```

This means **a utility always beats a component rule for the same property**,
regardless of specificity. That is by design — it lets utilities override
component defaults. The hazard is when a utility is written straight into the
markup of a component that *also* owns a CSS contract:

```tsx
// TicketCard.tsx — the component owns a semantic contract:
//   src/components/TicketCard/ticket.css → @layer components { .ticket-card { … } }
<div className="ticket-card flex h-9">
  {/*           ^^^^^^^^^^^ ^^^^ ^^^
                  semantic   │    │
                             └────└──these utilities now outrank any
                                     .ticket-card rule for display/height */}
```

The defect is **invisible in the stylesheet**: the `.ticket-card` rule looks
correct, but `h-9` silently overrides any height declared there. Debugging it
requires knowing that the utility layer wins — knowledge a contributor may not
have, and that the code does not surface.

### 1.2 Why this happened in practice

This is not hypothetical. A real React + Tailwind v3 codebase shipped a
defect — `tailwind-utility-beats-component-layer` — where an `h-9` utility in a
header control's JSX outranked an `@layer components` override for the same
element. The component CSS was "correct"; the live UI was wrong. The fix was to
remove the utility from the markup, but nothing prevented its reintroduction —
which is what motivated this hook.

ESLint's existing Tailwind plugins go the *other direction*: they enforce that
utility class names are **canonical** (`no-custom-classname` flags non-Tailwind
tokens), which would flag the *semantic* classes, not the utilities. No
off-the-shelf rule keeps utilities out of component markup. The closest is a
[closed feature request](https://github.com/francoismassart/eslint-plugin-tailwindcss/issues/362)
whose author ended up forking `no-custom-classname` and inverting it — exactly
the approach taken here, generalized and framework-agnostic.

---

## 2. What counts as a "utility"

The linter classifies each class token as **utility** or **semantic**. A token
is a utility when, after stripping CSS-framework variant prefixes
(`sm:`/`md:`/`lg:`, `hover:`/`focus:`, `dark:`, `group-hover:`, arbitrary
`[&>*]:`, …), the base token satisfies **any** of:

| # | Pattern | Example | Why |
|---|---------|---------|-----|
| 1 | Arbitrary value bracket | `min-h-[100dvh]`, `top-[117px]` | Tailwind-specific syntax |
| 2 | Known bare keyword | `flex`, `hidden`, `items-center`, `grid` | Curated set of value-less utilities |
| 3 | `<root>-<value>` where `root` is a known utility root AND `value` is a real utility value | `p-4`, `text-center`, `grid-cols-3`, `bg-blue-500` | Root + value |

### 2.1 Precision over recall (the key design decision)

The naive approach — "flag anything that starts with a known utility root" —
false-positives on semantic names that happen to share a root:

| Semantic name (must NOT flag) | Shares root with | Naive linter? |
|-------------------------------|------------------|---------------|
| `grid-container`             | `grid`           | ❌ false positive |
| `text-body`                  | `text`           | ❌ false positive |
| `card-flex`                  | (none)           | ✅ correct |

The fix is to require a **real utility value** after the root. `container` and
`body` are words, not utility values (`container` is a bare utility on its own;
`body` is not a utility value at all). So:

- `grid-cols-3` → root `grid-cols`, value `3` (numeric) → **utility** ✓
- `grid-container` → root `grid`, value `container` (not a utility value) → **semantic** ✓
- `text-center` → root `text`, value `center` (in known-values set) → **utility** ✓
- `text-body` → root `text`, value `body` (not a known value) → **semantic** ✓

A utility value is: a number, a fraction, an arbitrary bracket, a color shade
(`blue-500`), or a curated keyword (`center`, `between`, `full`, `solid`,
`auto`, …). This keeps precision high on real codebases — validated at zero
false positives across a 66-file semantic Svelte codebase.

### 2.2 What's deliberately NOT a utility

- **Semantic BEM names**: `ticket-card__title`, `badge--red`, `vword__body`
  — no root+value match, no bracket, not a bare keyword.
- **Project design tokens** that look like colors but aren't shades:
  `primary`, `muted-foreground` — matched as semantic unless added to
  `SEMANTIC_ALLOW` or detected as `<color>-<shade>`.

---

## 3. How tokens are extracted (framework-agnostic)

The linter parses class tokens out of markup **without a real parser** — it
walks the source string with a small state machine. This keeps it dependency
free (no `postcss`, no `svelte/compiler`, no babel) and lets one script cover
every framework.

| Syntax | Extracted from | Example |
|--------|----------------|---------|
| Static string | `class="…"` / `className="…"` | `class="flex gap-2"` |
| Expression (string literals) | `class={…}` / `className={…}` | `className={cn("base", cond && "extra")}` |
| Template literal (static parts) | `` class={`…`} `` | `` class={`base flex ${x}`} `` → `base`, `flex` |
| Svelte directive | `class:token` / `class:token={cond}` | `class:active` |
| Vue binding | `:class="…"` | `:class="[a, b]"` |

**Dynamic bindings are skipped** — `class={someVar}` can't be resolved
statically, so it's ignored. String literals *inside* `{…}` expressions are
extracted (`cn("base", cond && "extra")` and ternary `cond ? "a" : "b"`
patterns are covered), but string literals *inside* `${…}` template
interpolations are not — that content is conditional/dynamic, and extracting it
would risk false positives on branches that never execute together. This is the
are covered. This is the same ceiling as `eslint-plugin-tailwindcss`.

### 3.1 Supported file types

`.js .jsx .ts .tsx .mjs .cjs .svelte .vue .html .htm .php .astro .marko .liquid`

---

## 4. The CONTRACT_ONLY precision mode

A blanket "no utilities anywhere" rule is unusable on a Tailwind-saturated
codebase (the motivating project has ~2500 utility occurrences in markup). The
rule that actually matches the hazard is: **utilities only matter where a CSS
contract exists.**

`CONTRACT_ONLY=1` (the default in the shipped config) lints a file only when it
has a colocated `.css` file declaring `@layer components`. "Colocated" means
the CSS lives either:

- in the **same directory** as the component (`SettingsModal/SettingsModal.tsx`
  + `SettingsModal/settings.css`), or
- in a **same-named subdirectory** beside a flat component file
  (`TicketCard.tsx` + `TicketCard/ticket.css`).

A project-wide central `styles/` directory is **intentionally not counted** —
counting it would mark every file as contracted and collapse the mode back to
the blanket rule.

This matches both real layouts we tested:
- a **React project**: `TicketCard.tsx` (flat) + `TicketCard/ticket.css` (subdir)
  → contracted, flagged.
- a **Svelte project**: pure semantic classes, no `@layer components` CSS at all
  → not contracted, skipped (zero noise).

---

## 5. Configuration

All configuration is via environment variables, matching the
`block-shared-imports.sh` convention. Set them in your project's
`lefthook.yml` (or `lefthook-local.yml`) under the script's `env:`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONTRACT_ONLY` | `1` (in shipped config) | Only flag files with a colocated `@layer components` CSS. Set `0` to lint every file. |
| `SEMANTIC_ALLOW` | (empty) | Regex; tokens matching it are never flagged. Add your project's semantic prefixes: `^(ticket-card\|vword\|board-)` |
| `UTILITY_ALLOW` | (empty) | Regex; tokens matching it are always treated as a utility. For project-specific utilities not in the built-in set. |
| `SEMANTIC_QUIET` | `0` | `1` omits the explanatory footer (for compact diff output). |
| `SEMANTIC_FIX_TIP` | `1` | `0` hides the allowlist suggestion. |

### 5.1 Adopting on a new project

1. Add the hook to your `lefthook.yml` remotes (see INSTALL.md pattern).
2. Start with `CONTRACT_ONLY=1` — zero noise, catches only the real hazard.
3. If you have semantic names that share a utility root and get flagged, add
   them to `SEMANTIC_ALLOW`. (In practice this is rare — the value-based
   classification handles most cases.)
4. Optionally set `CONTRACT_ONLY=0` later to enforce a strict "no utilities in
   markup" policy project-wide.

---

## 6. Why a script, not an ESLint rule

An ESLint rule was the first design considered (see the research that preceded
this doc). It was rejected for this hook's purpose:

| Concern | ESLint rule | Standalone script |
|---------|-------------|-------------------|
| Framework coverage | One rule per parser (JSX needs eslint, Svelte needs eslint-plugin-svelte, Vue needs eslint-plugin-vue) | **One script, all frameworks** — parses raw markup |
| Dependencies | Pulls in the ESLint + parser chain | **Zero npm deps** — runs on node or bun alone |
| Adoptability | Requires the project to already use ESLint + flat config + the right parser | **Works on any project** with node or bun |
| Fits lefthook | Awkward — ESLint configs are per-project, can't be shipped via remote | **Natural fit** — matches the block-shared-imports.sh / check-wireloom-blocks.sh pattern already in this repo |
| Precision features (CONTRACT_ONLY) | Possible but requires reading CSS from an ESLint rule context | **Straightforward** — filesystem access is trivial |

The tradeoff: an ESLint rule gives editor-inline squiggles and autofix
infrastructure for free. If a project wants that, the classification logic in
`enforce-semantic-classes.mjs` (`classify`, `extractClassTokens`) is exported
and could be wrapped in a custom ESLint rule without rewriting the detection.
The script is the right default for a shared, cross-project hook; the ESLint
rule is a project-local enhancement.

---

## 7. Relationship to existing tools

| Tool | What it does | vs. this hook |
|------|--------------|---------------|
| [`eslint-plugin-tailwindcss`](https://github.com/francoismassart/eslint-plugin-tailwindcss) `no-custom-classname` | Flags classes that are **NOT** Tailwind utilities | **Inverse** — would flag semantic classes, not utilities |
| Same plugin, [issue #362](https://github.com/francoismassart/eslint-plugin-tailwindcss/issues/362) "whitelist Tailwind classes" | Requested, closed; author forked `no-custom-classname` | This hook generalizes that inversion, framework-agnostic |
| [`eslint-plugin-tailwind-canonical-classes`](https://github.com/MaisonnatM/eslint-plugin-tailwind-canonical-classes) | Normalizes Tailwind name spelling via v4 canonicalization | Orthogonal — about *spelling* of utilities, not *presence* |
| [stylelint `selector-class-pattern`](https://stylelint.io/user-guide/rules/selector-class-pattern/) | Regex-enforces class naming in `.css` files | Wrong layer — catches CSS selectors, not the JSX/Svelte `className` that's actually overriding the component layer |

No off-the-shelf rule keeps utilities out of component markup. The detection
machinery (token extraction, "is this a utility?") is the solved part — this
hook inverts it and adds the `CONTRACT_ONLY` precision mode that makes it
usable on real codebases.

---

## 8. Limitations & honest gaps

- **Dynamic class bindings are invisible.** `class={someVar}` cannot be
  analyzed statically; the hook skips them. String literals inside expressions
  are still caught, so `cn("a", x && "b")` is covered, but fully dynamic
  `class={computedClassName}` is not. This is the same ceiling as every
  Tailwind ESLint rule.
- **The utility root/value sets are heuristic, not exhaustive.** They cover
  Tailwind v3/v4's common surface, but novel utilities (custom plugins,
  UnoCSS presets) may slip through unless added to `UTILITY_ALLOW`. There is
  no integration with `tailwind.config.js` `resolveConfig` — that would make
  detection exact but reintroduce the dependency chain this hook avoids.
- **`CONTRACT_ONLY` depends on CSS colocation.** Projects that put all CSS in
  a central `styles/` with no per-component colocation won't benefit from the
  precision mode — every file is either all-contracted or none-contracted.
  For those, use `CONTRACT_ONLY=0` with a good `SEMANTIC_ALLOW`.
- **No autofix.** The hook reports; it doesn't rewrite markup. Moving a
  utility into a semantic class is a judgment call (which class? which
  property?) that doesn't automate cleanly.

---

## 9. Files

| File | Role |
|------|------|
| `scripts/enforce-semantic-classes.mjs` | The linter — token extraction, utility classification, contract detection. Dependency-free, runs on node or bun. |
| `scripts/enforce-semantic-classes.sh` | Thin shell wrapper so lefthook can invoke it with `runner: sh` (matches repo convention). |
| `configs/general/enforce-semantic-classes.yml` | Lefthook hook definition — `pre-commit`, globs, default env. |

## 10. Validation evidence

- **React + Tailwind v3 codebase:** a contracted component → 9 utilities
  correctly flagged (`flex`, `items-center`, `gap-2`, …); its semantic
  BEM-style classes correctly NOT flagged.
- **Svelte 5 codebase (no Tailwind):** 66 components scanned, zero false
  positives. Svelte `class:` directives and `class={cond ? "a" : "b"}`
  expressions parsed correctly.
- **Precision suite:** `grid-container`, `text-body`, `card-flex`,
  `sidebar-width`, `badge--red`, `btn-primary` → all correctly semantic.
  `grid`, `grid-cols-3`, `text-center`, `p-4`, `w-full` → all correctly utility.
