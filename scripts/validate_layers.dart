// FFCA layer-dependency validator.
//
// Enforces the Feature-First Clean Architecture dependency rules on a Dart
// monorepo's pubspec dependencies between its own packages. Used two ways:
//   - by the plugin hook, incrementally, on every pubspec.yaml edit:
//       dart run validate_layers.dart --file <path/to/pubspec.yaml>
//   - by CI and the ffca-audit skill, across the whole workspace:
//       dart run validate_layers.dart --all
//
// Exit codes: 0 = pass or graceful skip, 2 = FFCA violation, 64 = usage error.
//
// Imports are restricted to dart:io and dart:core so the script runs with just
// the Dart SDK, no `dart pub get` required on the user's machine.

import 'dart:io';

// ---------------------------------------------------------------------------
// Rules
//
// This is the single source of truth for the layer dependency policy. It
// implements the "Dependency rules" section of
// references/ffca/project_structure.md.
// Change cross-feature dependency scope here, not throughout the script.
//
// Each key is a source layer; the value is the set of target layers it may
// depend on. A dependency counts when it resolves to a package in the
// workspace, either through a `path:` or by name, as in a Dart workspace
// (`resolution: workspace`). Anything else is external and ignored. Targets
// not in the allowed set are violations. Consequences worth noting:
//   - `app` is never an allowed target  -> nothing may depend on an app.
//   - `data`/`presentation` never appear for `domain`/`data` -> domain and
//     data layers never depend on a presentation or (cross-feature) data layer.
//   - `shared` may depend only on `shared` -> shared never depends on a feature.
// ---------------------------------------------------------------------------
const Map<String, Set<String>> rules = {
  'app': {'domain', 'data', 'presentation', 'shared'},
  'domain': {'domain', 'shared'},
  'data': {'domain', 'shared'},
  'presentation': {'domain', 'presentation', 'shared'},
  'shared': {'shared'},
};

void main(List<String> args) {
  if (args.contains('--all')) {
    exit(_runAll(args));
  }

  final fileIndex = args.indexOf('--file');
  if (fileIndex != -1 && fileIndex + 1 < args.length) {
    exit(_runIncremental(args[fileIndex + 1]));
  }

  stderr.writeln(
    'Usage: validate_layers.dart --file <pubspec.yaml> | --all [rootDir]',
  );
  exit(64);
}

// ---------------------------------------------------------------------------
// Modes
// ---------------------------------------------------------------------------

/// Incremental mode (the hook default): validate the edited package plus its
/// direct dependents. Graceful-skips (exit 0) when the target is not a
/// pubspec.yaml, does not exist, or is not inside an FFCA-shaped workspace.
int _runIncremental(String rawPath) {
  if (_basename(rawPath) != 'pubspec.yaml') return 0;

  final file = File(rawPath);
  if (!file.existsSync()) return 0;

  final root = _findWorkspaceRoot(file.parent.absolute.path);
  if (root == null) return 0; // not FFCA-shaped

  final workspace = _discover(root);
  final editedDir = _normalize(file.parent.absolute.path);
  final edited = workspace.byDir[editedDir];
  if (edited == null) return 0; // root pubspec or outside features/apps/shared

  final scope = <Package>{edited};
  for (final p in workspace.packages) {
    if (p.deps.contains(edited.dir)) scope.add(p); // direct dependents
  }

  final violations = <_Violation>[];
  for (final p in scope) {
    violations.addAll(_checkPackage(p, workspace));
  }
  violations.addAll(_cycleViolations(workspace, from: edited));

  if (violations.isEmpty) return 0; // silent pass
  _report(violations, root);
  return 2;
}

