import 'dart:async';
import 'dart:convert';

import '../../core/domain/backend.dart';
import '../../core/domain/change_set.dart';
import '../../core/domain/execution.dart';
import '../../core/domain/workspace.dart';

/// A deterministic fixture for developing the UI before device services exist.
class FakeBackend implements Backend {
  static const _descriptor = BackendDescriptor(
    id: 'fake-backend',
    kind: BackendKind.fake,
    displayName: 'Fake Backend (development)',
    version: 'stage-0',
    health: BackendHealth.available,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: false,
      reason: 'Deterministic fixture only; this is not device evidence.',
    ),
  );

  static const _workspace = WorkspaceRef(
    backendId: 'fake-backend',
    filesystemOwnerId: 'fake-fixture',
    displayPath: '/storage/emulated/0/Codex/Workspaces/demo',
    hostPath: '/storage/emulated/0/Codex/Workspaces/demo',
    backendLocator: 'fixture://demo',
  );

  final Map<String, String> _files = <String, String>{
    'README.md': '# codex fixture\n\nThis deterministic workspace is for Stage 0 UI development.\n',
    'lib/main.dart': 'void main() => print(\'fixture\');\n',
  };
  final Map<String, int> _versions = <String, int>{
    'README.md': 1,
    'lib/main.dart': 1,
  };
  final Map<String, _FakeBackup> _backups = <String, _FakeBackup>{};
  var _nextBackupId = 1;

  @override
  BackendDescriptor get descriptor => _descriptor;

  @override
  Future<List<WorkspaceRef>> listWorkspaces() async => const <WorkspaceRef>[
    _workspace,
  ];

  @override
  Future<WorkspaceHandle> openWorkspace(WorkspaceRef workspace) async {
    if (workspace != _workspace) {
      throw const BackendException(
        'Fake backend only accepts its demo fixture.',
      );
    }
    return const WorkspaceHandle(_workspace);
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(
    WorkspaceHandle workspace, {
    String relativePath = '',
  }) async {
    _checkWorkspace(workspace);
    if (relativePath == 'lib') {
      return const <WorkspaceEntry>[
        WorkspaceEntry(
          name: 'main.dart',
          relativePath: 'lib/main.dart',
          isDirectory: false,
          sizeBytes: 39,
        ),
      ];
    }
    if (relativePath.isNotEmpty) {
      throw const BackendException('Fake directory does not exist.');
    }
    return const <WorkspaceEntry>[
      WorkspaceEntry(
        name: 'README.md',
        relativePath: 'README.md',
        isDirectory: false,
        sizeBytes: 128,
      ),
      WorkspaceEntry(
        name: 'lib',
        relativePath: 'lib',
        isDirectory: true,
        sizeBytes: 0,
      ),
    ];
  }

  @override
  Future<String> readText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async {
    _checkWorkspace(workspace);
    return _fileContent(relativePath);
  }

  @override
  Future<TextFileSnapshot> snapshotText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async {
    _checkWorkspace(workspace);
    final content = _fileContent(relativePath);
    final version = _versions[relativePath]!;
    return TextFileSnapshot(
      relativePath: relativePath,
      content: content,
      version: 'fake-v$version',
      sizeBytes: utf8.encode(content).length,
      uid: 1000,
      gid: 1000,
      mode: '644',
    );
  }

  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) async {
    _checkWorkspace(workspace);
    final before = await snapshotText(workspace, relativePath);
    if (before.version != expectedVersion) {
      throw const BackendException(
        'conflict: the file changed after the preview was created.',
      );
    }
    if (utf8.encode(content).length > 1024 * 1024) {
      throw const BackendException('too_large: text file exceeds 1 MiB.');
    }
    final backupId = 'fake-backup-${_nextBackupId++}';
    _backups[backupId] = _FakeBackup(
      relativePath: relativePath,
      content: before.content,
      version: before.version,
    );
    _files[relativePath] = content;
    final nextVersion = _nextVersion(relativePath);
    return WriteReceipt(
      backupId: backupId,
      relativePath: relativePath,
      beforeVersion: before.version,
      afterVersion: 'fake-v$nextVersion',
    );
  }

  @override
  Future<WriteReceipt> backupText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
  }) async {
    _checkWorkspace(workspace);
    final before = await snapshotText(workspace, relativePath);
    if (before.version != expectedVersion) {
      throw const BackendException(
        'conflict: the file changed before the backup was created.',
      );
    }
    final backupId = 'fake-backup-${_nextBackupId++}';
    _backups[backupId] = _FakeBackup(
      relativePath: relativePath,
      content: before.content,
      version: before.version,
    );
    return WriteReceipt(
      backupId: backupId,
      relativePath: relativePath,
      beforeVersion: before.version,
      afterVersion: before.version,
    );
  }

  @override
  Future<WriteReceipt> restoreText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String backupId,
    required String expectedVersion,
  }) async {
    _checkWorkspace(workspace);
    final backup = _backups[backupId];
    if (backup == null || backup.relativePath != relativePath) {
      throw const BackendException('not_found: backup does not exist.');
    }
    final before = await snapshotText(workspace, relativePath);
    if (before.version != expectedVersion) {
      throw const BackendException(
        'conflict: the file changed after the commit was created.',
      );
    }
    _files[relativePath] = backup.content;
    final nextVersion = _nextVersion(relativePath);
    return WriteReceipt(
      backupId: backupId,
      relativePath: relativePath,
      beforeVersion: before.version,
      afterVersion: 'fake-v$nextVersion',
      restored: true,
    );
  }

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) =>
      startInteractive(request).events;

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    final controller = StreamController<ExecutionEvent>();
    var stopped = false;
    unawaited(() async {
      await Future<void>.delayed(Duration.zero);
      if (stopped) return;
      controller.add(
        ExecutionEvent.stdout('fake backend: ${request.argv.join(' ')}\n'),
      );
      controller.add(const ExecutionEvent.exit(0));
      await controller.close();
    }());
    return _FakeInteractiveExecution(
      events: controller.stream,
      write: (_) async {},
      closeStdin: () async {},
      stop: () async {
        stopped = true;
        if (!controller.isClosed) await controller.close();
      },
    );
  }

  void _checkWorkspace(WorkspaceHandle workspace) {
    if (workspace.ref != _workspace) {
      throw const BackendException(
        'Workspace is not owned by the fake backend.',
      );
    }
  }

  String _fileContent(String relativePath) {
    final content = _files[relativePath];
    if (content == null) {
      throw BackendException(
        'not_found: fixture file not found: $relativePath',
      );
    }
    return content;
  }

  int _nextVersion(String relativePath) {
    final next = (_versions[relativePath] ?? 0) + 1;
    _versions[relativePath] = next;
    return next;
  }
}

class _FakeBackup {
  const _FakeBackup({
    required this.relativePath,
    required this.content,
    required this.version,
  });

  final String relativePath;
  final String content;
  final String version;
}

class _FakeInteractiveExecution
    implements InteractiveExecution, StdinClosableExecution {
  _FakeInteractiveExecution({
    required this.events,
    required Future<void> Function(String value) write,
    required Future<void> Function() closeStdin,
    required Future<void> Function() stop,
  }) : _write = write,
       _closeStdin = closeStdin,
       _stop = stop;

  @override
  final Stream<ExecutionEvent> events;

  final Future<void> Function(String value) _write;
  final Future<void> Function() _closeStdin;
  final Future<void> Function() _stop;

  @override
  Future<void> write(String value) => _write(value);

  @override
  Future<void> closeStdin() => _closeStdin();

  @override
  Future<void> stop() => _stop();
}
