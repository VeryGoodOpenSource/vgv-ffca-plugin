// FFCA layer-dependency validator.
//
// Enforces the Feature-First Clean Architecture dependency rules on a Dart
// monorepo's pubspec dependencies between its own packages. Used two ways:
//   - by the plugin hook, incrementally, on every pubspec.yaml or Dart edit:
//       dart run validate_layers.dart --file <path/to/pubspec.yaml>
//       dart run validate_layers.dart --file <path/to/lib/file.dart>
//   - by CI and the ffca-audit skill, across the whole workspace:
//       dart run validate_layers.dart --all
//
// Exit codes: 0 = pass, warnings only, or graceful skip; 2 = at least one
// error-severity FFCA finding; 64 = usage error. Findings go to stderr, each
// with a rule ID that a `# ffca-ignore:` comment can suppress (see below).
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
//
// On top of this table, _checkOwnership enforces how a feature's own packages
// fit together: a data layer depends on its own domain at runtime, a data
// layer never exists without a domain, and a domain never uses the Flutter SDK.
// ---------------------------------------------------------------------------
const Map<String, Set<String>> rules = {
  'app': {'domain', 'data', 'presentation', 'shared'},
  'domain': {'domain', 'shared'},
  'data': {'domain', 'shared'},
  'presentation': {'domain', 'presentation', 'shared'},
  'shared': {'shared'},
};

// ---------------------------------------------------------------------------
// Rule IDs and severities
//
// Every finding carries one of these stable IDs, which is also what a
// suppression names. An error exits 2 and blocks the hook; a warning is printed
// but leaves the exit code at 0.
//
// A finding is suppressed with a comment in the pubspec of the package it is
// reported on, or, for a finding in a Dart file, in that file. The reason is
// required:
//   # ffca-ignore: <rule-id> — <reason>     (pubspec.yaml)
//   // ffca-ignore: <rule-id> — <reason>    (Dart file)
// The suppression-* rules and unused-suppression cannot be suppressed.
// ---------------------------------------------------------------------------
enum Severity { error, warning }

const Map<String, Severity> ruleSeverities = {
  'package-name': Severity.error,
  'depends-on-app': Severity.error,
  'shared-depends-on-feature': Severity.error,
  'presentation-depends-on-data': Severity.error,
  'domain-depends-on-data': Severity.error,
  'domain-depends-on-presentation': Severity.error,
  'data-depends-on-presentation': Severity.error,
  'data-depends-on-feature-data': Severity.error,
  'layer-dependency': Severity.error,
  'dependency-cycle': Severity.error,
  'data-missing-own-domain': Severity.error,
  'data-without-domain': Severity.error,
  'domain-uses-flutter': Severity.error,
  'presentation-missing-own-domain': Severity.warning,
  'missing-primary-barrel': Severity.error,
  'deep-import': Severity.error,
  'cross-feature-primary-barrel': Severity.error,
  'data-barrel-exports-internals': Severity.error,
  'unused-dependency': Severity.warning,
  'suppression-missing-reason': Severity.error,
  'suppression-unknown-rule': Severity.error,
  'unused-suppression': Severity.warning,
};

const _unsuppressible = {
  'suppression-missing-reason',
  'suppression-unknown-rule',
  'unused-suppression',
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
    'Usage: validate_layers.dart --file <pubspec.yaml | file.dart> | '
    '--all [rootDir]',
  );
  exit(64);
}

// ---------------------------------------------------------------------------
// Modes
// ---------------------------------------------------------------------------

/// Incremental mode (the hook default): validate the edited package plus its
/// direct dependents, or, for a Dart file, only that file's imports and
/// exports. Graceful-skips (exit 0) when the target is neither a pubspec.yaml
/// nor a Dart file, does not exist, or is not inside an FFCA-shaped workspace.
int _runIncremental(String rawPath) {
  if (rawPath.endsWith('.dart')) return _runDartFile(rawPath);
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

  final result = _applySuppressions(
    violations,
    _declaredSuppressions(scope),
    reportUnused: false,
  );
  if (result.findings.isEmpty) return 0; // silent pass
  _report(result, root);
  return _exitCode(result.findings);
}

