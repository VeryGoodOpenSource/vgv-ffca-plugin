#!/bin/bash
# Tests for validate_layers.sh
#
# Usage: bash hooks/validate_layers_test.sh
#
# The hook reads a JSON payload from stdin, runs the validator on an edited
# pubspec.yaml, and maps its result to one of four outcomes: silent, blocked
# (exit 2 with the findings on stderr), warned (exit 0 with the findings as
# additional context on stdout), or skipped. Every case runs against a stubbed
# dart on a PATH that contains nothing else, so results do not depend on the
# Dart SDK or on the validator itself, which scripts/test covers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/validate_layers.sh"

PASSED=0
FAILED=0

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

BASE_PATH="$(dirname "$(command -v jq)"):/usr/bin:/bin:/usr/sbin:/sbin"

# An FFCA-shaped repo and a non-FFCA one, for the edited file paths.
FFCA_PUBSPEC="$STUB_DIR/repo/features/cart/cart_data/pubspec.yaml"
OTHER_PUBSPEC="$STUB_DIR/other/packages/some_pkg/pubspec.yaml"
mkdir -p "$(dirname "$FFCA_PUBSPEC")" "$(dirname "$OTHER_PUBSPEC")"
touch "$FFCA_PUBSPEC" "$OTHER_PUBSPEC"

# Install a stubbed dart that prints [output] to stderr and exits [code], the
# way the validator reports its findings.
# Usage: stub_dart <code> [output]
stub_dart() {
  printf '%s' "${2:-}" > "$STUB_DIR/dart_output"
  printf '#!/bin/sh\ncat "%s" >&2\nexit %s\n' "$STUB_DIR/dart_output" "$1" > "$STUB_DIR/bin/dart"
  chmod +x "$STUB_DIR/bin/dart"
}
mkdir -p "$STUB_DIR/bin"

no_dart() { rm -f "$STUB_DIR/bin/dart"; }

payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# Prints "silent" (exit 0, no output), "blocked" (exit 2, findings on stderr),
# "warned" (exit 0, findings in additionalContext), or "exit:<status>" /
# "malformed" for anything else, so a crashing hook cannot pass as silent.
run_hook() {
  local input="$1"
  local out err status=0
  out=$(printf '%s' "$input" \
    | env -i PATH="$STUB_DIR/bin:$BASE_PATH" CLAUDE_PLUGIN_ROOT="$STUB_DIR" \
        bash "$HOOK" 2>"$STUB_DIR/stderr") || status=$?
  err=$(cat "$STUB_DIR/stderr")
  if [ "$status" -eq 2 ] && [[ "$err" == *"FFCA findings"* ]]; then
    echo "blocked"
  elif [ "$status" -ne 0 ]; then
    echo "exit:$status"
  elif [ -z "$out" ]; then
    echo "silent"
  elif [ "$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' \
      | grep -c 'FFCA findings')" -gt 0 ]; then
    echo "warned"
  else
    echo "malformed"
  fi
}

assert_outcome() {
  local expected="$1" label="$2" input="$3"
  local result
  result=$(run_hook "$input")
  if [ "$result" = "$expected" ]; then
    printf "  \033[32mPASS\033[0m  %-8s %s\n" "$expected" "$label"
    PASSED=$((PASSED + 1))
  else
    printf "  \033[31mFAIL\033[0m  expected %s but got %s:  %s\n" "$expected" "$result" "$label"
    FAILED=$((FAILED + 1))
  fi
}

ERROR_OUTPUT='FFCA findings in features/cart/cart_data/pubspec.yaml:
  ✗ [data-missing-own-domain] cart_data does not depend on cart_domain
  → Add cart_domain under dependencies in the cart_data pubspec.
FFCA: 1 error, 0 warnings.'

WARNING_OUTPUT='FFCA findings in features/cart/cart_presentation/pubspec.yaml:
  ⚠ [presentation-missing-own-domain] cart_presentation does not depend on cart_domain
  → Add cart_domain under dependencies in the cart_presentation pubspec.
FFCA: 0 errors, 1 warning.'

echo "=== validate_layers tests ==="
echo ""
echo "--- Edits that are not this hook's business ---"
stub_dart 2 "$ERROR_OUTPUT"
assert_outcome silent "non-pubspec file"            "$(payload "$STUB_DIR/repo/features/cart/cart_data/lib/cart_data.dart")"
assert_outcome silent "pubspec outside an FFCA repo" "$(payload "$OTHER_PUBSPEC")"
assert_outcome silent "no file path"                '{"tool_name":"Edit","tool_input":{}}'

echo ""
echo "--- Validator results on an FFCA pubspec ---"
stub_dart 0
assert_outcome silent  "clean pass"                  "$(payload "$FFCA_PUBSPEC")"
stub_dart 2 "$ERROR_OUTPUT"
assert_outcome blocked "error finding blocks"        "$(payload "$FFCA_PUBSPEC")"
stub_dart 0 "$WARNING_OUTPUT"
assert_outcome warned  "warnings reach Claude"       "$(payload "$FFCA_PUBSPEC")"

echo ""
echo "--- Validator failures never block ---"
stub_dart 1 "Unhandled exception"
assert_outcome silent "validator crash"              "$(payload "$FFCA_PUBSPEC")"
stub_dart 64 "Usage: validate_layers.dart"
assert_outcome silent "usage error"                  "$(payload "$FFCA_PUBSPEC")"
no_dart
assert_outcome silent "dart not installed"           "$(payload "$FFCA_PUBSPEC")"

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
