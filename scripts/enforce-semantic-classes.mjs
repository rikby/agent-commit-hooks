#!/usr/bin/env node
//
// enforce-semantic-classes.mjs
//
// Flags CSS-framework utility classes (Tailwind, WindiCSS, UnoCSS, …) in
// component markup so that a project committed to semantic class names can keep
// utilities out of the render layer.
//
// Why this exists
// ───────────────
// Utility classes live in the CSS `@layer utilities` cascade layer, which always
// outranks `@layer components`. A utility written directly in JSX/Svelte markup
// therefore silently shadows any component-layer rule for the same property — a
// defect that is invisible in the stylesheet and very hard to debug
// (see markdown-ticket's `tailwind-utility-beats-component-layer` incident).
// This hook catches such utilities at commit time, before they ship.
//
// What it classifies as a "utility"
// ─────────────────────────────────
// A token is flagged as a utility when, after stripping CSS-framework variant
// prefixes (responsive `sm:`/`md:`/`lg:`, state `hover:`/`focus:`, `dark:`,
// `group-hover:`, arbitrary `[…]:` etc.), the base token:
//   1. uses an arbitrary value bracket  →  `min-h-[100dvh]`, `top-[117px]`
//   2. matches a known bare keyword     →  `flex`, `hidden`, `items-center`
//   3. is `<utility-root>-<utility-value>` where root is a known Tailwind root
//      (p, m, w, h, text, bg, border, rounded, gap, grid-cols, …) AND the value
//      is a real utility value (a number, a scale keyword, a color shade, a
//      fraction, or a known non-numeric value like `center`/`between`/`full`).
//
// Precision over recall: matching the root alone would false-positive on
// semantic names that happen to start with a root (`grid-container`, `text-body`,
// `card-flex`). Requiring a real utility value keeps semantic names clean.
//
// Frameworks / syntax supported
// ─────────────────────────────
//   React/JSX .jsx .tsx :  className="…"  className={`…`}  className={cn(…)}
//   Svelte      .svelte :  class="…"  class={…}  class:name  class:name={cond}
//   Vue         .vue    :  class="…"  :class="…"
//   HTML/PHP    .html…  :  class="…"
//
// Dynamic bindings that can't be resolved statically (class={someVar}) are
// skipped — string literals inside expressions are still extracted, so
// `class={cond ? "a" : "b"}` and `cn("base", cond && "extra")` are covered.
//
// Configuration (env vars — matches the block-shared-imports.sh convention)
// ────────────────────────────────────────────────────────────────────────
//   SEMANTIC_ALLOW       extra regex; tokens matching it are never flagged
//                        (e.g. '^(ticket-card|vword)' ). Combine with the
//                        built-ins below via OR.
//   UTILITY_ALLOW        regex; tokens matching it are always treated as a
//                        utility (project-specific utilities not in the set).
//   CONTRACT_ONLY=1      only flag a file when it has a sibling/same-name .css
//                        that declares `@layer components` (the precise rule:
//                        utilities only matter where a CSS contract exists).
//   SEMANTIC_QUIET=1     omit the explanatory footer (for -c diff output).
//   SEMANTIC_FIX_TIP=0   hide the autofix suggestion.
//
// Exit codes: 0 = clean, 1 = violations found, 2 = usage error.
//
// Usage:
//   node enforce-semantic-classes.mjs <file> [<file>…]
//   bun  enforce-semantic-classes.mjs <file> [<file>…]
//   git diff --cached --name-only --diff-filter=ACM | \
//     grep -E '\.(jsx?|tsx?|svelte|vue|html|php)$' | \
//     xargs node enforce-semantic-classes.mjs

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';

// ─────────────────────────────────────────────────────────────────────────────
// 1. Token extraction — pull class tokens out of markup, framework-agnostic
// ─────────────────────────────────────────────────────────────────────────────

// Extensions we lint. Anything else is ignored.
const LINTABLE = /\.(jsx?|tsx?|mjs|cjs|svelte|vue|html?|php|astro|marko|liquid)$/i;

// Match a class attribute start: `class=` or `className=` (JSX). `class:` is
// Svelte's directive and is handled separately.
const ATTR_START = /\b(class(?:Name)?)\s*=\s*/g;
// Svelte class directive: `class:token` or `class:token={cond}`. The token is a
// single class name (semantic by Svelte convention, but still classified here).
const SVELTE_DIRECTIVE = /\bclass:([A-Za-z0-9_-]+)(?:\s*=|\s)/g;

