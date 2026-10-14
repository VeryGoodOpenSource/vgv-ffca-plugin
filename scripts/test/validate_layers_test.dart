// Tests for validate_layers.dart.
//
// Each test runs the script as a subprocess against a fixture workspace and
// asserts on its exit code and stderr, exactly as the hook and CI invoke it.
// Run from the `scripts/` package root: `dart test`.

import 'dart:io';

import 'package:test/test.dart';

const _script = 'validate_layers.dart';
const _valid = 'test/fixtures/valid_workspace';
const _invalid = 'test/fixtures/invalid_workspace';
const _notFfca = 'test/fixtures/not_ffca';
const _warning = 'test/fixtures/warning_workspace';

/// Runs the validator and returns (exitCode, stdout, stderr).
({int code, String out, String err}) _run(List<String> args, {String? cwd}) {
  final result = Process.runSync(
      'dart',
      [
        'run',
        _absScript(cwd),
        ...args,
      ],
      workingDirectory: cwd);
  return (
    code: result.exitCode,
    out: result.stdout as String,
    err: result.stderr as String,
  );
}

// When a working directory is set, point at the script by absolute path so the
// subprocess can find it regardless of cwd.
String _absScript(String? cwd) =>
    cwd == null ? _script : '${Directory.current.path}/$_script';

String _pubspec(String workspaceRelPath, String pkgPath) =>
    '$workspaceRelPath/$pkgPath/pubspec.yaml';

