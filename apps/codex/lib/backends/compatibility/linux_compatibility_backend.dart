import '../../core/domain/backend.dart';
import '../../core/domain/change_set.dart';
import '../../core/domain/execution.dart';
import '../../core/domain/workspace.dart';

enum CompatibilityRuntimeState { missing, available, verified, failed }

class CompatibilityRuntimeDescriptor {
  const CompatibilityRuntimeDescriptor({
    required this.state,
    required this.version,
    this.rootfsDigest,
    this.maintenanceCwd,
    this.reason,
  });

  const CompatibilityRuntimeDescriptor.missing({String? reason})
    : this(
        state: CompatibilityRuntimeState.missing,
        version: null,
        maintenanceCwd: null,
        reason:
            reason ?? 'No verified Linux compatibility rootfs is installed.',
      );

  final CompatibilityRuntimeState state;
  final String? version;
  final String? rootfsDigest;

  /// App-private cwd for runtime maintenance commands such as CLI updates.
  /// It is never exposed as a user workspace or used for Codex sessions.
  final String? maintenanceCwd;
  final String? reason;

  factory CompatibilityRuntimeDescriptor.fromMap(Map<Object?, Object?> value) {
    final state = switch (value['state']) {
      'available' => CompatibilityRuntimeState.available,
      'verified' => CompatibilityRuntimeState.verified,
      'failed' => CompatibilityRuntimeState.failed,
      _ => CompatibilityRuntimeState.missing,
    };
    String? text(Object? field) =>
        field is String && field.isNotEmpty ? field : null;
    return CompatibilityRuntimeDescriptor(
      state: state,
      version: text(value['version']),
      rootfsDigest: text(value['rootfsDigest']),
      maintenanceCwd: text(value['maintenanceCwd']),
      reason: text(value['reason']),
    );
  }

  bool get usable => state == CompatibilityRuntimeState.verified;

  String get label {
    switch (state) {
      case CompatibilityRuntimeState.missing:
        return 'Missing';
      case CompatibilityRuntimeState.available:
        return 'Available';
      case CompatibilityRuntimeState.verified:
        return 'Verified';
      case CompatibilityRuntimeState.failed:
        return 'Failed';
    }
  }
}

/// The native boundary for an optional Linux/PRoot runtime.
///
/// A runtime must prove its rootfs and host-workspace mapping before this
/// backend will turn a host ExecutionRequest into a guest request. The
/// [UnavailableCompatibilityRuntime] fallback is used only by tests or
/// callers that intentionally construct this backend without the Android
/// channel client; the device selector injects the connected runtime client.
abstract interface class CompatibilityRuntimeClient {
  CompatibilityRuntimeDescriptor get descriptor;

  Future<CompatibilityRuntimeDescriptor> probe();

  void acceptProbeResult(CompatibilityRuntimeDescriptor descriptor);

  String mapHostPath(String hostPath);

  Stream<ExecutionEvent> execute(ExecutionRequest request);

  InteractiveExecution startInteractive(ExecutionRequest request);
}

class UnavailableCompatibilityRuntime implements CompatibilityRuntimeClient {
  const UnavailableCompatibilityRuntime();

  static const _message =
      'Linux compatibility runtime is unavailable; install and verify a '
      'rootfs before starting a guest process.';

  @override
  CompatibilityRuntimeDescriptor get descriptor =>
      const CompatibilityRuntimeDescriptor.missing();

  @override
  Future<CompatibilityRuntimeDescriptor> probe() async => descriptor;

  @override
  void acceptProbeResult(CompatibilityRuntimeDescriptor descriptor) {}

  @override
  String mapHostPath(String hostPath) => throw const BackendException(_message);

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) =>
      throw const BackendException(_message);

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) =>
      throw const BackendException(_message);
}

/// A compatibility execution view over the same Local Android host files.
///
/// File reads, snapshots, backups, writes, and restores are delegated to the
/// Local backend. Only process execution crosses the compatibility runtime
/// boundary. This prevents a guest rootfs from silently becoming a second
/// workspace owner; a requested Root identity is still enforced by the
/// native KernelSU gate and must not be implemented by PRoot fake-root alone.
class LinuxCompatibilityBackend implements Backend {
  LinuxCompatibilityBackend(
    this._hostBackend, {
    CompatibilityRuntimeClient? runtime,
  }) : _runtime = runtime ?? const UnavailableCompatibilityRuntime();