// Extract every class token from a source string, with the 1-based line number
// of the attribute it came from. Returns [{ token, line }].
function extractClassTokens(source) {
  const out = [];
  const n = source.length;
  let line = 1;

  // Precompute line-start offsets so we can map any index → line cheaply.
  const lineStarts = [0];
  for (let i = 0; i < n; i++) {
    if (source[i] === '\n') lineStarts.push(i + 1);
  }
  const indexToLine = (idx) => {
    // binary search the last lineStart <= idx
    let lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= idx) lo = mid;
      else hi = mid - 1;
    }
    return lo + 1;
  };

  // (a) Svelte class: directives — single tokens.
  for (const m of source.matchAll(SVELTE_DIRECTIVE)) {
    out.push({ token: m[1], line: indexToLine(m.index) });
  }

  // (b) class= / className= attributes — string or expression value.
  for (const m of source.matchAll(ATTR_START)) {
    const valueIdx = m.index + m[0].length;
    const ch = source[valueIdx];
    let tokens;
    if (ch === '"' || ch === "'") {
      tokens = tokensFromQuoted(source, valueIdx, ch);
    } else if (ch === '{') {
      // JSX expression or Svelte/Vue object binding — extract string literals.
      const close = matchingBrace(source, valueIdx);
      if (close !== -1) {
        const region = source.slice(valueIdx + 1, close);
        tokens = tokensFromExpression(region);
      }
    }
    if (tokens && tokens.length) {
      const ln = indexToLine(m.index);
      for (const t of tokens) out.push({ token: t, line: ln });
    }
  }
  return out;
}

// A quoted string value: `"flex items-center"`. Split on whitespace.
function tokensFromQuoted(source, openIdx, quote) {
  let end = openIdx + 1;
  while (end < source.length && source[end] !== quote) {
    if (source[end] === '\\') end++; // skip escaped char
    end++;
  }
  return source.slice(openIdx + 1, end).split(/\s+/).filter(Boolean);
}

// An expression value `{…}`. Collect string literals (double/single/backtick).
// For backtick template literals, keep only the static parts outside `${…}`.
function tokensFromExpression(expr) {
  const tokens = [];
  let i = 0;
  const push = (s) => { for (const t of s.split(/\s+/)) if (t) tokens.push(t); };
  while (i < expr.length) {
    const c = expr[i];
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < expr.length && expr[j] !== c) { if (expr[j] === '\\') j++; j++; }
      push(expr.slice(i + 1, j));
      i = j + 1;
    } else if (c === '`') {
      // template literal — collect literal segments, skip ${…}
      let j = i + 1;
      let seg = '';
      while (j < expr.length && expr[j] !== '`') {
        if (expr[j] === '\\' && j + 1 < expr.length) { seg += expr[j + 1]; j += 2; continue; }
        if (expr[j] === '$' && expr[j + 1] === '{') {
          push(seg); seg = '';
          let depth = 1, k = j + 2;
          while (k < expr.length && depth > 0) {
            if (expr[k] === '{') depth++;
            else if (expr[k] === '}') depth--;
            k++;
          }
          j = k; continue;
        }
        seg += expr[j]; j++;
      }
      if (seg) push(seg);
      i = j + 1;
    } else {
      i++;
    }
  }
  return tokens;
}

// Find the matching closing brace for the `{` at openIdx, respecting quotes.
function matchingBrace(source, openIdx) {
  let depth = 0;
  let i = openIdx;
  while (i < source.length) {
    const c = source[i];
    if (c === '"' || c === "'" || c === '`') {
      i = skipString(source, i, c);
      continue;
    }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return i; }
    i++;
  }
  return -1;
}

