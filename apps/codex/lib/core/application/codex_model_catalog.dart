import 'dart:async';
import 'dart:convert';

import '../domain/backend.dart';
import '../domain/execution.dart';
import '../domain/transcript.dart';
import '../domain/workspace.dart';
import 'codex_cli_arguments.dart';

typedef ModelCatalogExecutionFactory = InteractiveExecution Function(
  WorkspaceHandle workspace,
);

class CodexModelDescriptor {
  const CodexModelDescriptor({
    required this.id,
    required this.displayName,
    required this.reasoningEfforts,
    this.hidden = false,
  });

  final String id;
  final String displayName;
  final List<String> reasoningEfforts;
  final bool hidden;
}

class CodexModelCatalog {
  const CodexModelCatalog({required this.models});

  final List<CodexModelDescriptor> models;

  /// Selects the CLI's first visible Luna model for a fresh session, falling
  /// back to its first visible model when that family is unavailable. Catalog
  /// order belongs to the installed CLI, so the app need not pin a versioned
  /// model ID as its long-term default.
  CodexModelDescriptor? get recommendedDefaultModel {
    for (final model in models) {
      if (!model.hidden && model.id.toLowerCase().contains('luna')) {
        return model;
      }
    }
    for (final model in models) {
      if (!model.hidden) return model;
    }
    return null;
  }

  List<String> get modelIds => models.map((model) => model.id).toList();

  Map<String, List<String>> get modelEfforts => <String, List<String>>{
    for (final model in models) model.id: model.reasoningEfforts,
  };

  CodexModelCatalog withCurrentModel(String model) {
    if (models.any((candidate) => candidate.id == model)) return this;
    return CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: model,
          displayName: model,
          reasoningEfforts: const <String>['low'],
        ),
        ...models,
      ],
    );
  }
}

/// Reads the installed CLI's model catalog through its local app-server.
///
/// The app-server owns the same bundled/remote model resolution as the CLI,
/// so the Android picker does not drift from the runtime by maintaining a
/// second hardcoded model list.
class CodexModelCatalogClient {
  static Future<CodexModelCatalog> load({
    required Backend backend,
    required WorkspaceRef workspace,
    required String command,
    required ExecutionIdentity identity,
    Map<String, String> environment = const <String, String>{},
    ModelCatalogExecutionFactory? processFactory,
    bool preferCliCatalog = false,
  }) async {
    final handle = await backend.openWorkspace(workspace);
    // The installed CLI/app-server is the authority for the available model
    // set. Do not consult the retired Android/Bionic runtime's global cache:
    // it could be stale and belonged to a different CODEX_HOME.
    if (processFactory == null) {
      return _loadProductionCatalog(
        backend: backend,
        handle: handle,
        command: command,
        identity: identity,
        environment: environment,
        preferCliCatalog: preferCliCatalog,
      );
    }
    return _loadAppServerCatalog(
      backend: backend,
      handle: handle,
      command: command,
      identity: identity,
      environment: environment,
      processFactory: processFactory,
    );
  }

  /// Parses the JSON shape emitted by `codex debug models` and
  /// app-server. Kept public for protocol parsing tests.
  static CodexModelCatalog parseJsonCatalog(Map<Object?, Object?> raw) {
    final rawModels = raw['models'];
    final models = <CodexModelDescriptor>[];
    if (rawModels is List) {
      for (final model in rawModels) {
        final parsed = _parseModel(model);
        if (parsed != null &&
            !models.any((candidate) => candidate.id == parsed.id)) {
          models.add(parsed);
        }
      }
    }
    if (models.isEmpty) {
      throw const FormatException('Codex returned an empty model catalog.');
    }
    return CodexModelCatalog(models: List.unmodifiable(models));
  }

