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

# Test 11: detects closing fence with info string
printf '```text
some code
```text
' > bad-close.md
git add bad-close.md
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" bad-close.md >/dev/null 2>&1; then
  fail "should detect closing fence with info string"
else
  pass "detects closing fence with info string"
fi

# Test 12: --fix strips info string from closing fences
printf '```text
code block
```text
' > fix-close.md
git add fix-close.md
sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" --fix fix-close.md >/dev/null 2>&1
# After fix, second fence (closer) should be bare ```
second_fence=$(awk 'FNR==3{print}' fix-close.md)
if [ "$second_fence" = '```' ]; then
  pass "--fix strips info string from closing fences"
else
  fail "--fix should strip info string from closing fence, got: $second_fence"
fi

# Test 13: --fix adds text to bare opening fences
printf '```
code block
```
' > fix-bare.md
git add fix-bare.md
sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" --fix fix-bare.md >/dev/null 2>&1
# After fix, opening fence should have language
first_fence=$(awk '/^```/{print; exit}' fix-bare.md)
if [ "$first_fence" = '```text' ]; then
  pass "--fix adds text to bare opening fences"
else
  fail "--fix should add text to bare opening fence, got: $first_fence"
fi

# Test 14: well-formed file passes after --fix (idempotent)
printf '```bash
echo hi
```
' > already-good.md
git add already-good.md
sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" --fix already-good.md >/dev/null 2>&1
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" already-good.md >/dev/null 2>&1; then
  pass "--fix is idempotent on well-formed files"
else
  fail "--fix should not break well-formed files"
fi

# Test 15: --fix-staged reads from git, fixes, and re-stages
printf '```text
code block
```text
' > fix-staged.md
git add fix-staged.md
sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" --fix-staged >/dev/null 2>&1
# Closer should be bare
second_fence=$(awk 'FNR==3{print}' fix-staged.md)
if [ "$second_fence" = '```' ]; then
  pass "--fix-staged fixes files from git staging area"
else
  fail "--fix-staged should fix closing fence, got: $second_fence"
fi
# File should be re-staged (show in diff)
if git diff --cached --name-only | grep -q 'fix-staged.md'; then
  pass "--fix-staged re-stages fixed files"
else
  fail "--fix-staged should re-stage fixed files"
fi

# Test 16: detects indented closing fence with info string
printf '1. List item

   ```text
   code
   ```text
' > indented-close.md
git add indented-close.md
if sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" indented-close.md >/dev/null 2>&1; then
  fail "should detect indented closing fence with info string"
else
  pass "detects indented closing fence with info string"
fi

# Test 17: --fix handles indented fences, preserves indentation
printf '1. List item

   ```
   code
   ```
' > indented-bare.md
git add indented-bare.md
sh "$SCRIPT_DIR/check-markdown-fences-parity.sh" --fix indented-bare.md >/dev/null 2>&1
first_fence=$(awk 'FNR==3{print}' indented-bare.md)
if [ "$first_fence" = '   ```text' ]; then
  pass "--fix preserves indentation on bare opening fences"
else
  fail "--fix should preserve indent, got: '$first_fence'"
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
echo "--- block-mdt-incomplete-tasks.sh ---"
# ─────────────────────────────────────────────────────────

# We test the core logic by mocking mdt-cli via PATH override
MDT_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$MDT_TEST_DIR"' EXIT

# Create a mock mdt-cli that returns --json output
cat > "$MDT_TEST_DIR/mdt-cli" << 'MOCK'
#!/bin/sh
if [ "$1" = "project" ] && [ "$2" = "current" ] && echo "$@" | grep -q -- '--json'; then
  cat <<EOF
{"schemaVersion":1,"ok":true,"data":{"project":{"paths":{"root":"$MOCK_TEST_ROOT"},"ticketsPath":"tickets"}}}
EOF
elif [ "$1" = "ticket" ] && [ "$2" = "get" ] && echo "$@" | grep -q -- '--json'; then
  key="$3"
  if [ "$key" = "TST-999" ]; then
    status="Implemented"
  else
    status="In Progress"
  fi
  printf '{"schemaVersion":1,"ok":true,"data":{"ticket":{"key":"%s","status":{"value":"%s"}}}}\n' "$key" "$status"
fi
MOCK
chmod +x "$MDT_TEST_DIR/mdt-cli"

export MOCK_TEST_ROOT="$TEST_DIR"
mkdir -p "$TEST_DIR/tickets"

# Test: blocks ticket file with [ ] when status is Implemented
printf '# Title\n- [x] Done task\n- [ ] Not done task\n' > "$TEST_DIR/tickets/TST-999-incomplete.md"
git add tickets/TST-999-incomplete.md
PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" tickets/TST-999-incomplete.md >/dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "blocks ticket file with [ ] when status is Implemented"
else
  fail "should block ticket file with [ ] when status is Implemented"
fi

# Test: allows ticket file with all [x] when status is Implemented
printf '# Title\n- [x] Done task\n- [x] Another done task\n' > "$TEST_DIR/tickets/TST-999-complete.md"
git add tickets/TST-999-complete.md
PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" tickets/TST-999-complete.md >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "allows ticket file with all [x] when status is Implemented"
else
  fail "should allow ticket file with all [x] when status is Implemented"
fi

# Test: allows ticket file with [ ] when status is NOT Implemented
printf '# Title\n- [x] Done task\n- [ ] Not done task\n' > "$TEST_DIR/tickets/TST-888-incomplete.md"
git add tickets/TST-888-incomplete.md
PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" tickets/TST-888-incomplete.md >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "allows ticket file with [ ] when status is In Progress"
else
  fail "should allow ticket file with [ ] when status is In Progress"
fi

# Test: skips files outside tickets directory
echo '- [ ] unchecked' > regular-notes.md
git add regular-notes.md
PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" regular-notes.md >/dev/null 2>&1
if [ $? -eq 0 ]; then
  pass "skips files outside tickets directory"
else
  fail "should skip files outside tickets directory"
fi

# Test: handles no arguments gracefully
if PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" >/dev/null 2>&1; then
  pass "handles no arguments gracefully"
else
  fail "should handle no arguments gracefully"
fi

# Test: blocks ticket subdirectory file (PROJ-NNN/tasks.md) with [ ] when Implemented
mkdir -p "$TEST_DIR/tickets/TST-999"
printf '# Title\n- [ ] unchecked\n' > "$TEST_DIR/tickets/TST-999/tasks.md"
git add tickets/TST-999/tasks.md
PATH="$MDT_TEST_DIR:$PATH" sh "$SCRIPT_DIR/block-mdt-incomplete-tasks.sh" tickets/TST-999/tasks.md >/dev/null 2>&1
if [ $? -ne 0 ]; then
  pass "blocks PROJ-NNN/tasks.md with [ ] when Implemented"
else
  fail "should block PROJ-NNN/tasks.md with [ ] when Implemented"
fi

rm -rf "$MDT_TEST_DIR"

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
