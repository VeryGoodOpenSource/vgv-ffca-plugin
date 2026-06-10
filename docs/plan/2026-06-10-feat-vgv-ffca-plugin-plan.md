---
title: Implement vgv-ffca-plugin
type: feat
date: 2026-06-10
---

## Implement vgv-ffca-plugin - Standard

## Overview

Build the `vgv-ffca-plugin` Claude Code plugin exactly as specified in `vgv_ffca_plugin_spec.md`. The plugin operationalizes Feature-First Clean Architecture (FFCA) for Flutter monorepos through three asset types:

1. **Five skills** that teach Claude FFCA workflows (`ffca-architecture`, `ffca-feature`, `ffca-routing`, `ffca-cross-feature`, `ffca-audit`).
2. **A blocking validation hook** (`PostToolUse` on `Edit|Write`) that enforces layer dependency rules on every `pubspec.yaml` edit, backed by a pure-Dart `validate_layers.dart` script.
3. **An MCP configuration** wiring the Very Good CLI server.

The spec is the source of truth for structure, skill trigger descriptions, hook behavior, and validation rules. `ffca_architecture.md` is the conventions reference: it is copied verbatim to `references/ffca_architecture.md` and is never rewritten or summarized. Skills carry workflow guidance only; they point into the reference by section name so conventions live in exactly one place.

## Problem Statement / Motivation

FFCA is the approved VGV monorepo architecture, but there is no tooling to enforce its layer rules or teach its conventions to AI agents. The plugin is the delivery vehicle for the architecture, available before the FFCA SDK exists. It is the **Structure** layer of VGV's AI engineering stack, sitting between `vgv-wingspan` (workflow) and `vgv-ai-flutter-plugin` (code quality). It must coexist with `vgv-ai-flutter-plugin` without trigger conflicts: every skill self-scopes to FFCA repos via its description (detection signal: a `features/` folder containing `{feature}_domain`, `{feature}_data`, or `{feature}_presentation` packages).

## Proposed Solution

Build bottom-up, highest-risk-first. The validation script is the riskiest component (real logic, exit-code contract with the hook), so it is built test-first before anything else. Then the hook wraps it, then the skills and reference, then MCP config and README, then end-to-end verification.

### Structural reference (already studied)

The sibling plugin `vgv-ai-flutter-plugin` (in the plugin cache) establishes the conventions to mirror:

- **`hooks/scripts/analyze.sh`** is the template for the validation hook wrapper: `set -euo pipefail`, read stdin payload, check `jq` availability and skip gracefully, extract `file_path` with `jq -r '.tool_input.file_path // empty'`, filter by file type, run the tool, capture output and `exit 2` on failure.
- **SKILL.md frontmatter** uses these keys: `name`, `description`, `when_to_use`, `allowed-tools`, `effort`. The spec's "Description (trigger)" text maps to the combined `description` + `when_to_use` fields.
- **`.mcp.json`**, **`plugin.json`**, and the **README layout** (overview, installation, skills table, hooks table with prerequisites) all follow the sibling's shape.

Decision: the sibling's `hooks.json` references scripts at `hooks/scripts/`. The FFCA spec places `validate_layers.sh` directly at `hooks/validate_layers.sh`. **Follow the spec exactly** (`hooks/validate_layers.sh`, command `${CLAUDE_PLUGIN_ROOT}/hooks/validate_layers.sh`), not the sibling's nested layout.

### Final plugin structure

```
vgv-ffca-plugin/
├── .claude-plugin/
│   └── plugin.json
├── references/
│   ├── ffca_architecture.md            # byte-identical copy of provided file
│   └── code_templates/
│       ├── domain_templates.md
│       ├── data_templates.md
│       └── presentation_templates.md
├── skills/
│   ├── ffca-architecture/SKILL.md
│   ├── ffca-feature/SKILL.md
│   ├── ffca-routing/SKILL.md
│   ├── ffca-cross-feature/SKILL.md
│   └── ffca-audit/SKILL.md
├── hooks/
│   ├── hooks.json
│   └── validate_layers.sh
├── scripts/
│   ├── validate_layers.dart
│   ├── pubspec.yaml                     # for package:yaml + package:test
│   ├── sync_reference.dart              # stub with TODO (out of scope to implement)
│   └── test/
│       ├── validate_layers_test.dart
│       └── fixtures/
│           ├── valid_workspace/
│           └── invalid_workspace/
├── .mcp.json
└── README.md
```

