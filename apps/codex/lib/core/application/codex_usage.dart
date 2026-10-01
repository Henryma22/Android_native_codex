import 'dart:async';
import 'dart:convert';

import '../domain/backend.dart';
import '../domain/execution.dart';
import '../domain/transcript.dart';
import '../domain/workspace.dart';
import 'codex_cli_arguments.dart';

typedef UsageExecutionFactory = InteractiveExecution Function(
  WorkspaceHandle workspace,
);

class CodexUsageWindow {
  const CodexUsageWindow({
    required this.usedPercent,
    this.windowDurationMins,
    this.resetsAt,
  });

  final double usedPercent;
  final int? windowDurationMins;
  final DateTime? resetsAt;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100).toDouble();
}

class CodexUsageSnapshot {
  const CodexUsageSnapshot({this.fiveHour, this.sevenDay, this.error});

  final CodexUsageWindow? fiveHour;
  final CodexUsageWindow? sevenDay;
  final String? error;

  bool get hasData => fiveHour != null || sevenDay != null;
  bool get hasError => error != null && error!.trim().isNotEmpty;

  const CodexUsageSnapshot.error(String message)
    : fiveHour = null,
      sevenDay = null,
      error = message;

  factory CodexUsageSnapshot.fromRpcResponse(Map<String, dynamic> response) {
    final byLimitId = _asMap(response['rateLimitsByLimitId']);
    final selected =
        _asMap(byLimitId?['codex']) ?? _asMap(response['rateLimits']);
    if (selected == null) {
      throw const FormatException('Codex usage response has no rate limits.');
    }
    final limitId = selected['limitId'] ?? selected['limit_id'];
    if (limitId is String && limitId.isNotEmpty && limitId != 'codex') {
      throw FormatException('Unexpected Codex usage limit: $limitId');
    }

    CodexUsageWindow? fiveHour;
    CodexUsageWindow? sevenDay;
    for (final rawWindow in <Object?>[
      selected['primary'],
      selected['secondary'],
    ]) {
      final window = _parseWindow(rawWindow);
      if (window == null) continue;
      if (window.windowDurationMins == 300 && fiveHour == null) {
        fiveHour = window;
      } else if (window.windowDurationMins == 10080 && sevenDay == null) {
        sevenDay = window;
      }
    }
    if (fiveHour == null && sevenDay == null) {
      throw const FormatException('Codex returned no supported usage windows.');
    }
    return CodexUsageSnapshot(fiveHour: fiveHour, sevenDay: sevenDay);
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is! Map) return null;
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static CodexUsageWindow? _parseWindow(Object? raw) {
    final value = _asMap(raw);
    if (value == null) return null;
    final used = value['usedPercent'] ?? value['used_percent'];
    final duration =
        value['windowDurationMins'] ?? value['window_duration_mins'];
    if (used is! num || duration is! num) return null;
    final usedPercent = used.toDouble();
    final durationMins = duration.toInt();
    if (!usedPercent.isFinite ||
        durationMins <= 0 ||
        (durationMins != 300 && durationMins != 10080)) {
      return null;
    }
    final reset = value['resetsAt'] ?? value['resets_at'];
    final resetSeconds = reset is num ? reset.toDouble() : null;
    final resetsAt = resetSeconds != null && resetSeconds.isFinite
        ? DateTime.fromMillisecondsSinceEpoch(
            (resetSeconds * 1000).round(),
            isUtc: true,
          )
        : null;
    return CodexUsageWindow(
      usedPercent: usedPercent,
      windowDurationMins: durationMins,
      resetsAt: resetsAt,
    );
  }
}

/// Reads account-wide Codex rate limits from the local app-server.
///
/// This is deliberately a direct Android backend client. It does not use the
/// old Bridge, a socket, or a remote usage service, and it never creates a
/// thread or turn.
class CodexUsageClient {
  static Future<CodexUsageSnapshot> load({
    required Backend backend,
    required WorkspaceRef workspace,
    required String command,
    required ExecutionIdentity identity,
    Map<String, String> environment = const <String, String>{},
    UsageExecutionFactory? processFactory,
  }) async {
    try {
      final handle = await backend.openWorkspace(workspace);
      final process =
          processFactory?.call(handle) ??
          backend.startInteractive(
            ExecutionRequest(
              argv: codexArgumentsWithSessionIsolation(<String>[
                command,
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
              ], environment),
              cwd: handle.ref.hostPath,
              identity: identity,
              timeout: const Duration(seconds: 30),
              environment: environment,
            ),
          );
      final rpc = _CodexUsageRpc(process);
      try {
        await rpc.start();
        // The current app-server API defines this as a zero-argument method;
        // omitting params is intentional and matches CC Pocket's latest
        // CodexProcess implementation.
        final response = await rpc.request('account/rateLimits/read', null);
        return CodexUsageSnapshot.fromRpcResponse(response);
      } finally {
        await rpc.dispose();
      }
    } catch (error) {
      return CodexUsageSnapshot.error(_diagnostic(error));
    }
  }