function skipString(source, openIdx, quote) {
  let i = openIdx + 1;
  while (i < source.length) {
    if (source[i] === '\\') { i += 2; continue; }
    if (source[i] === quote) return i + 1;
    // template literal interpolations
    if (quote === '`' && source[i] === '$' && source[i + 1] === '{') {
      let depth = 1, k = i + 2;
      while (k < source.length && depth > 0) {
        if (source[k] === '{') depth++;
        else if (source[k] === '}') depth--;
        k++;
      }
      i = k; continue;
    }
    i++;
  }
  return i;
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Utility classification — is a token a CSS-framework utility?
// ─────────────────────────────────────────────────────────────────────────────

// Variant prefixes to strip: responsive (sm:/md:/lg:/xl:/2xl:), state
// (hover:/focus:/active:/group-hover:/focus-visible:/disabled:/…), color-scheme
// (dark:), and arbitrary variants ([&>*]:, [@media…]:). Multiple stack:
// `dark:hover:focus-visible:bg-red-500` → base `bg-red-500`.
function stripVariants(token) {
  let base = token;
  for (;;) {
    // a variant is `<seg>:` where seg has no `]` unclosed and no whitespace
    const v = /^([A-Za-z0-9_-]+|\[[^\]]*\]):/.exec(base);
    if (!v) break;
    base = base.slice(v[0].length);
  }
  return base;
}

// Bare keywords — utilities with no value suffix. Keep this curated; these are
// the only value-less tokens flagged. (Do NOT add short words that double as
// semantic roots.)
const BARE_KEYWORDS = new Set([
  // display
  'flex','inline-flex','grid','inline-grid','hidden','block','inline-block','inline',
  'contents','flow-root','table','table-row','table-cell','list-item',
  // position
  'static','relative','absolute','fixed','sticky',
  // typography
  'italic','not-italic','uppercase','lowercase','capitalize','normal-case',
  'underline','line-through','no-underline','overline','decoration-none',
  'antialiased','subpixel-antialiased','truncate','text-ellipsis','text-clip',
  'text-center','text-left','text-right','text-justify','text-start','text-end',
  'align-baseline','align-top','align-middle','align-bottom','align-text-top',
  'align-text-bottom','align-sub','align-super',
  'whitespace-normal','whitespace-nowrap','whitespace-pre','whitespace-pre-line',
  'whitespace-pre-wrap','break-normal','break-words','break-all',
  'list-none','list-disc','list-decimal','list-inside','list-outside',
  // box / float
  'box-border','box-content','float-left','float-right','float-none',
  'clear-left','clear-right','clear-both','clear-none',
  // flexbox / grid alignment (value-less forms)
  'flex-row','flex-col','flex-row-reverse','flex-col-reverse',
  'flex-wrap','flex-nowrap','flex-wrap-reverse','flex-1','flex-auto','flex-none',
  'flex-initial','flex-grow','flex-grow-0','flex-shrink','flex-shrink-0',
  'items-start','items-end','items-center','items-baseline','items-stretch','items-normal',
  'justify-start','justify-end','justify-center','justify-between','justify-around',
  'justify-evenly','justify-normal','justify-stretch',
  'justify-items-start','justify-items-end','justify-items-center','justify-items-stretch',
  'self-auto','self-start','self-end','self-center','self-stretch','self-baseline',
  'content-center','content-start','content-end','content-between','content-around',
  'content-evenly','content-baseline','content-stretch','content-normal',
  'place-content-center','place-content-start','place-content-end','place-content-between',
  'place-content-around','place-content-evenly','place-content-stretch',
  'place-items-start','place-items-end','place-items-center','place-items-stretch',
  'place-self-auto','place-self-start','place-self-end','place-self-center','place-self-stretch',
  'grid-flow-row','grid-flow-col','grid-flow-dense','grid-flow-row-dense','grid-flow-col-dense',
  'grow','grow-0','shrink','shrink-0','order-none','container',
  // visibility / a11y
  'visible','invisible','sr-only','not-sr-only','isolate','isolation-auto',
  // overflow
  'overflow-hidden','overflow-visible','overflow-scroll','overflow-auto','overflow-clip',
  'overflow-ellipsis','overflow-x-hidden','overflow-y-hidden',
  // object-fit
  'object-contain','object-cover','object-fill','object-none','object-scale-down',
  // background
  'bg-fixed','bg-local','bg-scroll','bg-clip-border','bg-clip-padding','bg-clip-content',
  'bg-clip-text','bg-repeat','bg-no-repeat','bg-repeat-x','bg-repeat-y','bg-repeat-round',
  'bg-repeat-space','bg-center','bg-top','bg-bottom','bg-left','bg-right','bg-cover','bg-contain',
  // transition / transform / animation
  'transition','transition-none','transition-all','transition-colors','transition-opacity',
  'transition-shadow','transition-transform','transition-duration','transform','transform-gpu',
  'transform-none','animate-none','animate-spin','animate-ping','animate-pulse','animate-bounce',
  // appearance / cursor / pointer / select / resize
  'appearance-none','cursor-auto','cursor-default','cursor-pointer','cursor-wait','cursor-text',
  'cursor-move','cursor-help','cursor-not-allowed','cursor-none','cursor-progress',
  'cursor-grab','cursor-grabbing',
  'pointer-events-none','pointer-events-auto','resize-none','resize','resize-x','resize-y',
  'select-none','select-text','select-all','select-auto',
  // misc
  'rounded','rounded-full','rounded-none',
  'border','border-solid','border-dashed','border-dotted','border-double','border-none',
  'border-collapse','border-separate',
  'ring','outline-none','blur-none',
  'snap-none','touch-none','touch-pan-x','touch-pan-y','touch-pinch-zoom','touch-manipulation',
  'tabular-nums','diagonal-fractions','stacked-fractions','ordinal','slashed-zero',
  'tracking-tight','tracking-normal','tracking-wide',
  'truncate','text-ellipsis',
  'not-sr-only',
  'grid-cols-none','grid-rows-none',
  'aspect-auto','aspect-square','aspect-video',
  'mix-blend-normal','mix-blend-multiply','mix-blend-screen','mix-blend-overlay',
  'mix-blend-darken','mix-blend-lighten','mix-blend-color-dodge','mix-blend-color-burn',
  'mix-blend-hard-light','mix-blend-soft-light','mix-blend-difference','mix-blend-exclusion',
  'mix-blend-hue','mix-blend-saturation','mix-blend-color','mix-blend-luminosity',
]);

