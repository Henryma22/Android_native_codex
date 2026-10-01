import 'dart:async';
import 'dart:convert';

import '../domain/backend.dart';
import '../domain/execution.dart';
import '../domain/workspace.dart';

typedef AuthInteractiveExecutionFactory = InteractiveExecution Function(
  WorkspaceHandle workspace,
);

class CodexAuthChallenge {
  const CodexAuthChallenge({this.verificationUrl, this.oneTimeCode});

  final String? verificationUrl;
  final String? oneTimeCode;

  bool get isEmpty => verificationUrl == null && oneTimeCode == null;

  @override
  bool operator ==(Object other) {
    return other is CodexAuthChallenge &&
        other.verificationUrl == verificationUrl &&
        other.oneTimeCode == oneTimeCode;
  }

  @override
  int get hashCode => Object.hash(verificationUrl, oneTimeCode);
}

/// Login modes exposed by the Codex CLI.
///
/// These values intentionally mirror the modes used by CC Pocket so the
/// independent Android client can reuse the same user-facing flow without
/// depending on network integration.
enum CodexAuthMode { deviceAuth, browser, apiKey }

extension CodexAuthModeWire on CodexAuthMode {
  String get wireValue => switch (this) {
    CodexAuthMode.deviceAuth => 'device-auth',
    CodexAuthMode.browser => 'browser',
    CodexAuthMode.apiKey => 'api-key',
  };

  String get displayName => switch (this) {
    CodexAuthMode.deviceAuth => 'Device code',
    CodexAuthMode.browser => 'Browser OAuth',
    CodexAuthMode.apiKey => 'API key',
  };
}

/// Parses only the user-facing device-auth challenge from bounded CLI output.
///
/// This parser deliberately rejects arbitrary URLs and generic `code` labels.
/// Authentication output is never returned to Flutter as a raw string.
class CodexAuthOutputParser {
  static final _urlPattern = RegExp(r'''https://[^\s<>"']+''');
  static final _labelledCodePattern = RegExp(
    r'(?:one[- ]time|device(?:[- ]login)?|verification|user)[- ]code\s*[:：]\s*([A-Z0-9][A-Z0-9-]{3,63})',
    caseSensitive: false,
  );
  static final _promptedCodePattern = RegExp(
    r'(?:enter|use|input|type)\s+(?:this\s+)?(?:one[- ]time\s+)?code\s*[:：]\s*([A-Z0-9][A-Z0-9-]{3,63})',
    caseSensitive: false,
  );
  static final _followingLineCodePattern = RegExp(
    r'(?:one[- ]time|device(?:[- ]login)?|verification|user)[- ]code[^\r\n]*\r?\n\s*([A-Z0-9][A-Z0-9-]{3,63})',
    caseSensitive: false,
  );

  static const _deviceQueryKeys = <String>{
    'device_code',
    'device_login_code',
    'one_time_code',
    'user_code',
    'verification_code',
  };

  static CodexAuthChallenge? parse(String output) {
    final normalized = _stripAnsi(output);
    Uri? acceptedUrl;
    for (final match in _urlPattern.allMatches(normalized)) {
      final candidate = match
          .group(0)
          ?.trim()
          .replaceFirst(RegExp(r'[.,;)\]]+$'), '');
      final uri = candidate == null ? null : Uri.tryParse(candidate);
      if (uri != null && _isAllowedAuthUrl(uri)) {
        acceptedUrl = uri;
        break;
      }
    }

    String? code;
    for (final pattern in <RegExp>[
      _labelledCodePattern,
      _promptedCodePattern,
      _followingLineCodePattern,
    ]) {
      code = pattern.firstMatch(normalized)?.group(1);
      if (_isPlausibleCode(code)) break;
      code = null;
    }
    code ??= _queryCode(acceptedUrl);

    if (acceptedUrl == null && code == null) return null;
    return CodexAuthChallenge(
      verificationUrl: acceptedUrl?.toString(),
      oneTimeCode: code,
    );
  }