  static const id = 'linux-compatibility';
  static const _hostRoot = '/storage/emulated/0/Codex/Workspaces';

  final Backend _hostBackend;
  final CompatibilityRuntimeClient _runtime;
  CompatibilityRuntimeDescriptor? _probedDescriptor;

  CompatibilityRuntimeDescriptor get runtimeProbeResult =>
      _probedDescriptor ?? _runtime.descriptor;

  @override
  BackendDescriptor get descriptor {
    final runtime = _probedDescriptor ?? _runtime.descriptor;
    final state = runtime.state;
    final health = switch (state) {
      CompatibilityRuntimeState.missing => BackendHealth.unavailable,
      CompatibilityRuntimeState.available => BackendHealth.available,
      CompatibilityRuntimeState.verified => BackendHealth.verified,
      CompatibilityRuntimeState.failed => BackendHealth.failed,
    };
    return BackendDescriptor(
      id: id,
      kind: BackendKind.linuxCompatibility,
      displayName: 'Linux Compatibility (PRoot)',
      version: runtime.version ?? 'not-installed',
      health: health,
      capabilities: CapabilitySnapshot(
        supported: true,
        available:
            state == CompatibilityRuntimeState.available ||
            state == CompatibilityRuntimeState.verified,
        verified: runtime.usable,
        failed: state == CompatibilityRuntimeState.failed,
        reason:
            runtime.reason ??
            (runtime.usable
                ? 'Guest execution is verified; files remain owned by Android host.'
                : 'Guest execution is disabled until the runtime is verified.'),
      ),
    );
  }

  Future<CompatibilityRuntimeDescriptor> refresh() async {
    final descriptor = await _runtime.probe();
    _probedDescriptor = descriptor;
    return descriptor;
  }

  void acceptRuntimeProbe(CompatibilityRuntimeDescriptor descriptor) {
    _probedDescriptor = descriptor;
    _runtime.acceptProbeResult(descriptor);
  }

  @override
  Future<List<WorkspaceRef>> listWorkspaces() async {
    final workspaces = await _hostBackend.listWorkspaces();
    return List<WorkspaceRef>.unmodifiable(
      workspaces.where(_isDirectHostWorkspace).map(_toCompatibilityWorkspace),
    );
  }

  @override
  Future<WorkspaceHandle> openWorkspace(WorkspaceRef workspace) async {
    if (_isRuntimeMaintenanceWorkspace(workspace)) {
      return WorkspaceHandle(workspace);
    }
    _requireWorkspace(workspace);
    await _hostBackend.openWorkspace(_toHostWorkspace(workspace));
    return WorkspaceHandle(workspace);
  }

  /// Returns the hidden app-private cwd for runtime maintenance operations.
  ///
  /// CLI/rootfs updates are independent from user workspaces. The native
  /// runtime creates and validates this directory as part of its probe; it is
  /// never returned from [listWorkspaces] and must not be used for a session.
  WorkspaceRef runtimeMaintenanceWorkspace() {
    final path = (_probedDescriptor ?? _runtime.descriptor).maintenanceCwd;
    if (path == null || path.trim().isEmpty) {
      throw const BackendException(
        'Linux compatibility runtime did not expose an app-private maintenance directory.',
      );
    }
    return WorkspaceRef(
      backendId: id,
      filesystemOwnerId: 'compatibility-runtime',
      displayPath: 'Android Codex runtime',
      hostPath: path,
      backendLocator: 'runtime://maintenance',
    );
  }

  @override
  Future<List<WorkspaceEntry>> listDirectory(
    WorkspaceHandle workspace, {
    String relativePath = '',
  }) => _hostBackend.listDirectory(
    _toHostHandle(workspace),
    relativePath: relativePath,
  );

  @override
  Future<TextFileSnapshot> snapshotText(
    WorkspaceHandle workspace,
    String relativePath,
  ) => _hostBackend.snapshotText(_toHostHandle(workspace), relativePath);