  /// Returns the current CLI's base instruction template for a model.
  ///
  /// Custom providers still need Codex's agent instructions. Read them from
  /// the installed CLI's bundled catalog instead of copying a versioned
  /// prompt into the Android app. `preferredModel` is used when the current
  /// catalog contains it; otherwise the first bundled model with a template
  /// is used.
  static String parseBaseInstructions(
    Map<Object?, Object?> raw, {
    String? preferredModel,
  }) {
    final rawModels = raw['models'];
    if (rawModels is! List) {
      throw const FormatException('Codex returned no bundled model list.');
    }
    final models = rawModels.whereType<Map>().toList(growable: false);
    final ordered = <Map>[
      if (preferredModel != null)
        ...models.where((model) => _modelId(model) == preferredModel),
      ...models.where((model) => _modelId(model) != preferredModel),
    ];
    for (final model in ordered) {
      final legacy = _stringValue(model['base_instructions']);
      if (legacy != null && legacy.trim().isNotEmpty) return legacy;
      final messages = model['model_messages'];
      if (messages is Map) {
        final template = _stringValue(messages['instructions_template']);
        if (template != null && template.trim().isNotEmpty) return template;
      }
    }
    throw const FormatException(
      'The installed Codex CLI did not provide a bundled instruction template.',
    );
  }

  static Future<String> loadBaseInstructions({
    required Backend backend,
    required WorkspaceRef workspace,
    required String command,
    required ExecutionIdentity identity,
    Map<String, String> environment = const <String, String>{},
    String? preferredModel,
  }) async {
    final handle = await backend.openWorkspace(workspace);
    final bundled = await _runCliCatalog(
      backend: backend,
      handle: handle,
      command: command,
      identity: identity,
      environment: environment,
      bundled: true,
      timeout: const Duration(seconds: 20),
    );
    return parseBaseInstructions(
      bundled.cast<Object?, Object?>(),
      preferredModel: preferredModel,
    );
  }

  static Future<CodexModelCatalog> _loadProductionCatalog({
    required Backend backend,
    required WorkspaceHandle handle,
    required String command,
    required ExecutionIdentity identity,
    required Map<String, String> environment,
    required bool preferCliCatalog,
  }) async {
    if (preferCliCatalog) {
      // A settings page or a fresh session has no thread-scoped app-server to
      // ask. Starting a second, standalone app-server just for model/list can
      // enter the runtime's cache/bootstrap path and leave the picker waiting
      // for many seconds on Android. The CLI catalog command is the same
      // installed runtime's non-interactive model source, closes stdin, and
      // has a bounded timeout.
      try {
        return await _loadCliCatalog(
          backend: backend,
          handle: handle,
          command: command,
          identity: identity,
          environment: environment,
          bundled: false,
          timeout: const Duration(seconds: 10),
        );
      } catch (onlineError) {
        try {
          return await _loadCliCatalog(
            backend: backend,
            handle: handle,
            command: command,
            identity: identity,
            environment: environment,
            bundled: true,
            timeout: const Duration(seconds: 8),
          );
        } catch (_) {
          // Preserve the online error: it is the more useful diagnostic when
          // both catalog sources fail.
          throw onlineError;
        }
      }
    }

    Object? firstError;
    try {
      // `model/list` is the installed app-server's authoritative catalog and
      // gives the complete selectable set in one process. Older or unusual
      // runtimes can fall back to the CLI catalog commands below.
      return await _loadAppServerCatalog(
        backend: backend,
        handle: handle,
        command: command,
        identity: identity,
        environment: environment,
      );
    } on Object catch (error) {
      firstError = error;
    }

    CodexModelCatalog? bundled;
    CodexModelCatalog? online;
    try {
      bundled = await _loadCliCatalog(
        backend: backend,
        handle: handle,
        command: command,
        identity: identity,
        environment: environment,
        bundled: true,
        timeout: const Duration(seconds: 20),
      );
    } catch (error) {
      firstError ??= error;
    }
    try {
      online = await _loadCliCatalog(
        backend: backend,
        handle: handle,
        command: command,
        identity: identity,
        environment: environment,
        // `debug models` is the CLI's normal catalog path. It can merge the
        // bundled models with a fresh or cached provider catalog, which is
        // the complete list the CLI itself can resolve.
        bundled: false,
        timeout: const Duration(seconds: 10),
      );
    } catch (error) {
      firstError ??= error;
    }
    final sources = <CodexModelCatalog>[
      if (online case final catalog?) catalog,
      if (bundled case final catalog?) catalog,
    ];
    if (sources.isNotEmpty) {
      var merged = sources.first;
      for (final source in sources.skip(1)) {
        merged = _mergeCatalog(merged, source);
      }
      return merged;
    }

    throw firstError ??
        const BackendException('Codex returned no model catalog sources.');
  }