  static String _diagnostic(Object error) {
    final text = '$error'.replaceFirst('BackendException: ', '').trim();
    if (text.isEmpty) return '无法读取 Codex 用量。';
    return text.length <= 180 ? text : '${text.substring(0, 177)}…';
  }
}

class _CodexUsageRpc {
  _CodexUsageRpc(this._process);

  final InteractiveExecution _process;
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  StreamSubscription<ExecutionEvent>? _subscription;
  String _buffer = '';
  final StringBuffer _stderr = StringBuffer();
  var _nextId = 1;
  var _stopped = false;

  Future<void> start() async {
    _subscription = _process.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) =>
          _fail(BackendException('Codex usage process failed: $error')),
    );
    await request('initialize', <String, dynamic>{
      'clientInfo': <String, String>{
        'name': 'codex-android',
        'version': '1.0.0',
        'title': 'Codex for Android',
      },
      'capabilities': <String, bool>{'experimentalApi': true},
    });
    await _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'initialized',
      'params': <String, dynamic>{},
    });
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic>? params,
  ) async {
    if (_stopped) throw const BackendException('Codex usage process stopped.');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending['$id'] = completer;
    try {
      await _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      });
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw BackendException(_timeoutMessage(method)),
      );
    } finally {
      _pending.remove('$id');
    }
  }

  Future<void> _write(Map<String, dynamic> value) async {
    if (_stopped) throw const BackendException('Codex usage process stopped.');
    await _process
        .write('${jsonEncode(value)}\n')
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw const BackendException(
            'Codex usage process did not become writable in time.',
          ),
        );
  }

  void _handleEvent(ExecutionEvent event) {
    if (event.stdout != null) _consume(event.stdout!);
    if (event.stderr != null) {
      _stderr.write(event.stderr);
    }
    if (event.error != null && !isBenignCodexRuntimeDiagnostic(event.error!)) {
      _fail(BackendException('Codex usage process failed: ${event.error}'));
    }
    if (event.exitCode != null) {
      _fail(
        BackendException(
          'Codex usage process exited with code ${event.exitCode}.',
        ),
      );
    }
  }

  String _timeoutMessage(String method) {
    final diagnostic = _stderr.toString().trim();
    if (diagnostic.isEmpty) {
      return 'Codex usage request timed out: $method';
    }
    final compact = diagnostic.replaceAll(RegExp(r'\s+'), ' ');
    final excerpt = compact.length <= 240
        ? compact
        : '${compact.substring(0, 237)}…';
    return 'Codex usage request timed out: $method ($excerpt)';
  }

  void _consume(String chunk) {
    _buffer += chunk;
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline < 0) return;
      final line = _buffer.substring(0, newline).trim();
      _buffer = _buffer.substring(newline + 1);
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          _handleEnvelope(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // The request timeout is the safe failure path for diagnostics or a
        // non-JSON line emitted by a broken runtime.
      }
    }
  }

  void _handleEnvelope(Map<String, dynamic> envelope) {
    final method = envelope['method'];
    if (method == 'currentTime/read') {
      unawaited(
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': envelope['id'],
          'result': <String, int>{
            'currentTimeAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
        }),
      );
      return;
    }
    if (method is String) return;
    final id = envelope['id'];
    if (id == null) return;
    final pending = _pending['$id'];
    if (pending == null || pending.isCompleted) return;
    if (envelope['error'] != null) {
      final error = envelope['error'];
      final message = error is Map ? error['message'] : null;
      pending.completeError(
        BackendException(
          message is String && message.isNotEmpty
              ? message
              : 'Codex rejected the usage request.',
        ),
      );
      return;
    }
    final result = envelope['result'];
    pending.complete(
      result is Map ? result.cast<String, dynamic>() : <String, dynamic>{},
    );
  }

  void _fail(Object error) {
    if (_stopped) return;
    _stopped = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    _stopped = true;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(const BackendException('Codex usage stopped.'));
      }
    }
    _pending.clear();
    final subscription = _subscription;
    _subscription = null;
    try {
      await _process.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      // A process that already exited is fully disposed for this read.
    }
    // Local Android execution streams use the controller's onCancel callback
    // to stop the child process. A broken native process teardown must not
    // turn an already-bounded usage read back into an unbounded settings
    // spinner.
    try {
      await subscription?.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The process stop above is the authoritative best-effort cleanup.
    }
  }
}
