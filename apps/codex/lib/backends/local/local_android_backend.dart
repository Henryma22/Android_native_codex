import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/domain/backend.dart';
import '../../core/domain/change_set.dart';
import '../../core/domain/execution.dart';
import '../../core/domain/workspace.dart';

class LocalBackupRecord {
  const LocalBackupRecord({
    required this.backupId,
    required this.kind,
    required this.relativePath,
    required this.sizeBytes,
    required this.createdAtMs,
    this.workspace,
    this.version = '',
    this.reason,
  });

  final String backupId;
  final String kind;
  final String relativePath;
  final int sizeBytes;
  final int createdAtMs;
  final WorkspaceRef? workspace;
  final String version;
  final String? reason;

  bool get isValid => workspace != null && reason == null;
}

class LocalAndroidBackend implements Backend {
  static const _channel = MethodChannel('io.henry.codex/local_backend');
  static const _hostEvents = EventChannel('io.henry.codex/host_events');
  static const _workspaceRoot = '/storage/emulated/0/Codex/Workspaces';

  LocalAndroidBackend({bool subscribeToHostEvents = true}) {
    if (subscribeToHostEvents) {
      _hostEventSubscription = _hostEvents.receiveBroadcastStream().listen(
        _handleHostEvent,
      );
    }
  }

  final Map<String, StreamController<ExecutionEvent>> _executions = {};
  StreamSubscription<Object?>? _hostEventSubscription;
  var _disposed = false;