  static CodexModelCatalog _mergeCatalog(
    CodexModelCatalog primary,
    CodexModelCatalog? secondary,
  ) {
    if (secondary == null) return primary;
    final merged = <CodexModelDescriptor>[];
    final positions = <String, int>{};
    void add(CodexModelDescriptor candidate) {
      final position = positions[candidate.id];
      if (position == null) {
        positions[candidate.id] = merged.length;
        merged.add(candidate);
        return;
      }
      final existing = merged[position];
      final efforts = <String>[
        ...existing.reasoningEfforts,
        for (final effort in candidate.reasoningEfforts)
          if (!existing.reasoningEfforts.contains(effort)) effort,
      ];
      merged[position] = CodexModelDescriptor(
        id: existing.id,
        displayName: existing.displayName,
        reasoningEfforts: List.unmodifiable(efforts),
        // A model present in either normal catalog is selectable. Keep it
        // hidden only when both sources mark it hidden.
        hidden: existing.hidden && candidate.hidden,
      );
    }

    for (final model in primary.models) add(model);
    for (final model in secondary.models) add(model);
    return CodexModelCatalog(models: List.unmodifiable(merged));
  }

  static Future<CodexModelCatalog> _loadAppServerCatalog({
    required Backend backend,
    required WorkspaceHandle handle,
    required String command,
    required ExecutionIdentity identity,
    required Map<String, String> environment,
    ModelCatalogExecutionFactory? processFactory,
  }) async {
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
            timeout: const Duration(minutes: 2),
            environment: environment,
          ),
        );
    final rpc = _ModelCatalogRpc(process);
    try {
      await rpc.start();
      final models = <CodexModelDescriptor>[];
      final seenCursors = <String>{};
      String? cursor;
      for (var page = 0; page < 8; page++) {
        final params = <String, dynamic>{
          'includeHidden': true,
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        };
        final response = await rpc.request('model/list', params);
        final data = response['data'];
        if (data is List) {
          for (final raw in data) {
            final parsed = _parseModel(raw);
            if (parsed != null &&
                !models.any((candidate) => candidate.id == parsed.id)) {
              models.add(parsed);
            }
          }
        }
        final next = response['nextCursor'];
        cursor = next is String && next.isNotEmpty ? next : null;
        if (cursor == null) break;
        if (!seenCursors.add(cursor)) break;
      }
      if (models.isEmpty) {
        throw const BackendException('Codex returned an empty model catalog.');
      }
      return CodexModelCatalog(models: List.unmodifiable(models));
    } finally {
      await rpc.dispose();
    }
  }

  static Future<CodexModelCatalog> _loadCliCatalog({
    required Backend backend,
    required WorkspaceHandle handle,
    required String command,
    required ExecutionIdentity identity,
    required Map<String, String> environment,
    required bool bundled,
    required Duration timeout,
  }) async {
    final decoded = await _runCliCatalog(
      backend: backend,
      handle: handle,
      command: command,
      identity: identity,
      environment: environment,
      bundled: bundled,
      timeout: timeout,
    );
    return parseJsonCatalog(decoded.cast<Object?, Object?>());
  }

  static Future<Map<dynamic, dynamic>> _runCliCatalog({
    required Backend backend,
    required WorkspaceHandle handle,
    required String command,
    required ExecutionIdentity identity,
    required Map<String, String> environment,
    required bool bundled,
    required Duration timeout,
  }) async {
    final process = backend.startInteractive(
      ExecutionRequest(
        argv: codexArgumentsWithSessionIsolation(<String>[
          command,
          'debug',
          'models',
          if (bundled) '--bundled',
        ], environment),
        cwd: handle.ref.hostPath,
        identity: identity,
        timeout: timeout,
        environment: environment,
      ),
    );
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final completed = Completer<int?>();
    late final StreamSubscription<ExecutionEvent> subscription;
    subscription = process.events.listen(
      (event) {
        if (event.stdout != null) stdout.write(event.stdout);
        if (event.stderr != null) stderr.write(event.stderr);
        if (event.error != null && !completed.isCompleted) {
          // The runtime can report a derived-cache housekeeping warning on
          // the same stream as the catalog command. It is not a catalog
          // failure and must not replace the live/CLI catalog with an error.
          if (!isBenignCodexRuntimeDiagnostic(event.error!)) {
            final diagnostic = _diagnostic(event.error!);
            completed.completeError(
              BackendException(
                'Codex model catalog failed: '
                '${diagnostic.isEmpty ? event.error : diagnostic}',
              ),
            );
          }
        }
        if (event.exitCode != null && !completed.isCompleted) {
          completed.complete(event.exitCode);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete(null);
      },
    );
    try {
      // Model discovery is a non-interactive CLI invocation too.  Android
      // and PRoot keep the process pipe open until the caller explicitly
      // closes stdin; without EOF, `codex debug models` can wait forever and
      // leave the Settings model picker in a permanent loading state.
      if (process case final StdinClosableExecution closable) {
        await closable.closeStdin();
      }
      final exitCode = await completed.future.timeout(timeout);
      if (exitCode != null && exitCode != 0) {
        final detail = _diagnostic(
          '${stderr.toString()}\n${stdout.toString()}',
        );
        throw BackendException(
          'Codex model catalog exited with code $exitCode'
          '${detail.isEmpty ? '.' : ': $detail'}',
        );
      }
      // The CLI may emit housekeeping warnings on stderr even when the JSON
      // command succeeded. Only stdout is the machine-readable catalog.
      final rawOutput = stdout.toString();
      final decoded = jsonDecode(rawOutput);
      if (decoded is! Map) {
        final detail = _diagnostic(
          rawOutput.isEmpty ? stderr.toString() : rawOutput,
        );
        throw BackendException(
          'Codex returned an invalid model catalog'
          '${detail.isEmpty ? '.' : ': $detail'}',
        );
      }
      return decoded;
    } on TimeoutException {
      await _stopBestEffort(process);
      throw BackendException(
        'Codex ${bundled ? 'bundled ' : ''}model catalog timed out.',
      );
    } finally {
      await subscription.cancel();
      await _stopBestEffort(process);
    }
  }

  static Future<void> _stopBestEffort(InteractiveExecution process) async {
    try {
      await process.stop().timeout(const Duration(seconds: 2));
    } catch (_) {
      // A failed or already-exited host process must not keep the Settings
      // picker waiting forever.
    }
  }

  static String _diagnostic(String value) {
    final filtered = value
        .split(RegExp(r'[\r\n]+'))
        .where((line) => !isBenignCodexRuntimeDiagnostic(line))
        .join(' ');
    final normalized = filtered
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~])'), '')
        .trim();
    if (normalized.isEmpty) return '';
    return normalized.length <= 180
        ? normalized
        : '${normalized.substring(0, 177)}…';
  }

  static CodexModelDescriptor? _parseModel(Object? raw) {
    if (raw is! Map) return null;
    final id = _modelId(raw);
    if (id == null || id.isEmpty) return null;
    final displayName =
        _stringValue(raw['displayName']) ??
        _stringValue(raw['display_name']) ??
        id;
    final efforts = <String>[];
    final rawEfforts =
        raw['supportedReasoningEfforts'] ?? raw['supported_reasoning_levels'];
    if (rawEfforts is List) {
      for (final rawEffort in rawEfforts) {
        final effort = rawEffort is Map
            ? _stringValue(rawEffort['effort']) ??
                  _stringValue(rawEffort['reasoningEffort'])
            : _stringValue(rawEffort);
        if (effort != null && effort.isNotEmpty && !efforts.contains(effort)) {
          efforts.add(effort);
        }
      }
    }
    if (efforts.isEmpty) {
      final defaultEffort =
          _stringValue(raw['defaultReasoningEffort']) ??
          _stringValue(raw['default_reasoning_level']);
      if (defaultEffort != null && defaultEffort.isNotEmpty) {
        efforts.add(defaultEffort);
      }
    }
    if (efforts.isEmpty) efforts.add('low');
    return CodexModelDescriptor(
      id: id,
      displayName: displayName,
      reasoningEfforts: List.unmodifiable(efforts),
      hidden:
          raw['hidden'] == true ||
          (_stringValue(raw['visibility']) != null &&
              _stringValue(raw['visibility']) != 'list'),
    );
  }

  static String? _stringValue(Object? value) {
    if (value is String) return value;
    return null;
  }

  static String? _modelId(Map<dynamic, dynamic> raw) =>
      _stringValue(raw['model']) ??
      _stringValue(raw['id']) ??
      _stringValue(raw['slug']);
}

