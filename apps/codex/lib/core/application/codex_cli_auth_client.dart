import 'dart:async';

import '../domain/backend.dart';
import '../domain/execution.dart';
import '../domain/workspace.dart';
import 'codex_auth_client.dart';

/// Owns the official CLI login process used by the local Android app.
///
/// Session turns still use app-server, but authentication deliberately uses
/// the same `codex login` commands as the CLI and the original CC Pocket
/// local-runtime implementation. This matters for browser OAuth: the CLI
/// owns the localhost callback server for the whole browser flow. API keys
/// are sent through stdin and never appear in argv, environment, or events.
class CodexCliAuthClient implements CodexLoginClient {
  CodexCliAuthClient({
    required Backend backend,
    required WorkspaceRef workspace,
    required String command,
    required ExecutionIdentity identity,
    Map<String, String> environment = const <String, String>{},
    AuthInteractiveExecutionFactory? processFactory,
  }) : _backend = backend,
       _workspace = workspace,
       _command = command,
       _identity = identity,
       _environment = Map<String, String>.unmodifiable(environment),
       _processFactory = processFactory;

  final Backend _backend;
  final WorkspaceRef _workspace;
  final String _command;
  final ExecutionIdentity _identity;
  final Map<String, String> _environment;
  final AuthInteractiveExecutionFactory? _processFactory;
  final StreamController<CodexAuthEvent> _events =
      StreamController<CodexAuthEvent>.broadcast();

  InteractiveExecution? _process;
  StreamSubscription<ExecutionEvent>? _subscription;
  CodexAuthMode? _mode;
  String _output = '';
  CodexAuthChallenge? _lastChallenge;
  bool _processExited = false;
  bool _exitEventEmitted = false;
  bool _stopped = false;
  bool _disposed = false;

  Stream<CodexAuthEvent> get events => _events.stream;

  /// The CLI process, rather than an app-server RPC, is the source of truth.
  /// A completion event is emitted when the CLI exits and the settings page
  /// then performs the bounded `codex login status` settle check.
  bool get isLoginPending =>
      _process != null && !_processExited && !_stopped && !_exitEventEmitted;

  /// Kept for the shared settings controller. CLI login has no app-server
  /// account/read endpoint; completion is observed from the owned process and
  /// confirmed by the caller's normal `codex login status` probe.
  Future<CodexAuthMode?> readAccount() async => null;

  Future<void> start({
    CodexAuthMode mode = CodexAuthMode.deviceAuth,
    String? apiKey,
  }) async {
    if (_disposed) throw StateError('auth client is disposed');
    if (_process != null && !_stopped) return;
    if (mode == CodexAuthMode.apiKey && apiKey?.trim().isEmpty != false) {
      throw StateError('API key is required for API key login.');
    }

    _mode = mode;
    _output = '';
    _lastChallenge = null;
    _processExited = false;
    _exitEventEmitted = false;
    _stopped = false;
    _emit(const CodexAuthEvent(type: CodexAuthEventType.status));

    try {
      final workspace = await _backend.openWorkspace(_workspace);
      final process =
          _processFactory?.call(workspace) ??
          _backend.startInteractive(
            ExecutionRequest(
              argv: <String>[
                _command,
                'login',
                if (mode == CodexAuthMode.deviceAuth) '--device-auth',
                if (mode == CodexAuthMode.apiKey) '--with-api-key',
              ],
              cwd: workspace.ref.hostPath,
              identity: _identity,
              timeout: const Duration(hours: 1),
              environment: _environment,
            ),
          );
      _process = process;
      _subscription = process.events.listen(
        _handleEvent,
        onError: (Object error) {
          _fail('Codex login process failed.');
        },
      );

      if (mode == CodexAuthMode.apiKey) {
        // The key is intentionally written only after the process has been
        // created. It is never included in argv or any diagnostic event.
        await process.write('${apiKey!.trim()}\n');
        // The official CLI uses read_to_string() for --with-api-key. Merely
        // writing a newline leaves the Android pipe open and makes the CLI
        // wait forever for EOF, so close only stdin and keep stdout/stderr
        // attached for the normal completion event.
        if (process is! StdinClosableExecution) {
          throw StateError(
            'The selected local runtime cannot close login stdin.',
          );
        }
        await (process as StdinClosableExecution).closeStdin();
      }
    } catch (error) {
      _stopped = true;
      _emit(
        CodexAuthEvent(
          type: CodexAuthEventType.error,
          message: _safeStartError(error),
        ),
      );
      rethrow;
    }
  }

