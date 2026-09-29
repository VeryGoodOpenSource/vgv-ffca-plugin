# 🦄 Contributing to VGV FFCA Plugin

First of all, thank you for taking the time to contribute! 🎉👍 Before you do, please carefully read this guide.

## Getting Started

1. **Fork** the repository and clone your fork locally.
2. Create a new branch from `main` for your work.
3. Open the project in your editor of choice. Any text editor works for skills and docs. The validator in `scripts/` needs the Dart SDK.

## Types of Contributions

| Contribution | Where |
| ------------ | ----- |
| **New skill** | `skills/<skill-name>/SKILL.md` |
| **Improve an existing skill** | Edit the relevant `skills/*/SKILL.md` |
| **Architecture conventions** | `references/ffca_architecture.md` |
| **Layer validator** | `scripts/validate_layers.dart` and `scripts/test/` |
| **Hook** | `hooks/` directory |
| **Agent** | `agents/` directory |
| **Bug reports & feature requests** | [GitHub Issues](https://github.com/VeryGoodOpenSource/vgv-ffca-plugin/issues) |

## Adding a New Skill

### 1. Create the skill file

Create `skills/<skill-name>/SKILL.md`. The file must begin with YAML frontmatter:

```yaml
---
name: <skill-name>
description: What the skill does, in one sentence.
when_to_use: When this skill should be triggered. Be specific.
allowed-tools: Read Glob Grep
---
```

| Field | Required | Rules |
| ----- | -------- | ----- |
| `name` | Yes | Lowercase letters, numbers, and hyphens only. Must match the skill's directory name. Prefix FFCA skills with `ffca-` |
| `description` | Yes | What the skill covers |
| `when_to_use` | Yes | The trigger phrases and scope. Self-scope to FFCA repos so the skill does not fire in a layered repo |
| `allowed-tools` | No | Space-separated list of tools the skill may use |
| `effort` | No | Reasoning effort hint, for example `high` for the audit skill |

After the frontmatter, open with an H1 title and a one-line summary, then the workflow sections.

### 2. Update `plugin.json` keywords

Add relevant keywords to the `keywords` array in `.claude-plugin/plugin.json`.

### 3. Update the README skills table

Add a row to the skills table in `README.md` and to the list of slash commands below it. The skill name must link to the `SKILL.md` file:

```markdown
| [**Skill Name**](skills/<skill-name>/SKILL.md) | Short description of what the skill covers |
```

## Skill Writing Guidelines

- **Point into the reference, do not restate it.** The conventions live in `references/ffca_architecture.md`. Link to the section by name so the architecture keeps one source of truth.
- **Use clear directives.** No soft language like "consider" or "prefer". Say "Use X" or "Do not use Y".
- **Fence all code blocks** with language identifiers, for example ` ```dart `.
- **Reference packages by full name**, for example `package:go_router_builder`.
- **Show anti-patterns alongside correct patterns** when it helps the reader see what to avoid.
- **Keep skills short.** The current skills run well under 100 lines. Put workflow and judgement calls in the skill and leave the conventions to the reference.

## Testing Locally

Pushing straight to a PR only tells you the files are valid. Load your working copy into a real Claude Code session and exercise it before you commit.

### Prerequisites

- **Claude Code CLI** installed (`npm install -g @anthropic-ai/claude-code`).
- **Dart SDK** and **jq** on your `PATH`. The hook needs both.
- **Very Good CLI** (`dart pub global activate very_good_cli`) for the MCP server tools.

### Load your local copy

From the repository root, launch Claude Code pointed at this directory:

```bash
claude --plugin-dir .
```

`--plugin-dir` loads the plugin for that session only and overrides any marketplace-installed copy. `${CLAUDE_PLUGIN_ROOT}` in `hooks/hooks.json` resolves to the directory you pass, so the hook script path resolves correctly.

### Verify each component loaded

| Component | How to verify |
| --------- | ------------- |
| **Skills** | Run `/help`. Skills appear namespaced as `/vgv-ffca-plugin:<skill>`, for example `/vgv-ffca-plugin:ffca-feature`. Invoke one to confirm it triggers |
| **Hook** | In an FFCA repo, have Claude add a forbidden dependency to a `pubspec.yaml`, for example a `_data` package to a `_presentation` package. The edit must be blocked with the rule and the fix |
| **Agent** | Run `/agents` and confirm `ffca-layer-auditor` is listed, or run `/vgv-ffca-plugin:ffca-audit` and confirm it dispatches the agent |
| **MCP server** | Run `/mcp` and confirm `very_good_cli` shows connected |

After editing a `SKILL.md`, an agent, or `.claude-plugin/plugin.json`, restart the session to pick up the change. Edits to `hooks/validate_layers.sh` take effect on the next matching tool call.

### Run the validator tests

The layer validator has its own test suite with fixture repos under `scripts/test/fixtures`:

```bash
cd scripts && dart pub get && dart test
```

Run the validator against a real FFCA workspace with:

```bash
dart run scripts/validate_layers.dart --all
```

### Validate before you push

Run the same plugin check CI runs, from the repository root:

```bash
claude plugin validate .
```

This checks the manifest, skill frontmatter, hook JSON, MCP config, and file references. It is static, so it does not replace the live checks above.

## CI Checks

Every pull request runs the following checks from `.github/workflows/ci.yaml`:

| Check | What it does | Config |
| ----- | ------------ | ------ |
| Markdown Quality | Lints all `*.md` files with markdownlint-cli2, except `CHANGELOG.md` and `references/ffca_architecture.md` | `config/custom.markdownlint.jsonc` |
| Spelling Check | Runs cspell on all `*.md` files except `CHANGELOG.md` | `config/cspell.json` |
| Layer Validator | Runs `dart analyze --fatal-infos`, `dart format --set-exit-if-changed`, and `dart test` in `scripts/` | `scripts/pubspec.yaml` |
| Skills Lint | Validates every `SKILL.md` in `skills/` | Very Good Workflows `skills_lint` |
| Plugin Validation | Validates the plugin | `claude plugin validate .` |

If the spelling check flags a legitimate word, add it to the `words` array in `config/cspell.json`.

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/) with the format:

```text
type(scope): description
```

| Type | When to use | Example |
| ---- | ----------- | ------- |
| `feat` | New skill or feature | `feat: add ffca-testing skill` |
| `fix` | Fix an error or incorrect guidance | `fix: correct routing callback example` |
| `docs` | Documentation-only change | `docs: clarify hook prerequisites` |
| `chore` | Maintenance and tooling | `chore: update cspell config` |
| `refactor` | Restructure without changing behavior | `refactor: split validator rules` |
| `ci` | CI pipeline changes | `ci: add validator format step` |

## Pull Requests

- Branch from `main`.
- Keep PRs focused. Open **one skill per PR** for new skills.
- Ensure all CI checks pass before requesting review.
- Link any related issues in the PR description.
