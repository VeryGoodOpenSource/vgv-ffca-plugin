#!/bin/bash
# Tests for warn_missing_prereqs.sh
#
# Usage: bash hooks/warn_missing_prereqs_test.sh
#
# The hook takes no input. In an FFCA-shaped project it prints a warning to
# stdout when dart or jq is missing from PATH, and prints nothing otherwise. It
# always exits 0. Every case runs on a PATH holding only stubbed tools plus
# find, so results do not depend on what is installed on the machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/warn_missing_prereqs.sh"
BASH_BIN="$(command -v bash)"

PASSED=0
FAILED=0

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
ln -s "$(command -v find)" "$BIN_DIR/find"

# Installs or removes stubbed tools on the hook's PATH.
# Usage: tools dart jq  (installs exactly the named tools)
tools() {
  rm -f "$BIN_DIR/dart" "$BIN_DIR/jq"
  local t
  for t in "$@"; do
    printf '#!/bin/sh\nexit 0\n' > "$BIN_DIR/$t"
    chmod +x "$BIN_DIR/$t"
  done
}

# Creates a project directory with pubspec.yaml files at the given paths.
# Usage: project <name> <relative package dir>...
project() {
  local dir="$TMP_DIR/projects/$1"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  local pkg
  for pkg in "$@"; do
    mkdir -p "$dir/$pkg"
    echo "name: $(basename "$pkg")" > "$dir/$pkg/pubspec.yaml"
  done
  PROJECT="$dir"
}

# Runs the hook from $PROJECT. Leaves stdout in LAST_OUTPUT and the exit status
# in LAST_STATUS. Pass --env to point at the project via CLAUDE_PROJECT_DIR
# while running from elsewhere.
LAST_OUTPUT=""
LAST_STATUS=0
run_hook() {
  LAST_STATUS=0
  if [ "${1:-}" = "--env" ]; then
    LAST_OUTPUT=$(cd "$TMP_DIR" && env -i PATH="$BIN_DIR" CLAUDE_PROJECT_DIR="$PROJECT" \
      "$BASH_BIN" "$HOOK" 2>/dev/null) || LAST_STATUS=$?
  else
    LAST_OUTPUT=$(cd "$PROJECT" && env -i PATH="$BIN_DIR" \
      "$BASH_BIN" "$HOOK" 2>/dev/null) || LAST_STATUS=$?
  fi
}

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASSED=$((PASSED + 1)); }
fail() { printf "  \033[31mFAIL\033[0m  %s\n    got (exit %s): %s\n" "$1" "$LAST_STATUS" "$LAST_OUTPUT"; FAILED=$((FAILED + 1)); }

# The hook is non-blocking: it must exit 0 whatever it finds.
assert_exit_zero() {
  if [ "$LAST_STATUS" -eq 0 ]; then pass "exit 0:  $1"; else fail "expected exit 0:  $1"; fi
}

assert_silent() {
  local label="$1"
  run_hook "${2:-}"
  assert_exit_zero "$label"
  if [ -z "$LAST_OUTPUT" ]; then pass "silent:  $label"; else fail "expected no warning:  $label"; fi
}

assert_warns() {
  local needle="$1" label="$2"
  run_hook "${3:-}"
  assert_exit_zero "$label"
  if [[ "$LAST_OUTPUT" == *"$needle"* ]]; then
    pass "warns '$needle':  $label"
  else
    fail "expected warning containing '$needle':  $label"
  fi
}

assert_not_mentions() {
  local needle="$1" label="$2"
  if [[ "$LAST_OUTPUT" != *"$needle"* ]]; then
    pass "omits '$needle':  $label"
  else
    fail "expected warning without '$needle':  $label"
  fi
}

FFCA_PKGS=(features/cart/cart_domain features/cart/cart_data features/cart/cart_presentation)

echo "=== warn_missing_prereqs tests ==="
echo ""
echo "--- FFCA repo, prerequisites present (no warning) ---"
project ffca "${FFCA_PKGS[@]}"
tools dart jq
assert_silent "dart and jq on PATH"

echo ""
echo "--- FFCA repo, prerequisites missing ---"
tools jq
assert_warns "dart not found" "dart missing"
assert_not_mentions "jq," "dart missing"
tools dart
assert_warns "jq not found" "jq missing"
tools
assert_warns "dart, jq not found" "both missing"
assert_warns "dart, jq not found" "project found via CLAUDE_PROJECT_DIR" --env

echo ""
echo "--- FFCA detection variants ---"
tools
project domain_only features/cart/cart_domain
assert_warns "FFCA layer validation is disabled" "single *_domain package"
project data_suffix features/auth/auth_data_firebase
assert_warns "FFCA layer validation is disabled" "*_data_<suffix> package"
project nested packages/app/features/cart/cart_presentation
assert_warns "FFCA layer validation is disabled" "features/ nested below the root"

echo ""
echo "--- Not an FFCA repo (no warning even without tools) ---"
tools
project plain packages/some_pkg
assert_silent "no features/ folder"
project empty_features features
assert_silent "empty features/ folder"
project no_pubspec
mkdir -p "$PROJECT/features/cart/cart_domain"
assert_silent "layer folder without pubspec.yaml"
project wrong_names features/cart/cart_utils
assert_silent "features/ package without a layer suffix"
project hidden .dart_tool/features/cart/cart_domain
assert_silent "features/ only inside a hidden folder"
project build_dir build/features/cart/cart_domain
assert_silent "features/ only inside build/"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
