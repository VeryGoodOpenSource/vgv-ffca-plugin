# 🦄 Contributing to VGV FFCA Plugin

First of all, thank you for taking the time to contribute! 🎉👍 Before you do, please carefully read this guide.

## Getting Started

1. **Fork** the repository and clone your fork locally.
2. Create a new branch from `main` for your work.
3. Install the [Dart SDK](https://dart.dev/get-dart) and `jq` if you plan to touch the hook or the validator.

## Types of Contributions

| Contribution | Where |
| ------------ | ----- |
| **New skill** | `skills/<skill-name>/SKILL.md` |
| **Improve an existing skill** | Edit the relevant `skills/*/SKILL.md` |
| **Agent** | `agents/` directory |
| **Hook** | `hooks/` directory |
| **Validator rules** | `scripts/validate_layers.dart` and its tests in `scripts/test/` |
| **Bug reports and feature requests** | [GitHub Issues](https://github.com/VeryGoodOpenSource/vgv-ffca-plugin/issues) |

## The FFCA Reference

`references/ffca_architecture.md` mirrors the canonical FFCA documentation. It is the single source of truth for the conventions, and the skills point into it by section name instead of restating it.

- Do not edit the reference to change a convention. Propose the change upstream, then sync the mirror.
- When a skill needs a convention, link to the relevant section of the reference. Do not copy the rule into the skill.

## Adding a New Skill

### 1. Create the skill file

Create `skills/<skill-name>/SKILL.md`. The file must begin with YAML frontmatter:

```yaml
---
name: <skill-name>
description: "What the skill covers, in one sentence."
when_to_use: Use when working in an FFCA monorepo and the user asks about X.
---
```

| Field | Required | Rules |
| ----- | -------- | ----- |
| `name` | Yes | Lowercase letters, numbers, and hyphens only. Prefix FFCA skills with `ffca-` |
| `description` | Yes | What the skill covers |
| `when_to_use` | Yes | When the skill should trigger, scoped to FFCA repos so it does not fire in layered repos |
| `allowed-tools` | No | Tools the skill may use without a permission prompt |

### 2. Update the README skills table

Add a row to the skills table and the direct-invocation list in `README.md`.

### 3. Update `plugin.json` keywords

Add relevant keywords to the `keywords` array in `.claude-plugin/plugin.json` when the skill covers new ground.

## Skill Writing Guidelines

- **Use clear directives.** Say "Use X" or "Do not use Y", not "consider" or "prefer".
- **Fence all code blocks** with language identifiers, such as ` ```dart `.
- **Provide complete, copy-pasteable snippets**, not fragments.
- **Reference packages by full name**, such as `package:go_router`.
- **Show anti-patterns alongside correct patterns** when it helps readers see what to avoid.
- **Keep prose tight.** Every word in a SKILL.md consumes context the user needs for their actual work. Prefer decision tables to long if/else narratives, and keep to one sentence per rule.

## Working on the Validator

The validator lives in `scripts/` and imports only `dart:io`, so the hook runs with just the Dart SDK. The `pubspec.yaml` there exists only for the test suite.

```bash
cd scripts
dart pub get
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
dart test
```

Add a fixture under `scripts/test/fixtures/` for every new rule, covering both a passing and a failing workspace.

## Testing Locally

From the repository root, launch Claude Code pointed at this directory:

```bash
claude --plugin-dir .
```

`--plugin-dir` loads the plugin for that session only and overrides any marketplace-installed copy.

| Component | How to verify |
| --------- | ------------- |
| **Skills** | Run `/help`. Skills appear namespaced as `/vgv-ffca-plugin:<skill>`. Invoke one to confirm it triggers. |
| **Agent** | Ask Claude to audit an FFCA repo and confirm it dispatches `ffca-layer-auditor`. |
| **Hook** | In an FFCA repo, have Claude add a forbidden dependency to a `pubspec.yaml` and confirm the edit is blocked. |

Restart the session after editing a `SKILL.md`, `hooks/hooks.json`, or `.claude-plugin/plugin.json`.

Before you push, run the same check CI runs:

```bash
claude plugin validate .
```

## CI Checks

Every pull request runs the following checks automatically:

| Check | What it does | Config |
| ----- | ------------ | ------ |
| Markdown lint | Lints all `*.md` files | `config/custom.markdownlint.jsonc` |
| Spelling | Runs cspell on all `*.md` files | `config/cspell.json` |
| Layer validator | Analyzes, formats, and tests the Dart validator | `scripts/` |
| Skills lint | Validates every skill's frontmatter, structure, and links | VGV `skills_lint` reusable workflow |
| Plugin validation | Validates the plugin manifest via Claude Code CLI | `claude plugin validate .` |

If the spelling check flags a legitimate word, add it to the `words` array in `config/cspell.json`.

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/). PRs are squash-merged with the PR title as the commit message, so the **PR title** must follow the format, since release-please builds the changelog from it:

```text
type(scope): description
```

| Type | When to use | Example |
| ---- | ----------- | ------- |
| `feat` | New skill or feature | `feat: add ffca-testing skill` |
| `fix` | Fix an error or incorrect guidance | `fix: correct $extra hydration example` |
| `docs` | Documentation-only change | `docs: clarify install steps` |
| `chore` | Maintenance and tooling | `chore: update cspell config` |
| `refactor` | Restructure without changing behavior | `refactor: split validator rules` |
| `ci` | CI pipeline changes | `ci: cache Dart dependencies` |

## Pull Requests

- Branch from `main`.
- Keep PRs focused, with one skill per PR for new skills.
- Fill out the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
- Ensure all CI checks pass before requesting review.
- Link any related issues in the PR description.
