enum ExecutionIdentity { app, root }

class ExecutionRequest {
  ExecutionRequest({
    required Iterable<String> argv,
    required this.cwd,
    this.identity = ExecutionIdentity.app,
    this.timeout = const Duration(minutes: 2),
    Map<String, String> environment = const <String, String>{},
  }) : argv = List<String>.unmodifiable(argv),
       environment = Map<String, String>.unmodifiable(environment);

  final List<String> argv;

  /// A canonical host path owned by the selected workspace.
  final String cwd;
  final ExecutionIdentity identity;
  final Duration timeout;
  final Map<String, String> environment;
}

class ExecutionEvent {
  const ExecutionEvent._({this.stdout, this.stderr, this.error, this.exitCode});

  const ExecutionEvent.stdout(String value) : this._(stdout: value);

  const ExecutionEvent.stderr(String value) : this._(stderr: value);

  const ExecutionEvent.error(String value) : this._(error: value);

  const ExecutionEvent.exit(int code) : this._(exitCode: code);

  final String? stdout;
  final String? stderr;
  final String? error;
  final int? exitCode;

  bool get isTerminal => exitCode != null;
}

/// A bidirectional process boundary used by protocols such as Codex
/// app-server. The caller still writes framed data explicitly; it never gets
/// a shell or an arbitrary Android service handle.
abstract interface class InteractiveExecution {
  Stream<ExecutionEvent> get events;

  Future<void> write(String value);

  Future<void> stop();
}

/// Optional process capability for one-shot commands that need stdin EOF.
///
/// Keeping this separate from [InteractiveExecution] means existing JSONL
/// protocol fixtures and clients do not have to fake a half-close operation;
/// Android's native and Linux-compatibility process wrappers implement it.
abstract interface class StdinClosableExecution {
  /// Closes the child process' stdin without terminating the process.
  Future<void> closeStdin();
}
