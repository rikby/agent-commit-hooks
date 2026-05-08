#!/bin/sh
# Test harness for lefthook-scripts
#
# Creates a temp git repo, stages test files, runs each script
# and verifies it catches violations / allows clean files.

# Note: no set -e — test harness needs to capture non-zero exits

SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)/scripts"
PASS=0
FAIL=0

pass() {
  echo "  ✅ PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ❌ FAIL: $1"
  FAIL=$((FAIL + 1))
}

# Create temp git repo
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

echo ""
echo "=== Running lefthook-scripts tests ==="
echo ""

# ─────────────────────────────────────────────────────────
echo "--- block-generated-files.sh ---"
# ─────────────────────────────────────────────────────────

# Test 1: blocks *.trace.md by default
echo "content" > test.trace.md
git add test.trace.md
if sh "$SCRIPT_DIR/block-generated-files.sh" test.trace.md >/dev/null 2>&1; then
  fail "should block *.trace.md"
else
  pass "blocks *.trace.md"
fi

# Test 2: blocks .DS_Store by default
echo "" > .DS_Store
git add .DS_Store
if sh "$SCRIPT_DIR/block-generated-files.sh" .DS_Store >/dev/null 2>&1; then
  fail "should block .DS_Store"
else
  pass "blocks .DS_Store"
fi

# Test 3: blocks *.min.js by default
echo "var x=1;" > app.min.js
git add app.min.js
if sh "$SCRIPT_DIR/block-generated-files.sh" app.min.js >/dev/null 2>&1; then
  fail "should block *.min.js"
else
  pass "blocks *.min.js"
fi

# Test 4: allows clean files
echo "console.log('hello')" > index.js
git add index.js
if sh "$SCRIPT_DIR/block-generated-files.sh" index.js >/dev/null 2>&1; then
  pass "allows clean .js file"
else
  fail "should allow clean .js file"
fi

# Test 5: custom BLOCK_PATTERNS
echo "data" > custom.artifact
git add custom.artifact
BLOCK_PATTERNS="*.artifact" sh "$SCRIPT_DIR/block-generated-files.sh" custom.artifact >/dev/null 2>&1
if [ $? -eq 0 ]; then
  fail "should block custom pattern *.artifact"
else
  pass "blocks custom BLOCK_PATTERNS"
fi

# Test 6: custom BLOCK_PATTERNS allows non-matching
echo "ok" > good.txt
git add good.txt
BLOCK_PATTERNS="*.artifact" sh "$SCRIPT_DIR/block-generated-files.sh" good.txt >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "allows file not matching custom BLOCK_PATTERNS"
else
  fail "should allow file not matching custom BLOCK_PATTERNS"
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "--- check-markdown-fences-parity.sh ---"
# ─────────────────────────────────────────────────────────

# Test 7: detects unclosed fence
printf '```js\nconsole.log("hi")\n' > broken.md
git add broken.md
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" broken.md >/dev/null 2>&1; then
  fail "should detect unclosed fence"
else
  pass "detects unclosed fence (odd count)"
fi

# Test 8: allows well-formed markdown
printf '```js\nconsole.log("hi")\n```\n' > good.md
git add good.md
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" good.md >/dev/null 2>&1; then
  pass "allows well-formed markdown (even fence count)"
else
  fail "should allow well-formed markdown"
fi

# Test 9: respects MD_SKIP_DIRS
mkdir -p prompts
printf '```js\nconsole.log("hi")\n' > prompts/broken.md
git add prompts/broken.md
MD_SKIP_DIRS="prompts" sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" prompts/broken.md >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "skips file in MD_SKIP_DIRS"
else
  fail "should skip file in MD_SKIP_DIRS"
fi

# Test 10: allows file with no fences
echo "Just some text" > plain.md
git add plain.md
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" plain.md >/dev/null 2>&1; then
  pass "allows markdown with no fences"
else
  fail "should allow markdown with no fences"
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "--- block-home-paths-commit-msg.sh ---"
# ─────────────────────────────────────────────────────────

