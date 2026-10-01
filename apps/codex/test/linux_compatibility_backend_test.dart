import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/compatibility/linux_compatibility_backend.dart';
import 'package:codex/core/application/codex_session_client.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/change_set.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/core/domain/workspace.dart';

void main() {
  test(
    'keeps host file ownership and fails closed without a verified runtime',
    () async {
      final host = _HostBackendStub();
      final backend = LinuxCompatibilityBackend(host);

      expect(backend.descriptor.kind, BackendKind.linuxCompatibility);
      expect(backend.descriptor.health, BackendHealth.unavailable);
      expect(backend.descriptor.capabilities.verified, isFalse);

      final workspaces = await backend.listWorkspaces();
      expect(workspaces, hasLength(1));
      expect(workspaces.single.backendId, LinuxCompatibilityBackend.id);
      expect(workspaces.single.hostPath, _HostBackendStub.hostWorkspace);

      final handle = await backend.openWorkspace(workspaces.single);
      await backend.listDirectory(handle);
      expect(host.lastOpenedWorkspace?.ref.backendId, 'local-android');
      expect(
        host.lastOpenedWorkspace?.ref.hostPath,
        _HostBackendStub.hostWorkspace,
      );

      expect(
        () => backend.startInteractive(
          ExecutionRequest(
            argv: const <String>['node', '--version'],
            cwd: _HostBackendStub.hostWorkspace,
          ),
        ),
        throwsA(isA<BackendException>()),
      );
    },
  );

  test(
    'maps only verified guest execution while delegating files to host',
    () async {
      final runtime = _RuntimeStub(
        const CompatibilityRuntimeDescriptor(
          state: CompatibilityRuntimeState.available,
          version: 'debian-bookworm-arm64',
        ),
      );
      final backend = LinuxCompatibilityBackend(
        _HostBackendStub(),
        runtime: runtime,
      );

      expect(backend.descriptor.health, BackendHealth.available);
      await backend.refresh();
      expect(backend.descriptor.health, BackendHealth.verified);

      final events = <ExecutionEvent>[];
      await for (final event in backend.execute(
        ExecutionRequest(
          argv: const <String>['node', '--version'],
          cwd: _HostBackendStub.hostWorkspace,
          environment: const <String, String>{'LANG': 'C.UTF-8'},
        ),
      )) {
        events.add(event);
      }

      expect(events.last.exitCode, 0);
      expect(runtime.lastRequest?.argv, <String>['node', '--version']);
      expect(runtime.lastRequest?.cwd, '/mnt/host/demo');
      expect(runtime.lastRequest?.environment['LANG'], 'C.UTF-8');
    },
  );

  test(
    'forwards Android Root identity to the gated native PRoot launcher',
    () async {
      final runtime = _RuntimeStub(
        const CompatibilityRuntimeDescriptor(
          state: CompatibilityRuntimeState.verified,
          version: 'debian-bookworm-arm64',
        ),
      );
      final backend = LinuxCompatibilityBackend(
        _HostBackendStub(),
        runtime: runtime,
      );

      backend.startInteractive(
        ExecutionRequest(
          argv: const <String>['codex', 'app-server'],
          cwd: _HostBackendStub.hostWorkspace,
          identity: ExecutionIdentity.root,
        ),
      );

      expect(runtime.lastRequest?.identity, ExecutionIdentity.root);
      expect(runtime.lastRequest?.cwd, '/mnt/host/demo');
    },
  );

  test('runs runtime maintenance from app-private storage without a user workspace', () async {
    const maintenanceCwd = '/data/user/0/io.henry.codex/no_backup';
    final runtime = _RuntimeStub(
      const CompatibilityRuntimeDescriptor(
        state: CompatibilityRuntimeState.verified,
        version: 'debian-bookworm-arm64',
        maintenanceCwd: maintenanceCwd,
      ),
    );
    final backend = LinuxCompatibilityBackend(
      _HostBackendStub(),
      runtime: runtime,
    );

    final maintenance = backend.runtimeMaintenanceWorkspace();
    expect(maintenance.filesystemOwnerId, 'compatibility-runtime');
    expect(maintenance.backendLocator, 'runtime://maintenance');
    expect(
      (await backend.listWorkspaces()).every(
        (workspace) => workspace.hostPath != maintenanceCwd,
      ),
      isTrue,
    );

    final events = <ExecutionEvent>[];
    await for (final event in backend.execute(
      ExecutionRequest(
        argv: const <String>['npm', 'view', '@openai/codex', 'version'],
        cwd: maintenanceCwd,
      ),
    )) {
      events.add(event);
    }

    expect(events.last.exitCode, 0);
    expect(runtime.lastRequest?.cwd, '/mnt/runtime');
  });

  test(
    'rejects SAF and traversal paths at the compatibility boundary',
    () async {
      final backend = LinuxCompatibilityBackend(
        _HostBackendStub(),
        runtime: _RuntimeStub(
          const CompatibilityRuntimeDescriptor(
            state: CompatibilityRuntimeState.verified,
            version: 'verified',
          ),
        ),
      );

      expect(
        () => backend.openWorkspace(
          const WorkspaceRef(
            backendId: LinuxCompatibilityBackend.id,
            filesystemOwnerId: 'android-saf',
            displayPath: 'content://example/tree',
            hostPath: 'content://example/tree',
            backendLocator: 'saf://example',
          ),
        ),
        throwsA(isA<BackendException>()),
      );
      expect(
        () => backend.execute(
          ExecutionRequest(
            argv: const <String>['sh'],
            cwd: '${_HostBackendStub.hostWorkspace}/../other',
          ),
        ),
        throwsA(isA<BackendException>()),
      );
    },
  );

  test(
    'uses /workspace for Codex while native execution keeps the host path',
    () async {
      final backend = LinuxCompatibilityBackend(
        _HostBackendStub(),
        runtime: _RuntimeStub(
          const CompatibilityRuntimeDescriptor(
            state: CompatibilityRuntimeState.verified,
            version: 'debian-bookworm-arm64',
          ),
        ),
      );
      await backend.refresh();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _SessionProbeProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server'],
        processFactory: (_) => process,
      );

      await client.start();

      final threadStart = process.writes
          .map(jsonDecode)
          .whereType<Map<String, dynamic>>()
          .firstWhere((message) => message['method'] == 'thread/start');
      final params = threadStart['params'] as Map<String, dynamic>;
      expect(params['cwd'], '/workspace');
      expect(
        params['sandbox'],
        'danger-full-access',
        reason: 'PRoot is the outer local boundary; Codex must not start bwrap inside it.',
      );
      expect(client.threadId, 'compatibility-thread');

      await client.dispose();
    },
  );
}

