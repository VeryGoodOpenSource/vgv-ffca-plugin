---
name: ffca-cross-feature
description: Cross-feature dependencies in FFCA: the Summary pattern, use cases that combine repositories, composing features, and feature-to-feature communication.
when_to_use: Use when one feature needs data or functionality from another feature, when sharing models across features, or when deciding between a use case and a new composing feature.
allowed-tools: Read Glob Grep
effort: high
---

# FFCA Cross-Feature

Workflow for the moment one feature needs another. The patterns live in `references/ffca_architecture.md`: read the cited sections before coupling two features.

## The one allowed coupling: domain to domain

Features couple only at the domain layer, and only in one direction. A consuming feature's domain may depend on a provider feature's domain (for example `cart_domain` on `product_domain`). Data layers and presentation layers never reach across features for data. Read section *Combining Different Features*.

## Decide how to combine

1. **Loose coupling by id: the Summary pattern.** When a feature stores references to another feature's models, store ids only. The read model holds full objects; the stored summary holds ids. Read the *Summary pattern* in section *Combining Different Features* and adapt the `Cart`/`CartSummary` shapes.
2. **Combine repositories with a use case.** To assemble a populated model from two features, add a `Query` or `Command` in the consuming feature's domain that takes both repository interfaces. Read *Use cases combine repositories* in the same section. Keep the use case in the consumer, never in the provider.
3. **Normalize inside the repository, not a use case.** When an API returns nested objects belonging to another feature, split them inside the data repository (data may depend on another feature's domain interface). Read the FAQ entry *Dealing with nested API objects*. The DTO-to-domain mapping is duplicated in the consuming data package on purpose, to keep bounded contexts decoupled.

## When a use case is not enough: compose a feature

If multi-domain logic grows complex (for example a checkout that needs both cart and product), create a composing feature whose domain depends on several other domains. Read section *Features* and *Combining Different Features* to judge the boundary. A new feature is warranted when the combined logic has its own models, screens, or lifecycle.

## How features talk at runtime

Features never hold references to each other. Read section *Presentation Layer*:

- Shared state belongs to a Bloc provided at the app level; features dispatch events to it, they do not know each other.
- A reusable widget that needs its own Cubit but uses another feature's domain lives in the owning feature's presentation package and is exported through its barrel. See *Widgets with State Management*. It does not become a new feature unless it grows its own domain logic.

## Identity versus entity

Auth and user profile are separate domains, not one. Read the FAQ entry *How do I handle Auth and User Profiles?* Glue them with a query in the consuming feature's domain so a new profile field never forces a change to auth.
