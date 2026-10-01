#!/bin/bash
set -euo pipefail

# PreToolUse hook: gate Very Good CLI MCP tool calls.
# Mirrors check-vgv-cli.sh in vgv-ai-flutter-plugin. When the CLI is installed
# and new enough, auto-approve the call so it works in every run mode, since a
# skill's allowed-tools grant only lasts for the turn that invoked it.
# Otherwise deny with an install or upgrade message instead of letting the
# call fail silently.

MIN_VERSION="1.3.0"

# Read the hook payload from stdin.
input=$(cat)

# Graceful skip if jq is unavailable: normal permission handling applies.
if ! command -v jq &>/dev/null; then
  echo "check_vgv_cli hook: jq not found, skipping" >&2
  exit 0
fi

decide() {
  jq -n --arg decision "$1" --arg reason "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: $decision,
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# The matcher is not a guarantee, so confirm the caller is a Very Good CLI
# tool. Covers mcp__very-good-cli__<tool> and the marketplace form
# mcp__plugin_<plugin>_very-good-cli__<tool>.
tool_name=$(jq -r '.tool_name // empty' <<<"$input")
if [[ "$tool_name" != mcp__*very-good-cli__* ]]; then
  exit 0
fi

# Resolve very_good from PATH, falling back to the pub cache, which a hook
# subprocess does not necessarily have on its PATH.
vgv_bin=$(command -v very_good || true)
if [[ -z "$vgv_bin" ]]; then
  fallback="${PUB_CACHE:-$HOME/.pub-cache}/bin/very_good"
  [[ -x "$fallback" ]] && vgv_bin=$fallback
fi
if [[ -z "$vgv_bin" ]]; then
  decide deny "Very Good CLI is not installed. This tool requires Very Good CLI >= ${MIN_VERSION}. Install with: dart pub global activate very_good_cli"
fi

# The very_good shim execs dart, so an unreadable version is inconclusive, not
# missing. Stand aside rather than deny a genuine call.
version=$("$vgv_bin" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ -z "$version" ]]; then
  exit 0
fi

IFS='.' read -r major minor patch <<<"$version"
IFS='.' read -r min_major min_minor min_patch <<<"$MIN_VERSION"
if ((major < min_major ||
  (major == min_major && minor < min_minor) ||
  (major == min_major && minor == min_minor && patch < min_patch))); then
  decide deny "Very Good CLI ${version} is too old. This tool requires Very Good CLI >= ${MIN_VERSION}. Update with: dart pub global activate very_good_cli"
fi

decide allow "Very Good CLI >= ${MIN_VERSION} verified; auto-approving Very Good CLI MCP tool call."
