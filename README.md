# VGV FFCA Plugin

A [Claude Code](https://claude.com/claude-code) plugin that operationalizes Feature-First Clean Architecture (FFCA) for Flutter monorepos.

Developed with 💙 by [Very Good Ventures](https://verygood.ventures) 🦄

## Overview

VGV FFCA Plugin teaches Claude the Feature-First Clean Architecture conventions and enforces its layer rules as you work. It ships three asset types:

- **Skills** that guide FFCA workflows: where code lives, how to scaffold a feature, how to wire routing, how to couple features, and how to audit a repo.
- **A blocking validation hook** that runs on every `pubspec.yaml` edit and stops the edit when it breaks a layer dependency rule, with the rule and the fix in the message so Claude self-corrects.
- **An MCP configuration** that wires the Very Good CLI server for project and package operations.

The conventions themselves live in a single reference, `references/ffca_architecture.md`, mirrored from the canonical Notion page. The skills never restate the conventions: they point into the reference by section name, so the architecture has exactly one source of truth.

## The stack

This plugin is the structure layer of Very Good Ventures' AI-assisted engineering stack. It composes with the other two plugins rather than replacing them.

| Layer | Plugin | Role |
| --- | --- | --- |
| Workflow | vgv-wingspan | brainstorm, plan, build, review |
| **Structure** | **vgv-ffca-plugin** | Monorepo structure, layer rules, FFCA conventions |
| Code quality | vgv-ai-flutter-plugin | Bloc, testing, a11y, theming, analyze and format hooks |

Each FFCA skill self-scopes to FFCA repos through its trigger description, so the plugin coexists with vgv-ai-flutter-plugin without conflicts. The detection signal is a `features/` folder containing `{feature}_domain`, `{feature}_data`, or `{feature}_presentation` packages.

## Installation

The plugin is currently a private repository in the VGVentures organization. Anyone with git access (via `gh auth`) can install it as a Claude Code marketplace.

For the platform team pilot, add the repository as a marketplace and install:

```bash
claude plugin marketplace add VGVentures/vgv-ffca-plugin && claude plugin install vgv-ffca-plugin
```

For local iteration, install from a checkout path:

```bash
claude plugin marketplace add /path/to/vgv-ffca-plugin && claude plugin install vgv-ffca-plugin
```

At v1.0 the repository transfers to VeryGoodOpenSource and registers in the `very_good_claude_marketplace` for one-line public install.

## Skills

| Skill | Description |
| --- | --- |
| [**FFCA Architecture**](skills/ffca-architecture/SKILL.md) | Orientation: where code lives across `apps/`, `features/`, `shared/`, the naming conventions, the layer dependency rules, and the anti-patterns to reject |
| [**FFCA Feature**](skills/ffca-feature/SKILL.md) | Scaffold and extend a feature: the three-package domain, data, and presentation structure, models, repositories, use cases, DTOs, mappers, Cubits, and Modules |
| [**FFCA Routing**](skills/ffca-routing/SKILL.md) | Navigation: callback injection, `go_router_builder` typed routes, the `$extra` hydration pattern, and the feature-isolation constraints |
| [**FFCA Cross-Feature**](skills/ffca-cross-feature/SKILL.md) | Coupling features: domain-to-domain dependencies, the Summary pattern, use cases that combine repositories, and composing features |
| [**FFCA Audit**](skills/ffca-audit/SKILL.md) | Whole-repo health check: the mechanical layer, naming, and cycle checks plus a qualitative review, producing a per-package verdict table |

Skills activate automatically when Claude detects an FFCA repo or an FFCA-shaped question. You can also invoke them directly:

```text
/ffca-architecture
/ffca-feature
/ffca-routing
/ffca-cross-feature
/ffca-audit
```

## Hook

A PostToolUse hook runs on every `Edit` or `Write`. When the edited file is a `pubspec.yaml` inside an FFCA-shaped repo, it validates the package's layer dependencies.

| Hook | Behavior |
| --- | --- |
| **Validate layers** | Runs the FFCA validator incrementally on the edited package and its direct dependents. Exits 2 on a violation (blocking: Claude must fix the dependency before continuing), printing the rule and the fix. Passes silently otherwise |

The validator is also runnable directly for CI and audits, across the whole workspace:

```bash
dart run scripts/validate_layers.dart --all
```

### Prerequisites

- **Dart SDK** must be available on your `PATH`. The validator imports only `dart:io`, so it runs with just the SDK, no `dart pub get` required.
- **jq** is used to parse the hook payload. The hook is skipped gracefully if `jq` or `dart` is not installed.

## How it fits together

The hook keeps individual pubspec edits compliant. The skills teach the conventions and workflows. The audit skill answers whether the whole repo is healthy, on demand. All three read from the same `references/ffca_architecture.md`, so when the architecture evolves, the reference is the only file that changes.
