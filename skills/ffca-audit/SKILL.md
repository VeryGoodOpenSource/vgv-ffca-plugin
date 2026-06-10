---
name: ffca-audit
description: Audit an FFCA monorepo for architecture compliance: the mechanical layer/naming/cycle checks plus a qualitative review, producing a per-package verdict table.
when_to_use: Use when auditing an FFCA monorepo for architecture compliance, reviewing the full dependency graph, assessing FFCA adoption in an existing project, or when the user asks for an architecture health check.
allowed-tools: Read Glob Grep Bash
effort: high
---

# FFCA Audit

Whole-repo architecture health check. The hook keeps individual edits compliant; this skill answers whether the repo as a whole is healthy. Run the mechanical pass first, then the qualitative review, then report.

## Step 1: mechanical checks

From the repo root, run the validator in full-graph mode:

```bash
dart run ${CLAUDE_PLUGIN_ROOT}/scripts/validate_layers.dart --all
```

This validates every package and runs the workspace-wide cycle check: naming, the layer dependency rules, and dependency cycles. It prints each violation with its rule and fix and exits 2 if any are found, 0 if the graph is clean. Treat every printed violation as a finding. The same command is what CI runs.

## Step 2: qualitative review

The script checks structure mechanically. Go beyond it by reading the relevant sections of `references/ffca_architecture.md` and inspecting the source:

1. **Enumerate and classify every package.** List all packages under `apps/`, `features/`, `shared/`. Classify each by folder, name, and inferred type (full feature, headless feature, shared package). Use section *Naming Conventions (Enforced)* and *Shared Libraries*.
2. **Verify presentation dependencies by usage.** For each presentation package, classify every path dependency by layer and confirm it is actually imported in the source. A declared dependency that is never imported is a finding. A presentation package depending on a data layer is a finding (cross-check section *Dependency Graph Rules*).
3. **Check barrel files.** Confirm each package has its primary barrel (`{feature}_{layer}.dart`), and that features with multiple entry points have subfeature barrels with no missing exports. See section *Subfeature Barrel Files* and *Layer Subfolder Conventions*.
4. **Flag misplaced packages.** Business or app-specific logic sitting in `shared/`, or generic utilities sitting in `features/`. Apply the decision rule and component table in section *Shared Libraries*.
5. **Flag high fan-in domains.** A domain that many features depend on may be doing too much. Note it for review against section *Combining Different Features*.

## Step 3: report

Produce a per-package verdict table followed by a prioritized findings list, suitable for a CODE_ASSESSMENT-style report.

| Package | Folder | Inferred type | Verdict | Notes |
| --- | --- | --- | --- | --- |
| product_domain | features/product | feature domain | pass | |
| cart_presentation | features/cart | feature presentation | fail | depends on product_data (presentation must not depend on a data layer) |

Verdict is `pass`, `warn`, or `fail`. Order the findings list by severity: layer-rule and cycle violations first (these break the architecture), then misplacement and barrel issues, then advisory notes such as high fan-in. For each finding, state the rule and the fix, the same way the mechanical pass does.