/// Full-graph mode (CI and ffca-audit): validate every package and run a
/// workspace-wide cycle check.
int _runAll(List<String> args) {
  final positional = args.where((a) => a != '--all').toList();
  final start =
      positional.isNotEmpty ? positional.first : Directory.current.path;

  final root = _findWorkspaceRoot(_normalize(Directory(start).absolute.path));
  if (root == null) {
    stdout.writeln(
      'No FFCA workspace found (no features/ folder); nothing to check.',
    );
    return 0;
  }

  final workspace = _discover(root);
  final violations = <_Violation>[];
  for (final p in workspace.packages) {
    violations.addAll(_checkPackage(p, workspace));
  }
  violations.addAll(_cycleViolations(workspace));

  if (violations.isEmpty) {
    stdout.writeln(
      'No FFCA violations found (${workspace.packages.length} packages checked).',
    );
    return 0;
  }
  _report(violations, root);
  return 2;
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

List<_Violation> _checkPackage(Package p, Workspace ws) {
  final out = <_Violation>[];

  // Naming: a package under features/{f}/ must be a valid FFCA package name.
  if (p.top == 'features' && p.layer == 'unknown') {
    out.add(
      _Violation(
        package: p,
        rule: '${p.name} is under features/${p.feature}/ but is not a valid '
            'FFCA package name (expected ${p.feature}_domain, ${p.feature}_data, '
            '${p.feature}_data_{backend}, or ${p.feature}_presentation)',
        fix: 'Rename it to one of ${p.feature}_domain, ${p.feature}_data, '
            '${p.feature}_data_{backend}, or ${p.feature}_presentation.',
      ),
    );
    return out; // can't classify the source layer; skip its dependency checks
  }

  final allowed = rules[p.layer];
  if (allowed == null) return out; // unknown source layer (e.g. app-less): skip

  for (final depDir in p.deps) {
    final target = ws.byDir[depDir];
    if (target == null) continue; // external or unresolved path
    if (target.layer == 'unknown') continue; // misnamed target, reported itself
    if (allowed.contains(target.layer)) continue; // ok
    out.add(_dependencyViolation(p, target));
  }
  return out;
}

_Violation _dependencyViolation(Package src, Package tgt) {
  final pair = '${src.name} depends on ${tgt.name}';

  // Target is an app: nothing may depend on an app.
  if (tgt.layer == 'app') {
    return _Violation(
      package: src,
      rule: '$pair (nothing may depend on an app)',
      fix: 'Apps are top-level composition roots; remove the dependency on '
          '${tgt.name}.',
    );
  }

  // Source is shared depending on a feature package.
  if (src.layer == 'shared') {
    return _Violation(
      package: src,
      rule: '$pair (shared packages must never depend on a feature)',
      fix: 'Move the shared code into the feature, or invert the dependency; '
          'shared/ depends only on external and other shared/ packages.',
    );
  }

  switch ('${src.layer}->${tgt.layer}') {
    case 'presentation->data':
      return _Violation(
        package: src,
        rule: '$pair (presentation must never depend on a data layer)',
        fix: 'Depend on ${tgt.feature}_domain instead and access data through '
            'its repository interface.',
      );
    case 'domain->data':
      return _Violation(
        package: src,
        rule: '$pair (a domain layer must never depend on a data layer)',
        fix: 'Domain packages define interfaces only; depend on other *_domain '
            'or shared/ packages instead.',
      );
    case 'domain->presentation':
      return _Violation(
        package: src,
        rule:
            '$pair (a domain layer must never depend on a presentation layer)',
        fix: 'Domain packages define interfaces only; depend on other *_domain '
            'or shared/ packages instead.',
      );
    case 'data->presentation':
      return _Violation(
        package: src,
        rule: '$pair (a data layer must never depend on a presentation layer)',
        fix: 'Data packages implement domain interfaces; depend on '
            '${src.feature}_domain or shared/ packages instead.',
      );
    case 'data->data':
      return _Violation(
        package: src,
        rule: "$pair (a data layer must never depend on another feature's data "
            'layer)',
        fix: 'Depend on ${tgt.feature}_domain and access it through its '
            'repository interface.',
      );
    default:
      return _Violation(
        package: src,
        rule: '$pair (a ${src.layer} layer must not depend on a ${tgt.layer} '
            'layer)',
        fix: 'Remove the dependency on ${tgt.name}; review the Dependency '
            'rules in references/ffca/project_structure.md.',
      );
  }
}

/// Detects dependency cycles. In incremental mode pass [from] to only report
/// cycles reachable from the edited package; in full mode omit it to scan the
/// whole graph (a topological walk that surfaces every back edge).
List<_Violation> _cycleViolations(Workspace ws, {Package? from}) {
  final out = <_Violation>[];
  final seenCycles = <String>{};
  final starts = from != null ? [from] : ws.packages;

  // Shared across starts so each node is explored once: a single O(V+E) walk in
  // --all mode. In incremental mode there is one start, so this is unchanged.
  final visited = <String>{};

  for (final start in starts) {
    final stack = <Package>[];
    final onStack = <String>{};

    void dfs(Package node) {
      stack.add(node);
      onStack.add(node.dir);
      visited.add(node.dir);
      for (final depDir in node.deps) {
        final next = ws.byDir[depDir];
        if (next == null) continue;
        if (onStack.contains(next.dir)) {
          // Found a cycle: slice the stack from the repeated node.
          final startIdx = stack.indexWhere((p) => p.dir == next.dir);
          final cycle = stack.sublist(startIdx).map((p) => p.name).toList()
            ..add(next.name);
          final key = (cycle.toSet().toList()..sort()).join('|');
          if (seenCycles.add(key)) {
            out.add(
              _Violation(
                package: cycle.first == next.name ? next : stack[startIdx],
                rule: 'dependency cycle detected: ${cycle.join(' → ')}',
                fix: 'Break the cycle; FFCA requires an acyclic dependency '
                    'graph.',
              ),
            );
          }
        } else if (!visited.contains(next.dir)) {
          dfs(next);
        }
      }
      stack.removeLast();
      onStack.remove(node.dir);
    }

    dfs(start);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Workspace discovery
// ---------------------------------------------------------------------------

/// Walks up from [startDir] to the nearest ancestor that contains a `features/`
/// directory. Returns null when none is found (repo is not FFCA-shaped).
String? _findWorkspaceRoot(String startDir) {
  var dir = Directory(_normalize(startDir));
  while (true) {
    if (Directory('${dir.path}/features').existsSync()) {
      return _normalize(dir.path);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // reached filesystem root
    dir = parent;
  }
}

Workspace _discover(String root) {
  final packages = <Package>[];
  final depsByPackage = <Package, List<_Dependency>>{};
  for (final top in ['features', 'apps', 'shared']) {
    final topDir = Directory('$root/$top');
    if (!topDir.existsSync()) continue;
    for (final entity in topDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (_basename(entity.path) != 'pubspec.yaml') continue;
      final pkgDir = _normalize(entity.parent.absolute.path);
      final parsed = _parsePubspec(entity);
      final package = _buildPackage(pkgDir, entity, parsed.name, top, root);
      packages.add(package);
      depsByPackage[package] = parsed.deps;
    }
  }

  // Resolve dependencies once every package is known. A `path:` wins; a
  // dependency without one resolves by name, the way a Dart workspace does.
  final byName = {for (final p in packages) p.name: p};
  for (final p in packages) {
    for (final dep in depsByPackage[p]!) {
      final path = dep.path;
      if (path != null) {
        p.deps.add(_normalize(_join(p.dir, path)));
      } else if (byName[dep.name] case final target?) {
        p.deps.add(target.dir);
      }
    }
  }

  final byDir = {for (final p in packages) p.dir: p};
  return Workspace(packages: packages, byDir: byDir);
}

Package _buildPackage(
  String pkgDir,
  File pubspec,
  String? parsedName,
  String top,
  String root,
) {
  final name = parsedName ?? _basename(pkgDir);

  String feature = '';
  String layer;
  switch (top) {
    case 'apps':
      layer = 'app';
    case 'shared':
      layer = 'shared';
    default: // features
      // features/{feature}/{package}/pubspec.yaml
      final rel = pkgDir.substring(root.length).split('/')
        ..removeWhere((s) => s.isEmpty);
      feature = rel.length >= 2 ? rel[1] : '';
      layer = _classifyFeatureLayer(name, feature);
  }

  return Package(
    dir: pkgDir,
    relPath: pubspec.absolute.path.substring(root.length + 1),
    name: name,
    top: top,
    feature: feature,
    layer: layer,
    deps: [],
  );
}

String _classifyFeatureLayer(String name, String feature) {
  if (name == '${feature}_domain') return 'domain';
  if (name == '${feature}_data') return 'data';
  if (name.startsWith('${feature}_data_')) return 'data';
  if (name == '${feature}_presentation') return 'presentation';
  return 'unknown';
}

// ---------------------------------------------------------------------------
// Minimal pubspec reader (name + dependency names and paths only)
// ---------------------------------------------------------------------------

_ParsedPubspec _parsePubspec(File file) {
  String? name;
  final deps = <_Dependency>[];
  final lines = file.readAsLinesSync();

  String? currentTop;
  for (var i = 0; i < lines.length; i++) {
    final line = _stripComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    final content = line.trim();

    if (indent == 0) {
      final key = content.split(':').first.trim();
      currentTop = key;
      if (key == 'name') {
        final value = content.substring(content.indexOf(':') + 1).trim();
        if (value.isNotEmpty) name = _unquote(value);
      }
      continue;
    }

    final inDeps = currentTop == 'dependencies' ||
        currentTop == 'dev_dependencies' ||
        currentTop == 'dependency_overrides';
    if (inDeps && indent == 2 && content.contains(':')) {
      // A dependency entry: `foo: ^1.0.0`, a bare `foo:`, or `foo:` with a
      // nested block. Scan the nested block for a `path:` value.
      final depName = _unquote(content.split(':').first.trim());
      String? path;
      if (content.endsWith(':')) {
        for (var j = i + 1; j < lines.length; j++) {
          final l2 = _stripComment(lines[j]);
          if (l2.trim().isEmpty) continue;
          final ind2 = l2.length - l2.trimLeft().length;
          if (ind2 <= 2) break;
          final c2 = l2.trim();
          if (c2.startsWith('path:')) {
            path = _unquote(c2.substring('path:'.length).trim());
          }
        }
      }
      // An override without a path only pins a version; it adds no edge.
      if (path != null || currentTop != 'dependency_overrides') {
        deps.add(_Dependency(name: depName, path: path));
      }
    }
  }
  return _ParsedPubspec(name: name, deps: deps);
}

String _stripComment(String line) {
  final hash = line.indexOf('#');
  if (hash == -1) return line;
  // Keep '#' that is part of a value (preceded by a non-space); only strip
  // full-line comments and trailing " #..." comments.
  if (hash == 0) return '';
  if (line[hash - 1] == ' ' || line[hash - 1] == '\t') {
    return line.substring(0, hash);
  }
  return line;
}

String _unquote(String s) {
  if (s.length >= 2 &&
      ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'")))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

void _report(List<_Violation> violations, String root) {
  // Group by the pubspec file the violation belongs to.
  final byPackage = <String, List<_Violation>>{};
  for (final v in violations) {
    byPackage.putIfAbsent(v.package.relPath, () => []).add(v);
  }
  final paths = byPackage.keys.toList()..sort();
  for (final path in paths) {
    stderr.writeln('FFCA violation in $path:');
    for (final v in byPackage[path]!) {
      stderr.writeln('  ✗ ${v.rule}');
      stderr.writeln('  → ${v.fix}');
    }
  }
}

// ---------------------------------------------------------------------------
// Path helpers (avoid package:path so the script stays dependency-free)
// ---------------------------------------------------------------------------

String _basename(String path) {
  final parts = path.split('/');
  return parts.isEmpty ? path : parts.last;
}

String _join(String base, String relative) => '$base/$relative';

/// Resolves `.`/`..` segments and trailing slashes to a canonical path.
String _normalize(String path) {
  final isAbsolute = path.startsWith('/');
  final segments = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (!isAbsolute) {
        segments.add('..');
      }
    } else {
      segments.add(part);
    }
  }
  return (isAbsolute ? '/' : '') + segments.join('/');
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Workspace {
  Workspace({required this.packages, required this.byDir});
  final List<Package> packages;
  final Map<String, Package> byDir;
}

class Package {
  Package({
    required this.dir,
    required this.relPath,
    required this.name,
    required this.top,
    required this.feature,
    required this.layer,
    required this.deps,
  });

  final String dir; // normalized absolute package directory
  final String relPath; // pubspec path relative to workspace root
  final String name; // package name from pubspec
  final String top; // features | apps | shared
  final String feature; // feature folder name (features/ only)
  final String layer; // domain | data | presentation | shared | app | unknown
  final List<String> deps; // normalized absolute dirs of workspace dependencies
}

class _ParsedPubspec {
  _ParsedPubspec({required this.name, required this.deps});
  final String? name;
  final List<_Dependency> deps;
}

class _Dependency {
  _Dependency({required this.name, this.path});
  final String name;
  final String? path; // relative `path:` value, null when resolved by name
}

class _Violation {
  _Violation({required this.package, required this.rule, required this.fix});
  final Package package;
  final String rule;
  final String fix;
}