  static String _stripAnsi(String value) {
    return value.replaceAll(RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~])'), '');
  }

  static bool _isAllowedDeviceUrl(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != 'auth.openai.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 && uri.port != 0 ||
        uri.fragment.isNotEmpty) {
      return false;
    }
    final path = uri.path.replaceFirst(RegExp(r'\/$'), '');
    if (path != '/device' && path != '/codex/device') return false;
    return uri.queryParameters.keys.every(_deviceQueryKeys.contains);
  }

  static bool _isAllowedAuthUrl(Uri uri) {
    return _isAllowedDeviceUrl(uri) || _isAllowedBrowserUrl(uri);
  }

  static bool _isAllowedBrowserUrl(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != 'auth.openai.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 && uri.port != 0 ||
        uri.path.replaceFirst(RegExp(r'\/$'), '') != '/oauth/authorize' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.isEmpty) {
      return false;
    }
    final parameters = uri.queryParameters;
    final redirect = Uri.tryParse(parameters['redirect_uri'] ?? '');
    return parameters['response_type'] == 'code' &&
        parameters['client_id']?.isNotEmpty == true &&
        parameters['scope']?.isNotEmpty == true &&
        parameters['code_challenge']?.isNotEmpty == true &&
        parameters['code_challenge_method'] == 'S256' &&
        parameters['state']?.isNotEmpty == true &&
        redirect != null &&
        redirect.scheme.toLowerCase() == 'http' &&
        redirect.host.toLowerCase() == 'localhost' &&
        redirect.hasPort &&
        redirect.port >= 1024 &&
        redirect.port <= 65535 &&
        redirect.path == '/auth/callback' &&
        redirect.userInfo.isEmpty &&
        !redirect.hasQuery &&
        redirect.fragment.isEmpty;
  }

  static String? _queryCode(Uri? uri) {
    if (uri == null) return null;
    for (final key in _deviceQueryKeys) {
      final value = uri.queryParameters[key];
      if (_isPlausibleCode(value)) return value;
    }
    return null;
  }

  static bool _isPlausibleCode(String? value) {
    if (value == null || value.length < 4 || value.length > 64) return false;
    return value.contains(RegExp(r'\d')) &&
        RegExp(r'^[A-Z0-9][A-Z0-9-]*$', caseSensitive: false).hasMatch(value);
  }
}

enum CodexAuthEventType { status, challenge, exit, error, stopped }

class CodexAuthEvent {
  const CodexAuthEvent({
    required this.type,
    this.challenge,
    this.exitCode,
    this.message,
  });

  final CodexAuthEventType type;
  final CodexAuthChallenge? challenge;
  final int? exitCode;
  final String? message;
}

/// Common lifecycle surface for the two official local login transports.
///
/// Browser OAuth uses app-server because it disables the CLI's Android-hostile
/// automatic browser opener. Device-code and API-key login continue to use the
/// interactive CLI process.
abstract interface class CodexLoginClient {
  Stream<CodexAuthEvent> get events;

  bool get isLoginPending;

  /// Reads persisted account state when the transport can do so without
  /// starting a second login flow. This lets the UI reconcile a browser
  /// callback when the process notification was delivered while Android was
  /// switching back from the external browser.
  Future<CodexAuthMode?> readAccount();

  Future<void> start({CodexAuthMode mode, String? apiKey});

  Future<void> stop();

  Future<void> dispose();
}