/// Dart-file mode: report only the findings located in the edited file, so a
/// Dart edit never blocks on a violation elsewhere in the package. Package-wide
/// findings, such as a missing barrel or an unused dependency, are reported on
/// pubspec edits and in full mode.
int _runDartFile(String rawPath) {
  final file = File(rawPath);
  if (!file.existsSync()) return 0;

  final root = _findWorkspaceRoot(file.parent.absolute.path);
  if (root == null) return 0; // not FFCA-shaped

  final workspace = _discover(root);
  final path = _normalize(file.absolute.path);
  final dartFile = workspace.packages
      .expand((p) => p.dartFiles)
      .where((f) => f.path == path)
      .firstOrNull;
  if (dartFile == null) return 0; // outside lib/ and bin/ of a known package

  final package = workspace.packages.firstWhere(
    (p) => p.dartFiles.contains(dartFile),
  );
  final violations = _checkImports(
    package,
    workspace,
  ).where((v) => v.file == dartFile).toList();

  final result = _applySuppressions(
      violations,
      [
        for (final s in dartFile.suppressions) (package, s),
      ],
      reportUnused: false);
  if (result.findings.isEmpty) return 0;
  _report(result, root);
  return _exitCode(result.findings);
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

  final result = _applySuppressions(
    violations,
    _declaredSuppressions(workspace.packages),
    reportUnused: true,
  );
  if (result.findings.isEmpty) {
    final suppressed =
        result.suppressed > 0 ? ', ${result.suppressed} suppressed' : '';
    stdout.writeln(
      'No FFCA violations found '
      '(${workspace.packages.length} packages checked$suppressed).',
    );
    return 0;
  }
  _report(result, root);
  return _exitCode(result.findings);
}

int _exitCode(List<_Violation> findings) =>
    findings.any((v) => v.severity == Severity.error) ? 2 : 0;

// ---------------------------------------------------------------------------
// Suppressions
// ---------------------------------------------------------------------------

/// Every suppression declared in [packages], in their pubspecs and Dart files.
List<(Package, _Suppression)> _declaredSuppressions(
  Iterable<Package> packages,
) =>
    [
      for (final p in packages) ...[
        for (final s in p.suppressions) (p, s),
        for (final f in p.dartFiles)
          for (final s in f.suppressions) (p, s),
      ],
    ];