Note: `scripts/test/` and `scripts/pubspec.yaml` are not in the spec's structure diagram, but the kickoff explicitly requires a `dart test` suite and a pubspec is acceptable for `package:yaml`. They live under `scripts/` so the validator and its tests form one self-contained Dart package.

## Technical Considerations

### `scripts/validate_layers.dart` (highest risk, build test-first)

**Constraints:** pure Dart. `dart:io` + `dart:core` for filesystem and process. `package:yaml` to parse pubspecs (acceptable per kickoff; requires `scripts/pubspec.yaml`).

**CLI surface:**
- `--file <path>`: incremental mode (default for the hook). Validates the edited package plus its direct dependents.
- `--all`: full-graph mode. Validates every package and runs a workspace-wide topological cycle check. Used by CI and the `ffca-audit` skill.

**Workspace discovery:** from the target pubspec, walk parent directories to find the workspace root (the dir containing `features/`, typically also the root `pubspec.yaml` with a `workspace:` key). Build a map of every package: `name → {path, layer, feature, dependencies}`. Layer/feature are inferred from the path under `features/{f}/{f}_{layer}` and the package name.

**Rules constant (isolated at top of file):** a `const rules` block, commented with a pointer to the `Dependency Graph Rules` section of `references/ffca_architecture.md`, so a convention change maps to one code location. Implements the spec's checks table verbatim:

| Check | Rule |
|---|---|
| Naming | A package under `features/{f}/` must be named `{f}_domain`, `{f}_data`, `{f}_data_{backend}`, or `{f}_presentation` |
| Domain deps | Path deps on other `*_domain` packages and `shared/` Dart packages only |
| Data deps | Own `{f}_domain` + `shared/`. Never any `*_presentation`, never another feature's `*_data` |
| Presentation deps | Own `{f}_domain`, other `*_domain`, other `*_presentation`, `shared/`. Never any `*_data` |
| Shared deps | External pub packages + other `shared/` packages only. Never `features/` |
| Apps | May depend on anything. Nothing depends on an app |
| Cycles | Incremental: cycles reachable from edited package. `--all`: topological sort of full graph |

**Only path dependencies are checked** (local packages). External pub dependencies are ignored for layer rules. The "shared deps: external only" rule means a `shared/` package must have no path dependency pointing into `features/`.

**Violation output (stderr, then `exit 2`)** matches the spec format exactly — the rule AND the fix on each finding:

```
FFCA violation in features/cart/cart_presentation/pubspec.yaml:
  ✗ cart_presentation depends on product_data (presentation must never depend on a data layer)
  → Depend on product_domain instead and access data through its repository interface.
```

**Graceful skips (`exit 0`, no output):**
- target file is not a `pubspec.yaml`
- repo has no `features/` folder (not FFCA-shaped)
- workspace root cannot be located

**Exit codes:** `0` pass/skip, `2` violation (blocks Claude). Reserve other non-zero codes for genuine script errors so the hook can distinguish a crash from a violation.

### Test matrix (`scripts/test/validate_layers_test.dart`)

Two fixture workspaces under `scripts/test/fixtures/`, pubspec.yaml files only (no Dart source). Each is a Dart workspace (root `pubspec.yaml` with `workspace:` listing members) so discovery works.

`valid_workspace/` — a minimal correct FFCA monorepo:
- `apps/mobile_app` depends on features + shared
- `features/product/{product_domain, product_data, product_presentation}`
- `features/cart/{cart_domain, cart_data, cart_presentation}` with `cart_domain → product_domain` (valid cross-feature domain dep)
- `features/auth/{auth_domain, auth_data_firebase}` (headless, backend suffix naming)
- `shared/ui_kit`, `shared/api_client`

