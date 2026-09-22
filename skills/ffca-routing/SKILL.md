---
name: ffca-routing
description: "Routing and navigation for FFCA monorepos: callback injection, go_router_builder typed routes, the $extra hydration pattern, and feature isolation."
when_to_use: Use when adding screens, routes, navigation, deep links, or navigation callbacks in an FFCA monorepo.
allowed-tools: Read Glob Grep Write Edit
effort: high
---

# FFCA Routing

Workflow for wiring navigation in an FFCA monorepo. The patterns and code shapes live in `references/ffca_architecture.md`, section *Routing & Navigation*, and in `references/code_templates/presentation_templates.md`. Read them before wiring routes.

## The core constraint

Features are isolated. A feature never imports the app's router or another feature's routes. Navigation is a dependency the app layer injects. Read section *Routing & Navigation* for the rationale, then follow the pattern that fits the feature's depth.

## Choose the injection pattern

1. **Shallow widget trees: callbacks on the Module.** The Module constructor takes typed callbacks (`onProductSelected`, `onCheckoutRequested`), and the app layer supplies them. Adapt the Module example in `references/code_templates/presentation_templates.md`.
2. **Deep widget trees: a Navigation class.** Define a navigation contract in the feature's presentation package and provide it to the subtree, so deep widgets invoke callbacks without prop drilling. See the `CartNavigation` example in section *Routing & Navigation*.
3. **Alternative: Actions and Intents.** Register Actions at the top of the tree and invoke typed Intents from deep widgets. Same trade-off as Provider (resolved at runtime). The Module-boundary callback stays the compile-time-safe cross-feature contract either way.

## Wire routes in the app layer with go_router_builder

The recommended implementation is `go_router` plus `go_router_builder`. The app layer defines `@TypedGoRoute` and `GoRouteData` classes that instantiate feature Modules and wire their callbacks to typed route navigation. Adapt the `GoRouteData` template in `references/code_templates/presentation_templates.md`.

Two hard rules from section *Routing & Navigation*:

- No string-based paths. Navigate with generated route classes, for example `ProductDetailRoute(id: id).go(context)`, never `context.push('/product/123')`.
- Features never import the app router configuration or another feature's route classes.

## Deep links and the $extra pattern

Every screen must be rebuildable from its URL parameters alone. `$extra` is a volatile optimization that is lost on refresh, process death, and cold-start deep links, so the route passes it as nullable and the Bloc treats it as optional: emit `Loaded` immediately when it is present, otherwise fetch by id and show loading. Adapt the `ProductDetailRoute` template and read the *Data hydration for deep links* part of section *Routing & Navigation*.