/// Drops the findings suppressed in their package's pubspec, or in the Dart
/// file they are located in, and adds findings for the invalid suppressions in
/// [declared]. Unused suppressions are only reported with [reportUnused], in
/// full mode, where every finding has been computed.
({List<_Violation> findings, int suppressed}) _applySuppressions(
  List<_Violation> violations,
  List<(Package, _Suppression)> declared, {
  required bool reportUnused,
}) {
  bool valid(_Suppression s) =>
      s.reason.isNotEmpty &&
      ruleSeverities.containsKey(s.ruleId) &&
      !_unsuppressible.contains(s.ruleId);

  final used = <_Suppression>{};
  final findings = <_Violation>[];
  var suppressed = 0;
  for (final v in violations) {
    final match = [...?v.file?.suppressions, ...v.package.suppressions]
        .where((s) => valid(s) && s.ruleId == v.id)
        .firstOrNull;
    if (match == null) {
      findings.add(v);
    } else {
      used.add(match);
      suppressed++;
    }
  }

  for (final (p, s) in declared) {
    final where = s.where;
    if (!ruleSeverities.containsKey(s.ruleId) ||
        _unsuppressible.contains(s.ruleId)) {
      findings.add(
        _Violation(
          id: 'suppression-unknown-rule',
          package: p,
          rule: 'ffca-ignore on $where names "${s.ruleId}", which is not a '
              'rule that can be suppressed',
          fix: 'Use one of the rule IDs shown in brackets in the validator '
              'output, or remove the comment.',
        ),
      );
    } else if (s.reason.isEmpty) {
      findings.add(
        _Violation(
          id: 'suppression-missing-reason',
          package: p,
          rule: 'ffca-ignore: ${s.ruleId} on $where has no reason, so it '
              'suppresses nothing',
          fix: 'Add the reason after the rule ID: '
              '${s.marker} ffca-ignore: ${s.ruleId} — <why this exception is '
              'needed>',
        ),
      );
    } else if (reportUnused && !used.contains(s)) {
      findings.add(
        _Violation(
          id: 'unused-suppression',
          package: p,
          rule: 'ffca-ignore: ${s.ruleId} on $where matches no finding',
          fix: 'Remove the comment; the exception is no longer needed.',
        ),
      );
    }
  }
  return (findings: findings, suppressed: suppressed);
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
        id: 'package-name',
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

  out.addAll(_checkOwnership(p, ws));
  out.addAll(_checkImports(p, ws));

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

/// Checks how a feature's own packages fit together, beyond the rules table.
/// Implements the "Dependency rules" section of
/// references/ffca/project_structure.md, the feature archetypes in
/// references/ffca/overview.md, and the pure Dart domain in
/// references/ffca/domain.md.
List<_Violation> _checkOwnership(Package p, Workspace ws) {
  final out = <_Violation>[];
  final domainName = '${p.feature}_domain';

  if (p.layer == 'data') {
    final domain = ws.packages
        .where((d) => d.feature == p.feature && d.name == domainName)
        .firstOrNull;
    if (domain == null) {
      out.add(
        _Violation(
          id: 'data-without-domain',
          package: p,
          rule: '${p.name} is a data layer but features/${p.feature}/ has no '
              '$domainName (a data layer implements its own feature\'s domain)',
          fix: 'Add $domainName with the repository interfaces ${p.name} '
              'implements, or move ${p.name} into the feature whose domain it '
              'implements.',
        ),
      );
    } else if (!p.runtimeDeps.contains(domain.dir)) {
      final devOnly = p.deps.contains(domain.dir);
      out.add(
        _Violation(
          id: 'data-missing-own-domain',
          package: p,
          rule: devOnly
              ? '${p.name} declares $domainName only outside dependencies '
                  '(a data layer implements its own feature\'s domain)'
              : '${p.name} does not depend on $domainName (a data layer '
                  'implements its own feature\'s domain)',
          fix: 'Add $domainName under dependencies in the ${p.name} pubspec.',
        ),
      );
    }
  }

  // A presentation-only feature has no domain, so this only applies when the
  // feature has one.
  if (p.layer == 'presentation') {
    final domain = ws.packages
        .where((d) => d.feature == p.feature && d.name == domainName)
        .firstOrNull;
    if (domain != null && !p.runtimeDeps.contains(domain.dir)) {
      out.add(
        _Violation(
          id: 'presentation-missing-own-domain',
          package: p,
          rule: '${p.name} does not depend on $domainName (a presentation '
              "layer renders its own feature's domain)",
          fix: 'Add $domainName under dependencies in the ${p.name} pubspec, '
              'or suppress this with the reason the screen does not use it.',
        ),
      );
    }
  }

  if (p.layer == 'domain' && p.flutterSdkDeps.isNotEmpty) {
    out.add(
      _Violation(
        id: 'domain-uses-flutter',
        package: p,
        rule: '${p.name} depends on the Flutter SDK through '
            '${p.flutterSdkDeps.join(', ')} (the domain layer is pure Dart)',
        fix: 'Remove the Flutter SDK dependencies and move Flutter code to '
            '${p.feature}_presentation; the domain holds models, repository '
            'interfaces, Commands, and Queries.',
      ),
    );
  }
  return out;
}

/// Checks the package's barrels and its imports and exports of other
/// workspace packages. Implements "Layer subfolders" and the barrel rule in
/// references/ffca/project_structure.md, the dedicated-barrel condition in its
/// "Dependency rules", and "Widgets that own state" in
/// references/ffca/presentation.md.
List<_Violation> _checkImports(Package p, Workspace ws) {
  final out = <_Violation>[];
  final barrel = 'lib/${p.name}.dart';

  if (p.top == 'features' && !p.dartFiles.any((f) => f.libRel == barrel)) {
    out.add(
      _Violation(
        id: 'missing-primary-barrel',
        package: p,
        rule: '${p.name} has no primary barrel $barrel',
        fix: 'Add $barrel exporting the public API of ${p.name}.',
      ),
    );
  }

  final used = <String>{};
  for (final f in p.dartFiles) {
    for (final d in f.directives) {
      final match = _packageUri.firstMatch(d.uri);
      final name = match?.group(1);
      final rest = match?.group(2) ?? d.uri;

      // A data barrel exporting its own DTOs or mappers. Data sources are
      // exported: the app constructs them to inject into the repository.
      if ((match == null || name == p.name) &&
          p.layer == 'data' &&
          f.libRel == barrel &&
          d.kind == 'export' &&
          _dataInternals.hasMatch(rest)) {
        out.add(
          _Violation(
            id: 'data-barrel-exports-internals',
            package: p,
            file: f,
            rule: 'line ${d.line} exports ${d.uri} (a data barrel never '
                'exposes its DTOs or mappers)',
            fix: 'Remove the export; DTOs and mappers are implementation '
                'details of the repository, which returns domain models.',
          ),
        );
      }
      if (match == null || name == p.name) continue; // within the package

      final target = ws.byName[name];
      if (target == null) continue; // external package
      used.add(target.name);

      if (rest.contains('/')) {
        out.add(
          _Violation(
            id: 'deep-import',
            package: p,
            file: f,
            rule: 'line ${d.line} ${d.kind}s ${d.uri}, which reaches past the '
                'barrels of ${target.name}',
            fix: 'Import a barrel at the root of ${target.name}/lib/ instead, '
                'and export what is missing from it.',
          ),
        );
      } else if (p.top == 'features' &&
          target.layer == 'presentation' &&
          target.feature != p.feature &&
          rest == '${target.name}.dart') {
        out.add(
          _Violation(
            id: 'cross-feature-primary-barrel',
            package: p,
            file: f,
            rule: 'line ${d.line} ${d.kind}s the primary barrel of '
                '${target.name} (another feature\'s presentation is imported '
                'through a dedicated barrel)',
            fix:
                'Add a subfeature barrel to ${target.name}/lib/ exporting only '
                'the widget ${p.name} needs, and import that instead.',
          ),
        );
      }
    }
  }

  for (final depDir in p.runtimeDeps) {
    final target = ws.byDir[depDir];
    if (target == null || used.contains(target.name)) continue;
    out.add(
      _Violation(
        id: 'unused-dependency',
        package: p,
        rule: '${p.name} declares ${target.name} but never imports it in lib/ '
            'or bin/',
        fix: 'Remove ${target.name} from the ${p.name} pubspec, or import it '
            'where it is needed.',
      ),
    );
  }
  return out;
}

final _packageUri = RegExp(r'^package:([^/]+)/(.+)$');
final _dataInternals = RegExp(r'(^|/)(dtos|mappers)/');

_Violation _dependencyViolation(Package src, Package tgt) {
  final pair = '${src.name} depends on ${tgt.name}';

  // Target is an app: nothing may depend on an app.
  if (tgt.layer == 'app') {
    return _Violation(
      id: 'depends-on-app',
      package: src,
      rule: '$pair (nothing may depend on an app)',
      fix: 'Apps are top-level composition roots; remove the dependency on '
          '${tgt.name}.',
    );
  }

  // Source is shared depending on a feature package.
  if (src.layer == 'shared') {
    return _Violation(
      id: 'shared-depends-on-feature',
      package: src,
      rule: '$pair (shared packages must never depend on a feature)',
      fix: 'Move the shared code into the feature, or invert the dependency; '
          'shared/ depends only on external and other shared/ packages.',
    );
  }

  switch ('${src.layer}->${tgt.layer}') {
    case 'presentation->data':
      return _Violation(
        id: 'presentation-depends-on-data',
        package: src,
        rule: '$pair (presentation must never depend on a data layer)',
        fix: 'Depend on ${tgt.feature}_domain instead and access data through '
            'its repository interface.',
      );
    case 'domain->data':
      return _Violation(
        id: 'domain-depends-on-data',
        package: src,
        rule: '$pair (a domain layer must never depend on a data layer)',
        fix: 'Domain packages define interfaces only; depend on other *_domain '
            'or shared/ packages instead.',
      );
    case 'domain->presentation':
      return _Violation(
        id: 'domain-depends-on-presentation',
        package: src,
        rule:
            '$pair (a domain layer must never depend on a presentation layer)',
        fix: 'Domain packages define interfaces only; depend on other *_domain '
            'or shared/ packages instead.',
      );
    case 'data->presentation':
      return _Violation(
        id: 'data-depends-on-presentation',
        package: src,
        rule: '$pair (a data layer must never depend on a presentation layer)',
        fix: 'Data packages implement domain interfaces; depend on '
            '${src.feature}_domain or shared/ packages instead.',
      );
    case 'data->data':
      return _Violation(
        id: 'data-depends-on-feature-data',
        package: src,
        rule: "$pair (a data layer must never depend on another feature's data "
            'layer)',
        fix: 'Depend on ${tgt.feature}_domain and access it through its '
            'repository interface.',
      );
    default:
      return _Violation(
        id: 'layer-dependency',
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
          // Found a cycle: slice the stack from the repeated node, then
          // rotate it to start at its alphabetically first package. The cycle
          // is reported on that package whichever package the walk started
          // from, so a suppression for it works the same in every mode.
          final startIdx = stack.indexWhere((p) => p.dir == next.dir);
          final members = stack.sublist(startIdx);
          final owner = members.reduce(
            (a, b) => a.name.compareTo(b.name) <= 0 ? a : b,
          );
          final at = members.indexOf(owner);
          final cycle = [
            ...members.sublist(at),
            ...members.sublist(0, at),
            owner,
          ].map((p) => p.name).toList();
          final key = (cycle.toSet().toList()..sort()).join('|');
          if (seenCycles.add(key)) {
            out.add(
              _Violation(
                id: 'dependency-cycle',
                package: owner,
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
    // Sorted so that discovery, and with it every report, does not depend on
    // the order the file system lists entries in.
    final entities = topDir.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      if (entity is! File) continue;
      if (_basename(entity.path) != 'pubspec.yaml') continue;
      final pkgDir = _normalize(entity.parent.absolute.path);
      final parsed = _parsePubspec(entity);
      final package = _buildPackage(pkgDir, entity, parsed.name, top, root);
      package.suppressions.addAll(parsed.suppressions);
      package.dartFiles.addAll(_readDartFiles(pkgDir, root));
      package.flutterSdkDeps.addAll([
        for (final dep in parsed.deps)
          if (dep.runtime && dep.sdk == 'flutter') dep.name,
      ]);
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
      final String dir;
      if (path != null) {
        dir = _normalize(_join(p.dir, path));
      } else if (byName[dep.name] case final target?) {
        dir = target.dir;
      } else {
        continue;
      }
      p.deps.add(dir);
      if (dep.runtime) p.runtimeDeps.add(dir);
    }
  }

  final byDir = {for (final p in packages) p.dir: p};
  return Workspace(packages: packages, byDir: byDir, byName: byName);
}

/// Reads the imports, exports, and suppressions of every Dart file under the
/// package's lib/ and bin/.
List<_DartFile> _readDartFiles(String pkgDir, String root) {
  final files = <_DartFile>[];
  for (final sub in ['lib', 'bin']) {
    final dir = Directory('$pkgDir/$sub');
    if (!dir.existsSync()) continue;
    final entities = dir.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = _normalize(entity.absolute.path);
      final relPath = path.substring(root.length + 1);
      final lines = entity.readAsLinesSync();
      files.add(
        _DartFile(
          path: path,
          relPath: relPath,
          libRel: path.substring(pkgDir.length + 1),
          directives: [
            for (var i = 0; i < lines.length; i++)
              if (_directivePattern.firstMatch(lines[i]) case final m?)
                _Directive(kind: m.group(1)!, uri: m.group(2)!, line: i + 1),
          ],
          suppressions: _parseSuppressions(lines, where: relPath),
        ),
      );
    }
  }
  return files;
}

/// An `import` or `export` directive's URI. Directives always start a line in
/// formatted Dart, and the URI is the first string after the keyword.
final _directivePattern = RegExp(r'''^\s*(import|export)\s+['"]([^'"]+)['"]''');

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
    runtimeDeps: [],
    flutterSdkDeps: [],
    suppressions: [],
    dartFiles: [],
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

  // Suppressions are comments, so read them before comments are stripped.
  final suppressions = _parseSuppressions(
    lines,
    where: 'the ${_basename(_normalize(file.parent.absolute.path))} pubspec',
  );

  String? currentTop;
  // The indentation of the entries in the current top-level section, taken
  // from its first indented line, so 2- and 4-space pubspecs both read.
  int? entryIndent;
  for (var i = 0; i < lines.length; i++) {
    final line = _stripComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    final content = line.trim();

    if (indent == 0) {
      final key = content.split(':').first.trim();
      currentTop = key;
      entryIndent = null;
      if (key == 'name') {
        final value = content.substring(content.indexOf(':') + 1).trim();
        if (value.isNotEmpty) name = _unquote(value);
      }
      continue;
    }

    entryIndent ??= indent;
    final inDeps = currentTop == 'dependencies' ||
        currentTop == 'dev_dependencies' ||
        currentTop == 'dependency_overrides';
    if (inDeps && indent == entryIndent && content.contains(':')) {
      // A dependency entry: `foo: ^1.0.0`, a bare `foo:`, or `foo:` with a
      // nested block. Scan the nested block for `path:` and `sdk:` values.
      final depName = _unquote(content.split(':').first.trim());
      String? path;
      String? sdk;
      if (content.endsWith(':')) {
        for (var j = i + 1; j < lines.length; j++) {
          final l2 = _stripComment(lines[j]);
          if (l2.trim().isEmpty) continue;
          final ind2 = l2.length - l2.trimLeft().length;
          if (ind2 <= indent) break;
          final c2 = l2.trim();
          if (c2.startsWith('path:')) {
            path = _unquote(c2.substring('path:'.length).trim());
          } else if (c2.startsWith('sdk:')) {
            sdk = _unquote(c2.substring('sdk:'.length).trim());
          }
        }
      }
      // An override without a path only pins a version; it adds no edge.
      if (path != null || currentTop != 'dependency_overrides') {
        deps.add(
          _Dependency(
            name: depName,
            path: path,
            sdk: sdk,
            runtime: currentTop == 'dependencies',
          ),
        );
      }
    }
  }
  return _ParsedPubspec(name: name, deps: deps, suppressions: suppressions);
}

/// Reads `ffca-ignore` comments from a pubspec or a Dart file. [where] names
/// the file in messages, for example `the cart_data pubspec`.
List<_Suppression> _parseSuppressions(
  List<String> lines, {
  required String where,
}) =>
    [
      for (var i = 0; i < lines.length; i++)
        if (_suppressionPattern.firstMatch(lines[i]) case final m?)
          _Suppression(
            ruleId: m.group(2)!,
            reason: m.group(3)!.replaceFirst(_reasonSeparator, '').trim(),
            marker: m.group(1)!,
            where: 'line ${i + 1} of $where',
          ),
    ];

/// `# ffca-ignore: <rule-id> <separator> <reason>` in a pubspec, or the same
/// after `//` in a Dart file, where the separator is an em dash, an en dash, a
/// hyphen, or a colon.
final _suppressionPattern = RegExp(
  r'(#|//)\s*ffca-ignore:\s*([A-Za-z0-9_-]+)(.*)$',
);
final _reasonSeparator = RegExp(r'^\s*[—–:-]+');

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

void _report(
  ({List<_Violation> findings, int suppressed}) result,
  String root,
) {
  // Group by the file the finding is located in: a Dart file, or else the
  // pubspec of the package it belongs to.
  final byPackage = <String, List<_Violation>>{};
  for (final v in result.findings) {
    byPackage
        .putIfAbsent(v.file?.relPath ?? v.package.relPath, () => [])
        .add(v);
  }
  final paths = byPackage.keys.toList()..sort();
  for (final path in paths) {
    stderr.writeln('FFCA findings in $path:');
    for (final v in byPackage[path]!) {
      final mark = v.severity == Severity.error ? '✗' : '⚠';
      stderr.writeln('  $mark [${v.id}] ${v.rule}');
      stderr.writeln('  → ${v.fix}');
    }
  }

  final errors =
      result.findings.where((v) => v.severity == Severity.error).length;
  final warnings = result.findings.length - errors;
  final suppressed =
      result.suppressed > 0 ? ', ${result.suppressed} suppressed' : '';
  stderr.writeln(
    'FFCA: ${_plural(errors, 'error')}, ${_plural(warnings, 'warning')}'
    '$suppressed.',
  );
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

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
  Workspace({
    required this.packages,
    required this.byDir,
    required this.byName,
  });
  final List<Package> packages;
  final Map<String, Package> byDir;
  final Map<String, Package> byName;
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
    required this.runtimeDeps,
    required this.flutterSdkDeps,
    required this.suppressions,
    required this.dartFiles,
  });

  final String dir; // normalized absolute package directory
  final String relPath; // pubspec path relative to workspace root
  final String name; // package name from pubspec
  final String top; // features | apps | shared
  final String feature; // feature folder name (features/ only)
  final String layer; // domain | data | presentation | shared | app | unknown
  final List<String> deps; // normalized absolute dirs of workspace dependencies
  final List<String> runtimeDeps; // the subset declared under `dependencies`
  final List<String> flutterSdkDeps; // runtime deps with `sdk: flutter`
  final List<_Suppression> suppressions; // `# ffca-ignore:` comments
  final List<_DartFile> dartFiles; // Dart files under lib/ and bin/
}