// Utility roots that take a value. Ordered: longer/multi-word roots first so the
// alternation matches greedily (e.g. `grid-cols` before `grid`, `space-x` before
// `space`, `border-t` before `border`). Anchored as ^(ROOTS)(?:-(.+))?$.
const ROOTS = [
  // multi-word roots (longest first within group)
  'max-w','min-w','max-h','min-h',
  'grid-cols','grid-rows','grid-flow',
  'col-start','col-end','row-start','row-end',
  'auto-cols','auto-rows',
  'flex-grow','flex-shrink','flex-basis',
  'space-x','space-y','divide-x','divide-y',
  'place-content','place-items','place-self',
  'justify-items','justify-self',
  'border-collapse','border-spacing','border-style',
  'ring-offset','backdrop-blur','backdrop-filter','backdrop-brightness','backdrop-contrast',
  'backdrop-grayscale','backdrop-hue-rotate','backdrop-invert','backdrop-opacity',
  'backdrop-saturate','backdrop-sepia',
  'mix-blend','bg-blend','bg-clip','bg-origin','bg-position','bg-size','bg-image',
  'bg-gradient','box-decoration','box-sizing',
  'will-change','transform-origin',
  'stroke-width','pointer-events',
  'overflow-x','overflow-y','overscroll-x','overscroll-y','overscroll',
  'flex-wrap','flex-direction',
  'text-decoration','text-transform','text-overflow','text-orientation','text-align',
  'text-indent','text-justify','text-underline','white-space','word-break','word-spacing',
  'line-clamp','line-height','letter-spacing','font-family','font-weight','font-size',
  'vertical-align','table-layout','border-collapse',
  'grid-template','grid-auto',
  // single-word roots
  'aspect','accent','align','animate','backdrop','basis','bg','blur','bottom',
  'border','break','caret','clear','col','color','content','columns','cursor','decoration',
  'delay','divide','duration','ease','fill','float','font','from','gap','gradient','grid','grow',
  'h','height','hue-rotate','indent','inset','invert','isolate','items','justify','leading','left',
  'list','m','margin','max','mb','me','min','mix-blend','ml','ms','mt','mx','my',
  'object','opacity','order','origin','outline','overflow','overscroll','p','padding','pb','pe',
  'place','pl','pointer-events','pr','ps','pt','px','py','resize','right','ring','rotate',
  'rounded','row','saturate','scale','select','self','shadow','skew','space','stroke','tab','text',
  'to','top','tracking','transform','transition','translate','underline','via','w','width',
  'whitespace','z',
].join('|');

const ROOT_RE = new RegExp(`^(${ROOTS})(?:-(.+))?$`);

