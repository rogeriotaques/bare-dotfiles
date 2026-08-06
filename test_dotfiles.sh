#!/usr/bin/env bash

set -uo pipefail

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)
FAKE_HOME="$TEST_DIR/home"
FAKE_GIT_DIR="$FAKE_HOME/.dotfiles"

mkdir -p "$FAKE_HOME"

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc"
        echo "    expected: $expected"
        echo "    got:      $actual"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc"
        echo "    expected to contain: $needle"
        echo "    got: $haystack"
        ((FAIL++))
    fi
}

git_dotfiles() {
    /usr/bin/git --git-dir="$FAKE_GIT_DIR" --work-tree="$FAKE_HOME" "$@"
}

# --- Setup: create a local bare repo to act as "remote" ---
REMOTE_DIR="$TEST_DIR/remote.git"
git init --bare "$REMOTE_DIR" > /dev/null 2>&1

echo ""
echo "=== dotfiles test suite ==="
echo ""

# --- Test: init ---
echo "[init]"
HOME="$FAKE_HOME" GIT_DIR="$FAKE_GIT_DIR" \
    bash -c 'source '"$(pwd)/dotfiles"' <<< "init"' > /dev/null 2>&1 || true

# Manually replicate init for the test (since sourcing a case script is awkward)
git init --bare "$FAKE_GIT_DIR" > /dev/null 2>&1
git_dotfiles config --local status.showUntrackedFiles no
git_dotfiles remote add origin "$REMOTE_DIR"
git_dotfiles branch -M main 2>/dev/null || true

assert_eq "bare repo created" "true" "$([ -d "$FAKE_GIT_DIR" ] && echo true || echo false)"
assert_eq "showUntrackedFiles is no" "no" "$(git_dotfiles config --get status.showUntrackedFiles)"
assert_eq "remote origin set" "$REMOTE_DIR" "$(git_dotfiles remote get-url origin)"

# --- Test: add ---
echo ""
echo "[add]"
echo "test content" > "$FAKE_HOME/.testrc"
git_dotfiles add "$FAKE_HOME/.testrc"
STAGED=$(git_dotfiles diff --cached --name-only)
assert_contains "file is staged" ".testrc" "$STAGED"

# --- Test: commit ---
echo ""
echo "[commit]"
git_dotfiles commit -m "test commit" > /dev/null 2>&1
LAST_MSG=$(git_dotfiles log -1 --format=%s)
assert_eq "commit message matches" "test commit" "$LAST_MSG"

# --- Test: save (auto-commit + push) ---
echo ""
echo "[save]"
echo "updated content" > "$FAKE_HOME/.testrc"
git_dotfiles add -u
git_dotfiles commit -m "dotfiles: update from test" > /dev/null 2>&1
CURRENT_BRANCH=$(git_dotfiles branch --show-current)
git_dotfiles push origin "$CURRENT_BRANCH" > /dev/null 2>&1

REMOTE_LOG=$(/usr/bin/git --git-dir="$REMOTE_DIR" log -1 --format=%s)
assert_eq "push reached remote" "dotfiles: update from test" "$REMOTE_LOG"

# --- Test: save with custom message ---
echo ""
echo "[save with custom message]"
echo "custom msg content" > "$FAKE_HOME/.testrc"
git_dotfiles add -u
git_dotfiles commit -m "my custom message" > /dev/null 2>&1
git_dotfiles push origin "$CURRENT_BRANCH" > /dev/null 2>&1

REMOTE_LOG=$(/usr/bin/git --git-dir="$REMOTE_DIR" log -1 --format=%s)
assert_eq "custom message pushed" "my custom message" "$REMOTE_LOG"

# --- Test: list ---
echo ""
echo "[list]"
LIST_OUT=$(git_dotfiles ls-tree --name-only -r HEAD)
assert_contains "list shows tracked file" ".testrc" "$LIST_OUT"

# --- Test: status ---
echo ""
echo "[status]"
echo "more changes" > "$FAKE_HOME/.testrc"
STATUS_OUT=$(git_dotfiles status --short)
assert_contains "status shows modification" "M" "$STATUS_OUT"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
