# vgv-ffca-plugin: Specification

**Status:** Draft
**Author:** Rémy (VGV)
**Distribution:** very_good_claude_marketplace

---

## Overview

A Claude Code plugin that operationalizes Feature-First Clean Architecture (FFCA) for Flutter monorepos. It is the third layer of VGV's AI-assisted engineering stack:

| Layer | Plugin | Role |
|---|---|---|
| Workflow | vgv-wingspan | brainstorm → plan → build → review |
| **Structure** | **vgv-ffca-plugin** | Monorepo structure, layer rules, FFCA conventions |
| Code quality | vgv-ai-flutter-plugin | Bloc, testing, a11y, theming, analyze/format hooks |

The plugin ships three asset types: **skills** that teach Claude the FFCA conventions, a **blocking validation hook** that enforces layer rules on every pubspec edit, and an **MCP configuration** that wires the Very Good CLI server.

The plugin is the delivery vehicle for the approved architecture, available before the FFCA SDK exists. When the SDK ships, its MCP tools slot into the same plugin (v2).

---

## Plugin Structure

```
vgv-ffca-plugin/
├── .claude-plugin/
│   └── plugin.json
├── references/
│   ├── ffca_architecture.md         # THE reference: full conventions, synced from the Notion page
│   └── code_templates/
│       ├── domain_templates.md
│       ├── data_templates.md
│       └── presentation_templates.md
├── skills/
│   ├── ffca-architecture/
│   │   └── SKILL.md
│   ├── ffca-feature/
│   │   └── SKILL.md
│   ├── ffca-routing/
│   │   └── SKILL.md
│   ├── ffca-cross-feature/
│   │   └── SKILL.md
│   └── ffca-audit/
│       └── SKILL.md
├── hooks/
│   ├── hooks.json
│   └── validate_layers.sh
├── scripts/
│   ├── validate_layers.dart
│   └── sync_reference.dart           # regenerates references/ from the Notion page export
└── .mcp.json
```

---

## plugin.json

```json
{
  "name": "vgv-ffca-plugin",
  "version": "0.1.0",
  "description": "Feature-First Clean Architecture (FFCA) for Flutter monorepos. Skills, validation hooks, and conventions for AI-first development, by Very Good Ventures.",
  "author": "Very Good Ventures"
}
```

---

## Shared Reference

