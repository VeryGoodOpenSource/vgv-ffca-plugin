---
name: ffca-architecture
description: Feature-First Clean Architecture orientation for Flutter monorepos: where code lives, layer boundaries, naming, and package organization.
when_to_use: Use when working in an FFCA monorepo (a features/ folder containing {feature}_domain, {feature}_data, or {feature}_presentation packages), or when the user asks about Feature-First Clean Architecture, monorepo structure, where code should live, layer dependencies, or package organization.
allowed-tools: Read Glob Grep
effort: high
---

# FFCA Architecture

Orientation skill for Feature-First Clean Architecture (FFCA) monorepos. It tells you how to navigate the structure and which rules apply. It does not restate the conventions: those live in `references/ffca_architecture.md`, and every step below points you to the section to read.

## Confirm you are in an FFCA repo

The detection signal is a `features/` folder whose packages follow the `{feature}_domain`, `{feature}_data`, or `{feature}_presentation` naming. If the repo uses the standard VGV layered structure (`packages/` with `_repository`/`_api_client`), this is not an FFCA repo: defer to the layered-architecture skill instead.

## Workflow: deciding where code lives

1. Read `references/ffca_architecture.md`, section *The Structure*, to place the work in one of the three top-level folders: `apps/`, `features/`, `shared/`.
2. To decide between a feature and a shared package, apply the decision rule in section *Shared Libraries* (business capability an app composes goes to `features/`; a generic, pub-publishable utility goes to `shared/`). Use its component table to settle edge cases.
3. To decide whether a feature needs a presentation layer, read section *Headless Features*. A feature with no screens stays domain plus data and can grow a presentation package later with no structural change.
4. Before naming any package, read section *Naming Conventions (Enforced)*. The names are mechanically validated by the hook, so they are not optional.
5. To place a file inside a package, read section *Layer Subfolder Conventions* for the per-layer folder map (`models/`, `repositories/`, `use_cases/`, `data_sources/`, `dtos/`, `mappers/`, and the per-screen `bloc/`, `views/`, module layout).

## Before you wire dependencies

Read `references/ffca_architecture.md`, section *Dependency Graph Rules*, before adding any path dependency to a pubspec. The hook enforces these rules on every pubspec edit and blocks the edit on a violation, so confirm the direction first:

- apps depend on features and shared
- shared depends only on external and other shared packages
- the domain layer imports nothing else from its feature
- the data layer imports its own domain
- the presentation layer imports domains, never a data layer

## Anti-patterns to reject

These are the violations the architecture exists to prevent. Read the cited sections for the rationale:

- Presentation importing a data layer. Depend on the domain and go through its repository interface. See section *Dependency Graph Rules*.
- A shared package depending on a feature. See section *Shared Libraries*.
- Business logic living in `shared/`. Volatile, app-specific logic belongs in a feature domain. See the component table in section *Shared Libraries*.

## Where to go next

- Creating or extending a feature: use the `ffca-feature` skill.
- Routes, navigation, or deep links: use the `ffca-routing` skill.
- One feature needing another's data: use the `ffca-cross-feature` skill.
- Checking the whole repo's health: use the `ffca-audit` skill.
