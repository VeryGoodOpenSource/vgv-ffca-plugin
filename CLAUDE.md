@AGENTS.md

<!-- markdownlint-disable-file MD041 -->
<!-- First line is the @AGENTS.md import (Claude Code memory), not a heading. -->

## Hooks

`hooks/hooks.json` defines one SessionStart hook, one SubagentStart hook, one PostToolUse hook, and one PreToolUse hook.

- SessionStart and SubagentStart → `sync-vge-standards.sh`. At session start it syncs the Very Good Engineering bundles for major `VGE_TARGET_MAJOR` into `${XDG_CACHE_HOME:-~/.cache}/very_good_engineering/bundles/`, the cache vgv-ai-flutter-plugin shares, under a lock so two plugins never download twice. It sends conditional GETs for the manifest and index, downloads only missing or changed documents, keeps each only when its sha256 and byte count match the index, and prunes documents the index drops. It prints one line naming the synced path. When VGE publishes a newer major or stops listing the target one, it pauses the sync and prints a notice instead of syncing. With `--subagent`, matched to `ffca-layer-auditor`, it only hands that agent the path line as `additionalContext`, with no network. It skips when `jq`, `curl`, or a sha256 tool is missing, fails open on any network, parse, or filesystem error, and always exits 0. Bump `VGE_TARGET_MAJOR` in the same change that updates the skills for a new major.

- `Edit|MultiEdit|Write` matcher → `validate_layers.sh`. The matcher is a filter, not a guarantee, so the hook reads `tool_name` from the payload and exits 0 unless it is `Edit`, `MultiEdit`, or `Write`. When the edited file is a `pubspec.yaml` or a Dart file inside an FFCA-shaped repo, meaning a `features/` folder exists above it, the hook runs `dart run scripts/validate_layers.dart --file <path>`. For a pubspec, the validator checks the edited package and its direct dependents, reporting the edited package's warnings and errors but only the errors of its dependents, and running the import checks and suppression validation for the edited package only, and it does not require a barrel from a package with no `lib/` yet. For a Dart file under a package's `lib/` or `bin/`, it reports only the import and barrel findings located in that file, so a Dart edit never blocks on a violation elsewhere. Exit 2 means at least one error-severity finding. The hook forwards only the validator's report, from the first `FFCA findings in` line, so `dart run`'s own notices never reach Claude. It prints the findings to stderr and exits 2, which blocks Claude until the dependency is fixed. When the validator exits 0 with output, every finding is a warning: the hook returns it as `additionalContext` JSON and exits 0, so Claude sees it without being blocked. A `# ffca-ignore: <rule-id> — <reason>` comment in a pubspec suppresses that rule for that package, and `// ffca-ignore:` in a Dart file suppresses it for that file, except for rules reported on the pubspec, which a Dart file cannot suppress.
- Any other file, or a repo with no `features/` folder, exits 0 silently.
- The hook skips with exit 0 when `jq` or `dart` is missing from `PATH`. The `dart` check runs only for FFCA pubspec and Dart edits. A validator failure other than exit 2 is reported to stderr but never blocks.

- `mcp__.*very-good-cli__.*` matcher → `check_vgv_cli.sh`. For a Very Good CLI MCP tool, it returns `allow` when `very_good --version` is 1.3.0 or newer and `deny` with an install or upgrade message when the CLI is missing or older. It stands aside with exit 0 for any other tool, when the version cannot be read, or when `jq` is missing. `allowed-tools` grants only last for the invoking turn, so this hook is what keeps the tools approved afterwards.

`hooks/sync-vge-standards_test.sh` covers the SessionStart and SubagentStart hook against a stubbed `curl` and runs in CI under the **Hook Tests** job.

`hooks/check_vgv_cli_test.sh` covers the PreToolUse hook against a stubbed `very_good` and runs in CI under the **Hook Tests** job.

`scripts/test/validate_layers_test.dart` covers the validator and runs in CI under the **Layer Validator** job. Add a fixture and a case there when changing a rule, and add a new rule as a value of the `Rule` enum, with its ID and severity, and to the rules table in the **Hooks** section of `README.md`.

`hooks/validate_layers_test.sh` covers the PostToolUse hook against the same fixtures and runs in CI under the **Hook Tests** job.