`invalid_workspace/` — must plant **every** violation so each rule has a failing test:
1. Bad naming under `features/` (e.g., `features/orders/orders_service`)
2. Domain depending on data (`x_domain → x_data`)
3. Data depending on presentation (`x_data → x_presentation`)
4. Presentation depending on `*_data` (`cart_presentation → product_data`) — the spec's canonical example
5. Shared depending on a feature (`shared/foo → some_domain`)
6. A dependency cycle (`a_domain → b_domain → a_domain`)
7. A package depending on an app (`x → mobile_app`)

Test cases assert:
- Valid workspace passes in **both** incremental (`--file` on each package) and `--all` modes (exit 0, no violations).
- Each planted violation in the invalid workspace is caught with its specific message substring (rule text present, fix text present), exit code 2.
- Graceful-skip cases: non-pubspec path → exit 0; a workspace with no `features/` → exit 0.

Tests invoke the script via `Process.run('dart', ['run', 'validate_layers.dart', ...])` (or call an exposed `run(args)` entrypoint directly for speed) and assert on exit code + stderr.

### `hooks/validate_layers.sh`

Mirror `analyze.sh`:
1. `set -euo pipefail`, read stdin payload.
2. `command -v jq` and `command -v dart`; if either missing, echo a skip note to stderr and `exit 0`.
3. `file_path=$(jq -r '.tool_input.file_path // empty')`; if empty or basename is not `pubspec.yaml`, `exit 0`.
4. FFCA-shape check: walk up from the file to find a `features/` dir; if none, `exit 0`.
5. `dart run ${CLAUDE_PLUGIN_ROOT}/scripts/validate_layers.dart --file "$file_path"`; propagate exit code (capture output, re-emit on failure, `exit 2`).

### `hooks/hooks.json`

Exactly the spec block: `PostToolUse` matcher `Edit|Write`, command `${CLAUDE_PLUGIN_ROOT}/hooks/validate_layers.sh`. Add a top-level `description` field (sibling convention) and a `timeout` (~30s) consistent with the sibling.

### Skills