`references/ffca_architecture.md` is the single FFCA reference inside the plugin: the full conventions document, generated from the [FFCA architecture Notion page](https://www.notion.so/verygoodventures/Feature-First-Clean-Architecture-2fb45eb3279580568023d1cf9bc00c24). All four skills point into it instead of carrying their own copy of the conventions.

This follows the progressive-disclosure model that skills are built on, and the same depth-to-load-frequency principle as the CLAUDE.md hybrid approach:

- **SKILL.md files stay lean:** trigger description, the workflow for that task, the non-negotiable rules for that context, and pointers into the reference ("Read `references/ffca_architecture.md`, section *Dependency Graph Rules*, before wiring pubspec dependencies").
- **The reference carries the depth:** full naming tables, layer rules, folder conventions, decision trees, and rationale. Claude reads the relevant section on demand when a skill directs it there.
- **One sync target:** when the Notion page changes, only `references/ffca_architecture.md` regenerates (via `scripts/sync_reference.dart` from a Notion export). The skill files only change when a *workflow* changes, not when conventions are reworded.

`references/code_templates/` holds the canonical code examples per layer (model, repository, mapper, Cubit, Module, GoRouteData). Only `ffca-feature` and `ffca-routing` point to these.

---

## Skills

Each skill self-scopes to FFCA repos through its description, so the plugin coexists with vgv-ai-flutter-plugin without triggering conflicts. The detection signal: a `features/` folder containing `{feature}_domain`, `{feature}_data`, or `{feature}_presentation` packages.

Skills contain workflow guidance only; conventions live in the shared reference. Each SKILL.md names the reference sections it depends on, so drift is traceable when the architecture evolves.

### Skill 1: ffca-architecture

**Description (trigger):** "Use when working in an FFCA monorepo (a features/ folder containing {feature}_domain, {feature}_data, or {feature}_presentation packages), or when the user asks about Feature-First Clean Architecture, monorepo structure, where code should live, layer dependencies, or package organization."

**Content:**
- The three top-level folders: apps/, features/, shared/
- Feature types: full feature, headless feature, shared package
- The decision rule: business capability → features/, pub-publishable generic → shared/
- Naming conventions table (enforced)
- Dependency graph rules (the six rules from the architecture page)
- Layer subfolder conventions (models/, repositories/, use_cases/, data_sources/, dtos/, mappers/, bloc/, views/)
- Anti-patterns: presentation importing data, shared depending on features, business logic in shared/

### Skill 2: ffca-feature

**Description (trigger):** "Use when creating a new feature, headless feature, screen, or adding a layer to an existing feature in an FFCA monorepo. Covers the three-package scaffold, domain models, repositories, use cases, DTOs, mappers, Cubits, and Modules."

**Content:**
- Workflow: check for a pre-generated API client (Swagger) first, then domain → data → presentation
- Domain: model with manual `==`/`hashCode`/`toString`, `abstract interface class` repositories, CQS use cases (Query/Command) only when combining repositories
- Data: data sources with dtos/ subfolders, extension mappers, repository implementations
- Presentation: Cubit + sealed states (Initial/Loading/Loaded/Error), screen with switch-on-state, Module wiring Providers and callbacks
- Headless feature: domain + data only, how to grow into a full feature
- Pubspec templates per layer with correct path dependencies
- Barrel files: primary + subfeature barrels
- Test scaffolding per layer (delegates to vgv-ai-flutter-plugin's testing skill for blocTest/mocktail details)

### Skill 3: ffca-routing

**Description (trigger):** "Use when adding screens, routes, navigation, deep links, or navigation callbacks in an FFCA monorepo."

**Content:**
- Callback injection: Module exposes typed callbacks, app layer wires them
- go_router_builder: `@TypedGoRoute` + `GoRouteData` classes in the app layer
- The `$extra` hydration pattern: screens rebuild from URL params alone, `$extra` is an optional optimization
- The Actions/Intent alternative for deep widget trees
- Constraints: no string-based paths, features never import the app router or another feature's routes

### Skill 4: ffca-cross-feature

**Description (trigger):** "Use when one feature needs data or functionality from another feature, when sharing models across features, or when deciding between a use case and a new composing feature."

**Content:**
- Cross-feature domain dependencies: cart_domain → product_domain
- The Summary pattern: loose coupling through IDs
- Use cases in the consuming feature's domain
- Composing features for complex multi-domain logic (checkout depends on cart + product)
- Shared Blocs at app level; features communicate by dispatching events, never by knowing each other
- Reusable widgets with their own Cubit live in the owning feature's presentation package

### Skill 5: ffca-audit

**Description (trigger):** "Use when auditing an FFCA monorepo for architecture compliance, reviewing the full dependency graph, assessing FFCA adoption in an existing project, or when the user asks for an architecture health check."

**Content:**
- Runs `dart run scripts/validate_layers.dart --all` for the full-graph mechanical checks (naming, layer rules, cycles)
- Goes beyond the script with qualitative review against `references/ffca_architecture.md`:
  - Enumerate all packages and classify each by folder, naming, and inferred type (feature, headless feature, shared)
  - Classify every presentation package's path dependencies by layer and confirm actual usage via import analysis (a declared dependency that's never imported is also a finding)
  - Check barrel file consistency: primary barrels exist, subfeature barrels where expected, no missing exports
  - Flag misplaced packages (business logic in shared/, generic utilities in features/)
  - Flag high fan-in domains that may be doing too much
- Output: a per-package verdict table plus a prioritized findings list, suitable for a `CODE_ASSESSMENT`-style report

The hook keeps individual edits compliant; the audit skill answers "is this whole repo healthy", on demand and in CI-adjacent reviews.

---

## Hooks

### hooks.json

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate_layers.sh"
          }
        ]
      }
    ]
  }
}
```

### validate_layers.sh

Thin shell wrapper, mirroring the analyze hook in vgv-ai-flutter-plugin:

1. Parse the hook payload from stdin with `jq`, extract `file_path`
2. Exit 0 silently unless the file is a `pubspec.yaml`
3. Exit 0 silently if the repo is not FFCA-shaped (no `features/` folder) or if `dart`/`jq` is unavailable (graceful skip)
4. Run `dart run ${CLAUDE_PLUGIN_ROOT}/scripts/validate_layers.dart --file <file_path>`
5. Propagate the exit code: 0 passes, 2 blocks Claude until the violation is fixed

### validate_layers.dart

Two modes:

- **Incremental (hook, default):** validates the edited package plus its direct dependents. Fast on any workspace size; an edit can only break its own rules or the packages that depend on it.
- **Full graph (`--all`):** validates every package and runs the workspace-wide cycle check. Used by CI and the `ffca-audit` skill.

Checks per package:

| Check | Rule |
|---|---|
| Naming | A package under `features/{f}/` must be named `{f}_domain`, `{f}_data`, `{f}_data_{backend}`, or `{f}_presentation` |
| Domain deps | Path dependencies on other `*_domain` packages and `shared/` Dart packages only |
| Data deps | Own `{f}_domain`, `shared/` packages. Never any `*_presentation`, never another feature's `*_data` |
| Presentation deps | Own `{f}_domain`, other `*_domain` packages, other `*_presentation` packages, `shared/`. Never any `*_data` |
| Shared deps | External pub packages and other `shared/` packages only. Never `features/` |
| Apps | May depend on anything. Nothing depends on an app |
| Cycles | Incremental mode: cycles reachable from the edited package. `--all` mode: topological sort of the full workspace graph |

Output on failure (exit 2, stderr):

```
FFCA violation in features/cart/cart_presentation/pubspec.yaml:
  ✗ cart_presentation depends on product_data (presentation must never depend on a data layer)
  → Depend on product_domain instead and access data through its repository interface.
