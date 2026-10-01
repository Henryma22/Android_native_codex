import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/services/codex_cli_updater.dart';

void main() {
  group('CodexCliUpdater', () {
    test(
      'orders prereleases below stable versions and ignores build metadata',
      () {
        expect(
          CodexCliUpdater.compareVersions('0.156.1', '0.156.1-beta.2'),
          greaterThan(0),
        );
        expect(
          CodexCliUpdater.compareVersions('0.156.1-beta.10', '0.156.1-beta.2'),
          greaterThan(0),
        );
        expect(
          CodexCliUpdater.compareVersions('0.156.1+build.2', '0.156.1+build.1'),
          0,
        );
        expect(
          CodexCliUpdater.parseVersion('Codex CLI 0.156.1-beta.2+android.4'),
          '0.156.1-beta.2+android.4',
        );
      },
    );

    test('updates a prerelease installation to the stable release', () async {
      final backend = _UpdaterBackend(installedVersion: '0.156.1-beta.2');
      final workspace = (await backend.listWorkspaces()).single;

      final result = await CodexCliUpdater(
        backend: backend,
        workspace: workspace,
      ).update();

      expect(result.updated, isTrue);
      expect(result.installedVersion, '0.156.1');
      expect(backend.activeVersion, '0.156.1');
    });

    test(
      'rolls back to the newest retained verified overlay version',
      () async {
        final backend = _UpdaterBackend(
          installedVersion: '0.154.0',
          activeTarget: 'versions/0.158.0',
          retainedVersions: <String>[
            '0.155.0',
            '0.157.0',
            '0.158.0',
            'not-a-version',
          ],
        );
        final workspace = (await backend.listWorkspaces()).single;

        final result = await CodexCliUpdater(
          backend: backend,
          workspace: workspace,
        ).rollbackToPrevious();

        expect(result.rolledBack, isTrue);
        expect(result.installedVersion, '0.157.0');
        expect(backend.activeTarget, 'versions/0.157.0');
        expect(backend.activeVersion, '0.157.0');
      },
    );

    test(
      'falls back to the rootfs CLI when no older overlay is retained',
      () async {
        final backend = _UpdaterBackend(
          installedVersion: '0.157.0',
          activeTarget: 'versions/0.158.0',
          retainedVersions: <String>['0.158.0'],
        );
        final workspace = (await backend.listWorkspaces()).single;

        final result = await CodexCliUpdater(
          backend: backend,
          workspace: workspace,
        ).rollbackToPrevious();

        expect(result.rolledBack, isTrue);
        expect(result.installedVersion, '0.157.0');
        expect(backend.activeTarget, isNull);
        expect(backend.activeVersion, '0.157.0');
        expect(
          backend.requests.any((request) => request.argv.first == 'rm'),
          isTrue,
        );
      },
    );

    test(
      'does not change the active launcher when no older CLI exists',
      () async {
        final backend = _UpdaterBackend(
          installedVersion: '0.159.0',
          activeTarget: 'versions/0.158.0',
          retainedVersions: <String>['0.158.0'],
        );
        final workspace = (await backend.listWorkspaces()).single;

        await expectLater(
          CodexCliUpdater(
            backend: backend,
            workspace: workspace,
          ).rollbackToPrevious(),
          throwsA(isA<BackendException>()),
        );

        expect(backend.activeTarget, 'versions/0.158.0');
        expect(
          backend.requests.any((request) => request.argv.first == 'ln'),
          isFalse,
        );
        expect(
          backend.requests.any((request) => request.argv.first == 'rm'),
          isFalse,
        );
      },
    );

    test('installs a versioned PRoot CLI and switches the launcher', () async {
      final backend = _UpdaterBackend();
      final workspace = (await backend.listWorkspaces()).single;

      final result = await CodexCliUpdater(
        backend: backend,
        workspace: workspace,
      ).update();

      expect(result.updated, isTrue);
      expect(result.installedVersion, '0.156.1');
      expect(backend.activeVersion, '0.156.1');
      expect(
        backend.requests.any(
          (request) => request.argv.contains(
            '/home/codex/.codex-cli/versions/0.156.1/bin/codex',
          ),
        ),
        isTrue,
      );
      expect(
        backend.requests
            .where(
              (request) =>
                  request.argv.length > 1 &&
                  request.argv.first == 'npm' &&
                  request.argv[1] == 'install',
            )
            .every((request) => request.identity == ExecutionIdentity.app),
        isTrue,
      );
      expect(
        backend.requests.any(
          (request) =>
              request.argv.first == 'mv' &&
              request.argv.contains('/home/codex/.codex-cli/current'),
        ),
        isTrue,
      );
      expect(
        backend.requests.every(
          (request) =>
              !request.argv.contains('sh') && !request.argv.contains('-c'),
        ),
        isTrue,
      );
    });

    test(
      'does not mutate the launcher when the installed version is current',
      () async {
        final backend = _UpdaterBackend(latestVersion: '0.154.0');
        final workspace = (await backend.listWorkspaces()).single;

        final result = await CodexCliUpdater(
          backend: backend,
          workspace: workspace,
        ).update();

        expect(result.updated, isFalse);
        expect(
          backend.requests.any((request) => request.argv.first == 'ln'),
          isFalse,
        );
        expect(backend.activeVersion, '0.154.0');
      },
    );

    test('keeps the active CLI when staged verification fails', () async {
      final backend = _UpdaterBackend(stagedVersion: '0.155.0');
      final workspace = (await backend.listWorkspaces()).single;

      await expectLater(
        CodexCliUpdater(backend: backend, workspace: workspace).update(),
        throwsA(isA<BackendException>()),
      );

      expect(backend.activeVersion, '0.154.0');
      expect(
        backend.requests.any((request) => request.argv.first == 'ln'),
        isFalse,
      );
    });

    test(
      'restores the previous launcher when active verification fails',
      () async {
        final backend = _UpdaterBackend(
          installedVersion: '0.155.0',
          activeTarget: 'versions/0.155.0',
          failFirstActiveVerification: true,
        );
        final workspace = (await backend.listWorkspaces()).single;

        await expectLater(
          CodexCliUpdater(backend: backend, workspace: workspace).update(),
          throwsA(isA<BackendException>()),
        );

        expect(backend.activeVersion, '0.155.0');
        expect(backend.activeTarget, 'versions/0.155.0');
        expect(
          backend.requests.where((request) => request.argv.first == 'ln'),
          hasLength(2),
        );
      },
    );

    test(
      'removes the first update link when activation verification fails',
      () async {
        final backend = _UpdaterBackend(failFirstActiveVerification: true);
        final workspace = (await backend.listWorkspaces()).single;

        await expectLater(
          CodexCliUpdater(backend: backend, workspace: workspace).update(),
          throwsA(isA<BackendException>()),
        );

        expect(backend.activeTarget, isNull);
        expect(backend.activeVersion, '0.154.0');
        expect(
          backend.requests.where((request) => request.argv.first == 'rm'),
          hasLength(2),
        );
      },
    );
  });
}

