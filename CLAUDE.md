@AGENTS.md

<!-- markdownlint-disable-file MD041 -->
<!-- First line is the @AGENTS.md import (Claude Code memory), not a heading. -->

## Hooks

`hooks/hooks.json` defines one PostToolUse hook and one PreToolUse hook.

- `Edit|Write` matcher → `validate_layers.sh`. When the edited file is a `pubspec.yaml` inside an FFCA-shaped repo, meaning a `features/` folder exists above it, the hook runs `dart run scripts/validate_layers.dart --file <pubspec>`. The validator checks the edited package and its direct dependents. Exit 2 means at least one error-severity finding. The hook prints the findings to stderr and exits 2, which blocks Claude until the dependency is fixed. When the validator exits 0 with output, every finding is a warning: the hook returns it as `additionalContext` JSON and exits 0, so Claude sees it without being blocked. A `# ffca-ignore: <rule-id> — <reason>` comment in a pubspec suppresses that rule for that package.
- Any other file, or a repo with no `features/` folder, exits 0 silently.
- The hook skips with exit 0 when `jq` or `dart` is missing from `PATH`. A validator failure other than exit 2 is reported to stderr but never blocks.

- `mcp__.*very-good-cli__.*` matcher → `check_vgv_cli.sh`. For a Very Good CLI MCP tool, it returns `allow` when `very_good --version` is 1.3.0 or newer and `deny` with an install or upgrade message when the CLI is missing or older. It stands aside with exit 0 for any other tool, when the version cannot be read, or when `jq` is missing. `allowed-tools` grants only last for the invoking turn, so this hook is what keeps the tools approved afterwards.

`hooks/check_vgv_cli_test.sh` covers the PreToolUse hook against a stubbed `very_good`, and `hooks/validate_layers_test.sh` covers the PostToolUse hook against a stubbed `dart`. Both run in CI under the **Hook Tests** job.

`scripts/test/validate_layers_test.dart` covers the validator and runs in CI under the **Layer Validator** job. Add a fixture and a case there when changing a rule, and add a new rule's ID and severity to `ruleSeverities` and to the rules table in the **Hooks** section of `README.md`.