Each `SKILL.md`: frontmatter (`name: vgv-ffca-<x>`, `description`/`when_to_use` carrying the spec's exact trigger text, `allowed-tools`, `effort`), then workflow guidance only. Conventions are NEVER restated — every convention reference is a pointer like: "Read `references/ffca_architecture.md`, section *Dependency Graph Rules*, before wiring pubspec dependencies." Each skill names the reference sections it depends on.

- **ffca-architecture**: orientation skill. Points into Structure, Naming Conventions, Dependency Graph Rules, Layer Subfolder Conventions, anti-patterns. No code templates.
- **ffca-feature**: scaffold workflow (check for Swagger client → domain → data → presentation; headless variant). Points into Feature Layers sections AND `references/code_templates/` (domain, data, presentation). Delegates blocTest/mocktail detail to vgv-ai-flutter-plugin's testing skill.
- **ffca-routing**: callback injection, go_router_builder `GoRouteData`, `$extra` hydration, Actions/Intents alternative. Points into Routing & Navigation section AND `references/code_templates/presentation_templates.md`.
- **ffca-cross-feature**: cross-feature domain deps, Summary pattern, composing features, shared app-level Blocs. Points into Combining Different Features + FAQ sections. No code templates.
- **ffca-audit**: runs `dart run scripts/validate_layers.dart --all`, then the qualitative checks from the spec (classify packages, verify declared-vs-imported deps, barrel consistency, misplaced packages, high fan-in domains). Outputs a per-package verdict table + prioritized findings list.

### `references/code_templates/`

Extract the code examples already in `ffca_architecture.md` into ready-to-adapt template files (do not invent new code):
- `domain_templates.md`: model (manual `==`/`hashCode`/`toString`), `abstract interface class` repository (`IProductsRepository`), Summary pattern, Query/Command use cases.
- `data_templates.md`: data source + `dtos/`, extension mapper (`toDomain()`), repository implementation.
- `presentation_templates.md`: Cubit + sealed states, Module (Provider + BlocProvider wiring), `GoRouteData` route, Navigation class.

### `.mcp.json` and `plugin.json`

`.mcp.json`: exactly the spec's Very Good CLI server block. `plugin.json`: exactly the spec's block (name, version `0.1.0`, description, author). Optionally enrich author/keywords per sibling convention, but the spec's four fields are the floor.

### `scripts/sync_reference.dart`

Out of scope to implement. Stub it: a `main()` that prints a "not yet implemented" notice plus a comment block describing the Notion source page URL and the intended regeneration flow.

## Acceptance Criteria

- [ ] Plugin tree matches the spec's structure exactly (plus the justified `scripts/test/` + `scripts/pubspec.yaml` additions)
- [ ] `references/ffca_architecture.md` is byte-identical to the provided file (verify with `diff`)
- [ ] `validate_layers.dart` implements all seven checks with the isolated `rules` constant pointing at the reference section
- [ ] Incremental (`--file`) and `--all` modes both implemented; `--all` includes topological cycle detection
- [ ] Violation output includes both the rule and the fix, exits 2; graceful skips exit 0
- [ ] `dart test` passes in `scripts/`; every validation rule has a failing-fixture test; valid workspace passes both modes
- [ ] `hooks/validate_layers.sh` parses payload with jq, filters to `pubspec.yaml`, skips gracefully when not FFCA-shaped or when `dart`/`jq` missing, propagates exit 2
- [ ] `hooks/hooks.json` matches the spec block
- [ ] All five SKILL.md files use the spec's exact trigger descriptions, contain workflow guidance only, and point into the reference by section name (no restated conventions)
- [ ] `references/code_templates/` populated by extraction from the reference (domain, data, presentation)
- [ ] `.mcp.json` and `plugin.json` match the spec
- [ ] `sync_reference.dart` stubbed with TODO + Notion source comment
- [ ] README complete: overview, three-layer stack positioning table, installation (private repo), skills table, hook behavior table with prerequisites (Dart SDK, jq)
- [ ] No em dashes anywhere in authored prose (VGV style: use colons)
- [ ] End-to-end verification (step 8) performed in a live session against a scratch fixture: hook blocks the `cart_presentation → product_data` edit and Claude self-corrects; a valid edit passes silently; an FFCA question triggers the right skill; `/ffca-audit` flags planted violations
- [ ] Conventional commits; PR opened from `feat/implement-ffca-plugin` for review

## Success Metrics

- `dart test` green with one failing-fixture test per rule.
- In a live Claude Code session, the hook blocks an invalid pubspec edit with the exact spec violation message, and a valid edit passes with no output.
- An FFCA-shaped question triggers the correct skill, which answers from the reference rather than from restated conventions.

## Dependencies & Risks

- **Dart SDK + jq** required at runtime for the hook; both skip gracefully if absent.
- **Workspace-root discovery** is the trickiest logic: ambiguous when `features/` is nested or absent. Mitigation: explicit graceful-skip path + a fixture test for the no-`features/` case.
- **Incremental dependent resolution**: an edit to `x_domain` can break `x_data`/`x_presentation` that depend on it. Incremental mode must validate the edited package plus its direct dependents, not just the edited package. Covered by a dedicated test.
- **Skill trigger collisions** with `vgv-ai-flutter-plugin`: mitigated by the FFCA self-scoping language in every description (the `features/` + `{feature}_{layer}` signal).
- **Byte-identical reference**: copy with `cp`, never through an editor; verify with `diff`.
- **Out of scope (do not build):** Mason bricks/scaffolding commands, `sync_reference.dart` automation (stub only), marketplace registration, Arcana integration.

## References & Research

- Spec (source of truth): `vgv_ffca_plugin_spec.md`
- Conventions reference: `ffca_architecture.md` (sections: Structure, Naming Conventions, Feature Layers, Dependency Graph Rules, Layer Subfolder Conventions, Routing & Navigation, FAQ)
- Kickoff steps + Definition of Done: `vgv_ffca_kickoff_prompt.md`
- Structural reference plugin: `vgv-ai-flutter-plugin` (plugin cache) — `hooks/scripts/analyze.sh` (hook wrapper pattern), `skills/layered-architecture/SKILL.md` (frontmatter format), `README.md` (layout), `.claude-plugin/plugin.json`, `.mcp.json`