class _DartFile {
  _DartFile({
    required this.path,
    required this.relPath,
    required this.libRel,
    required this.directives,
    required this.suppressions,
  });
  final String path; // normalized absolute path
  final String relPath; // path relative to the workspace root
  final String libRel; // path relative to the package, for example lib/a.dart
  final List<_Directive> directives;
  final List<_Suppression> suppressions; // `// ffca-ignore:` comments
}

class _Directive {
  _Directive({required this.kind, required this.uri, required this.line});
  final String kind; // import | export
  final String uri;
  final int line; // 1-based
}

class _ParsedPubspec {
  _ParsedPubspec({
    required this.name,
    required this.deps,
    required this.suppressions,
  });
  final String? name;
  final List<_Dependency> deps;
  final List<_Suppression> suppressions;
}

class _Dependency {
  _Dependency({
    required this.name,
    required this.runtime,
    this.path,
    this.sdk,
  });
  final String name;
  final bool runtime; // declared under `dependencies`, not dev or overrides
  final String? path; // relative `path:` value, null when resolved by name
  final String? sdk; // `sdk:` value, for example `flutter`
}

class _Violation {
  _Violation({
    required this.id,
    required this.package,
    required this.rule,
    required this.fix,
    this.file,
  });
  final String id; // a key of ruleSeverities
  final Package package;
  final _DartFile? file; // the Dart file the finding is located in, if any
  final String rule;
  final String fix;

  Severity get severity => ruleSeverities[id]!;
}

class _Suppression {
  _Suppression({
    required this.ruleId,
    required this.reason,
    required this.marker,
    required this.where,
  });
  final String ruleId;
  final String reason; // empty when none was given
  final String marker; // `#` in a pubspec, `//` in a Dart file
  final String where; // for example `line 2 of the cart_data pubspec`
}