```

Each violation includes the rule and the fix, so Claude self-corrects in the same turn.

Rules live in a `rules` constant at the top of the script, isolated so the pending architecture decisions (cross-feature dependency scope) change one block, not the whole script. The same script runs in CI: `dart run scripts/validate_layers.dart --all`.

---

## MCP Configuration

`.mcp.json` reuses the Very Good CLI MCP server, identical to vgv-ai-flutter-plugin:

```json
{
  "mcpServers": {
    "very_good_cli": {
      "command": "very_good",
      "args": ["mcp"]
    }
  }
}
```

This gives Claude `create`, `tests`, `packages_get`, and `packages_check_licenses` today. FFCA SDK tools (`create_feature`, `validate_graph`, `add_model`, and the rest of the catalog) are added here in v2 once the SDK ships.

---

## Distribution

Two stages, gated on the architecture's approval status:

**Stage 1 (now): private repo in VGVentures.**

```bash
gh repo create VGVentures/vgv-ffca-plugin --private
```

The plugin's `references/ffca_architecture.md` is the full architecture doc, which isn't approved or published on VGE yet, so the repo starts private. Claude Code marketplaces work with private repos for anyone with git access via `gh auth`, which covers the platform team pilot. For the very first local iteration, no repo is needed at all: build the plugin in a folder and install it from a local marketplace path to test the hook.

**Stage 2 (at v1.0): transfer to VeryGoodOpenSource and register in the marketplace.**

Once the open discussions are resolved and the architecture is public-ready, transfer the repo and open one PR to `very_good_claude_marketplace` adding the plugin entry. From then on:

```bash
claude plugin install vgv-ffca-plugin@very_good_claude_marketplace
```

Standalone install, no Arcana dependency. Arcana integration (auto-enable via its settings.json template) can come later as a one-line change on the Arcana side.

---

## Versioning Roadmap

| Version | Contents | Gate |
|---|---|---|
| 0.1.0 | Skills (including audit) + validation hook + Very Good CLI MCP | None: ship now, iterate as the architecture evolves |
| 0.x | Iterate on skill content and hook rules from pilot project feedback | Pilot project |
| 1.0.0 | Stable conventions, resolved open discussions (Component+Builder, widget-tree composition) baked into skills and rules | Open discussions resolved with Brian |
| 2.0.0 | FFCA SDK MCP tools replace skill-guided generation with deterministic tool calls | SDK Phase 1 ships |

Generation stays skill-guided until v2: a Mason command layer in between would be throwaway work once the SDK's deterministic tools arrive.

---

## Drift Prevention

The architecture Notion page is the single source of truth; `references/ffca_architecture.md` is its in-plugin mirror. Three mechanisms keep the plugin honest:

1. `scripts/sync_reference.dart` regenerates `references/ffca_architecture.md` from the Notion page export. A CI check (or scheduled workflow) flags when the plugin's copy is stale.
2. Skills never restate conventions; they point into the reference by section name. A reworded convention requires zero skill edits.
3. The validation rules constant in `validate_layers.dart` names the "Dependency Graph Rules" section it implements, so a rule change on the page maps to one code location.