void main() {
  group('valid workspace', () {
    test('passes in --all mode', () {
      final r = _run(['--all', _valid]);
      expect(r.code, 0, reason: r.err);
      expect(r.out, contains('No FFCA violations found'));
    });

    test('passes in --all mode when run from the workspace root', () {
      final r = _run(['--all'], cwd: _valid);
      expect(r.code, 0, reason: r.err);
    });

    test('passes incrementally for every package', () {
      const packages = [
        'apps/mobile_app',
        'features/product/product_domain',
        'features/product/product_data',
        'features/product/product_presentation',
        'features/cart/cart_domain',
        'features/cart/cart_data',
        'features/cart/cart_presentation',
        'features/auth/auth_domain',
        'features/auth/auth_data_firebase',
        'features/ideas/ideas_presentation',
        'shared/ui_kit',
        'shared/api_client',
      ];
      for (final pkg in packages) {
        final r = _run(['--file', _pubspec(_valid, pkg)]);
        expect(r.code, 0, reason: '$pkg should pass but got: ${r.err}');
        expect(r.err, isEmpty, reason: '$pkg should be silent on pass');
      }
    });

    test('accepts a presentation-only feature with no domain sibling', () {
      // features/ideas/ holds only ideas_presentation, which composes
      // product_domain and cart_domain. A missing sibling is a signal about
      // what the feature is, never a violation.
      final r = _run([
        '--file',
        _pubspec(_valid, 'features/ideas/ideas_presentation'),
      ]);
      expect(r.code, 0, reason: r.err);
      expect(r.err, isEmpty);
    });
  });

  group('invalid workspace --all catches every rule', () {
    late String err;
    setUpAll(() {
      final r = _run(['--all', _invalid]);
      expect(r.code, 2, reason: 'invalid workspace must fail');
      err = r.err;
    });

    test('naming violation', () {
      expect(err, contains('orders_service is under features/orders/'));
      expect(err, contains('valid FFCA package name'));
    });

    test('domain depends on data', () {
      expect(err, contains('alpha_domain depends on alpha_data'));
      expect(err, contains('a domain layer must never depend on a data layer'));
    });

    test('data depends on presentation', () {
      expect(err, contains('beta_data depends on beta_presentation'));
      expect(
        err,
        contains('a data layer must never depend on a presentation layer'),
      );
    });

    test('presentation depends on another feature data', () {
      expect(err, contains('gamma_presentation depends on delta_data'));
      expect(err, contains('presentation must never depend on a data layer'));
      // Assert the fix text, not just the rule, so wrong guidance is caught.
      expect(err, contains('access data through its repository interface'));
    });

    test("data depends on another feature's data", () {
      expect(err, contains('theta_data depends on delta_data'));
      expect(
        err,
        contains("a data layer must never depend on another feature's data"),
      );
      expect(
        err,
        contains('Depend on delta_domain and access it through its repository'),
      );
    });

    test('shared depends on a feature', () {
      expect(err, contains('bad_shared depends on alpha_domain'));
      expect(err, contains('shared packages must never depend on a feature'));
      expect(err, contains('Move the shared code into the feature'));
    });

    test('dependency cycle', () {
      expect(err, contains('dependency cycle detected'));
      expect(err, contains('epsilon_domain'));
      expect(err, contains('zeta_domain'));
    });

    test('package depends on an app', () {
      expect(err, contains('eta_data depends on mobile_app'));
      expect(err, contains('nothing may depend on an app'));
    });

    test('data does not depend on its own domain', () {
      expect(err, contains('iota_data does not depend on iota_domain'));
      expect(err, contains("a data layer implements its own feature's domain"));
      expect(err, contains('Add iota_domain under dependencies'));
    });

    test('data declares its own domain only as a dev dependency', () {
      expect(
        err,
        contains('mu_data declares mu_domain only outside dependencies'),
      );
    });

    test('data in a feature with no domain', () {
      expect(
        err,
        contains('kappa_data is a data layer but features/kappa/ has no '
            'kappa_domain'),
      );
      expect(err, contains('Add kappa_domain with the repository interfaces'));
    });

    test('domain depends on the Flutter SDK', () {
      expect(
        err,
        contains('lambda_domain depends on the Flutter SDK through flutter'),
      );
      expect(err, contains('the domain layer is pure Dart'));
    });

    test('resolves dependencies by workspace name and by path', () {
      // The fixture is a Dart workspace: alpha_domain declares `alpha_data:
      // any` and resolves by name, theta_data keeps a `path:` dependency.
      expect(err, contains('alpha_domain depends on alpha_data'));
      expect(err, contains('theta_data depends on delta_data'));
    });

    test('every violation includes a fix line', () {
      // One arrow per violation; there are at least the thirteen planted rules.
      final arrows = '→'.allMatches(err).length;
      expect(arrows, greaterThanOrEqualTo(13));
    });

    test('every finding carries a rule ID', () {
      final findings = err.split('\n').where((l) => l.startsWith('  ✗'));
      expect(findings, isNotEmpty);
      for (final line in findings) {
        expect(line, matches(RegExp(r'^  ✗ \[[a-z-]+\] ')));
      }
    });

    test('ends with a summary line', () {
      expect(err, contains(RegExp(r'FFCA: \d+ errors, 0 warnings\.')));
    });

    test('a suppression without a reason suppresses nothing', () {
      expect(err, contains('[suppression-missing-reason]'));
      expect(err, contains('omicron_data does not depend on omicron_domain'));
    });

    test('a suppression naming an unknown rule', () {
      expect(err, contains('[suppression-unknown-rule]'));
      expect(err, contains('"domain-uses-widgets"'));
    });
  });

  group('invalid workspace incremental mode', () {
    test('flags the edited package own violation', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/alpha/alpha_domain'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('alpha_domain depends on alpha_data'));
    });

    test('flags direct dependents of the edited package', () {
      // Editing alpha_data must surface alpha_domain's violation, because
      // alpha_domain is a direct dependent of alpha_data.
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/alpha/alpha_data'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('alpha_domain depends on alpha_data'));
    });

    test('detects a cycle reachable from the edited package', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/epsilon/epsilon_domain'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('dependency cycle detected'));
    });

    test('flags shared depending on a feature', () {
      final r = _run(['--file', _pubspec(_invalid, 'shared/bad_shared')]);
      expect(r.code, 2);
      expect(r.err, contains('shared packages must never depend on a feature'));
    });

    test('flags presentation depending on a data layer', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/gamma/gamma_presentation'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('presentation must never depend on a data layer'));
    });

    test('flags data depending on a presentation layer', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/beta/beta_data'),
      ]);
      expect(r.code, 2);
      expect(
        r.err,
        contains('a data layer must never depend on a presentation layer'),
      );
    });

    test('flags a package depending on an app', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/eta/eta_data'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('nothing may depend on an app'));
    });

    test('flags data not depending on its own domain', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/iota/iota_data'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('iota_data does not depend on iota_domain'));
    });

    test('flags data declaring its own domain only as a dev dependency', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/mu/mu_data'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('mu_data declares mu_domain only outside'));
    });

    test('flags data in a feature with no domain', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/kappa/kappa_data'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('features/kappa/ has no kappa_domain'));
    });

    test('flags a domain depending on the Flutter SDK', () {
      final r = _run([
        '--file',
        _pubspec(_invalid, 'features/lambda/lambda_domain'),
      ]);
      expect(r.code, 2);
      expect(r.err, contains('the domain layer is pure Dart'));
    });

    test('planted fixtures report only their own rule', () {
      // beta and theta now depend on their own domain, so the ownership
      // checks add nothing to the layer rule each of them plants.
      for (final pkg in [
        'features/beta/beta_data',
        'features/theta/theta_data',
      ]) {
        final r = _run(['--file', _pubspec(_invalid, pkg)]);
        expect(r.code, 2);
        expect(
          '✗'.allMatches(r.err).length,
          1,
          reason: '$pkg should report one violation, got: ${r.err}',
        );
      }
    });
  });

  group('severities and suppressions', () {
    test('--all exits 0 when every finding is a warning or suppressed', () {
      final r = _run(['--all', _warning]);
      expect(r.code, 0, reason: r.err);
      expect(r.err, contains('FFCA: 0 errors, 2 warnings, 1 suppressed.'));
    });

    test('reports a warning with its rule ID', () {
      final r = _run(['--all', _warning]);
      expect(
        r.err,
        contains('⚠ [presentation-missing-own-domain] nu_presentation does '
            'not depend on nu_domain'),
      );
    });

    test('does not print a suppressed finding', () {
      final r = _run(['--all', _warning]);
      expect(r.err, isNot(contains('xi_data')));
    });

    test('reports an unused suppression in --all mode', () {
      final r = _run(['--all', _warning]);
      expect(
        r.err,
        contains('⚠ [unused-suppression] ffca-ignore: domain-uses-flutter on '
            'line 2 of the rho_domain pubspec matches no finding'),
      );
    });

    test('incremental mode exits 0 on a warning and still prints it', () {
      final r = _run([
        '--file',
        _pubspec(_warning, 'features/nu/nu_presentation'),
      ]);
      expect(r.code, 0);
      expect(r.err, contains('[presentation-missing-own-domain]'));
    });

    test('incremental mode is silent on a suppressed finding', () {
      final r = _run(['--file', _pubspec(_warning, 'features/xi/xi_data')]);
      expect(r.code, 0);
      expect(r.err, isEmpty);
    });

    test('incremental mode does not report unused suppressions', () {
      final r = _run([
        '--file',
        _pubspec(_warning, 'features/rho/rho_domain'),
      ]);
      expect(r.code, 0);
      expect(r.err, isEmpty);
    });
  });

  group('graceful skips (exit 0)', () {
    test('non-pubspec file', () {
      final r = _run(['--file', '$_valid/README.md']);
      expect(r.code, 0);
      expect(r.err, isEmpty);
    });

    test('pubspec outside an FFCA workspace', () {
      final r = _run(['--file', _pubspec(_notFfca, 'packages/some_pkg')]);
      expect(r.code, 0);
      expect(r.err, isEmpty);
    });

    test('nonexistent file', () {
      final r = _run(['--file', '$_valid/does/not/exist/pubspec.yaml']);
      expect(r.code, 0);
    });

    test('--all on a non-FFCA directory reports nothing to check', () {
      final r = _run(['--all', _notFfca]);
      expect(r.code, 0);
      expect(r.out, contains('No FFCA workspace found'));
    });
  });

  group('usage', () {
    test('no recognized mode is a usage error', () {
      final r = _run([]);
      expect(r.code, 64);
      expect(r.err, contains('Usage'));
    });
  });
}