  Future<void> stop() async {
    final wasStopped = _stopped;
    final emitStopped = !wasStopped && !_processExited && !_exitEventEmitted;
    _stopped = true;
    _processExited = true;
    final subscription = _subscription;
    _subscription = null;
    final process = _process;
    _process = null;
    try {
      await process?.stop();
    } finally {
      await subscription?.cancel();
      if (emitStopped) {
        _emit(const CodexAuthEvent(type: CodexAuthEventType.stopped));
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _events.close();
  }

  void _handleEvent(ExecutionEvent event) {
    if (event.stdout != null) _consumeOutput(event.stdout!);
    if (event.stderr != null) _consumeOutput(event.stderr!);
    if (event.error != null && !_stopped) {
      _fail('Codex login process failed.');
    }
    final exitCode = event.exitCode;
    if (exitCode == null || _stopped) return;
    _processExited = true;
    if (exitCode == 0) {
      _emitExit(0, 'Login process completed; checking Codex status.');
    } else {
      _fail(_failureMessage(exitCode));
    }
  }

  void _consumeOutput(String chunk) {
    if (chunk.isEmpty) return;
    _output += chunk;
    if (_output.length > 32768) {
      _output = _output.substring(_output.length - 32768);
    }
    final challenge = CodexAuthOutputParser.parse(_output);
    if (challenge == null || challenge == _lastChallenge) return;
    if (_mode == CodexAuthMode.apiKey) return;
    _lastChallenge = challenge;
    _emit(
      CodexAuthEvent(
        type: CodexAuthEventType.challenge,
        challenge: challenge,
        message: _mode == CodexAuthMode.browser
            ? 'Browser authorization is waiting for completion.'
            : 'Device authorization is waiting for completion.',
      ),
    );
  }

  void _fail(String message) {
    if (_stopped || _exitEventEmitted) return;
    _processExited = true;
    _emit(CodexAuthEvent(type: CodexAuthEventType.error, message: message));
  }

  String _failureMessage(int exitCode) {
    final normalized = _output.toLowerCase();
    if (_mode == CodexAuthMode.apiKey &&
        (normalized.contains('invalid api key') ||
            normalized.contains('incorrect api key') ||
            normalized.contains('api key is invalid'))) {
      return 'Codex rejected the API key.';
    }
    if (normalized.contains('network') ||
        normalized.contains('request failed') ||
        normalized.contains('connection')) {
      return 'Codex could not reach the OpenAI authentication service.';
    }
    final detail = _safeFailureDetail(_output);
    final base =
        'Codex ${_mode?.displayName ?? 'login'} failed (exit code $exitCode).';
    return detail == null ? base : '$base $detail';
  }

  /// Keep the real CLI failure useful without exposing OAuth material. The
  /// CLI writes its actionable error to stderr; previously that output was
  /// retained only in memory and every native failure became the same opaque
  /// exit-code message.
  static String? _safeFailureDetail(String output) {
    final lines = output
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_redactSensitiveLoginData)
        .where(
          (line) =>
              line.contains('panicked') ||
              line.contains('Error logging in') ||
              line.contains('error') ||
              line.contains('Error') ||
              line.contains('failed') ||
              line.contains('Failed') ||
              line.contains('permission') ||
              line.contains('Permission') ||
              line.contains('address') ||
              line.contains('Address') ||
              line.contains('os error'),
        )
        .take(2)
        .toList(growable: false);
    if (lines.isEmpty) return null;
    return 'Details: ${lines.join(' | ')}';
  }

  static String _redactSensitiveLoginData(String line) {
    return line
        .replaceAll(
          RegExp(r'https://auth\.openai\.com[^\s]*'),
          'https://auth.openai.com/<redacted>',
        )
        .replaceAll(
          RegExp(r'http://localhost:\d+[^\s]*'),
          'http://localhost:<redacted>',
        )
        .replaceAll(
          RegExp(
            r'(code|state|access_token|refresh_token|api_key)=([^&\s]+)',
            caseSensitive: false,
          ),
          r'\$1=<redacted>',
        );
  }

  static String _safeStartError(Object error) {
    if (error is BackendException) return error.message;
    if (error is StateError && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return 'Could not start the Codex login process.';
  }

  void _emitExit(int exitCode, String message) {
    if (_exitEventEmitted) return;
    _exitEventEmitted = true;
    _emit(
      CodexAuthEvent(
        type: CodexAuthEventType.exit,
        exitCode: exitCode,
        message: message,
      ),
    );
  }

  void _emit(CodexAuthEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