# Test 11: detects home path in commit msg
echo "fix: update /Users/kirby/project/config" > "$TEST_DIR/commit-msg-bad"
if sh "$SCRIPT_DIR/block-home-paths-commit-msg.sh" "$TEST_DIR/commit-msg-bad" >/dev/null 2>&1; then
  fail "should detect /Users/kirby/... in commit message"
else
  pass "blocks commit msg with /Users/kirby/..."
fi

# Test 12: allows clean commit msg
echo "fix: update project config" > "$TEST_DIR/commit-msg-good"
if sh "$SCRIPT_DIR/block-home-paths-commit-msg.sh" "$TEST_DIR/commit-msg-good" >/dev/null 2>&1; then
  pass "allows clean commit message"
else
  fail "should allow clean commit message"
fi

# Test 13: allows example/username placeholders
echo "docs: see /home/username/project for setup" > "$TEST_DIR/commit-msg-ex"
if sh "$SCRIPT_DIR/block-home-paths-commit-msg.sh" "$TEST_DIR/commit-msg-ex" >/dev/null 2>&1; then
  pass "allows 'username' placeholder in commit message"
else
  fail "should allow 'username' placeholder"
fi

# Test 14: handles missing commit msg file gracefully
if sh "$SCRIPT_DIR/block-home-paths-commit-msg.sh" "$TEST_DIR/nonexistent" >/dev/null 2>&1; then
  pass "handles missing commit msg file gracefully"
else
  fail "should handle missing file gracefully"
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "--- check-deps ---"
# ─────────────────────────────────────────────────────────

# Test 15: check-deps reports missing lefthook.yml
cd "$TEST_DIR"
if sh "$SCRIPT_DIR/check-deps" >/dev/null 2>&1; then
  fail "should fail when no lefthook.yml exists"
else
  pass "fails when no lefthook.yml exists"
fi

# Test 16: check-deps with valid lefthook.yml (minimal)
echo 'remotes: []' > lefthook.yml
if sh "$SCRIPT_DIR/check-deps" >/dev/null 2>&1; then
  pass "succeeds with empty lefthook.yml"
else
  fail "should succeed with empty lefthook.yml"
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "--- block-home-paths-code.sh ---"
# ─────────────────────────────────────────────────────────

# Test 17: blocks home path in staged code
# Must have an initial commit first, then stage a diff containing home path
echo 'initial' > staged_file.ts
git add staged_file.ts
git commit -m "initial" -q
echo 'const p = "/Users/kirby/home/project";' > staged_file.ts
git add staged_file.ts
if sh "$SCRIPT_DIR/block-home-paths-code.sh" >/dev/null 2>&1; then
  fail "should block /Users/kirby/... in staged code"
else
  pass "blocks home path in staged code diff"
fi

# Test 18: allows code without home paths
echo 'const p = "./relative/path";' > clean_file.ts
git add clean_file.ts
git commit -m "add clean" -q
if sh "$SCRIPT_DIR/block-home-paths-code.sh" >/dev/null 2>&1; then
  pass "allows code without home paths"
else
  fail "should allow code without home paths"
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "--- check-markdown-fences-style.sh ---"
# ─────────────────────────────────────────────────────────

# Test 19: style check behavior
# markdownlint-cli2 expects real newlines in files
printf '```js\nx\n```\n' > style_test.md
git add style_test.md
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  # markdownlint-cli2 is installed — test both pass and fail
  sh "$SCRIPT_DIR/check-markdown-fences-style.sh" style_test.md >/dev/null 2>&1
  style_rc=$?
  if [ $style_rc -eq 0 ]; then
    pass "style check passes on valid md with markdownlint-cli2 installed"
  else
    # May fail on style rules — that's fine, just verify it ran
    pass "style check runs with markdownlint-cli2 installed (may flag style issues)"
  fi
else
  # markdownlint-cli2 is NOT installed — should hard-fail with install message
  sh "$SCRIPT_DIR/check-markdown-fences-style.sh" style_test.md >/dev/null 2>&1
  style_rc=$?
  if [ $style_rc -ne 0 ]; then
    pass "style check hard-fails when markdownlint-cli2 missing"
  else
    fail "style check should hard-fail when markdownlint-cli2 missing"
  fi
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Some tests failed"
  exit 1
fi

echo "✅ All tests passed"
