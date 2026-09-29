#!/bin/bash
# SessionStart hook: warn when FFCA layer validation cannot run.
# validate_layers.sh skips silently (stderr only) without jq or dart, so Claude
# would never learn the PostToolUse check is off. Output is injected into
# Claude's context. Only speaks up in FFCA-shaped repos. Non-blocking, always
# exits 0.

root="${CLAUDE_PROJECT_DIR:-$PWD}"

# FFCA-shaped: a features/{feature}/{feature}_{domain,data,presentation}
# package somewhere under the project. Hidden, build, and node_modules folders
# are pruned so the scan stays fast on large repos.
ffca=$(find "$root" -mindepth 1 -maxdepth 6 \
  \( -name '.*' -o -name build -o -name node_modules \) -prune -o \
  \( -path '*/features/*/*_domain/pubspec.yaml' \
  -o -path '*/features/*/*_data*/pubspec.yaml' \
  -o -path '*/features/*/*_presentation/pubspec.yaml' \) \
  -print -quit 2>/dev/null)
[[ -n "$ffca" ]] || exit 0

missing=()
command -v dart &>/dev/null || missing+=("dart")
command -v jq &>/dev/null || missing+=("jq")
[[ ${#missing[@]} -gt 0 ]] || exit 0

list=$(printf '%s, ' "${missing[@]}")
list=${list%, }
echo "⚠️ FFCA layer validation is disabled this session: ${list} not found on the PATH available to hooks. The vgv-ffca-plugin PostToolUse hook will skip every pubspec.yaml edit, so layer violations will not be caught. Install the missing tools (Dart SDK: https://dart.dev/get-dart, jq: https://jqlang.org/download), make sure they are on PATH for non-interactive shells (e.g. in ~/.zprofile), and start a new session."

exit 0
