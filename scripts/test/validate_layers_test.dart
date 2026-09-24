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

    test('every violation includes a fix line', () {
      // One arrow per violation; there are at least the seven planted rules.
      final arrows = '→'.allMatches(err).length;
      expect(arrows, greaterThanOrEqualTo(7));
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
