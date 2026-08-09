#!/usr/bin/env node
//
// test-enforce-semantic-classes.mjs — regression suite for the linter.
// Run: node scripts/test-enforce-semantic-classes.mjs
//
// Pure unit tests against the exported classify() + a few integration runs over
// synthetic source. No external test framework — just assertions + exit code.

import assert from 'node:assert';
import { classify } from './enforce-semantic-classes.mjs';
import { writeFileSync, mkdtempSync, rmSync, mkdirSync, writeFileSync as wf } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';

let pass = 0, fail = 0;
function test(name, fn) {
  try { fn(); console.log(`  ✅ ${name}`); pass++; }
  catch (e) { console.log(`  ❌ ${name}\n     ${e.message}`); fail++; }
}
function eq(actual, expected, label) {
  assert.strictEqual(actual, expected, `${label || ''} (got ${actual}, expected ${expected})`);
}

// ── Unit: classify() ───────────────────────────────────────────────────────
console.log('Unit: classify()');

test('bare keyword: flex → utility',     () => eq(classify('flex'), 'utility'));
test('bare keyword: hidden → utility',   () => eq(classify('hidden'), 'utility'));
test('bare keyword: items-center → utility', () => eq(classify('items-center'), 'utility'));
test('container → utility',              () => eq(classify('container'), 'utility'));

test('root+numeric: p-4 → utility',      () => eq(classify('p-4'), 'utility'));
test('root+numeric: m-2 → utility',      () => eq(classify('m-2'), 'utility'));
test('root+color: bg-blue-500 → utility',() => eq(classify('bg-blue-500'), 'utility'));
test('root+keyword: text-center → utility', () => eq(classify('text-center'), 'utility'));
test('compound root: grid-cols-3 → utility',() => eq(classify('grid-cols-3'), 'utility'));
test('fraction: w-1/2 → utility',        () => eq(classify('w-1/2'), 'utility'));

test('arbitrary: min-h-[100dvh] → utility', () => eq(classify('min-h-[100dvh]'), 'utility'));
test('arbitrary: top-[117px] → utility', () => eq(classify('top-[117px]'), 'utility'));

test('variant stacking: dark:hover:bg-red-500 → utility', () =>
  eq(classify('dark:hover:bg-red-500'), 'utility'));
test('responsive variant: sm:flex → utility', () => eq(classify('sm:flex'), 'utility'));
test('arbitrary variant: [&>*]:block → utility', () => eq(classify('[&>*]:block'), 'utility'));

// ── Precision: semantic names must NOT false-positive ──────────────────────
console.log('\nPrecision: semantic names (must be semantic)');
test('grid-container → semantic',  () => eq(classify('grid-container'), 'semantic'));
test('text-body → semantic',       () => eq(classify('text-body'), 'semantic'));
test('card-flex → semantic',       () => eq(classify('card-flex'), 'semantic'));
test('sidebar-width → semantic',   () => eq(classify('sidebar-width'), 'semantic'));
test('ticket-card → semantic',     () => eq(classify('ticket-card'), 'semantic'));
test('ticket-card__title → semantic', () => eq(classify('ticket-card__title'), 'semantic'));
test('ticket-card--invalid → semantic', () => eq(classify('ticket-card--invalid'), 'semantic'));
test('badge--red → semantic',      () => eq(classify('badge--red'), 'semantic'));
test('btn-primary → semantic',     () => eq(classify('btn-primary'), 'semantic'));
test('list-item-title → semantic', () => eq(classify('list-item-title'), 'semantic'));
test('vword__body → semantic',     () => eq(classify('vword__body'), 'semantic'));
test('insight__type → semantic',   () => eq(classify('insight__type'), 'semantic'));

// ── Integration: end-to-end over synthetic files ───────────────────────────
console.log('\nIntegration: end-to-end');

const tmp = mkdtempSync(path.join(os.tmpdir(), 'esc-test-'));
const script = path.resolve(path.dirname(new URL(import.meta.url).pathname), 'enforce-semantic-classes.mjs');

