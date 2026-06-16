#!/bin/bash
set -euo pipefail

# PostToolUse hook: enforce FFCA layer dependency rules on pubspec.yaml edits.
# Mirrors the analyze hook in vgv-ai-flutter-plugin: parse the payload with jq,
# filter to the files we care about, skip gracefully when prerequisites are
# missing, then run the validator and propagate its exit code (2 blocks Claude).

# Read the hook payload from stdin.
input=$(cat)

# Graceful skip if jq or dart is unavailable.
if ! command -v jq &>/dev/null; then
  echo "validate_layers hook: jq not found, skipping" >&2
  exit 0
fi
if ! command -v dart &>/dev/null; then
  echo "validate_layers hook: dart not found, skipping" >&2
  exit 0
fi

# Extract the edited file path.
file_path=$(jq -r '.tool_input.file_path // empty' <<<"$input")

# Skip unless this is a pubspec.yaml.
if [[ -z "$file_path" || "$(basename "$file_path")" != "pubspec.yaml" ]]; then
  exit 0
fi

# Skip silently if the repo is not FFCA-shaped (no features/ folder above the
# edited file). Only walks absolute paths; relative paths fall through to the
# validator, which performs the same check itself.
if [[ "$file_path" == /* ]]; then
  dir=$(dirname "$file_path")
  ffca=0
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/features" ]]; then
      ffca=1
      break
    fi
    parent=$(dirname "$dir")
    [[ "$parent" == "$dir" ]] && break
    dir=$parent
  done
  [[ "$ffca" -eq 1 ]] || exit 0
fi

# Run the validator in incremental mode and propagate its exit code.
set +e
output=$(dart run "${CLAUDE_PLUGIN_ROOT}/scripts/validate_layers.dart" --file "$file_path" 2>&1)
code=$?
set -e

if [[ "$code" -eq 2 ]]; then
  echo "$output" >&2
  exit 2
fi

# Any other non-zero code is a validator problem, not an FFCA violation: surface
# it but do not block Claude.
if [[ "$code" -ne 0 ]]; then
  echo "validate_layers hook: validator exited $code, skipping" >&2
  [[ -n "$output" ]] && echo "$output" >&2
  exit 0
fi

exit 0