class _ModelCatalogRpc {
  _ModelCatalogRpc(this._process);

  final InteractiveExecution _process;
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  StreamSubscription<ExecutionEvent>? _subscription;
  String _lineBuffer = '';
  int _nextRequestId = 1;
  bool _stopped = false;

  Future<void> start() async {
    _subscription = _process.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        _fail(BackendException('Model catalog process failed: $error'));
      },
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
    Map<String, dynamic> params,
  ) async {
    final id = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending['$id'] = completer;
    try {
      final operation = () async {
        await _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          'params': params,
        });
        return completer.future;
      }();
      return await operation.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _pending.remove('$id');
          throw BackendException(
            'Codex model catalog request timed out: $method',
          );
        },
      );
    } catch (error, stackTrace) {
      _pending.remove('$id');
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  Future<void> _write(Map<String, dynamic> value) async {
    if (_stopped)
      throw const BackendException('Model catalog process stopped.');
    await _process.write('${jsonEncode(value)}\n');
  }

  void _handleEvent(ExecutionEvent event) {
    if (event.stdout != null) _consume(event.stdout!);
    if (event.error != null && !isBenignCodexRuntimeDiagnostic(event.error!)) {
      final diagnostic = CodexModelCatalogClient._diagnostic(event.error!);
      _fail(
        BackendException(
          'Model catalog process failed: '
          '${diagnostic.isEmpty ? event.error : diagnostic}',
        ),
      );
    }
    if (event.exitCode != null) {
      _fail(
        BackendException(
          'Codex model catalog process exited with code ${event.exitCode}.',
        ),
      );
    }
  }

  void _consume(String chunk) {
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
        // Ignore malformed diagnostics; the pending RPC timeout is the safe
        // failure path for a non-conforming app-server.
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
    final pending = _pending.remove('$id');
    if (pending == null || pending.isCompleted) return;
    if (envelope['error'] != null) {
      pending.completeError(
        const BackendException('Codex rejected the model catalog request.'),
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
        pending.completeError(const BackendException('Model catalog stopped.'));
      }
    }
    _pending.clear();
    final subscription = _subscription;
    _subscription = null;
    await CodexModelCatalogClient._stopBestEffort(_process);
    await subscription?.cancel();
  }
}
