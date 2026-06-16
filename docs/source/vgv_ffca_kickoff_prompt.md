# Kickoff: Implement vgv-ffca-plugin

Paste this into Claude Code from an empty working directory, with `vgv_ffca_plugin_spec.md` and `ffca_architecture.md` placed alongside it. If Wingspan is installed, run `/plan` with this file first, then `/build` the resulting plan.

---

## Goal

Implement the **vgv-ffca-plugin** Claude Code plugin exactly as specified in `vgv_ffca_plugin_spec.md`. The plugin operationalizes Feature-First Clean Architecture (FFCA) for Flutter monorepos through five skills, a blocking pubspec validation hook, and a Very Good CLI MCP configuration.

## Provided Files

- `vgv_ffca_plugin_spec.md`: the full specification. It is the source of truth for structure, skill descriptions, hook behavior, and validation rules. Follow it; don't redesign it.
- `ffca_architecture.md`: the FFCA conventions reference, already generated from the canonical Notion page. Copy it verbatim to `references/ffca_architecture.md`. Do not rewrite or summarize it.

## Steps

### 1. Repo bootstrap

```bash
gh repo create VGVentures/vgv-ffca-plugin --private --clone
cd vgv-ffca-plugin
```

### 2. Study the structural reference

Clone the sibling plugin and mirror its conventions for plugin metadata, hook wiring, and shell wrapper style:

```bash
git clone https://github.com/VeryGoodOpenSource/vgv-ai-flutter-plugin /tmp/reference-plugin
```

Specifically copy the patterns from: `.claude-plugin/plugin.json`, `hooks/hooks.json`, the analyze hook's shell script (jq payload parsing, graceful skip when prerequisites are missing, exit code propagation), and the SKILL.md frontmatter format.

### 3. Scaffold the plugin structure

Create the tree exactly as in the spec's Plugin Structure section: `.claude-plugin/`, `references/` (drop in the provided `ffca_architecture.md`), `references/code_templates/`, `skills/` (five skill folders), `hooks/`, `scripts/`, `.mcp.json`.

### 4. Implement validate_layers.dart (test-first)

This is the highest-risk component; build it before the skills.

- Pure Dart, `dart:io` and `dart:core` only if possible; `package:yaml` is acceptable if a pubspec is added for the script.
- Two modes per the spec: incremental (default, edited package + direct dependents) and `--all` (full graph + workspace topological cycle check).
- Implement the checks table from the spec verbatim. Keep the rules in an isolated `rules` constant at the top of the file, with a comment naming the "Dependency Graph Rules" section of `references/ffca_architecture.md`.
- Violation output format per the spec: the rule AND the fix, exit 2.
- Graceful skips (exit 0): file is not a pubspec.yaml, repo has no `features/` folder, workspace root not found.

**Fixture workspace for tests:** build `test/fixtures/valid_workspace/` and `test/fixtures/invalid_workspace/` containing minimal FFCA monorepos (pubspec.yaml files only, no Dart source needed). The invalid fixture must cover every rule: bad naming under `features/`, domain depending on data, data depending on presentation, presentation depending on `*_data`, shared depending on a feature, a dependency cycle, and a package depending on an app. Write `dart test` cases asserting each violation is caught with the right message and that the valid workspace passes both modes.

### 5. Implement the hook

- `hooks/hooks.json` per the spec.
- `hooks/validate_layers.sh`: jq payload parsing, pubspec.yaml filter, FFCA-shape check, graceful skip when `dart` or `jq` is missing, then `dart run` the script and propagate exit 2.

### 6. Author the five skills

Per the spec's Skills section: `ffca-architecture`, `ffca-feature`, `ffca-routing`, `ffca-cross-feature`, `ffca-audit`. Rules:

- Use the exact trigger descriptions from the spec in each SKILL.md frontmatter.
- Skills contain workflow guidance only. Conventions are NEVER restated; point into `references/ffca_architecture.md` by section name (e.g., "Read references/ffca_architecture.md, section Dependency Graph Rules, before wiring pubspec dependencies").
- Populate `references/code_templates/` (domain, data, presentation templates) by extracting the code examples from `ffca_architecture.md` into ready-to-adapt template files. Only `ffca-feature` and `ffca-routing` point to these.
- `ffca-audit` instructs running `dart run scripts/validate_layers.dart --all` plus the qualitative checks listed in the spec, producing the per-package verdict table.

### 7. MCP config and README

- `.mcp.json` per the spec (Very Good CLI server).
- README: overview, the three-layer stack positioning table, installation (private repo instructions for now), skills table, hook behavior table with prerequisites (Dart SDK, jq), modeled on the vgv-ai-flutter-plugin README.

### 8. End-to-end verification (required, not optional)

1. Install the plugin into a Claude Code session from the local path.
2. In a scratch FFCA fixture workspace, ask Claude to add `product_data` as a dependency of `cart_presentation`'s pubspec. **Verify the hook blocks with the expected violation message and Claude self-corrects.**
3. Make a valid pubspec edit and verify the hook passes silently.
4. Ask an FFCA-shaped question ("where should a CartBadge widget live?") and verify the right skill triggers and answers from the reference.
5. Run `/ffca-audit` (or trigger it by asking for an architecture health check) against the invalid fixture and verify the verdict table flags the planted violations.

### 9. Ship

Conventional commits, push to the private repo, open a PR from a feature branch for review.

## Definition of Done

- [ ] Repo exists at VGVentures/vgv-ffca-plugin (private) with the spec's exact structure
- [ ] `dart test` passes; every validation rule has a failing-fixture test
- [ ] Hook blocks invalid pubspec edits in a live Claude Code session (verified manually, step 8)
- [ ] All five skills trigger correctly and point into the reference rather than restating it
- [ ] `references/ffca_architecture.md` is byte-identical to the provided file
- [ ] README complete
- [ ] No em dashes anywhere in authored prose (VGV style: use colons)

## Out of Scope (do not build)

- Mason bricks or scaffolding commands (v2 brings SDK MCP tools instead)
- `scripts/sync_reference.dart` automation (stub it with a TODO and a comment describing the Notion source page; the provided reference file is current as of today)
- Marketplace registration (happens at v1.0 after transfer to VeryGoodOpenSource)
- Arcana integration