function runLint(file, env = {}) {
  try {
    execFileSync(process.execPath, [script, file], {
      env: { ...process.env, ...env },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { code: 0, out: '' };
  } catch (e) {
    return { code: e.status ?? 1, out: (e.stdout || '') + (e.stderr || '') };
  }
}

test('React: detects utilities in className', () => {
  const f = path.join(tmp, 'r.jsx');
  writeFileSync(f, '<div className="ticket-card flex items-center gap-2"><span className="ticket-card__title">x</span></div>\n');
  const r = runLint(f);
  assert(r.out.includes('"flex"'), 'flex not reported');
  assert(r.out.includes('"gap-2"'), 'gap-2 not reported');
  assert(!r.out.includes('ticket-card__title'), 'semantic name falsely flagged');
  eq(r.code, 1, 'exit code');
});

test('Svelte: static class= detected', () => {
  const f = path.join(tmp, 's1.svelte');
  writeFileSync(f, '<div class="vword flex">a</div>\n');
  const r = runLint(f);
  assert(r.out.includes('"flex"'), 'flex not reported');
});

test('Svelte: class: directive NOT flagged', () => {
  const f = path.join(tmp, 's2.svelte');
  writeFileSync(f, '<button class:active class:is-open={x}>b</button>\n');
  const r = runLint(f);
  assert(!r.out.includes('active'), 'class: directive flagged');
  eq(r.code, 0, 'exit code');
});

test('Svelte: ternary string literals extracted', () => {
  const f = path.join(tmp, 's3.svelte');
  writeFileSync(f, '<div class={x ? "block p-4" : "hidden"}>c</div>\n');
  const r = runLint(f);
  assert(r.out.includes('"block"'), 'block not extracted from ternary');
  assert(r.out.includes('"hidden"'), 'hidden not extracted from ternary');
});

test('JSX: template literal static parts extracted (interpolation skipped)', () => {
  const f = path.join(tmp, 't.jsx');
  writeFileSync(f, '<Card className={`base flex ${cond ? "grid" : ""}`} />\n');
  const r = runLint(f);
  // Static parts outside ${…} are extracted.
  assert(r.out.includes('"flex"'), 'flex not extracted from template literal');
  // String literals INSIDE ${…} are conditional/dynamic — deliberately not
  // extracted (conservative: avoids false positives on conditional classes).
  assert(!r.out.includes('"grid"'), 'grid inside interpolation should be skipped');
});

test('CONTRACT_ONLY: skips files without colocated @layer components CSS', () => {
  const f = path.join(tmp, 'nocss.jsx');
  writeFileSync(f, '<div className="flex p-4">x</div>\n');
  const r = runLint(f, { CONTRACT_ONLY: '1' });
  eq(r.code, 0, 'should be skipped');
  eq(r.out, '', 'should produce no output');
});

test('CONTRACT_ONLY: flags files WITH colocated @layer components CSS', () => {
  const dir = path.join(tmp, 'contracted');
  mkdirSync(dir);
  writeFileSync(path.join(dir, 'Comp.css'), '@layer components { .comp { color: red; } }\n');
  const f = path.join(dir, 'Comp.tsx');
  writeFileSync(f, '<div className="comp flex p-4">x</div>\n');
  const r = runLint(f, { CONTRACT_ONLY: '1' });
  eq(r.code, 1, 'should be flagged');
  assert(r.out.includes('"flex"'), 'flex not reported');
  assert(!r.out.includes('"comp"'), 'semantic .comp class flagged');
});

test('CONTRACT_ONLY: detects same-named subdir (TicketCard.tsx + TicketCard/)', () => {
  const root = path.join(tmp, 'flat');
  mkdirSync(root);
  const sub = path.join(root, 'FlatComp');
  mkdirSync(sub);
  writeFileSync(path.join(sub, 'style.css'), '@layer components { .c { } }\n');
  const f = path.join(root, 'FlatComp.tsx');
  writeFileSync(f, '<div className="c flex">x</div>\n');
  const r = runLint(f, { CONTRACT_ONLY: '1' });
  eq(r.code, 1, 'should find contract in same-named subdir');
});

test('SEMANTIC_ALLOW: suppresses matching tokens', () => {
  const f = path.join(tmp, 'allow.jsx');
  writeFileSync(f, '<div className="flex my-utility">x</div>\n');
  const r = runLint(f, { SEMANTIC_ALLOW: '^my-utility$' });
  assert(r.out.includes('"flex"'), 'flex should still be reported');
  assert(!r.out.includes('my-utility'), 'allowed token should be suppressed');
});

test('exit 0 on clean semantic file', () => {
  const f = path.join(tmp, 'clean.jsx');
  writeFileSync(f, '<div className="ticket-card ticket-card__title">x</div>\n');
  const r = runLint(f);
  eq(r.code, 0, 'clean file should pass');
});

rmSync(tmp, { recursive: true, force: true });

console.log(`\nRESULT: ${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
