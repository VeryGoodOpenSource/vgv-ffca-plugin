---
name: ffca-feature
description: Scaffold and extend FFCA features: the three-package domain/data/presentation structure, models, repositories, use cases, DTOs, mappers, Cubits, and Modules.
when_to_use: Use when creating a new feature, headless feature, screen, or adding a layer to an existing feature in an FFCA monorepo. Covers the three-package scaffold, domain models, repositories, use cases, DTOs, mappers, Cubits, and Modules.
allowed-tools: Read Glob Grep Write Edit mcp__very_good_cli__create mcp__very_good_cli__packages_get
effort: high
---

# FFCA Feature

Workflow for building a feature in an FFCA monorepo. Conventions and code shapes are not restated here: read the cited sections of `references/ffca_architecture.md` and adapt the templates in `references/code_templates/`.

## Before you start

1. Confirm the repo is FFCA-shaped (a `features/` folder with `{feature}_{layer}` packages). If not, stop and use the layered-architecture skill.
2. Read `references/ffca_architecture.md`, section *Feature Layers*, for the layer model, and section *Naming Conventions (Enforced)* for package names (the hook validates them).
3. Check for a pre-generated API client first. If the backend ships one OpenAPI/Swagger definition, read the FAQ entry *What if the backend has one large OpenAPI / Swagger definition for all endpoints?* The client belongs in `shared/`, and each feature's data layer consumes it.

## Build order: domain, then data, then presentation

Scaffold each package with the Very Good CLI (`dart_package` for domain and data, `flutter_package` for presentation), then fill it in. Build in dependency order so each layer compiles against the one below it.

### 1. Domain (`{feature}_domain`, Dart package)

Read section *Domain Layer* and adapt `references/code_templates/domain_templates.md`:

- Models in `models/`: plain Dart with value equality. Do not suffix them with `Model` or `Entity`.
- Repository interfaces in `repositories/`: `abstract interface class`, one per feature, named for the feature's own aggregate. A feature's domain never defines another feature's repository.
- Use cases in `use_cases/`: add a `Query` or `Command` class only when you combine multiple repositories or repeat the same work across Blocs. A passthrough to a single repository does not need one. Verbs: `execute` for commands, `get`/`watch` for queries.
- Add the primary barrel `{feature}_domain.dart`.

### 2. Data (`{feature}_data`, Dart package)

Read section *Data Layer* and adapt `references/code_templates/data_templates.md`:

- Data sources in `data_sources/`, each with a `dtos/` subfolder. Do not leak DTOs to other layers.
- Mappers in `mappers/`: extension methods (for example `toDomain()`) converting DTOs to domain models.
- Repository implementations in `repositories/` that fulfil the domain interface.
- Add the primary barrel `{feature}_data.dart`.

### 3. Presentation (`{feature}_presentation`, Flutter package)

Read section *Presentation Layer* and adapt `references/code_templates/presentation_templates.md`:

- Per screen: a `{screen}/bloc/` Cubit with sealed states (Initial, Loading, Loaded, Error), a `{screen}/views/` screen that switches on state, and a `{screen}/{screen}_module.dart` that wires Providers and exposes navigation callbacks.
- Add subfeature barrels per independent entry point plus the primary barrel `{feature}_presentation.dart`. Read section *Subfeature Barrel Files* for why this matters to deferred imports.
- For navigation wiring, use the `ffca-routing` skill.

## Headless features

A feature with no UI is domain plus data only. Read section *Headless Features*. When a screen is needed later, add a `{feature}_presentation` package: no change to the existing packages. If the data layer is backend-specific, name it `{feature}_data_{backend}` (for example `auth_data_firebase`).

## Pubspecs and dependencies

When you add path dependencies, follow section *Dependency Graph Rules*. The pubspec hook blocks edits that violate a layer rule and tells you the fix, so set the direction correctly the first time: data depends on its own domain, presentation depends on domains (never a data layer), neither depends on an app.

## Tests

Every package gets tests. This skill does not cover test mechanics: delegate `blocTest`, `mocktail`, and golden details to the vgv-ai-flutter-plugin testing skill. Cover each repository implementation, each use case, and each Cubit (success, failure, edge cases).