// Non-numeric values that are genuine Tailwind utility values. A root+value
// token is a utility only if the value is numeric, fractional, arbitrary, a
// color shade, or in this set. This is what stops `grid-container` (value
// `container`, not in set) from false-positive-ing.
const KNOWN_VALUES = new Set([
  // spacing / sizing scale
  '0','0.5','1','1.5','2','2.5','3','3.5','4','5','6','7','8','9','10','11','12','14','16',
  '20','24','28','32','36','40','44','48','52','56','60','64','72','80','96','112','128','px',
  '0.5x','1x','2x','3x','4x','5x',
  // sizing keywords
  'auto','none','full','screen','max','min','fit','svh','lvh','dvh','svw','lvw','dvw',
  'inherit','initial','revert','unset','transparent','current',
  // scale / typography
  'xs','sm','base','md','lg','xl','2xl','3xl','4xl','5xl','6xl','7xl','8xl','9xl','tiny','wide','narrow',
  'thin','extralight','light','normal','medium','semibold','bold','extrabold','black',
  'sans','serif','mono','display',
  'tight','snug','relaxed','loose',
  'wide','wider','widest','narrower','narrowest',
  // alignment / distribution
  'center','start','end','between','around','evenly','stretch','baseline','normal',
  'top','bottom','left','right','middle','super','sub','first','last',
  // borders / radius
  'solid','dashed','dotted','double','hidden','visible','scroll','clip','ellipsis',
  't','r','b','l','x','y','tl','tr','bl','br','ts','te','bs','be','ss','se',
  'collapse','separate','spacing',
  // flex / grid
  'wrap','nowrap','wrap-reverse','row','col','row-reverse','col-reverse','reverse',
  'square','video','span','full-width',
  // object / background
  'contain','cover','fill','scale-down','local','fixed','absolute','relative','sticky','static',
  'repeat','no-repeat','repeat-x','repeat-y','round','space','clip-text','clip-border',
  'clip-padding','clip-content','border-box','padding-box','content-box',
  // effects
  'blur','grayscale','invert','saturate','sepia','isolate','default',
  // cursor / pointer
  'pointer','wait','text','move','help','not-allowed','progress','grab','grabbing','zoom-in','zoom-out',
  'events-none','events-auto',
]);

function isNumericValue(v) {
  // numbers, negatives, decimals, fractions: 4  -mx-1  0.5  1/2  2/3  -1/2
  return /^-?\d+(\.\d+)?$/.test(v) || /^-?\d+\/\d+$/.test(v);
}

function isColorShade(v) {
  // blue-500, red-100, gray-50, primary, primary-foreground, muted-foreground
  // — a color name optionally with a shade, OR a project token (single word that
  // the project defines in its palette). We only treat <word>-<digits> and
  // <word>-<digits>/opacity as color shades here; bare tokens are left to
  // KNOWN_VALUES / allowlist to avoid false positives.
  return /^[a-z]+-\d{2,3}$/.test(v);            // blue-500
}

// Is the value part of a root-value utility a real utility value?
function isUtilityValue(value) {
  if (value == null) return false;
  if (value.includes('[')) return true;            // arbitrary value: text-[#fff]
  if (isNumericValue(value)) return true;
  if (isColorShade(value)) return true;
  // opacity shorthand: blue-500/50, bg-red-500/80
  if (/^[a-z]+-\d{2,3}\/\d{1,3}$/.test(value)) return true;
  // allow known values (center, between, full, solid, auto, …)
  return KNOWN_VALUES.has(value);
}

// Project-supplied utility allow regex (UTILE_ALLOW env).
const UTILITY_ALLOW_RE = process.env.UTILITY_ALLOW
  ? new RegExp(process.env.UTILITY_ALLOW) : null;