/// Owns one local Codex app-server login process.
///
/// Authentication uses the official `account/login/start` JSON-RPC contract.
/// This avoids terminal prompts and keeps browser OAuth completion inside the
/// same local app-server process that owns the callback listener.
class CodexAuthClient implements CodexLoginClient {
  CodexAuthClient({
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
  String _lineBuffer = '';
  int _nextRequestId = 1;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};
  String? _loginId;
  Map<String, dynamic>? _earlyLoginCompletion;
  CodexAuthMode? _mode;
  var _awaitingLoginCompletion = false;
  bool _exitEventEmitted = false;
  bool _stopped = false;
  bool _disposed = false;

  Stream<CodexAuthEvent> get events => _events.stream;

  bool get isLoginPending => _awaitingLoginCompletion;

  /// Reads the account owned by the same app-server process as the pending
  /// login. This is used as a bounded foreground/resume fallback when a
  /// browser callback completed but its notification was not delivered to
  /// Flutter.
  Future<CodexAuthMode?> readAccount() async {
    if (_process == null || _stopped) return null;
    final response = await _request('account/read', const <String, dynamic>{});
    final account = response['account'];
    if (account is! Map) return null;
    return switch (account['type']) {
      'apiKey' => CodexAuthMode.apiKey,
      'chatgpt' => CodexAuthMode.browser,
      _ => null,
    };
  }

  Future<void> start({
    CodexAuthMode mode = CodexAuthMode.deviceAuth,
    String? apiKey,
  }) async {
    if (_disposed) throw StateError('auth client is disposed');
    if (_process != null && !_stopped) return;
    if (mode == CodexAuthMode.apiKey && apiKey?.trim().isEmpty != false) {
      throw StateError('API key is required for API key login.');
    }
    _stopped = false;
    _lineBuffer = '';
    _nextRequestId = 1;
    _pendingRequests.clear();
    _loginId = null;
    _earlyLoginCompletion = null;
    _mode = mode;
    _awaitingLoginCompletion = false;
    _exitEventEmitted = false;
    _emit(const CodexAuthEvent(type: CodexAuthEventType.status));
    try {
      final workspace = await _backend.openWorkspace(_workspace);
      final process =
          _processFactory?.call(workspace) ??
          _backend.startInteractive(
            ExecutionRequest(
              argv: <String>[
                _command,
                '-c',
                'features.code_mode=false',
                '-c',
                'features.code_mode_only=false',
                '-c',
                'features.respect_system_proxy=true',
                '-c',
                'suppress_unstable_features_warning=true',
                'app-server',
                '--listen',
                'stdio://',
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
          _completePending(StateError('Login process failed.'));
          _emit(
            CodexAuthEvent(
              type: CodexAuthEventType.error,
              message: 'Login process failed.',
            ),
          );
        },
      );
      final params = switch (mode) {
        CodexAuthMode.deviceAuth => const <String, dynamic>{
          'type': 'chatgptDeviceCode',
        },
        CodexAuthMode.browser => const <String, dynamic>{
          'type': 'chatgpt',
          'codexStreamlinedLogin': false,
          'useHostedLoginSuccessPage': false,
        },
        CodexAuthMode.apiKey => <String, dynamic>{
          'type': 'apiKey',
          // The secret is sent only to the local app-server request. It is
          // never emitted as a Flutter event or written to session history.
          'apiKey': apiKey!.trim(),
        },
      };
      await _request('initialize', <String, dynamic>{
        'clientInfo': <String, String>{
          'name': 'codex-android',
          'version': '1.0.0',
          'title': 'Codex for Android',
        },
        'capabilities': <String, bool>{'experimentalApi': true},
      });
      await _notify('initialized', <String, dynamic>{});
      final response = await _request('account/login/start', params);
      _handleLoginStartResponse(response, mode);
      // API-key login can persist credentials synchronously. In that case the
      // server may write the start response and account/login/completed in one
      // stdout batch. The completion notification is buffered until the
      // response has armed the mode-specific correlation state above.
      final earlyCompletion = _earlyLoginCompletion;
      _earlyLoginCompletion = null;
      if (earlyCompletion != null) {
        _handleLoginCompleted(earlyCompletion);
      }
    } catch (error, stackTrace) {
      // A failed browser/API-key flow must not leave its app-server alive.
      // Otherwise a retry creates a second login process while the first one
      // still owns the same CODEX_HOME and localhost callback state.
      await _cleanupFailedStart();
      _completePending(error);
      _emit(
        CodexAuthEvent(
          type: CodexAuthEventType.error,
          message: _safeError(error),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _cleanupFailedStart() async {
    _stopped = true;
    _awaitingLoginCompletion = false;
    _earlyLoginCompletion = null;
    _loginId = null;
    final subscription = _subscription;
    _subscription = null;
    final process = _process;
    _process = null;
    _completePending(StateError('Login process stopped.'));
    await subscription?.cancel();
    await process?.stop();
  }

  Future<void> stop() async {
    final wasStopped = _stopped;
    final loginId = _loginId;
    if (!wasStopped && loginId != null) {
      // Keep the process writable until the cancel notification has been
      // queued.  Setting _stopped first silently dropped this RPC, which left
      // browser OAuth sessions running after the Flutter card was closed.
      try {
        await _notify('account/login/cancel', <String, dynamic>{
          'loginId': loginId,
        });
      } catch (_) {
        // The process may already have exited; teardown remains best effort.
      }
    }
    _stopped = true;
    _awaitingLoginCompletion = false;
    _earlyLoginCompletion = null;
    final cancelFuture = _subscription?.cancel();
    _subscription = null;
    final process = _process;
    _process = null;
    _completePending(StateError('Login process stopped.'));
    await process?.stop();
    await cancelFuture;
    if (!wasStopped) {
      _emit(const CodexAuthEvent(type: CodexAuthEventType.stopped));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _events.close();
  }

  void _handleEvent(ExecutionEvent event) {
    if (event.stdout != null) _consumeStdout(event.stdout!);
    if (event.error != null) {
      _completePending(StateError('Login process failed.'));
      _emit(
        CodexAuthEvent(
          type: CodexAuthEventType.error,
          message: 'Login process failed.',
        ),
      );
    }
    final exitCode = event.exitCode;
    if (exitCode != null) {
      _stopped = true;
      _completePending(
        StateError('Codex app-server exited with code $exitCode.'),
      );
      _emitExit(
        exitCode,
        exitCode == 0
            ? 'Login process completed.'
            : 'Login process exited with an error.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final requestId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests['$requestId'] = completer;
    try {
      final operation = () async {
        await _writeEnvelope(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': requestId,
          'method': method,
          'params': params,
        });
        return completer.future;
      }();
      return await operation.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove('$requestId');
          throw StateError('Codex login request timed out.');
        },
      );
    } catch (error, stackTrace) {
      _pendingRequests.remove('$requestId');
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  Future<void> _notify(String method, Map<String, dynamic> params) {
    return _writeEnvelope(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  Future<void> _writeEnvelope(Map<String, dynamic> envelope) async {
    final process = _process;
    if (process == null || _stopped) {
      throw StateError('Codex login process is not running.');
    }
    await process.write('${jsonEncode(envelope)}\n');
  }

  void _consumeStdout(String chunk) {
    _lineBuffer += chunk;
    while (true) {
      final newline = _lineBuffer.indexOf('\n');
      if (newline < 0) return;
      final line = _lineBuffer.substring(0, newline).trim();
      _lineBuffer = _lineBuffer.substring(newline + 1);
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) _handleEnvelope(decoded.cast<String, dynamic>());
      } catch (_) {
        // app-server stdout must be JSONL. Ignore malformed diagnostics and
        // keep the login surface fail-closed without exposing raw output.
      }
    }
  }

  void _handleEnvelope(Map<String, dynamic> envelope) {
    final method = envelope['method'];
    if (method is String) {
      if (method == 'account/login/completed') {
        final params = _asMap(envelope['params']);
        if (!_awaitingLoginCompletion) {
          _earlyLoginCompletion = params;
        } else {
          _handleLoginCompleted(params);
        }
      } else if (method == 'account/updated') {
        // Codex emits account/login/completed followed by account/updated on
        // a normal login. Some Android/PRoot combinations can deliver the
        // latter after the former has already been consumed, while older
        // servers may only surface the account update to this client. Once
        // account/login/start has armed the current flow, account/updated is
        // therefore a safe success signal. Do not buffer it before the start
        // response: app-server may publish the existing account during
        // initialize, which must not complete a new login attempt.
        if (_awaitingLoginCompletion) _completeSuccessfulLogin();
      } else if (method == 'currentTime/read') {
        unawaited(
          _writeEnvelope(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': envelope['id'],
            'result': <String, int>{
              'currentTimeAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
          }),
        );
      }
      return;
    }
    final id = envelope['id'];
    if (id == null) return;
    final pending = _pendingRequests.remove('$id');
    if (pending == null || pending.isCompleted) return;
    if (envelope['error'] != null) {
      pending.completeError(StateError(_safeRpcError(envelope['error'])));
      return;
    }
    pending.complete(_asMap(envelope['result']));
  }

  void _handleLoginStartResponse(
    Map<String, dynamic> response,
    CodexAuthMode mode,
  ) {
    final responseType = response['type'];
    switch (mode) {
      case CodexAuthMode.apiKey:
        if (responseType != 'apiKey') {
          throw StateError(
            'Codex returned an unexpected API key login response.',
          );
        }
        // The response only acknowledges account/login/start. Keep the local
        // app-server alive until it emits account/login/completed and
        // account/updated. Stopping immediately here races Codex's credential
        // persistence and makes API-key login appear to succeed while the
        // next status check still reports the previous account.
        _awaitingLoginCompletion = true;
        _emit(
          const CodexAuthEvent(
            type: CodexAuthEventType.status,
            message: 'API key accepted; waiting for Codex to finish login.',
          ),
        );
      case CodexAuthMode.browser:
        if (responseType != 'chatgpt') {
          throw StateError(
            'Codex returned an unexpected browser login response.',
          );
        }
        _awaitingLoginCompletion = true;
        final loginId = response['loginId'];
        final authUrl = response['authUrl'];
        if (loginId is! String || authUrl is! String) {
          throw StateError('Codex did not return a browser login URL.');
        }
        final challenge = CodexAuthOutputParser.parse(authUrl);
        if (challenge?.verificationUrl == null) {
          throw StateError('Codex returned an unverified browser login URL.');
        }
        _loginId = loginId;
        _emit(
          CodexAuthEvent(
            type: CodexAuthEventType.challenge,
            challenge: challenge,
            message: 'Browser authorization is waiting for completion.',
          ),
        );
      case CodexAuthMode.deviceAuth:
        if (responseType != 'chatgptDeviceCode') {
          throw StateError(
            'Codex returned an unexpected device login response.',
          );
        }
        _awaitingLoginCompletion = true;
        final loginId = response['loginId'];
        final verificationUrl = response['verificationUrl'];
        final userCode = response['userCode'];
        if (loginId is! String ||
            verificationUrl is! String ||
            userCode is! String) {
          throw StateError('Codex did not return a device login challenge.');
        }
        final parsed = CodexAuthOutputParser.parse(verificationUrl);
        if (parsed?.verificationUrl == null || !_isPlausibleCode(userCode)) {
          throw StateError(
            'Codex returned an unverified device login challenge.',
          );
        }
        _loginId = loginId;
        _emit(
          CodexAuthEvent(
            type: CodexAuthEventType.challenge,
            challenge: CodexAuthChallenge(
              verificationUrl: parsed!.verificationUrl,
              oneTimeCode: userCode,
            ),
            message: 'Device authorization is waiting for completion.',
          ),
        );
    }
  }

  void _handleLoginCompleted(Map<String, dynamic> params) {
    if (!_awaitingLoginCompletion) return;
    final loginId = params['loginId'];
    switch (_mode) {
      case CodexAuthMode.browser:
      case CodexAuthMode.deviceAuth:
        // Managed ChatGPT flows are correlated by the login id returned from
        // account/login/start. Do not let a stale notification complete a
        // newer login attempt.
        if (_loginId == null || loginId != _loginId) return;
      case CodexAuthMode.apiKey:
        // API-key completion is intentionally uncorrelated in the protocol
        // (loginId is normally null). Accept a null id, and tolerate a
        // server-generated id for compatibility with older builds.
        if (loginId != null && loginId is! String) return;
      case null:
        return;
    }
    if (params['success'] == true) {
      _completeSuccessfulLogin();
      return;
    }
    _awaitingLoginCompletion = false;
    final detail = _safeCompletionError(params['error']);
    _emit(
      CodexAuthEvent(
        type: CodexAuthEventType.error,
        message: detail == null
            ? 'Codex login was not completed.'
            : 'Codex login failed: $detail',
      ),
    );
  }

  void _completeSuccessfulLogin() {
    if (!_awaitingLoginCompletion) return;
    // Codex has already committed the login. Clear the pending id before
    // Flutter tears down the app-server so cleanup cannot race the success
    // callback with account/login/cancel.
    _loginId = null;
    _awaitingLoginCompletion = false;
    _emitExit(0, 'Login process completed.');
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

  void _completePending(Object error) {
    for (final pending in _pendingRequests.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pendingRequests.clear();
  }

  void _emit(CodexAuthEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  static bool _isPlausibleCode(String value) {
    return value.length >= 4 &&
        value.length <= 64 &&
        value.contains(RegExp(r'\d')) &&
        RegExp(r'^[A-Z0-9][A-Z0-9-]*$', caseSensitive: false).hasMatch(value);
  }

  static String _safeError(Object error) {
    if (error is BackendException) return error.message;
    if (error is StateError) {
      final message = _safeCompletionError(error.message);
      if (message != null) return message;
    }
    return 'Could not start the login process.';
  }

  static String _safeRpcError(Object? value) {
    String? message;
    if (value is Map) {
      message = _stringValue(value['message']);
      if (message == null && value['data'] is Map) {
        message = _stringValue((value['data'] as Map)['message']);
      }
    } else {
      message = _stringValue(value);
    }
    final safe = _safeCompletionError(message);
    return safe == null
        ? 'Codex rejected the login request.'
        : 'Codex rejected the login request: $safe';
  }

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }

  static String? _safeCompletionError(Object? value) {
    if (value is! String) return null;
    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '<redacted-api-key>')
        .trim();
    if (normalized.isEmpty) return null;
    return normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 237)}…';
  }
}