class _UpdaterBackend extends FakeBackend {
  _UpdaterBackend({
    this.latestVersion = '0.156.1',
    this.stagedVersion = '0.156.1',
    this.installedVersion = '0.154.0',
    this.activeTarget,
    this.failFirstActiveVerification = false,
    this.retainedVersions = const <String>[],
  });

  static const _compatibilityDescriptor = BackendDescriptor(
    id: 'test-linux-compatibility',
    kind: BackendKind.linuxCompatibility,
    displayName: 'Test Linux compatibility',
    version: 'test',
    health: BackendHealth.verified,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: true,
    ),
  );

  final String latestVersion;
  final String stagedVersion;
  final String installedVersion;
  final bool failFirstActiveVerification;
  final List<String> retainedVersions;
  final List<ExecutionRequest> requests = <ExecutionRequest>[];
  String? activeTarget;
  String? _stagedLinkTarget;
  String get activeVersion =>
      activeTarget == null ? installedVersion : activeTarget!.split('/').last;
  var _firstActiveVerification = true;

  @override
  BackendDescriptor get descriptor => _compatibilityDescriptor;

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) async* {
    requests.add(request);
    final argv = request.argv;
    if (argv.length >= 2 && argv[0] == 'npm' && argv[1] == 'view') {
      yield ExecutionEvent.stdout('"$latestVersion"\n');
    } else if (argv.length == 4 && argv[0] == 'ls') {
      yield ExecutionEvent.stdout('${retainedVersions.join('\n')}\n');
    } else if (argv.length >= 3 && argv[0] == 'npm' && argv[1] == 'install') {
      yield const ExecutionEvent.stdout('installed\n');
    } else if (argv.length == 2 &&
        argv[0] == 'codex' &&
        argv[1] == '--version') {
      if (failFirstActiveVerification &&
          activeTarget?.contains('versions/') == true &&
          activeVersion != installedVersion &&
          _firstActiveVerification) {
        _firstActiveVerification = false;
        yield ExecutionEvent.stdout('codex $installedVersion\n');
      } else {
        yield ExecutionEvent.stdout('codex $activeVersion\n');
      }
    } else if (argv.length == 2 &&
        argv[1] == '--version' &&
        argv[0].contains('/home/codex/.codex-cli/versions/')) {
      final version = RegExp(r'/versions/([^/]+)/bin/codex$')
          .firstMatch(argv[0])
          ?.group(1);
      yield ExecutionEvent.stdout(
        'codex ${retainedVersions.contains(version) ? version : stagedVersion}\n',
      );
    } else if (argv.length == 2 &&
        argv[0] == '/usr/local/bin/codex' &&
        argv[1] == '--version') {
      yield ExecutionEvent.stdout('codex $installedVersion\n');
    } else if (argv.length == 2 && argv[0] == 'readlink') {
      final target = activeTarget;
      if (target == null) {
        yield const ExecutionEvent.stderr('current launcher does not exist');
        yield const ExecutionEvent.exit(1);
        return;
      }
      yield ExecutionEvent.stdout('$target\n');
    } else if (argv.length == 5 && argv[0] == 'ln') {
      _stagedLinkTarget = argv[3];
      yield const ExecutionEvent.stdout('');
    } else if (argv.length == 5 && argv[0] == 'mv') {
      activeTarget = _stagedLinkTarget;
      _stagedLinkTarget = null;
      yield const ExecutionEvent.stdout('');
    } else if (argv.length == 4 && argv[0] == 'rm') {
      if (argv[3] == '/home/codex/.codex-cli/current') {
        activeTarget = null;
      } else {
        _stagedLinkTarget = null;
      }
      yield const ExecutionEvent.stdout('');
    } else {
      yield ExecutionEvent.stderr('unexpected command: ${argv.join(' ')}');
      yield const ExecutionEvent.exit(1);
      return;
    }
    yield const ExecutionEvent.exit(0);
  }
}