// Classify a single token. Returns 'utility' | 'semantic'.
export function classify(token) {
  const base = stripVariants(token);
  if (UTILITY_ALLOW_RE?.test(base)) return 'utility';
  if (/\[.+\]/.test(base)) return 'utility';       // arbitrary value
  if (BARE_KEYWORDS.has(base)) return 'utility';
  const m = ROOT_RE.exec(base);
  if (m) {
    const value = m[2];
    if (value === undefined) {
      // bare root like `rounded`, `border`, `ring` (no suffix) — most are
      // already in BARE_KEYWORDS; if a bare root reached here without being a
      // known keyword, be conservative (semantic) to avoid false positives.
      return 'semantic';
    }
    if (isUtilityValue(value)) return 'utility';
  }
  return 'semantic';
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Contract detection — only enforce where a CSS contract exists
// ─────────────────────────────────────────────────────────────────────────────

// Does this component file have a CSS contract? True when a `.css` file that
// declares `@layer components` lives either in the same directory as the
// component OR in a same-named subdirectory beside it (the common
// `Component.tsx` + `Component/Component.css` layout). We scan the whole dir
// rather than matching the base name because projects name their CSS freely
// (TicketCard.tsx ↔ ticket.css, settings.css, etc.). A project-wide `styles/`
// directory is intentionally NOT counted — that would mark every file as
// contracted and defeat the opt-in precision mode.
const contractDirCache = new Map();
function dirHasComponentLayer(dir) {
  const abs = path.resolve(dir);
  let cached = contractDirCache.get(abs);
  if (cached !== undefined) return cached;
  cached = false;
  let entries = [];
  try { entries = readdirSync(abs); } catch { entries = []; }
  for (const name of entries) {
    if (!name.endsWith('.css') && !name.endsWith('.module.css')) continue;
    let src;
    try { src = readFileSync(path.join(abs, name), 'utf8'); } catch { continue; }
    if (/@layer\s+components\b/.test(src)) { cached = true; break; }
  }
  contractDirCache.set(abs, cached);
  return cached;
}

function hasComponentContract(file) {
  const dir = path.dirname(file);
  if (dirHasComponentLayer(dir)) return true;
  // Same-named subdirectory beside the component: TicketCard.tsx → TicketCard/
  const base = path.basename(file).replace(/\.[^.]+$/, '');
  return dirHasComponentLayer(path.join(dir, base));
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Main — lint files, report, exit
// ─────────────────────────────────────────────────────────────────────────────

const QUIET = process.env.SEMANTIC_QUIET === '1';
const CONTRACT_ONLY = process.env.CONTRACT_ONLY === '1';
const FIX_TIP = process.env.SEMANTIC_FIX_TIP !== '0';

const SEMANTIC_ALLOW_RE = process.env.SEMANTIC_ALLOW
  ? new RegExp(process.env.SEMANTIC_ALLOW) : null;

function lintFile(file) {
  if (!LINTABLE.test(file)) return [];
  let source;
  try { source = readFileSync(file, 'utf8'); }
  catch { return []; } // binary or unreadable — skip

  if (CONTRACT_ONLY && !hasComponentContract(file)) return [];

  const tokens = extractClassTokens(source);
  const violations = [];
  const seen = new Set();
  for (const { token, line } of tokens) {
    if (SEMANTIC_ALLOW_RE?.test(token)) continue;
    if (classify(token) !== 'utility') continue;
    const key = `${file}:${line}:${token}`;
    if (seen.has(key)) continue;
    seen.add(key);
    violations.push({ file, line, token });
  }
  return violations;
}

function main(argv) {
  const files = argv.filter((a) => !a.startsWith('-'));
  if (!files.length) {
    process.stderr.write(
      'usage: enforce-semantic-classes.mjs <file> [<file>…]\n' +
      'env: SEMANTIC_ALLOW=regex  UTILITY_ALLOW=regex  CONTRACT_ONLY=1\n'
    );
    return 2;
  }

  let total = 0;
  for (const file of files) {
    const violations = lintFile(file);
    if (!violations.length) continue;
    total += violations.length;
    for (const v of violations) {
      process.stdout.write(
        `❌ ${v.file}:${v.line}  utility class "${v.token}"\n`
      );
    }
  }

  if (total > 0) {
    if (!QUIET) {
      process.stdout.write(
        `\n❌ ${total} utility class(es) found in component markup.\n` +
        `   Utilities sit in @layer utilities, which always outranks\n` +
        `   @layer components — they silently shadow your CSS contract.\n` +
        `   Move the styling into the component's CSS (semantic class)\n` +
        `   or into a shared @layer utilities rule.\n`
      );
      if (FIX_TIP) {
        process.stdout.write(
          `\n   Allowlist a known-semantic name with:\n` +
          `     SEMANTIC_ALLOW='^(ticket-card|vword|…)'  (project-specific)\n`
        );
      }
    }
    return 1;
  }
  return 0;
}

// Run only when invoked directly (not when imported by tests).
if (import.meta.url === `file://${process.argv[1]}`) {
  const code = main(process.argv.slice(2));
  process.exit(code);
}