  @override
  Future<String> readText(WorkspaceHandle workspace, String relativePath) =>
      _hostBackend.readText(_toHostHandle(workspace), relativePath);

  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) => _hostBackend.writeText(
    _toHostHandle(workspace),
    relativePath,
    expectedVersion: expectedVersion,
    content: content,
  );

  @override
  Future<WriteReceipt> backupText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
  }) => _hostBackend.backupText(
    _toHostHandle(workspace),
    relativePath,
    expectedVersion: expectedVersion,
  );

  @override
  Future<WriteReceipt> restoreText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String backupId,
    required String expectedVersion,
  }) => _hostBackend.restoreText(
    _toHostHandle(workspace),
    relativePath,
    backupId: backupId,
    expectedVersion: expectedVersion,
  );

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) {
    return _runtime.execute(_guestRequest(request));
  }

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    return _runtime.startInteractive(_guestRequest(request));
  }

  ExecutionRequest _guestRequest(ExecutionRequest request) {
    if (!_isSafeExecutionPath(request.cwd)) {
      throw const BackendException(
        'Compatibility execution cwd must remain inside the fixed host workspace or app-private runtime directory.',
      );
    }
    final runtime = _probedDescriptor ?? _runtime.descriptor;
    if (!runtime.usable) {
      throw BackendException(
        runtime.reason ?? 'Linux compatibility runtime is not verified.',
      );
    }
    return ExecutionRequest(
      argv: request.argv,
      cwd: _runtime.mapHostPath(request.cwd),
      identity: request.identity,
      timeout: request.timeout,
      environment: request.environment,
    );
  }

  void _requireWorkspace(WorkspaceRef workspace) {
    if (workspace.backendId != id || !_isDirectHostWorkspace(workspace)) {
      throw const BackendException(
        'Linux compatibility only supports direct Android host workspaces.',
      );
    }
  }

  bool _isRuntimeMaintenanceWorkspace(WorkspaceRef workspace) {
    final maintenance =
        (_probedDescriptor ?? _runtime.descriptor).maintenanceCwd;
    return workspace.backendId == id &&
        workspace.filesystemOwnerId == 'compatibility-runtime' &&
        maintenance != null &&
        workspace.hostPath == maintenance &&
        workspace.backendLocator == 'runtime://maintenance';
  }

  bool _isSafeExecutionPath(String path) {
    if (_isSafeHostPath(path)) return true;
    final maintenance =
        (_probedDescriptor ?? _runtime.descriptor).maintenanceCwd;
    if (maintenance == null || path != maintenance) return false;
    return path.startsWith('/') &&
        !path.contains('\u0000') &&
        !path.contains('\r') &&
        !path.contains('\n') &&
        path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .every((segment) => segment != '.' && segment != '..');
  }

  WorkspaceHandle _toHostHandle(WorkspaceHandle workspace) {
    _requireWorkspace(workspace.ref);
    return WorkspaceHandle(_toHostWorkspace(workspace.ref));
  }

  WorkspaceRef _toHostWorkspace(WorkspaceRef workspace) {
    _requireWorkspace(workspace);
    return WorkspaceRef(
      backendId: _hostBackend.descriptor.id,
      filesystemOwnerId: workspace.filesystemOwnerId,
      displayPath: workspace.displayPath,
      hostPath: workspace.hostPath,
      backendLocator: workspace.backendLocator,
    );
  }

  static bool _isDirectHostWorkspace(WorkspaceRef workspace) {
    return workspace.hostPath.startsWith('$_hostRoot/') &&
        _isSafeHostPath(workspace.hostPath);
  }

  static bool _isSafeHostPath(String path) {
    if (!path.startsWith('$_hostRoot/')) return false;
    final relative = path.substring(_hostRoot.length + 1);
    if (relative.isEmpty) return false;
    final segments = relative.split('/');
    return segments.every(
      (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
    );
  }

  static WorkspaceRef _toCompatibilityWorkspace(WorkspaceRef workspace) {
    return WorkspaceRef(
      backendId: id,
      filesystemOwnerId: workspace.filesystemOwnerId,
      displayPath: workspace.displayPath,
      hostPath: workspace.hostPath,
      backendLocator: workspace.backendLocator,
    );
  }
}
