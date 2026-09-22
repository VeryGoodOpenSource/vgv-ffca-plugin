---
name: ffca-audit
description: "Audit an FFCA monorepo for architecture compliance: the mechanical layer/naming/cycle checks plus a qualitative review, producing a per-package verdict table."
when_to_use: Use when auditing an FFCA monorepo for architecture compliance, reviewing the full dependency graph, assessing FFCA adoption in an existing project, or when the user asks for an architecture health check.
allowed-tools: Task Read Glob Grep Bash
effort: high
---

# FFCA Audit

Whole-repo architecture health check. The hook keeps individual pubspec edits compliant; this skill answers whether the repo as a whole is healthy.

The audit itself is performed by the **`ffca-layer-auditor` agent**, so the work runs in its own context and can be reused by build, review, and pre-PR flows. This skill is the entry point that dispatches it.

## What to do

1. Confirm the repo is FFCA-shaped (a `features/` folder with `{feature}_{layer}` packages). If not, say so and stop.
2. Launch the `ffca-layer-auditor` agent (subagent type `ffca-layer-auditor`) against the repo. The agent runs `dart run scripts/validate_layers.dart --all` for the mechanical pass (naming, layer rules, cycles), then adds the source-level checks (declared-but-unused dependencies, barrel hygiene, DTO leakage, use-case necessity, module entry, misplaced packages, high fan-in) and reads `references/ffca_architecture.md` for the detail behind each.
3. Relay the agent's output: the per-package verdict table and the severity-ordered findings list. Each finding states the rule and the fix. The agent is read-only and does not auto-fix.

If the agent is unavailable for any reason, fall back to running `dart run ${CLAUDE_PLUGIN_ROOT}/scripts/validate_layers.dart --all` yourself and reporting its violations, then note that the qualitative source-level checks were skipped.