  /// Releases the native event subscription and any Host processes owned by
  /// this backend. The app normally owns one instance for its whole home
  /// page; the explicit boundary also keeps short-lived test/embedding
  /// instances from retaining a broadcast subscription.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _hostEventSubscription?.cancel();
    _hostEventSubscription = null;
    final active = Map<String, StreamController<ExecutionEvent>>.from(
      _executions,
    );
    _executions.clear();
    for (final entry in active.entries) {
      try {
        await _channel.invokeMethod<void>('stopHostProcess', <String, Object?>{
          'processId': entry.key,
        });
      } catch (_) {
        // Disposal is best effort; the native owner also cleans up on exit.
      }
      if (!entry.value.isClosed) await entry.value.close();
    }
  }

  static const _descriptor = BackendDescriptor(
    id: 'local-android',
    kind: BackendKind.localAndroid,
    displayName: 'Local Android (host workspace)',
    version: 'stage-4a-contract',
    health: BackendHealth.available,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: false,
      reason:
          'The fixed host workspace is probed directly for App UID access; '
          'operations fall back to a separately verified root helper only when '
          'the App UID path is unavailable.',
    ),
  );

  @override
  BackendDescriptor get descriptor => _descriptor;

  @override
  Future<List<WorkspaceRef>> listWorkspaces() async {
    BackendException? fixedWorkspaceError;
    var fixedWorkspaces = <WorkspaceRef>[];
    try {
      final entries = await _listDirectory('');
      fixedWorkspaces = entries
          .where((entry) => entry.isDirectory)
          .map(
            (entry) => WorkspaceRef(
              backendId: descriptor.id,
              filesystemOwnerId: 'android-host',
              displayPath: '$_workspaceRoot/${entry.name}',
              hostPath: '$_workspaceRoot/${entry.name}',
              backendLocator: 'host://${entry.relativePath}',
            ),
          )
          .toList(growable: false);
    } on BackendException catch (error) {
      fixedWorkspaceError = error;
    }
    final safWorkspaces = await _listSafWorkspaces();
    if (fixedWorkspaces.isEmpty &&
        safWorkspaces.isEmpty &&
        fixedWorkspaceError != null) {
      throw fixedWorkspaceError;
    }
    return <WorkspaceRef>[...fixedWorkspaces, ...safWorkspaces];
  }

  /// Opens Android's document-tree picker and persists the selected grant.
  /// The user must explicitly choose the directory; no storage permission is
  /// requested during backend construction or ordinary startup.
  Future<WorkspaceRef?> pickSafWorkspace() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pickSafWorkspace');
      if (raw == null) return null;
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no SAF workspace.',
        );
      }
      return _safWorkspaceFromMap(raw);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('SAF workspace picker is unavailable.');
    }
  }

  /// Creates a real directory below the fixed direct host workspace root.
  ///
  /// This deliberately does not create a SAF-backed workspace: a direct host
  /// path is required before Host commands or a Local Session can be exposed.
  Future<WorkspaceRef> createHostWorkspace(String rawName) async {
    final name = _normalizeWorkspaceName(rawName);
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'createHostWorkspace',
        <String, Object?>{'name': name},
      );
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no Host workspace.',
        );
      }
      final returnedName = raw['name'] as String?;
      final relativePath = raw['relativePath'] as String?;
      final path = raw['path'] as String?;
      if (returnedName != name ||
          relativePath != name ||
          path != '$_workspaceRoot/$name') {
        throw const BackendException(
          'Local backend returned an invalid Host workspace.',
        );
      }
      return WorkspaceRef(
        backendId: descriptor.id,
        filesystemOwnerId: 'android-host',
        displayPath: path!,
        hostPath: path,
        backendLocator: 'host://$relativePath',
      );
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException(
        'Direct Host workspace creation is unavailable.',
      );
    }
  }

  /// Deletes one direct workspace below the fixed host root.
  ///
  /// SAF trees intentionally keep their existing document-provider semantics;
  /// this operation is only for workspaces created by this app under
  /// /storage/emulated/0/Codex/Workspaces.
  Future<void> deleteHostWorkspace(WorkspaceRef workspace) async {
    final relativePath = _relativeWorkspacePath(workspace);
    if (relativePath.contains('/')) {
      throw const BackendException('Only a direct workspace can be deleted.');
    }
    try {
      await _channel.invokeMethod<void>(
        'deleteHostWorkspace',
        <String, Object?>{'name': relativePath},
      );
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException(
        'Direct Host workspace deletion is unavailable.',
      );
    }
  }

  Future<void> forgetSafWorkspace(WorkspaceRef workspace) async {
    if (!_isSafWorkspace(workspace)) {
      throw const BackendException('Workspace is not a SAF workspace.');
    }
    try {
      await _channel.invokeMethod<void>('forgetSafWorkspace', <String, Object?>{
        'uri': workspace.hostPath,
      });
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('SAF workspace management is unavailable.');
    }
  }

  @override
  Future<WorkspaceHandle> openWorkspace(WorkspaceRef workspace) async {
    if (workspace.backendId != descriptor.id ||
        (!_isSafWorkspace(workspace) &&
            !workspace.displayPath.startsWith('$_workspaceRoot/'))) {
      throw const BackendException('Workspace is not owned by Local Android.');
    }
    return WorkspaceHandle(workspace);
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(
    WorkspaceHandle workspace, {
    String relativePath = '',
  }) async {
    _validateRelativePath(relativePath, allowEmpty: true);
    if (_isSafWorkspace(workspace.ref)) {
      return _listSafDirectory(workspace.ref.hostPath, relativePath);
    }
    final workspacePath = _relativeWorkspacePath(workspace.ref);
    final targetPath = relativePath.isEmpty
        ? workspacePath
        : '$workspacePath/$relativePath';
    final entries = await _listDirectory(targetPath);
    return entries
        .map(
          (entry) => WorkspaceEntry(
            name: entry.name,
            relativePath: relativePath.isEmpty
                ? entry.name
                : '$relativePath/${entry.name}',
            isDirectory: entry.isDirectory,
            sizeBytes: entry.sizeBytes,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<String> readText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async {
    _validateRelativePath(relativePath, allowEmpty: false);
    try {
      final saf = _isSafWorkspace(workspace.ref);
      final content = await _channel.invokeMethod<String>(
        saf ? 'readSafText' : 'readHostText',
        saf
            ? <String, Object?>{
                'uri': workspace.ref.hostPath,
                'relativePath': relativePath,
              }
            : <String, Object?>{
                'workspacePath': _relativeWorkspacePath(workspace.ref),
                'relativePath': relativePath,
              },
      );
      if (content == null) {
        throw const BackendException('Local backend returned no file content.');
      }
      return content;
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  @override
  Future<TextFileSnapshot> snapshotText(
    WorkspaceHandle workspace,
    String relativePath,
  ) async {
    _validateRelativePath(relativePath, allowEmpty: false);
    try {
      final saf = _isSafWorkspace(workspace.ref);
      final raw = await _channel.invokeMethod<Object?>(
        saf ? 'snapshotSafText' : 'snapshotHostText',
        saf
            ? <String, Object?>{
                'uri': workspace.ref.hostPath,
                'relativePath': relativePath,
              }
            : <String, Object?>{
                'workspacePath': _relativeWorkspacePath(workspace.ref),
                'relativePath': relativePath,
              },
      );
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no file snapshot.',
        );
      }
      return _snapshotFromMap(raw);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) async {
    _validateRelativePath(relativePath, allowEmpty: false);
    try {
      final saf = _isSafWorkspace(workspace.ref);
      final raw = await _channel.invokeMethod<Object?>(
        saf ? 'writeSafText' : 'writeHostText',
        saf
            ? <String, Object?>{
                'uri': workspace.ref.hostPath,
                'relativePath': relativePath,
                'expectedVersion': expectedVersion,
                'content': content,
              }
            : <String, Object?>{
                'workspacePath': _relativeWorkspacePath(workspace.ref),
                'relativePath': relativePath,
                'expectedVersion': expectedVersion,
                'content': content,
              },
      );
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no write receipt.',
        );
      }
      return _receiptFromMap(raw);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  @override
  Future<WriteReceipt> backupText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
  }) async {
    _validateRelativePath(relativePath, allowEmpty: false);
    try {
      final saf = _isSafWorkspace(workspace.ref);
      final raw = await _channel.invokeMethod<Object?>(
        saf ? 'backupSafText' : 'backupHostText',
        saf
            ? <String, Object?>{
                'uri': workspace.ref.hostPath,
                'relativePath': relativePath,
                'expectedVersion': expectedVersion,
              }
            : <String, Object?>{
                'workspacePath': _relativeWorkspacePath(workspace.ref),
                'relativePath': relativePath,
                'expectedVersion': expectedVersion,
              },
      );
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no backup receipt.',
        );
      }
      return _receiptFromMap(raw);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  @override
  Future<WriteReceipt> restoreText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String backupId,
    required String expectedVersion,
  }) async {
    _validateRelativePath(relativePath, allowEmpty: false);
    try {
      final saf = _isSafWorkspace(workspace.ref);
      final raw = await _channel.invokeMethod<Object?>(
        saf ? 'restoreSafText' : 'restoreHostText',
        saf
            ? <String, Object?>{
                'uri': workspace.ref.hostPath,
                'relativePath': relativePath,
                'backupId': backupId,
                'expectedVersion': expectedVersion,
              }
            : <String, Object?>{
                'workspacePath': _relativeWorkspacePath(workspace.ref),
                'relativePath': relativePath,
                'backupId': backupId,
                'expectedVersion': expectedVersion,
              },
      );
      if (raw is! Map<Object?, Object?>) {
        throw const BackendException(
          'Local backend returned no restore receipt.',
        );
      }
      return _receiptFromMap(raw);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  /// Lists durable app-private backup metadata. File contents never cross the
  /// platform channel; restoreBackup re-checks the current file version before
  /// asking the native backend to restore the selected record.
  Future<List<LocalBackupRecord>> listBackups() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listBackups');
      return (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(_backupFromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local backup history is unavailable.');
    }
  }

  Future<WriteReceipt> restoreBackup(LocalBackupRecord backup) async {
    final workspace = backup.workspace;
    if (!backup.isValid || workspace == null) {
      throw BackendException(
        'Backup ${backup.backupId} is unavailable: '
        '${backup.reason ?? 'invalid backup metadata'}.',
      );
    }
    final handle = await openWorkspace(workspace);
    final current = await snapshotText(handle, backup.relativePath);
    return restoreText(
      handle,
      backup.relativePath,
      backupId: backup.backupId,
      expectedVersion: current.version,
    );
  }

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) =>
      startInteractive(request).events;

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    if (_disposed) {
      throw const BackendException('Local Android backend is disposed.');
    }
    if (request.cwd.startsWith('content://')) {
      throw const BackendException(
        'unsupported: SAF document trees provide file data only; '
        'Host execution requires a real host workspace path.',
      );
    }
    final controller = StreamController<ExecutionEvent>();
    String? processId;
    var cancelled = false;
    final started = Completer<String>();
    Future<void>? stopInFlight;

    Future<void> stopOperation() async {
      cancelled = true;
      final id = processId;
      try {
        if (id != null) {
          _executions.remove(id);
          await _channel.invokeMethod<void>(
            'stopHostProcess',
            <String, Object?>{'processId': id},
          );
        }
      } on PlatformException catch (error) {
        throw BackendException('${error.code}: ${error.message ?? error.code}');
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    Future<void> stop() {
      final existing = stopInFlight;
      if (existing != null) return existing;
      final operation = stopOperation();
      stopInFlight = operation;
      return operation;
    }

    // A subscription is a transport observer, not the session owner. In
    // particular, a parent-owned CC Pocket page may cancel its UI listener
    // while the session remains alive in the home-level runtime handle. Do
    // not let a listener cancellation kill the native process; every caller
    // that owns an execution already calls its explicit `stop()` method.
    _startExecution(
      request,
      controller,
      () => cancelled,
      (id) {
        processId = id;
        if (!started.isCompleted) started.complete(id);
      },
      started,
      stop,
    );
    return _LocalInteractiveExecution(
      events: controller.stream,
      write: (value) async {
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        final id = processId ?? await started.future;
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        try {
          await _channel.invokeMethod<void>(
            'writeHostProcess',
            <String, Object?>{'processId': id, 'value': value},
          );
        } on PlatformException catch (error) {
          throw BackendException(
            '${error.code}: ${error.message ?? error.code}',
          );
        }
      },
      closeStdin: () async {
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        final id = processId ?? await started.future;
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        try {
          await _channel.invokeMethod<void>(
            'closeHostProcessStdin',
            <String, Object?>{'processId': id},
          );
        } on PlatformException catch (error) {
          throw BackendException(
            '${error.code}: ${error.message ?? error.code}',
          );
        }
      },
      stop: stop,
    );
  }

  Future<void> _startExecution(
    ExecutionRequest request,
    StreamController<ExecutionEvent> controller,
    bool Function() isCancelled,
    void Function(String id) setProcessId,
    Completer<String> started,
    Future<void> Function() stop,
  ) async {
    String? processId;
    try {
      final id = await _channel.invokeMethod<String>(
        'startHostProcess',
        <String, Object?>{
          'argv': request.argv,
          'cwd': request.cwd,
          'identity': request.identity.name,
          'timeoutMs': request.timeout.inMilliseconds,
          'environment': request.environment,
        },
      );
      if (id == null) {
        throw const BackendException('Local backend returned no process id.');
      }
      processId = id;
      setProcessId(id);
      if (_disposed) {
        await _channel.invokeMethod<void>('stopHostProcess', <String, Object?>{
          'processId': id,
        });
        throw const BackendException('Local Android backend is disposed.');
      }
      if (isCancelled()) {
        await stop();
        if (!controller.isClosed) await controller.close();
        return;
      }
      _executions[id] = controller;
      await _channel.invokeMethod<void>('attachHostProcess', <String, Object?>{
        'processId': id,
      });
    } catch (error, stackTrace) {
      if (processId != null) {
        _executions.remove(processId);
        await stop();
      }
      if (!started.isCompleted) {
        started.completeError(_backendError(error), stackTrace);
      }
      if (!controller.isClosed) {
        controller.addError(_backendError(error), stackTrace);
        await controller.close();
      }
    }
  }

  void _handleHostEvent(Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final processId = raw['processId'] as String?;
    final type = raw['type'] as String?;
    final controller = processId == null ? null : _executions[processId];
    if (controller == null || type == null || controller.isClosed) return;
    switch (type) {
      case 'stdout':
        controller.add(ExecutionEvent.stdout(raw['value'] as String? ?? ''));
      case 'stderr':
        controller.add(ExecutionEvent.stderr(raw['value'] as String? ?? ''));
      case 'error':
        controller.add(ExecutionEvent.error(raw['value'] as String? ?? ''));
      case 'exit':
        controller.add(
          ExecutionEvent.exit((raw['exitCode'] as num?)?.toInt() ?? -1),
        );
        _executions.remove(processId);
        controller.close();
    }
  }

  BackendException _backendError(Object error) {
    if (error is PlatformException) {
      return BackendException('${error.code}: ${error.message ?? error.code}');
    }
    if (error is BackendException) return error;
    return BackendException('$error');
  }

  Future<List<WorkspaceEntry>> _listDirectory(String relativePath) async {
    _validateRelativePath(relativePath, allowEmpty: true);
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listHostDirectory',
        <String, Object?>{'relativePath': relativePath},
      );
      return (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(_entryFromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('Local Android backend is unavailable.');
    }
  }

  Future<List<WorkspaceEntry>> _listSafDirectory(
    String uri,
    String relativePath,
  ) async {
    _validateRelativePath(relativePath, allowEmpty: true);
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listSafDirectory',
        <String, Object?>{'uri': uri, 'relativePath': relativePath},
      );
      return (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(_entryFromMap)
          .toList(growable: false);
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const BackendException('SAF workspace support is unavailable.');
    }
  }

  Future<List<WorkspaceRef>> _listSafWorkspaces() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listSafWorkspaces',
      );
      return (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(_safWorkspaceFromMap)
          .toList(growable: false);
    } on MissingPluginException {
      return const <WorkspaceRef>[];
    } on PlatformException catch (error) {
      throw BackendException('${error.code}: ${error.message ?? error.code}');
    }
  }

  WorkspaceEntry _entryFromMap(Map<Object?, Object?> value) {
    return WorkspaceEntry(
      name: value['name'] as String? ?? '<invalid>',
      relativePath: value['relativePath'] as String? ?? '',
      isDirectory: value['isDirectory'] as bool? ?? false,
      sizeBytes: (value['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  TextFileSnapshot _snapshotFromMap(Map<Object?, Object?> value) {
    final content = value['content'] as String?;
    final version = value['version'] as String?;
    if (content == null || version == null) {
      throw const BackendException(
        'Local backend returned an invalid snapshot.',
      );
    }
    return TextFileSnapshot(
      relativePath: value['relativePath'] as String? ?? '',
      content: content,
      version: version,
      sizeBytes: (value['sizeBytes'] as num?)?.toInt() ?? content.length,
      uid: (value['uid'] as num?)?.toInt(),
      gid: (value['gid'] as num?)?.toInt(),
      mode: value['mode'] as String?,
      isSymbolicLink: value['isSymbolicLink'] as bool? ?? false,
    );
  }

  WriteReceipt _receiptFromMap(Map<Object?, Object?> value) {
    final backupId = value['backupId'] as String?;
    final relativePath = value['relativePath'] as String?;
    final beforeVersion = value['beforeVersion'] as String?;
    final afterVersion = value['afterVersion'] as String?;
    if (backupId == null ||
        relativePath == null ||
        beforeVersion == null ||
        afterVersion == null) {
      throw const BackendException(
        'Local backend returned an invalid receipt.',
      );
    }
    return WriteReceipt(
      backupId: backupId,
      relativePath: relativePath,
      beforeVersion: beforeVersion,
      afterVersion: afterVersion,
      restored: value['restored'] as bool? ?? false,
    );
  }

  LocalBackupRecord _backupFromMap(Map<Object?, Object?> value) {
    final backupId = value['backupId'] as String?;
    final kind = value['kind'] as String? ?? 'invalid';
    final relativePath = value['relativePath'] as String? ?? '';
    final valid = value['valid'] as bool? ?? false;
    final reason = value['reason'] as String?;
    final createdAtMs = (value['createdAtMs'] as num?)?.toInt() ?? 0;
    final sizeBytes = (value['sizeBytes'] as num?)?.toInt() ?? 0;
    if (backupId == null || backupId.isEmpty) {
      throw const BackendException(
        'Local backend returned an invalid backup id.',
      );
    }
    if (!valid) {
      return LocalBackupRecord(
        backupId: backupId,
        kind: kind,
        relativePath: relativePath,
        sizeBytes: sizeBytes,
        createdAtMs: createdAtMs,
        reason: reason ?? 'invalid backup metadata',
      );
    }
    final WorkspaceRef workspace;
    if (kind == 'host') {
      final path = value['workspacePath'] as String?;
      if (path == null || !path.startsWith('$_workspaceRoot/')) {
        throw const BackendException(
          'Local backend returned an invalid Host backup.',
        );
      }
      final relativeWorkspace = path.substring('$_workspaceRoot/'.length);
      workspace = WorkspaceRef(
        backendId: descriptor.id,
        filesystemOwnerId: 'android-host',
        displayPath: path,
        hostPath: path,
        backendLocator: 'host://$relativeWorkspace',
      );
    } else if (kind == 'saf') {
      final uri = value['workspaceUri'] as String?;
      if (uri == null || !uri.startsWith('content://')) {
        throw const BackendException(
          'Local backend returned an invalid SAF backup.',
        );
      }
      workspace = WorkspaceRef(
        backendId: descriptor.id,
        filesystemOwnerId: 'android-saf',
        displayPath: 'SAF: $uri',
        hostPath: uri,
        backendLocator: 'saf://$uri',
      );
    } else {
      throw const BackendException(
        'Local backend returned an unknown backup kind.',
      );
    }
    return LocalBackupRecord(
      backupId: backupId,
      kind: kind,
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      createdAtMs: createdAtMs,
      workspace: workspace,
      version: value['version'] as String? ?? '',
      reason: reason,
    );
  }

  WorkspaceRef _safWorkspaceFromMap(Map<Object?, Object?> value) {
    final uri = value['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw const BackendException(
        'Local backend returned an invalid SAF URI.',
      );
    }
    final name = value['name'] as String? ?? uri;
    final displayPath = value['displayPath'] as String? ?? 'SAF: $name';
    final owner = value['filesystemOwnerId'] as String? ?? 'android-saf';
    return WorkspaceRef(
      backendId: descriptor.id,
      filesystemOwnerId: owner,
      displayPath: displayPath,
      hostPath: uri,
      backendLocator: 'saf://$uri',
    );
  }

  String _relativeWorkspacePath(WorkspaceRef workspace) {
    if (workspace.backendId != descriptor.id ||
        !workspace.displayPath.startsWith('$_workspaceRoot/')) {
      throw const BackendException('Workspace is not owned by Local Android.');
    }
    return workspace.displayPath.substring('$_workspaceRoot/'.length);
  }

  static String _normalizeWorkspaceName(String value) {
    final name = value.trim();
    if (name.isEmpty || name == '.' || name == '..') {
      throw const BackendException('A workspace folder name is required.');
    }
    if (name.length > 80 ||
        name.contains('/') ||
        name.contains('\\') ||
        name.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw const BackendException(
        'Workspace name must be one safe directory name.',
      );
    }
    return name;
  }

  static bool _isSafWorkspace(WorkspaceRef workspace) =>
      workspace.filesystemOwnerId.startsWith('android-saf');

  static void _validateRelativePath(String value, {required bool allowEmpty}) {
    if (!allowEmpty && value.isEmpty) {
      throw const BackendException('A relative path is required.');
    }
    if (value.isEmpty) {
      return;
    }
    if (value.startsWith('/') || value.endsWith('/') || value.contains('\\')) {
      throw const BackendException(
        'Path must be relative and slash-normalized.',
      );
    }
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw const BackendException('Path traversal is not allowed.');
      }
      if (segment.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
        throw const BackendException('Control characters are not allowed.');
      }
    }
  }
}

class _LocalInteractiveExecution
    implements InteractiveExecution, StdinClosableExecution {
  _LocalInteractiveExecution({
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
