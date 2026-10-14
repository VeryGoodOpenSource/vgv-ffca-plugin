#!/bin/bash
# Tests for validate_layers.sh
#
# Usage: bash hooks/validate_layers_test.sh
#
# The hook reads a JSON payload from stdin and either passes (exit 0, silent), skips
# (exit 0 with a "skipping" note on stderr) or blocks (exit 2). Any other exit is its
# own outcome, never mistaken for a pass, and so is the validator itself failing to run.
# Cases run against the validator fixtures in scripts/test/fixtures, so the runner needs
# dart and jq installed. HOME is passed through because SDK version managers such as
# asdf or fvm resolve dart from it. The missing-tool cases run on a PATH that holds only
# the few utilities the hook needs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
HOOK="$SCRIPT_DIR/validate_layers.sh"
FIXTURES="$PLUGIN_ROOT/scripts/test/fixtures"
BASH_BIN="$(command -v bash)"

for tool in jq dart; do
  if ! command -v "$tool" &>/dev/null; then
    echo "validate_layers_test: $tool is required to run these tests" >&2
    exit 1
  fi
done

PASSED=0
FAILED=0

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# Minimal PATHs for the missing-tool cases: core utilities only, then the same plus jq.
mkdir -p "$STUB_DIR/core" "$STUB_DIR/jq"
for util in cat dirname basename; do
  ln -s "$(command -v "$util")" "$STUB_DIR/core/$util"
done
ln -s "$(command -v jq)" "$STUB_DIR/jq/jq"

VALID="$FIXTURES/valid_workspace/features/cart/cart_domain/pubspec.yaml"
VIOLATING="$FIXTURES/invalid_workspace/features/alpha/alpha_domain/pubspec.yaml"
NOT_FFCA="$FIXTURES/not_ffca/packages/some_pkg/pubspec.yaml"
NOT_PUBSPEC="$FIXTURES/invalid_workspace/features/alpha/alpha_domain/lib/alpha_domain.dart"

payload() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }

# Prints "pass" (exit 0, silent), "skip" (exit 0, missing-tool note), "block" (exit 2),
# "error" (exit 0 after the validator itself failed) or "exit:<status>" for anything
# else, so a crashing hook or validator cannot pass as a pass.
# Usage: run_hook <payload> [path]
run_hook() {
  local input="$1" path="${2:-$PATH}"
  local stderr status=0
  stderr=$(printf '%s' "$input" \
    | env -i PATH="$path" HOME="$HOME" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
        "$BASH_BIN" "$HOOK" 2>&1 >/dev/null) || status=$?
  if [ "$status" -eq 2 ]; then
    echo "block"
  elif [ "$status" -ne 0 ]; then
    echo "exit:$status"
  elif [[ "$stderr" == *"validator exited"* ]]; then
    echo "error"
  elif [[ "$stderr" == *"not found, skipping"* ]]; then
    echo "skip"
  else
    echo "pass"
  fi
}

assert_outcome() {
  local expected="$1" label="$2" input="$3" path="${4:-$PATH}"
  local result
  result=$(run_hook "$input" "$path")
  if [ "$result" = "$expected" ]; then
    printf "  \033[32mPASS\033[0m  %-6s %s\n" "$expected" "$label"
    PASSED=$((PASSED + 1))
  else
    printf "  \033[31mFAIL\033[0m  expected %s but got %s:  %s\n" "$expected" "$result" "$label"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== validate_layers tests ==="
echo ""
echo "--- Tools that are not this hook's business (pass) ---"
# A violating pubspec proves the hook stood aside instead of validating.
assert_outcome pass  "Read on a violating pubspec"         "$(payload Read "$VIOLATING")"
assert_outcome pass  "Bash tool call"                      '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
assert_outcome pass  "NotebookEdit on a violating pubspec" "$(payload NotebookEdit "$VIOLATING")"
assert_outcome pass  "empty payload"                       '{}'
assert_outcome pass  "null tool_name"                      "{\"tool_name\":null,\"tool_input\":{\"file_path\":\"$VIOLATING\"}}"

echo ""
echo "--- Files the hook does not validate (pass) ---"
assert_outcome pass  "non-pubspec file"                    "$(payload Edit "$NOT_PUBSPEC")"
assert_outcome pass  "missing file_path"                   '{"tool_name":"Write","tool_input":{}}'
assert_outcome pass  "pubspec in a non-FFCA repo"          "$(payload Edit "$NOT_FFCA")"

echo ""
echo "--- FFCA pubspec edits ---"
assert_outcome pass  "Edit on a valid pubspec"             "$(payload Edit "$VALID")"
assert_outcome pass  "Write on a valid pubspec"            "$(payload Write "$VALID")"
assert_outcome block "Edit on a violating pubspec"         "$(payload Edit "$VIOLATING")"
assert_outcome block "Write on a violating pubspec"        "$(payload Write "$VIOLATING")"
assert_outcome block "MultiEdit on a violating pubspec"    "$(payload MultiEdit "$VIOLATING")"

echo ""
echo "--- Missing prerequisites (skip) ---"
assert_outcome skip  "jq not installed"                    "$(payload Edit "$VIOLATING")" "$STUB_DIR/core"
assert_outcome skip  "dart not installed"                  "$(payload Edit "$VIOLATING")" "$STUB_DIR/core:$STUB_DIR/jq"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