class _RuntimeStub implements CompatibilityRuntimeClient {
  _RuntimeStub(this._descriptor);

  CompatibilityRuntimeDescriptor _descriptor;
  ExecutionRequest? lastRequest;

  @override
  CompatibilityRuntimeDescriptor get descriptor => _descriptor;

  @override
  Future<CompatibilityRuntimeDescriptor> probe() async {
    _descriptor = const CompatibilityRuntimeDescriptor(
      state: CompatibilityRuntimeState.verified,
      version: 'debian-bookworm-arm64',
      rootfsDigest: 'rootfs-test-digest',
    );
    return _descriptor;
  }

  @override
  void acceptProbeResult(CompatibilityRuntimeDescriptor descriptor) {
    _descriptor = descriptor;
  }

  @override
  String mapHostPath(String hostPath) =>
      hostPath == _HostBackendStub.hostWorkspace
      ? '/mnt/host/demo'
      : hostPath == '/data/user/0/io.henry.codex/no_backup'
      ? '/mnt/runtime'
      : '/mnt/host/${hostPath.substring(_HostBackendStub.hostWorkspace.length + 1)}';

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) {
    lastRequest = request;
    return Stream<ExecutionEvent>.fromIterable(const <ExecutionEvent>[
      ExecutionEvent.stdout('guest-ok\n'),
      ExecutionEvent.exit(0),
    ]);
  }

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    lastRequest = request;
    return _EmptyInteractiveExecution();
  }
}

class _EmptyInteractiveExecution implements InteractiveExecution {
  @override
  Stream<ExecutionEvent> get events => const Stream<ExecutionEvent>.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> write(String value) async {}
}

class _SessionProbeProcess implements InteractiveExecution {
  final StreamController<ExecutionEvent> _events =
      StreamController<ExecutionEvent>.broadcast();
  final List<String> writes = <String>[];

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value.trim());
    final message = jsonDecode(value) as Map<String, dynamic>;
    final id = message['id'];
    if (id == null) return;
    final result = message['method'] == 'thread/start'
        ? <String, dynamic>{
            'thread': <String, String>{'id': 'compatibility-thread'},
          }
        : <String, dynamic>{};
    _events.add(
      ExecutionEvent.stdout(
        '${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result})}\n',
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _events.close();
  }
}

class _HostBackendStub implements Backend {
  static const hostWorkspace = '/storage/emulated/0/Codex/Workspaces/demo';

  WorkspaceHandle? lastOpenedWorkspace;

  static const _descriptor = BackendDescriptor(
    id: 'local-android',
    kind: BackendKind.localAndroid,
    displayName: 'Local Android',
    version: 'test',
    health: BackendHealth.verified,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: true,
    ),
  );

  @override
  BackendDescriptor get descriptor => _descriptor;

  @override
  Future<List<WorkspaceRef>> listWorkspaces() async => const <WorkspaceRef>[
    WorkspaceRef(
      backendId: 'local-android',
      filesystemOwnerId: 'android-host',
      displayPath: hostWorkspace,
      hostPath: hostWorkspace,
      backendLocator: 'host://demo',
    ),
    WorkspaceRef(
      backendId: 'local-android',
      filesystemOwnerId: 'android-saf',
      displayPath: 'content://example/tree',
      hostPath: 'content://example/tree',
      backendLocator: 'saf://example',
    ),
  ];

  @override
  Future<WorkspaceHandle> openWorkspace(WorkspaceRef workspace) async {
    lastOpenedWorkspace = WorkspaceHandle(workspace);
    return lastOpenedWorkspace!;
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(
    WorkspaceHandle workspace, {
    String relativePath = '',
  }) async => const <WorkspaceEntry>[];

  @override
  Future<TextFileSnapshot> snapshotText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async => const TextFileSnapshot(
    relativePath: 'README.md',
    content: 'host',
    version: 'v1',
    sizeBytes: 4,
  );

  @override
  Future<String> readText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async => 'host';

  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) async => const WriteReceipt(
    backupId: 'backup',
    relativePath: 'README.md',
    beforeVersion: 'v1',
    afterVersion: 'v2',
  );

  @override
  Future<WriteReceipt> backupText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
  }) async => const WriteReceipt(
    backupId: 'backup',
    relativePath: 'README.md',
    beforeVersion: 'v1',
    afterVersion: 'v1',
  );

  @override
  Future<WriteReceipt> restoreText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String backupId,
    required String expectedVersion,
  }) async => const WriteReceipt(
    backupId: 'backup',
    relativePath: 'README.md',
    beforeVersion: 'v2',
    afterVersion: 'v3',
    restored: true,
  );

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) =>
      Stream<ExecutionEvent>.empty();

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) =>
      _EmptyInteractiveExecution();
}
