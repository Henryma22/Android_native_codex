import 'change_set.dart';
import 'execution.dart';
import 'workspace.dart';

/// The environments that can own a Codex workspace.
enum BackendKind { localAndroid, linuxCompatibility, fake }

/// A deliberately small health vocabulary for the UI boundary.
enum BackendHealth { unavailable, available, verified, failed }

/// A capability is reported as evidence, rather than as one overloaded flag.
class CapabilitySnapshot {
  const CapabilitySnapshot({
    required this.supported,
    required this.available,
    required this.verified,
    this.managedChangesSupported = true,
    this.blocked = false,
    this.failed = false,
    this.reason,
  });

  final bool supported;
  final bool available;
  final bool verified;

  /// Whether the backend exposes approval-gated, versioned text changes.
  final bool managedChangesSupported;
  final bool blocked;
  final bool failed;
  final String? reason;

  bool get usable => supported && available && verified && !blocked && !failed;
}

class BackendDescriptor {
  const BackendDescriptor({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.version,
    required this.health,
    required this.capabilities,
  });

  final String id;
  final BackendKind kind;
  final String displayName;
  final String version;
  final BackendHealth health;
  final CapabilitySnapshot capabilities;

  String get healthLabel {
    switch (health) {
      case BackendHealth.unavailable:
        return 'Unavailable';
      case BackendHealth.available:
        return 'Available';
      case BackendHealth.verified:
        return 'Verified';
      case BackendHealth.failed:
        return 'Failed';
    }
  }
}

/// The only contract the UI uses to reach an execution environment.
abstract interface class Backend {
  BackendDescriptor get descriptor;

  Future<List<WorkspaceRef>> listWorkspaces();

  Future<WorkspaceHandle> openWorkspace(WorkspaceRef workspace);

  Future<List<WorkspaceEntry>> listDirectory(
    WorkspaceHandle workspace, {
    String relativePath = '',
  });

  Future<TextFileSnapshot> snapshotText(
    WorkspaceHandle workspace,
    String relativePath,
  );

  Future<String> readText(WorkspaceHandle workspace, String relativePath);

  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  });

  /// Creates a recoverable pre-change backup without changing file contents.
  Future<WriteReceipt> backupText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
  });

  Future<WriteReceipt> restoreText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String backupId,
    required String expectedVersion,
  });

  Stream<ExecutionEvent> execute(ExecutionRequest request);

  InteractiveExecution startInteractive(ExecutionRequest request);
}

class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => 'BackendException: $message';
}
