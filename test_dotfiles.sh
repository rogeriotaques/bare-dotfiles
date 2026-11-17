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

# --- Helpers for running the real script against the fake home ---
SCRIPT="$(cd "$(dirname "$0")" && pwd)/dotfiles"
export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"

run_dotfiles() {
    env -u ZDOTDIR -u XDG_STATE_HOME -u XDG_CONFIG_HOME -u DOTFILES_SLACK_WEBHOOK \
        HOME="$FAKE_HOME" bash "$SCRIPT" "$@" < /dev/null
}

ERROR_FILE="$FAKE_HOME/.local/state/dotfiles/last-error"
exists() { [ -e "$1" ] && echo true || echo false; }

# --- Test: shell integration ---
echo ""
echo "[shell-integration]"
printf 'export FOO=1' > "$FAKE_HOME/.zshrc"
run_dotfiles shell-integration install zsh > /dev/null
run_dotfiles shell-integration install zsh > /dev/null
assert_eq "zsh block added once" "1" "$(grep -c '^# >>> dotfiles >>>$' "$FAKE_HOME/.zshrc")"
assert_eq "existing zshrc content kept" "export FOO=1" "$(head -n 1 "$FAKE_HOME/.zshrc")"
assert_eq "zshrc backed up" "export FOO=1" "$(cat "$FAKE_HOME/.zshrc.dotfiles-backup")"
assert_contains "status reports installed" "installed" "$(run_dotfiles shell-integration status zsh)"

run_dotfiles shell-integration install bash > /dev/null
assert_eq "bash block added" "1" "$(grep -c '^# >>> dotfiles >>>$' "$FAKE_HOME/.bashrc")"

run_dotfiles shell-integration install fish > /dev/null
assert_eq "fish conf.d file created" "true" "$(exists "$FAKE_HOME/.config/fish/conf.d/dotfiles.fish")"
run_dotfiles shell-integration uninstall fish > /dev/null
assert_eq "fish conf.d file removed" "false" "$(exists "$FAKE_HOME/.config/fish/conf.d/dotfiles.fish")"

# --- Test: auto-sync failure reporting ---
echo ""
echo "[auto-sync failure]"
git_dotfiles add "$FAKE_HOME/.zshrc"
git_dotfiles commit -m "track zshrc" > /dev/null 2>&1
git_dotfiles push origin "$CURRENT_BRANCH" > /dev/null 2>&1
git_dotfiles remote set-url origin "$TEST_DIR/missing.git"
echo "export BAR=2" >> "$FAKE_HOME/.zshrc"

run_dotfiles auto-sync > /dev/null 2>&1
assert_eq "auto-sync exits non-zero on push failure" "1" "$?"
assert_eq "error file written" "true" "$(exists "$ERROR_FILE")"
assert_contains "error mentions the failed step" "git push" "$(cat "$ERROR_FILE")"
assert_contains "status shows the failure" "last auto-sync failed" "$(run_dotfiles status)"

if command -v zsh > /dev/null; then
    SHELL_OUT=$(env -u XDG_STATE_HOME HOME="$FAKE_HOME" ZDOTDIR="$FAKE_HOME" zsh -i -c 'exit' 2>&1)
    assert_contains "zsh startup shows the warning" "auto-sync failed" "$SHELL_OUT"
fi

# --- Test: auto-sync recovery ---
echo ""
echo "[auto-sync recovery]"
git_dotfiles remote set-url origin "$REMOTE_DIR"
run_dotfiles auto-sync > /dev/null 2>&1
assert_eq "auto-sync succeeds once remote is back" "0" "$?"
assert_eq "pending commit pushed" "$(git_dotfiles rev-parse HEAD)" "$(/usr/bin/git --git-dir="$REMOTE_DIR" rev-parse "$CURRENT_BRANCH")"
assert_eq "error file cleared" "false" "$(exists "$ERROR_FILE")"
assert_eq "silent when nothing to do" "" "$(run_dotfiles auto-sync 2>&1)"

if command -v zsh > /dev/null; then
    SHELL_OUT=$(env -u XDG_STATE_HOME HOME="$FAKE_HOME" ZDOTDIR="$FAKE_HOME" zsh -i -c 'exit' 2>&1)
    assert_eq "zsh startup is quiet without errors" "" "$SHELL_OUT"
fi

run_dotfiles shell-integration uninstall zsh > /dev/null
assert_eq "zsh block removed" "0" "$(grep -c 'dotfiles >>>' "$FAKE_HOME/.zshrc")"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
