import 'dart:async';
import 'dart:convert';

import 'android_codex_agents.dart';
import 'codex_cli_arguments.dart';
import 'codex_model_catalog.dart';
import 'codex_mcp_server_summary.dart';
import 'codex_permission_profile_summary.dart';
import 'codex_plugin_summary.dart';
import 'codex_thread_summary.dart';
import 'codex_thread_title.dart';
import '../domain/backend.dart';
import '../domain/execution.dart';
import '../domain/image_attachment.dart';
import '../domain/session.dart';
import '../domain/workspace.dart';

typedef InteractiveExecutionFactory = InteractiveExecution Function(
  WorkspaceHandle workspace,
);

typedef CodexCommandOutputCallback = void Function(String text, bool isStderr);

/// The small set of turn settings exposed by the CC Pocket-style mode bar.
/// Values are sent using the Codex app-server field names understood by the
/// installed CLI; no external service state is involved.
class CodexTurnSettings {
  const CodexTurnSettings({
    this.model = 'gpt-6-luna',
    this.reasoningEffort = 'low',
    this.approvalPolicy = 'on-request',
    this.sandbox = 'workspace-write',
    this.permissions,
    this.collaborationMode = 'default',
  });

  final String model;
  final String reasoningEffort;
  final String approvalPolicy;
  final String sandbox;

  /// Named app-server permission profile. When present and supported by the
  /// installed CLI, it is sent instead of the legacy sandbox field.
  final String? permissions;
  final String collaborationMode;
}

/// The provider-owned identity returned by `thread/fork`.
///
/// The rollout path is intentionally kept alongside the new thread id. Each
/// Android app session has its own CODEX_HOME, so a fork must be resumed from
/// a copied rollout path in the destination session rather than by asking a
/// second process to share the source session's SQLite store.
class CodexForkResult {
  const CodexForkResult({
    required this.threadId,
    this.threadPath,
    this.threadName,
  });

  final String threadId;
  final String? threadPath;
  final String? threadName;
}

/// Result returned by the app-server `command/exec` method.
///
/// This is deliberately separate from [ExecutionEvent]: the command is
/// executed by the already-running session app-server, so it does not create
/// a second process or a second CODEX_HOME. The client supports streamed argv
/// output and the session-scoped PTY primitives used by the focused `/exec
/// --tty` panel; it does not attempt to embed the full Codex CLI TUI.
class CodexCommandExecResult {
  const CodexCommandExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get combinedOutput =>
      [stdout, stderr].where((value) => value.isNotEmpty).join('\n');
}

class _PendingAutomaticThreadTitle {
  final Completer<String?> response = Completer<String?>();
  final Completer<void> cancellation = Completer<void>();
  String? temporaryThreadId;
  String? turnId;
  String? responseText;
  var turnCompleted = false;
}

/// Minimal JSON-RPC client for one local Codex app-server process.
///
/// The client deliberately owns one process and one thread. It does not know
/// about Android root helpers or filesystem implementation details. All
/// process identity and filesystem access stay behind [Backend].
class CodexSessionClient implements SessionClient {
  static const _approvalMethods = <String>{
    'item/commandExecution/requestApproval',
    'item/fileChange/requestApproval',
    'item/permissions/requestApproval',
    'item/tool/requestUserInput',
  };

  CodexSessionClient({
    required Backend backend,
    required WorkspaceRef workspace,
    required List<String> argv,
    ExecutionIdentity identity = ExecutionIdentity.app,
    Map<String, String> environment = const <String, String>{},
    String? resumeThreadId,
    String? resumeThreadPath,
    CodexTurnSettings settings = const CodexTurnSettings(),
    String? automaticTitleModel,
    String? automaticTitleEffort,
    InteractiveExecutionFactory? processFactory,
  }) : _backend = backend,
       _workspace = workspace,
       _argv = List<String>.unmodifiable(argv),
       _identity = identity,
       _environment = Map<String, String>.unmodifiable(environment),
       _resumeThreadId = resumeThreadId,
       _resumeThreadPath = resumeThreadPath,
       _settings = settings,
       _automaticTitleModel = automaticTitleModel,
       _automaticTitleEffort = automaticTitleEffort,
       _processFactory = processFactory;

  final Backend _backend;
  final WorkspaceRef _workspace;
  final List<String> _argv;
  final ExecutionIdentity _identity;
  final Map<String, String> _environment;
  final String? _resumeThreadId;
  final String? _resumeThreadPath;
  final String? _automaticTitleModel;
  final String? _automaticTitleEffort;
  CodexTurnSettings _settings;
  String get _effectiveApprovalPolicy => _settings.approvalPolicy;
  final InteractiveExecutionFactory? _processFactory;
  final StreamController<CodexSessionEvent> _eventController =
      StreamController<CodexSessionEvent>.broadcast();
  final Map<String, Completer<Object?>> _pending = {};

  InteractiveExecution? _process;
  StreamSubscription<ExecutionEvent>? _processSubscription;
  Future<void>? _startInFlight;
  String _lineBuffer = '';
  String? _threadId;
  String? _threadPath;
  String? _turnId;
  bool _assistantDeltaReceivedForTurn = false;
  final Set<String> _assistantItemsWithDeltas = <String>{};
  int _nextRequestId = 1;
  int _processGeneration = 0;
  int _threadNameRevision = 0;
  String? _sessionCwd;
  String? _threadName;
  _PendingAutomaticThreadTitle? _pendingAutomaticTitle;
  final Map<String, _PendingAutomaticThreadTitle> _pendingTitleTurns = {};
  bool _disposed = false;
  bool _stopped = false;
  bool _exitEventEmitted = false;
  bool? _permissionProfilesSupported;
  List<CodexPermissionProfileSummary>? _permissionProfiles;
  String? _activeCommandProcessId;
  String _activeCommandStdout = '';
  String _activeCommandStderr = '';
  CodexCommandOutputCallback? _commandOutputCallback;
  String? _interruptingTurnId;

  @override
  Stream<CodexSessionEvent> get events => _eventController.stream;

  @override
  String? get threadId => _threadId;

  /// The app-server rollout path for the currently loaded thread.
  String? get threadPath => _threadPath;

  /// The isolated CODEX_HOME used by this process. The local UI uses this
  /// only to derive a destination path for a forked rollout; it never shares
  /// the source home with another session.
  String? get codexHome => _environment['CODEX_HOME'];

  Map<String, String> get runtimeEnvironment => _environment;

  /// Forks the currently loaded provider thread using the official app-server
  /// RPC. The destination process is created by the UI after its rollout is
  /// copied to a new isolated CODEX_HOME.
  Future<CodexForkResult> forkThread() async {
    await start();
    final threadId = _threadId;
    if (threadId == null || threadId.isEmpty) {
      throw const CodexSessionException('Codex thread is not ready');
    }
    if (_turnId != null) {
      throw const CodexSessionException(
        'Stop the active turn before forking this session.',
      );
    }
    final response = _asMap(
      await _request('thread/fork', <String, dynamic>{
        'threadId': threadId,
      }, timeout: const Duration(seconds: 45)),
    );
    final thread = _asMap(response['thread']);
    final forkedThreadId = thread['id'];
    if (forkedThreadId is! String || forkedThreadId.trim().isEmpty) {
      throw const CodexSessionException(
        'thread/fork returned no forked thread id.',
      );
    }
    final rawPath = thread['path'];
    final rawName = thread['name'];
    return CodexForkResult(
      threadId: forkedThreadId.trim(),
      threadPath: rawPath is String && rawPath.trim().isNotEmpty
          ? rawPath.trim()
          : null,
      threadName: rawName is String && rawName.trim().isNotEmpty
          ? rawName.trim()
          : null,
    );
  }

  /// Changes the settings used by the next turn. Sandbox changes are also
  /// retained for the next session because the current thread's sandbox is
  /// fixed when it is started.
  void updateSettings(CodexTurnSettings settings) {
    _settings = settings;
    final threadId = _threadId;
    if (threadId != null && !_stopped) {
      unawaited(_syncThreadSettings(threadId, settings));
    }
  }

  /// Reads the profiles exposed by the installed app-server. Older CLI
  /// versions may not implement this experimental method; callers can then
  /// keep using the legacy sandbox/approval fields.
  Future<List<CodexPermissionProfileSummary>> readPermissionProfiles({
    bool forceRefresh = false,
  }) async {
    await start();
    if (!forceRefresh && _permissionProfiles != null) {
      return _permissionProfiles!;
    }
    try {
      final profiles = await _loadPermissionProfiles();
      _permissionProfilesSupported = true;
      _permissionProfiles = profiles;
      return profiles;
    } on Object catch (error) {
      if (_isUnsupportedRpcMethod(error) ||
          _isUnsupportedRpcParameters(error)) {
        _permissionProfilesSupported = false;
        _permissionProfiles = const <CodexPermissionProfileSummary>[];
        return _permissionProfiles!;
      }
      rethrow;
    }
  }

  /// Reads account quota through the already running local app-server.
  ///
  /// Reusing the active process keeps this request on the same authenticated
  /// and network-configured path as the real conversation turn.
  Future<Map<String, dynamic>> readAccountRateLimits({
    Duration timeout = const Duration(minutes: 2),
  }) async {
    await start();
    return _asMap(
      await _request('account/rateLimits/read', null, timeout: timeout),
    );
  }

  /// Reads selectable models from the already-running session app-server.
  /// Reusing this process avoids starting several extra PRoot/CLI workers just
  /// to open the model picker.
  Future<CodexModelCatalog> readModelCatalog({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await start();
    final models = <Object?>[];
    final seenCursors = <String>{};
    String? cursor;
    for (var page = 0; page < 8; page++) {
      final response = _asMap(
        await _request('model/list', <String, dynamic>{
          'includeHidden': true,
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        }, timeout: timeout),
      );
      final data = response['data'];
      if (data is List) models.addAll(data);
      final next = response['nextCursor'];
      cursor = next is String && next.isNotEmpty ? next : null;
      if (cursor == null || !seenCursors.add(cursor)) break;
    }
    return CodexModelCatalogClient.parseJsonCatalog(<Object?, Object?>{
      'models': models,
    });
  }

  /// Reads MCP server summaries from this session's authenticated app-server.
  /// Secret-bearing config values are discarded before returning to the UI.
  Future<List<CodexMcpServerSummary>> readMcpServers() async {
    await start();
    final cwd = _sessionCwd;
    if (cwd == null || cwd.isEmpty) {
      throw const CodexSessionException('Codex session workspace is not ready');
    }
    final response = _asMap(
      await _request('config/read', <String, dynamic>{
        'includeLayers': false,
        'cwd': cwd,
      }, timeout: const Duration(seconds: 30)),
    );
    final config = _asMap(response['config']);
    return CodexMcpServerSummary.parse(_mcpServersFromConfig(config));
  }

  /// Reads the installed/available plugin catalog from this session's
  /// app-server. The request stays on the active process and session home, so
  /// it does not create an isolated CLI config that would disagree with the UI.
  Future<List<CodexPluginSummary>> readPlugins({
    bool forceRefetch = false,
  }) async {
    await start();
    final response = await _readPluginListResponse(forceRefetch: forceRefetch);
    return CodexPluginSummary.parseResponse(response);
  }

  /// Reads marketplace identities independently from plugin entries so the
  /// Settings page can manage an empty marketplace as well as populated ones.
  Future<List<CodexPluginMarketplaceSummary>> readPluginMarketplaces({
    bool forceRefetch = false,
  }) async {
    await start();
    final response = await _readPluginListResponse(forceRefetch: forceRefetch);
    return CodexPluginMarketplaceSummary.parseResponse(response);
  }

  /// Reads all thread metadata visible to the active app-server session.
  ///
  /// Each Android app session has an isolated CODEX_HOME, so this is not a
  /// global cross-session history import. Pagination is followed here so UI
  /// callers receive a complete list for the current session/workspace.
  Future<List<CodexThreadSummary>> readThreads({
    bool archived = false,
    String? searchTerm,
  }) async {
    await start();
    final threads = <CodexThreadSummary>[];
    final seenCursors = <String>{};
    var useExtendedParams = true;
    var requiresClientSideSearch = false;
    String? cursor;
    while (true) {
      final params = <String, dynamic>{
        'archived': archived,
        if (cursor != null) 'cursor': cursor,
        'limit': 100,
      };
      if (useExtendedParams) {
        if (_sessionCwd case final cwd?) {
          if (cwd.isNotEmpty) params['cwd'] = cwd;
        }
        if (searchTerm?.trim().isNotEmpty == true) {
          params['searchTerm'] = searchTerm!.trim();
        }
        params
          ..['sortKey'] = 'updated_at'
          ..['sortDirection'] = 'desc'
          ..['useStateDbOnly'] = true;
      } else {
        // Older app-server versions accept the core archive/cursor/limit
        // fields but reject newer filtering and state-db hints. Preserve the
        // requested search below without making the old server parse it.
        requiresClientSideSearch = searchTerm?.trim().isNotEmpty == true;
      }

      late final Map<String, dynamic> response;
      try {
        response = _asMap(
          await _request(
            'thread/list',
            params,
            timeout: const Duration(seconds: 45),
          ),
        );
      } catch (error) {
        if (!useExtendedParams || !_isUnsupportedRpcParameters(error)) {
          rethrow;
        }
        // Keep the fallback narrow: a real transport/auth/server failure must
        // still reach the caller instead of being hidden behind a retry.
        useExtendedParams = false;
        requiresClientSideSearch = searchTerm?.trim().isNotEmpty == true;
        final fallbackParams = <String, dynamic>{
          'archived': archived,
          if (cursor != null) 'cursor': cursor,
          'limit': 100,
        };
        response = _asMap(
          await _request(
            'thread/list',
            fallbackParams,
            timeout: const Duration(seconds: 45),
          ),
        );
      }
      final page = CodexThreadListPage.parseResponse(response);
      threads.addAll(page.threads);
      final nextCursor = page.nextCursor;
      if (nextCursor == null) break;
      if (!seenCursors.add(nextCursor)) {
        throw const CodexSessionException(
          'Codex thread list returned a repeated pagination cursor',
        );
      }
      cursor = nextCursor;
    }
    if (!requiresClientSideSearch) {
      return List<CodexThreadSummary>.unmodifiable(threads);
    }
    final query = searchTerm!.trim().toLowerCase();
    return List<CodexThreadSummary>.unmodifiable(
      threads.where(
        (thread) => <String>[
          thread.id,
          thread.sessionId ?? '',
          thread.name ?? '',
          thread.preview ?? '',
        ].any((value) => value.toLowerCase().contains(query)),
      ),
    );
  }

  static bool _isUnsupportedRpcParameters(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('-32602') ||
        text.contains('invalid params') ||
        text.contains('unknown parameter') ||
        text.contains('unknown field') ||
        text.contains('unexpected field') ||
        text.contains('unrecognized field') ||
        text.contains('additional propert');
  }

  static bool _isUnsupportedRpcMethod(Object error) {
    final text = '$error'.toLowerCase();
    return text.contains('-32601') ||
        text.contains('method not found') ||
        text.contains('unknown method') ||
        text.contains('unsupported method');
  }

  String get _runtimeSandbox =>
      _identity == ExecutionIdentity.root ||
          _backend.descriptor.kind == BackendKind.linuxCompatibility
      ? 'danger-full-access'
      : _settings.sandbox;

  Map<String, dynamic> get _runtimeSandboxPolicy => switch (_runtimeSandbox) {
    'danger-full-access' => <String, dynamic>{'type': 'dangerFullAccess'},
    'read-only' => <String, dynamic>{'type': 'readOnly'},
    _ => <String, dynamic>{'type': 'workspaceWrite'},
  };

  bool get _useNamedPermissionProfile {
    final requested = _settings.permissions?.trim();
    if (_permissionProfilesSupported != true ||
        requested == null ||
        requested.isEmpty) {
      return false;
    }
    final profiles = _permissionProfiles;
    return profiles != null &&
        profiles.any((profile) => profile.id == requested && profile.allowed);
  }

  Future<List<CodexPermissionProfileSummary>> _loadPermissionProfiles() async {
    final profiles = <CodexPermissionProfileSummary>[];
    final seenCursors = <String>{};
    String? cursor;
    while (true) {
      final rawResponse = _asMap(
        await _request('permissionProfile/list', <String, dynamic>{
          'limit': 100,
          if (_sessionCwd != null && _sessionCwd!.isNotEmpty)
            'cwd': _sessionCwd,
          if (cursor != null) 'cursor': cursor,
        }, timeout: const Duration(seconds: 3)),
      );
      profiles.addAll(CodexPermissionProfileSummary.parseResponse(rawResponse));
      final nextCursor = rawResponse['nextCursor'];
      if (nextCursor == null) return profiles;
      if (nextCursor is! String ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        throw const CodexSessionException(
          'Codex permission profile list returned an invalid pagination cursor',
        );
      }
      cursor = nextCursor;
    }
  }

  Future<void> _syncThreadSettings(
    String threadId,
    CodexTurnSettings settings,
  ) async {
    final params = <String, dynamic>{
      'threadId': threadId,
      'model': settings.model,
      'effort': settings.reasoningEffort,
      'approvalPolicy': settings.approvalPolicy,
      'collaborationMode': <String, dynamic>{
        'mode': settings.collaborationMode,
        'settings': <String, String>{
          'model': settings.model,
          'reasoning_effort': settings.reasoningEffort,
        },
      },
      if (_useNamedPermissionProfile)
        'permissions': settings.permissions
      else
        'sandboxPolicy': _runtimeSandboxPolicy,
    };
    try {
      await _request(
        'thread/settings/update',
        params,
        timeout: const Duration(seconds: 30),
      );
    } on Object catch (error) {
      if (_isUnsupportedRpcMethod(error) ||
          _isUnsupportedRpcParameters(error)) {
        return;
      }
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.error,
          text: '$error',
          method: 'thread/settings/update',
          threadId: threadId,
        ),
      );
    }
  }

  /// Installs a plugin through the active app-server. The catalog lookup
  /// resolves a local marketplace path or a remote marketplace name so the
  /// app never needs to reproduce the CLI's marketplace storage layout.
  Future<Map<String, dynamic>> installPlugin(
    CodexPluginInstallRequest request,
  ) async {
    final catalog = await _readPluginCatalogResponse();
    final marketplace = _findPluginMarketplace(
      catalog,
      request.marketplaceName,
      pluginName: request.pluginName,
    );
    final path = marketplace['path'];
    final params = <String, dynamic>{'pluginName': request.pluginName};
    if (path is String && path.trim().isNotEmpty) {
      params['marketplacePath'] = path;
    } else {
      params['remoteMarketplaceName'] = request.marketplaceName;
    }
    return _asMap(
      await _request(
        'plugin/install',
        params,
        timeout: const Duration(minutes: 3),
      ),
    );
  }

  Future<Map<String, dynamic>> uninstallPlugin(String pluginId) async {
    final normalized = pluginId.trim();
    if (normalized.isEmpty || normalized.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const CodexSessionException('Plugin id is invalid.');
    }
    await start();
    return _asMap(
      await _request('plugin/uninstall', <String, dynamic>{
        'pluginId': normalized,
      }, timeout: const Duration(minutes: 3)),
    );
  }

  /// Enables or disables one installed plugin in the active session's user
  /// config. Codex exposes this as a config/value/write operation rather than
  /// a separate plugin RPC; keeping the write on the app-server preserves its
  /// config-layer/version handling and avoids reproducing config.toml parsing.
  Future<Map<String, dynamic>> setPluginEnabled(
    String pluginId,
    bool enabled,
  ) async {
    final normalized = pluginId.trim();
    if (normalized.isEmpty ||
        normalized.contains(RegExp(r'[\x00-\x1f\x7f/\\]')) ||
        !normalized.contains('@')) {
      throw const CodexSessionException('Plugin id is invalid.');
    }
    await start();
    return _asMap(
      await _request('config/value/write', <String, dynamic>{
        'keyPath': 'plugins.$normalized.enabled',
        'value': enabled,
        'mergeStrategy': 'replace',
        'filePath': null,
        'expectedVersion': null,
      }, timeout: const Duration(seconds: 30)),
    );
  }

  Future<Map<String, dynamic>> addPluginMarketplace(
    CodexPluginMarketplaceAddRequest request,
  ) async {
    await start();
    return _asMap(
      await _request('marketplace/add', <String, dynamic>{
        'source': request.source,
        if (request.refName != null) 'refName': request.refName,
        if (request.sparsePaths.isNotEmpty) 'sparsePaths': request.sparsePaths,
      }, timeout: const Duration(minutes: 3)),
    );
  }

  Future<Map<String, dynamic>> removePluginMarketplace(
    String marketplaceName,
  ) async {
    await start();
    return _asMap(
      await _request('marketplace/remove', <String, dynamic>{
        'marketplaceName': marketplaceName,
      }, timeout: const Duration(minutes: 3)),
    );
  }

  Future<Map<String, dynamic>> upgradePluginMarketplace(
    String? marketplaceName,
  ) async {
    await start();
    return _asMap(
      await _request('marketplace/upgrade', <String, dynamic>{
        if (marketplaceName != null) 'marketplaceName': marketplaceName,
      }, timeout: const Duration(minutes: 3)),
    );
  }

  Future<Map<String, dynamic>> _readPluginCatalogResponse() async {
    await start();
    return _readPluginListResponse();
  }

  Future<Map<String, dynamic>> _readPluginListResponse({
    bool forceRefetch = false,
  }) async {
    final cwd = _sessionCwd;
    final params = <String, dynamic>{
      if (cwd != null && cwd.isNotEmpty) 'cwds': <String>[cwd],
      if (forceRefetch) 'forceRefetch': true,
    };
    try {
      return _asMap(
        await _request(
          'plugin/list',
          params.isEmpty ? null : params,
          timeout: const Duration(seconds: 45),
        ),
      );
    } catch (error) {
      if (params.isEmpty || !_isUnsupportedRpcParameters(error)) rethrow;
      // `cwds` and `forceRefetch` were added after the base plugin/list
      // response. Older servers can still return the catalog without them.
      return _asMap(
        await _request(
          'plugin/list',
          null,
          timeout: const Duration(seconds: 45),
        ),
      );
    }
  }

  static Map<String, dynamic> _findPluginMarketplace(
    Map<String, dynamic> response,
    String marketplaceName, {
    required String pluginName,
  }) {
    final marketplaces = response['marketplaces'];
    if (marketplaces is! List) {
      throw const CodexSessionException(
        'Codex returned no plugin marketplaces.',
      );
    }
    for (final rawMarketplace in marketplaces) {
      if (rawMarketplace is! Map) continue;
      final marketplace = _asMap(rawMarketplace);
      if (marketplace['name'] != marketplaceName) continue;
      final plugins = marketplace['plugins'];
      if (plugins is List &&
          plugins.any(
            (rawPlugin) =>
                rawPlugin is Map && _asMap(rawPlugin)['name'] == pluginName,
          )) {
        return marketplace;
      }
      // Remote catalogs can expose an installable selector without a local
      // plugin path. Let app-server validate the exact remote name.
      if (marketplace['path'] == null) return marketplace;
    }
    throw CodexSessionException(
      'Plugin "$pluginName" was not found in marketplace "$marketplaceName".',
    );
  }

  /// Starts the app-server-owned MCP OAuth flow for this local session.
  ///
  /// The app-server owns the loopback callback and credential exchange. Only
  /// the returned authorization URL crosses into the Android browser; raw
  /// OAuth errors and callback details are intentionally not surfaced here.
  Future<Uri> beginMcpOAuthLogin(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        normalizedName.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const CodexSessionException('MCP server name is invalid.');
    }
    await start();
    final threadId = _threadId;
    if (threadId == null || threadId.isEmpty) {
      throw const CodexSessionException('The Codex thread is not ready.');
    }

    late final Map<String, dynamic> response;
    try {
      response = _asMap(
        await _request('mcpServer/oauth/login', <String, dynamic>{
          'name': normalizedName,
          'threadId': threadId,
        }, timeout: const Duration(seconds: 90)),
      );
    } on Object {
      throw CodexSessionException(
        'Could not start MCP OAuth for "$normalizedName". Confirm that it is '
        'configured as a streamable HTTP server and supports OAuth.',
      );
    }

    final rawUrl = response['authorizationUrl'];
    final authorizationUrl = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (authorizationUrl == null ||
        !const <String>{'http', 'https'}.contains(authorizationUrl.scheme) ||
        authorizationUrl.host.isEmpty ||
        authorizationUrl.userInfo.isNotEmpty) {
      throw const CodexSessionException(
        'Codex returned an invalid MCP authorization URL.',
      );
    }
    return authorizationUrl;
  }

  /// Removes one MCP server from this app-server's user config layer only.
  ///
  /// Refuses to mutate when another config layer also defines the same server,
  /// so a project/profile override cannot make a successful-looking no-op.
  /// Secret-bearing config and raw app-server errors are never surfaced.
  Future<void> removeMcpServer(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        normalizedName.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const CodexSessionException('MCP server name is invalid.');
    }
    await start();
    final cwd = _sessionCwd;
    if (cwd == null || cwd.isEmpty) {
      throw const CodexSessionException('Codex session workspace is not ready');
    }

    Map<String, dynamic> layeredConfig;
    try {
      layeredConfig = _asMap(
        await _request('config/read', <String, dynamic>{
          'includeLayers': true,
          'cwd': cwd,
        }, timeout: const Duration(seconds: 30)),
      );
    } on Object {
      throw const CodexSessionException(
        'Could not read layered MCP configuration.',
      );
    }

    final rawLayers = layeredConfig['layers'];
    if (rawLayers is! List) {
      throw const CodexSessionException(
        'This Codex app-server does not expose config layers for safe MCP edits.',
      );
    }
    final layers = <Map>[];
    for (final layer in rawLayers) {
      if (layer is! Map) {
        throw const CodexSessionException(
          'Codex returned an invalid config layer; no MCP changes were made.',
        );
      }
      layers.add(layer);
    }
    final baseUserIndices = <int>[];
    for (var index = 0; index < layers.length; index++) {
      final source = _asMap(layers[index]['name']);
      if (source['type'] == 'user' &&
          (!source.containsKey('profile') || source['profile'] == null)) {
        baseUserIndices.add(index);
      }
    }
    if (baseUserIndices.length != 1) {
      throw const CodexSessionException(
        'A unique writable base user config layer was not found.',
      );
    }

    final baseUserIndex = baseUserIndices.single;
    final userLayer = _asMap(layers[baseUserIndex]);
    if (userLayer['disabledReason'] is String &&
        (userLayer['disabledReason'] as String).isNotEmpty) {
      throw const CodexSessionException(
        'The base user config layer is disabled; no MCP changes were made.',
      );
    }
    final version = userLayer['version'];
    if (version is! String || version.isEmpty) {
      throw const CodexSessionException(
        'The writable user config layer has no version.',
      );
    }
    final userServers = _mcpServersFromConfig(_asMap(userLayer['config']));
    if (!userServers.containsKey(normalizedName)) {
      throw CodexSessionException(
        'MCP server "$normalizedName" is not defined in the base user config.',
      );
    }

    for (var index = 0; index < layers.length; index++) {
      if (index == baseUserIndex) continue;
      if (_mcpServersFromConfig(_asMap(layers[index]['config']))
          .containsKey(normalizedName)) {
        throw CodexSessionException(
          'MCP server "$normalizedName" is also defined by another config layer; it was not changed.',
        );
      }
    }
    final effectiveServers = _mcpServersFromConfig(
      _asMap(layeredConfig['config']),
    );
    if (!effectiveServers.containsKey(normalizedName)) {
      throw CodexSessionException(
        'MCP server "$normalizedName" is not present in the effective session config.',
      );
    }

    final keyPath = 'mcp_servers.${jsonEncode(normalizedName)}';
    try {
      await _request('config/batchWrite', <String, dynamic>{
        'edits': <Map<String, dynamic>>[
          <String, dynamic>{
            'keyPath': keyPath,
            'value': null,
            'mergeStrategy': 'replace',
          },
        ],
        'filePath': null,
        'expectedVersion': version,
        'reloadUserConfig': true,
      }, timeout: const Duration(seconds: 30));
    } on Object {
      throw const CodexSessionException(
        'Codex rejected the MCP configuration update; no success was reported.',
      );
    }

    Map<String, dynamic> verifiedConfig;
    try {
      verifiedConfig = _asMap(
        await _request('config/read', <String, dynamic>{
          'includeLayers': false,
          'cwd': cwd,
        }, timeout: const Duration(seconds: 30)),
      );
    } on Object {
      throw const CodexSessionException(
        'MCP config was written, but its effective state could not be verified.',
      );
    }
    if (_mcpServersFromConfig(_asMap(verifiedConfig['config']))
        .containsKey(normalizedName)) {
      throw const CodexSessionException(
        'The MCP server remains in the effective config after the update.',
      );
    }
  }

  Future<void> addMcpServer(CodexMcpAddRequest request) async {
    final name = request.name.trim();
    await start();
    final cwd = _sessionCwd;
    if (cwd == null || cwd.isEmpty) {
      throw const CodexSessionException('Codex session workspace is not ready');
    }

    Map<String, dynamic> layeredConfig;
    try {
      layeredConfig = _asMap(
        await _request('config/read', <String, dynamic>{
          'includeLayers': true,
          'cwd': cwd,
        }, timeout: const Duration(seconds: 30)),
      );
    } on Object {
      throw const CodexSessionException(
        'Could not read layered MCP configuration.',
      );
    }
    final rawLayers = layeredConfig['layers'];
    if (rawLayers is! List) {
      throw const CodexSessionException(
        'This Codex app-server does not expose config layers for safe MCP edits.',
      );
    }
    final layers = rawLayers
        .whereType<Map>()
        .map(_asMap)
        .toList(growable: false);
    final baseUserIndices = <int>[];
    for (var index = 0; index < layers.length; index++) {
      final source = _asMap(layers[index]['name']);
      if (source['type'] == 'user' &&
          (!source.containsKey('profile') || source['profile'] == null)) {
        baseUserIndices.add(index);
      }
    }
    if (baseUserIndices.length != 1) {
      throw const CodexSessionException(
        'A unique writable base user config layer was not found.',
      );
    }
    final baseUserIndex = baseUserIndices.single;
    final userLayer = layers[baseUserIndex];
    if (userLayer['disabledReason'] is String &&
        (userLayer['disabledReason'] as String).isNotEmpty) {
      throw const CodexSessionException(
        'The base user config layer is disabled; no MCP changes were made.',
      );
    }
    final version = userLayer['version'];
    if (version is! String || version.isEmpty) {
      throw const CodexSessionException(
        'The writable user config layer has no version.',
      );
    }
    if (_mcpServersFromConfig(_asMap(userLayer['config'])).containsKey(name)) {
      throw CodexSessionException(
        'MCP server "$name" is already defined in the base user config.',
      );
    }
    for (var index = 0; index < layers.length; index++) {
      if (index == baseUserIndex) continue;
      if (_mcpServersFromConfig(_asMap(layers[index]['config']))
          .containsKey(name)) {
        throw CodexSessionException(
          'MCP server "$name" is already defined by another config layer.',
        );
      }
    }
    if (_mcpServersFromConfig(_asMap(layeredConfig['config']))
        .containsKey(name)) {
      throw CodexSessionException(
        'MCP server "$name" already exists in the effective session config.',
      );
    }

    try {
      await _request('config/batchWrite', <String, dynamic>{
        'edits': <Map<String, dynamic>>[
          <String, dynamic>{
            'keyPath': 'mcp_servers.${jsonEncode(name)}',
            'value': request.config,
            'mergeStrategy': 'replace',
          },
        ],
        'filePath': null,
        'expectedVersion': version,
        'reloadUserConfig': true,
      }, timeout: const Duration(seconds: 30));
    } on Object {
      throw const CodexSessionException(
        'Codex rejected the MCP configuration update; no success was reported.',
      );
    }

    Map<String, dynamic> verifiedConfig;
    try {
      verifiedConfig = _asMap(
        await _request('config/read', <String, dynamic>{
          'includeLayers': false,
          'cwd': cwd,
        }, timeout: const Duration(seconds: 30)),
      );
    } on Object {
      throw const CodexSessionException(
        'MCP config was written, but its effective state could not be verified.',
      );
    }
    final stored = _asMap(
      _mcpServersFromConfig(_asMap(verifiedConfig['config']))[name],
    );
    final matches = request.config.entries.every((entry) {
      final actual = stored[entry.key];
      return entry.value is List
          ? jsonEncode(actual) == jsonEncode(entry.value)
          : actual == entry.value ||
                (entry.value is Map &&
                    jsonEncode(actual) == jsonEncode(entry.value));
    });
    if (!matches) {
      throw const CodexSessionException(
        'The MCP server configuration could not be verified after writing.',
      );
    }
  }

  /// Queries live MCP connection health for the current app-server thread.
  /// The reduced detail mode avoids fetching resource inventories that the UI
  /// does not display.
  Future<List<CodexMcpServerStatusSummary>> readMcpServerStatuses() async {
    await start();
    final threadId = _threadId;
    if (threadId == null || threadId.isEmpty) {
      throw const CodexSessionException('Codex thread is not ready');
    }
    final statuses = <CodexMcpServerStatusSummary>[];
    final seenCursors = <String>{};
    String? cursor;
    while (true) {
      final response = _asMap(
        await _request('mcpServerStatus/list', <String, dynamic>{
          'detail': 'toolsAndAuthOnly',
          'limit': 100,
          'threadId': threadId,
          if (cursor != null) 'cursor': cursor,
        }, timeout: const Duration(seconds: 45)),
      );
      statuses.addAll(CodexMcpServerStatusSummary.parse(response['data']));
      final nextCursor = response['nextCursor'];
      if (nextCursor == null) return statuses;
      if (nextCursor is! String ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        throw const CodexSessionException(
          'Codex MCP status returned an invalid pagination cursor',
        );
      }
      cursor = nextCursor;
    }
  }

  /// Requests the app-server's non-destructive context compaction flow.
  Future<void> compact() async {
    await start();
    final threadId = _threadId;
    if (threadId == null || threadId.isEmpty) {
      throw const CodexSessionException('Codex thread is not ready');
    }
    await _request('thread/compact/start', <String, dynamic>{
      'threadId': threadId,
    });
  }

  /// Runs an argv vector through this session's existing app-server process.
  ///
  /// Unlike `/cli`, this does not spawn a second Codex process. The app-server
  /// applies the session's current permission profile/sandbox and workspace
  /// environment. Shell syntax is intentionally not accepted here; callers
  /// must pass already-tokenized argv.
  Future<CodexCommandExecResult> executeCommand(
    Iterable<String> command, {
    String? cwd,
    Duration timeout = const Duration(minutes: 2),
    CodexCommandOutputCallback? onOutput,
    bool tty = false,
    int ptyRows = 24,
    int ptyCols = 80,
  }) async {
    final argv = command.toList(growable: false);
    if (argv.isEmpty ||
        argv.any((part) => part.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
      throw const CodexSessionException(
        'command/exec requires a non-empty argv without control characters.',
      );
    }
    if (tty &&
        (ptyRows <= 0 || ptyRows > 65535 || ptyCols <= 0 || ptyCols > 65535)) {
      throw const CodexSessionException(
        'PTY rows and columns must be between 1 and 65535.',
      );
    }
    await start();
    if (_activeCommandProcessId != null) {
      throw const CodexSessionException(
        'Another session command is already running.',
      );
    }
    final workingDirectory = cwd?.trim().isNotEmpty == true
        ? cwd!.trim()
        : _sessionCwd;
    final processId = 'session-command-${_nextRequestId++}';
    _activeCommandProcessId = processId;
    _activeCommandStdout = '';
    _activeCommandStderr = '';
    _commandOutputCallback = onOutput;
    try {
      final response = _asMap(
        await _request('command/exec', <String, dynamic>{
          'command': argv,
          'processId': processId,
          'streamStdoutStderr': true,
          if (tty) ...{
            'tty': true,
            'streamStdin': true,
            'size': <String, int>{'rows': ptyRows, 'cols': ptyCols},
          },
          if (workingDirectory != null && workingDirectory.isNotEmpty)
            'cwd': workingDirectory,
          if (_useNamedPermissionProfile)
            'permissionProfile': _settings.permissions
          else
            'sandboxPolicy': _runtimeSandboxPolicy,
          'timeoutMs': timeout.inMilliseconds,
        }, timeout: timeout + const Duration(seconds: 5)),
      );
      final rawExitCode = response['exitCode'];
      final exitCode = rawExitCode is int
          ? rawExitCode
          : rawExitCode is num
          ? rawExitCode.toInt()
          : int.tryParse('$rawExitCode');
      if (exitCode == null) {
        throw const CodexSessionException(
          'command/exec returned no valid exit code.',
        );
      }
      final bufferedStdout = response['stdout'] is String
          ? response['stdout'] as String
          : '';
      final bufferedStderr = response['stderr'] is String
          ? response['stderr'] as String
          : '';
      return CodexCommandExecResult(
        exitCode: exitCode,
        stdout: '$_activeCommandStdout$bufferedStdout',
        stderr: '$_activeCommandStderr$bufferedStderr',
      );
    } finally {
      _activeCommandProcessId = null;
      _activeCommandStdout = '';
      _activeCommandStderr = '';
      _commandOutputCallback = null;
    }
  }

  /// Writes UTF-8 bytes to the active PTY/streaming command's stdin.
  Future<void> writeCommandInput(
    String input, {
    bool closeStdin = false,
  }) async {
    final processId = _activeCommandProcessId;
    if (processId == null) {
      throw const CodexSessionException('No active streaming command.');
    }
    await _request('command/exec/write', <String, dynamic>{
      'processId': processId,
      if (input.isNotEmpty) 'deltaBase64': base64Encode(utf8.encode(input)),
      'closeStdin': closeStdin,
    });
  }

  /// Resizes the active PTY-backed command in character cells.
  Future<void> resizeCommand({required int rows, required int cols}) async {
    final processId = _activeCommandProcessId;
    if (processId == null) {
      throw const CodexSessionException('No active streaming command.');
    }
    if (rows <= 0 || rows > 65535 || cols <= 0 || cols > 65535) {
      throw const CodexSessionException(
        'PTY rows and columns must be between 1 and 65535.',
      );
    }
    await _request('command/exec/resize', <String, dynamic>{
      'processId': processId,
      'size': <String, int>{'rows': rows, 'cols': cols},
    });
  }

  /// Persists the user-selected name on the Codex thread when it is loaded.
  Future<void> setThreadName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const CodexSessionException('Thread name cannot be empty.');
    }
    _threadNameRevision++;
    await _cancelAutomaticThreadTitle();
    await _setThreadName(normalized);
    _threadName = normalized;
  }

  /// Generate and persist a title without adding a message to the visible
  /// conversation. OpenAI sessions use the fixed phone Luna/low title route;
  /// custom providers may supply their configured model and effort so their
  /// sessions receive the same semantic naming behavior.
  Future<String?> generateAutomaticThreadTitle(String userPrompt) async {
    final selectedModel = _settings.model.trim();
    final model = (_automaticTitleModel?.trim().isNotEmpty ?? false)
        ? _automaticTitleModel!.trim()
        : selectedModel;
    if (model.isEmpty ||
        (_automaticTitleModel == null &&
            !selectedModel.toLowerCase().contains('luna')) ||
        userPrompt.trim().isEmpty) {
      return null;
    }
    final effort = _automaticTitleEffort?.trim().isNotEmpty == true
        ? _automaticTitleEffort!.trim()
        : 'low';
    if (_backend.descriptor.kind == BackendKind.fake &&
        _processFactory == null) {
      return null;
    }
    await start();
    final sourceThreadId = _threadId;
    final cwd = _sessionCwd;
    if (sourceThreadId == null || cwd == null || _threadName != null) {
      return null;
    }
    if (_pendingAutomaticTitle != null || _stopped) {
      return null;
    }

    final revision = _threadNameRevision;
    final pendingTitle = _PendingAutomaticThreadTitle();
    _pendingAutomaticTitle = pendingTitle;
    String? temporaryThreadId;
    try {
      final configResponse = _asMap(
        await _request('config/read', <String, dynamic>{
          'includeLayers': false,
          'cwd': cwd,
        }, timeout: const Duration(seconds: 30)),
      );
      if (_titleWasCancelled(pendingTitle, revision)) return null;
      final serverConfig = _asMap(configResponse['config']);
      final effectiveMcpServers = _mcpServersFromConfig(serverConfig);

      final threadResponse = _asMap(
        await _request('thread/start', <String, dynamic>{
          'cwd': cwd,
          'model': model,
          'approvalPolicy': 'never',
          'sandbox': 'read-only',
          'ephemeral': true,
          'threadSource': 'system',
          'runtimeWorkspaceRoots': <String>[],
          'environments': <Object?>[],
          'dynamicTools': <Object?>[],
          'selectedCapabilityRoots': <Object?>[],
          'config': <String, Object?>{
            ...CodexThreadTitle.isolatedConfig(effectiveMcpServers),
            'model_reasoning_effort': effort,
          },
        }, timeout: const Duration(seconds: 30)),
      );
      temporaryThreadId = _asMap(threadResponse['thread'])['id'] as String?;
      if (temporaryThreadId == null || temporaryThreadId.isEmpty) {
        return null;
      }
      pendingTitle.temporaryThreadId = temporaryThreadId;
      _pendingTitleTurns[temporaryThreadId] = pendingTitle;
      if (_titleWasCancelled(pendingTitle, revision)) return null;

      final turnResponse = _asMap(
        await _request('turn/start', <String, dynamic>{
          'threadId': temporaryThreadId,
          'input': <Map<String, String>>[
            <String, String>{
              'type': 'text',
              'text': CodexThreadTitle.promptFor(userPrompt),
            },
          ],
          'outputSchema': CodexThreadTitle.outputSchema,
          'effort': effort,
        }, timeout: const Duration(seconds: 30)),
      );
      final returnedTurnId = _asMap(turnResponse['turn'])['id'] as String?;
      pendingTitle.turnId ??= returnedTurnId;
      if (pendingTitle.turnId == null ||
          _titleWasCancelled(pendingTitle, revision)) {
        return null;
      }

      final response = await Future.any<String?>(<Future<String?>>[
        pendingTitle.response.future,
        pendingTitle.cancellation.future.then<String?>((_) => null),
      ]).timeout(const Duration(seconds: 30), onTimeout: () => null);
      final title = response == null ? null : CodexThreadTitle.parse(response);
      if (title == null || _titleWasCancelled(pendingTitle, revision)) {
        return null;
      }

      await _setThreadName(title, threadId: sourceThreadId);
      if (_titleWasCancelled(pendingTitle, revision)) return null;
      _threadName = title;
      return title;
    } catch (_) {
      // Title metadata is optional and must never fail the visible session.
      return null;
    } finally {
      if (temporaryThreadId != null) {
        _pendingTitleTurns.remove(temporaryThreadId);
      }
      if (!pendingTitle.turnCompleted &&
          pendingTitle.turnId != null &&
          temporaryThreadId != null &&
          _process != null &&
          !_stopped) {
        try {
          await _request('turn/interrupt', <String, String>{
            'threadId': temporaryThreadId,
            'turnId': pendingTitle.turnId!,
          }, timeout: const Duration(seconds: 5));
        } catch (_) {
          // The turn may already have completed or the process may be exiting.
        }
      }
      if (temporaryThreadId != null && _process != null && !_stopped) {
        try {
          await _request('thread/unsubscribe', <String, String>{
            'threadId': temporaryThreadId,
          }, timeout: const Duration(seconds: 5));
        } catch (_) {
          // Best effort: the thread is ephemeral and session-process-owned.
        }
      }
      if (identical(_pendingAutomaticTitle, pendingTitle)) {
        _pendingAutomaticTitle = null;
      }
    }
  }

  Future<void> _setThreadName(String name, {String? threadId}) async {
    final targetThreadId = threadId ?? _threadId;
    if (targetThreadId == null || targetThreadId.isEmpty) {
      throw const CodexSessionException('Codex thread is not ready');
    }
    await _request('thread/name/set', <String, dynamic>{
      'threadId': targetThreadId,
      'name': name,
    });
  }

  bool _titleWasCancelled(
    _PendingAutomaticThreadTitle pendingTitle,
    int revision,
  ) =>
      pendingTitle.cancellation.isCompleted ||
      revision != _threadNameRevision ||
      _threadId == null ||
      _stopped;

  Future<void> _cancelAutomaticThreadTitle() async {
    final pendingTitle = _pendingAutomaticTitle;
    if (pendingTitle == null) return;
    if (!pendingTitle.cancellation.isCompleted) {
      pendingTitle.cancellation.complete();
    }
    final temporaryThreadId = pendingTitle.temporaryThreadId;
    final turnId = pendingTitle.turnId;
    if (temporaryThreadId == null || turnId == null || _stopped) return;
    try {
      await _request('turn/interrupt', <String, String>{
        'threadId': temporaryThreadId,
        'turnId': turnId,
      }, timeout: const Duration(seconds: 5));
    } catch (_) {
      // The title turn may already have completed.
    }
  }

  bool _handleAutomaticTitleNotification(
    String method,
    Map<String, dynamic> params,
  ) {
    final threadId = params['threadId'];
    if (threadId is! String) return false;
    final pendingTitle = _pendingTitleTurns[threadId];
    if (pendingTitle == null) return false;

    final turn = _asMap(params['turn']);
    final incomingTurnId = turn['id'] ?? params['turnId'];
    if (incomingTurnId is String && incomingTurnId.isNotEmpty) {
      pendingTitle.turnId ??= incomingTurnId;
    }
    if (method == 'item/completed') {
      final item = _asMap(params['item']);
      if (item['type'] == 'agentMessage' && item['text'] is String) {
        pendingTitle.responseText = item['text'] as String;
      }
    } else if (method == 'turn/completed' ||
        method == 'turn/failed' ||
        method == 'turn/interrupted' ||
        method == 'turn/aborted') {
      final expectedTurnId = pendingTitle.turnId;
      if (expectedTurnId == null ||
          incomingTurnId == null ||
          incomingTurnId == expectedTurnId) {
        pendingTitle.turnCompleted = true;
        if (!pendingTitle.response.isCompleted) {
          pendingTitle.response.complete(
            method == 'turn/completed' && turn['status'] == 'completed'
                ? pendingTitle.responseText
                : null,
          );
        }
      }
    }
    // Do not expose usage, deltas, or lifecycle events from this hidden thread.
    return true;
  }

  @override
  Future<void> start() {
    if (_threadId != null && _process != null && !_stopped) {
      return Future<void>.value();
    }
    final existing = _startInFlight;
    if (existing != null) return existing;
    final operation = _start();
    _startInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_startInFlight, operation)) _startInFlight = null;
    });
  }

  @override
  Future<void> sendPrompt(
    String text, {
    List<ImageAttachment> images = const <ImageAttachment>[],
  }) async {
    final prompt = text.trim();
    if (prompt.isEmpty && images.isEmpty) {
      throw const CodexSessionException('prompt is empty');
    }
    await start();
    final threadId = _threadId;
    if (threadId == null) {
      throw const CodexSessionException('Codex thread is not ready');
    }
    _emit(
      CodexSessionEvent(
        type: CodexSessionEventType.user,
        text: prompt.isEmpty ? '[图片 ${images.length} 张]' : prompt,
        params: <String, dynamic>{'imageCount': images.length},
        threadId: threadId,
      ),
    );
    final input = <Map<String, dynamic>>[
      if (prompt.isNotEmpty) <String, dynamic>{'type': 'text', 'text': prompt},
      for (final image in images)
        // Codex app-server uses the SDK's ImageInput wire shape.
        <String, dynamic>{'type': 'image', 'url': image.dataUrl},
    ];
    await _request('turn/start', <String, dynamic>{
      'threadId': threadId,
      'input': input,
      'model': _settings.model,
      'effort': _settings.reasoningEffort,
      'approvalPolicy': _effectiveApprovalPolicy,
      if (_useNamedPermissionProfile)
        'permissions': _settings.permissions
      else
        'sandboxPolicy': _runtimeSandboxPolicy,
      'collaborationMode': <String, dynamic>{
        'mode': _settings.collaborationMode,
        'settings': <String, String>{
          'model': _settings.model,
          'reasoning_effort': _settings.reasoningEffort,
        },
      },
    });
  }

  @override
  Future<void> respondToRequest(
    Object requestId,
    Map<String, dynamic> result,
  ) async {
    await _writeEnvelope(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': requestId,
      'result': result,
    });
  }

  @override
  Future<void> respondToApproval(
    CodexSessionEvent approval, {
    required bool approved,
    bool forSession = false,
    Map<String, dynamic>? decisionOverride,
  }) async {
    final requestId = approval.requestId;
    final method = approval.requestMethod;
    if (requestId == null ||
        method == null ||
        !_approvalMethods.contains(method)) {
      throw const CodexSessionException('Unsupported approval request.');
    }
    final rawDecisions = approval.params?['availableDecisions'];
    bool supportsDecision(String decision) => rawDecisions is List
        ? rawDecisions.contains(decision)
        : _legacyApprovalSupports(approval, decision);
    if (decisionOverride != null) {
      final isAdvertised = rawDecisions is List
          ? rawDecisions.any(
              (candidate) => _sameJsonValue(candidate, decisionOverride),
            )
          : _legacyApprovalAmendmentSupports(approval, decisionOverride);
      if (method != 'item/commandExecution/requestApproval' ||
          forSession ||
          !isAdvertised) {
        throw const CodexSessionException(
          'Codex did not offer this persistent approval rule.',
        );
      }
      await respondToRequest(requestId, <String, dynamic>{
        'decision': decisionOverride,
      });
      return;
    }
    if (approved &&
        !supportsDecision(forSession ? 'acceptForSession' : 'accept')) {
      throw const CodexSessionException(
        'Codex did not offer this approval decision.',
      );
    }
    if (!approved && method != 'item/permissions/requestApproval') {
      final rejection =
          rawDecisions is List &&
              rawDecisions.contains('cancel') &&
              !rawDecisions.contains('decline')
          ? 'cancel'
          : 'decline';
      if (!supportsDecision(rejection)) {
        throw const CodexSessionException(
          'Codex did not offer a rejection decision.',
        );
      }
    }
    if (method == 'item/permissions/requestApproval') {
      final permissions = approved
          ? _asMap(approval.params?['permissions'])
          : <String, dynamic>{};
      await respondToRequest(requestId, <String, dynamic>{
        'scope': forSession && approved ? 'session' : 'turn',
        'permissions': permissions,
      });
      return;
    }
    final decisions = rawDecisions;
    final canCancel =
        decisions is List &&
        decisions.contains('cancel') &&
        !decisions.contains('decline');
    await respondToRequest(requestId, <String, dynamic>{
      'decision': approved
          ? (forSession ? 'acceptForSession' : 'accept')
          : (canCancel ? 'cancel' : 'decline'),
    });
  }

  @override
  Future<void> stop() async {
    _threadNameRevision++;
    await _cancelAutomaticThreadTitle();
    // Invalidate the current event stream before asking the process to stop.
    // A native process can still flush a late stdout/exit event while its
    // subscription is being cancelled; that event must not affect a later
    // session created by start().
    _processGeneration++;
    if (!_stopped && _threadId != null && _turnId != null) {
      await interrupt();
    }
    final wasStopped = _stopped;
    _stopped = true;
    _turnId = null;
    _interruptingTurnId = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          const CodexSessionException('Codex session stopped.'),
        );
      }
    }
    _pending.clear();
    final subscription = _processSubscription;
    _processSubscription = null;
    final cancelFuture = subscription?.cancel();
    final process = _process;
    _process = null;
    await process?.stop();
    await cancelFuture;
    if (!wasStopped) {
      _emit(const CodexSessionEvent(type: CodexSessionEventType.stopped));
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _eventController.close();
  }

  Future<void> _start() async {
    if (_disposed) throw const CodexSessionException('session is disposed');
    _stopped = false;
    _threadId = null;
    _threadPath = null;
    _turnId = null;
    _assistantDeltaReceivedForTurn = false;
    _assistantItemsWithDeltas.clear();
    _lineBuffer = '';
    _exitEventEmitted = false;
    final processGeneration = ++_processGeneration;
    _emit(const CodexSessionEvent(type: CodexSessionEventType.status));
    try {
      final workspace = await _backend.openWorkspace(_workspace);
      final process =
          _processFactory?.call(workspace) ??
          _backend.startInteractive(
            ExecutionRequest(
              argv: _argv,
              cwd: workspace.ref.hostPath,
              identity: _identity,
              timeout: const Duration(hours: 12),
              environment: _environment,
            ),
          );
      _process = process;
      _processSubscription = process.events.listen(
        (event) {
          if (processGeneration != _processGeneration) return;
          _handleExecutionEvent(event);
        },
        onError: (Object error, StackTrace stack) {
          if (processGeneration != _processGeneration) return;
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.error,
              text: '$error',
              method: 'execution/error',
            ),
          );
        },
      );

      await _request('initialize', <String, dynamic>{
        'clientInfo': <String, String>{
          'name': 'codex',
          'version': '1.0.0',
          'title': 'codex',
        },
        'capabilities': <String, bool>{'experimentalApi': true},
      });
      await _notify('initialized', <String, dynamic>{});

      final resumeThreadId = _resumeThreadId;
      // The native compatibility worker binds the selected Android host
      // workspace to the guest's fixed /workspace path. Keep the native
      // process request on the host path, but give Codex app-server the path
      // it can actually resolve inside the guest namespace.
      final sessionCwd =
          _backend.descriptor.kind == BackendKind.linuxCompatibility
          ? '/workspace'
          : workspace.ref.hostPath;
      _sessionCwd = sessionCwd;
      final threadMethod = resumeThreadId == null
          ? 'thread/start'
          : 'thread/resume';
      // The PRoot guest is already the local execution boundary: it exposes
      // only the verified rootfs, the selected host workspace as /workspace,
      // and the guest home/temp directories. Codex's workspace-write mode
      // would add a second bwrap sandbox inside that guest. Android/PRoot
      // cannot provide the Linux kernel primitives that bwrap needs, which
      // makes every workspace command exit with code 182. Disable only that
      // inner layer for the compatibility backend; the requested value stays
      // in the UI state and the outer PRoot boundary remains enforced.
      // A root session needs to inspect and operate on files outside the
      // selected workspace. Preserve the user's selected Codex approval
      // policy instead of forcing every Root command through `untrusted` or a
      // private broker. RootAccessPolicy remains a visible soft-routing aid;
      // it is not an OS write sandbox and cannot replace user judgment for
      // boot-critical changes.
      // `danger-full-access` provides the requested visibility only where the
      // selected execution identity actually has host access.
      final response = await _request(threadMethod, <String, dynamic>{
        'cwd': sessionCwd,
        // Android workspaces are local app-owned directories and are not
        // required to be Git repositories.  Keep the same behavior for
        // thread/start and thread/resume so the direct App UID runtime and
        // the PRoot fallback share one session contract.
        'skipGitRepoCheck': true,
        'experimentalRawEvents': false,
        'persistExtendedHistory': true,
        'model': _settings.model,
        'approvalPolicy': _effectiveApprovalPolicy,
        if (_useNamedPermissionProfile)
          'permissions': _settings.permissions
        else
          'sandbox': _runtimeSandbox,
        'developerInstructions': androidCodexAgentInstructions.trim(),
        'config': <String, String>{
          'model_reasoning_effort': _settings.reasoningEffort,
        },
        if (resumeThreadId != null) 'threadId': resumeThreadId,
        if (resumeThreadId != null &&
            _resumeThreadPath != null &&
            _resumeThreadPath!.trim().isNotEmpty)
          'path': _resumeThreadPath,
      });
      final thread = _asMap(response)['thread'];
      final responseThreadId = _asMap(thread)['id'];
      final threadId = responseThreadId is String && responseThreadId.isNotEmpty
          ? responseThreadId
          : resumeThreadId;
      if (threadId == null || threadId.isEmpty) {
        throw CodexSessionException('$threadMethod returned no thread id');
      }
      _threadId = threadId;
      final responseThreadPath = _asMap(thread)['path'];
      _threadPath =
          responseThreadPath is String && responseThreadPath.trim().isNotEmpty
          ? responseThreadPath.trim()
          : (_resumeThreadPath?.trim().isNotEmpty == true
                ? _resumeThreadPath!.trim()
                : null);
      final responseThreadName = _asMap(thread)['name'];
      if (responseThreadName is String &&
          responseThreadName.trim().isNotEmpty) {
        _threadName = responseThreadName.trim();
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.threadName,
            text: _threadName,
            threadId: threadId,
          ),
        );
      }
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.status,
          threadId: threadId,
          text: 'ready',
        ),
      );
    } catch (error) {
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.error,
          text: '$error',
          method: 'session/start-error',
        ),
      );
      await stop();
      rethrow;
    }
  }

  Future<Object?> _request(
    String method,
    Map<String, dynamic>? params, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final id = '${_nextRequestId++}';
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      await _writeEnvelope(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': int.parse(id),
        'method': method,
        if (params != null) 'params': params,
      });
    } catch (error, stack) {
      _pending.remove(id);
      completer.completeError(error, stack);
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw CodexSessionException('RPC request timed out: $method');
      },
    );
  }

  Future<void> _notify(String method, Map<String, dynamic> params) =>
      _writeEnvelope(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      });

  /// Requests that the active turn stop before the process is torn down.
  ///
  /// `turn/interrupt` is a deferred RPC in app-server: its response is sent
  /// after the core emits the aborted/completed notification. Register the
  /// request instead of writing an untracked JSON-RPC envelope, otherwise a
  /// missing notification leaves the UI stuck in `interrupting` forever.
  @override
  Future<void> interrupt() async {
    final commandProcessId = _activeCommandProcessId;
    if (commandProcessId != null && !_stopped) {
      try {
        await _request('command/exec/terminate', <String, String>{
          'processId': commandProcessId,
        }, timeout: const Duration(seconds: 5));
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.status,
            text: 'interrupting',
            threadId: _threadId,
          ),
        );
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.status,
            text: 'idle',
            threadId: _threadId,
          ),
        );
      } catch (error) {
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.error,
            text: '$error',
            method: 'command/exec/terminate-error',
          ),
        );
      }
      return;
    }
    final threadId = _threadId;
    final turnId = _turnId;
    if (threadId == null || turnId == null || _stopped) return;
    if (_interruptingTurnId == turnId) return;
    _interruptingTurnId = turnId;
    _emit(
      CodexSessionEvent(
        type: CodexSessionEventType.status,
        text: 'interrupting',
        threadId: threadId,
      ),
    );
    try {
      final response = _request('turn/interrupt', <String, String>{
        'threadId': threadId,
        'turnId': turnId,
      }, timeout: const Duration(seconds: 15));
      unawaited(_finishTurnInterrupt(response, threadId, turnId));
    } catch (error) {
      _interruptingTurnId = null;
      if (!_stopped) _emitInterruptError(error);
    }
  }

  Future<void> _finishTurnInterrupt(
    Future<Object?> response,
    String threadId,
    String turnId,
  ) async {
    try {
      await response;
      if (_stopped || _turnId != turnId) return;
      // Some compatible app-server builds return the deferred RPC response
      // without forwarding the terminal notification to this client. Treat a
      // successful interrupt response as terminal in that case.
      _turnId = null;
      _interruptingTurnId = null;
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.status,
          text: 'idle',
          method: 'turn/interrupted',
          threadId: threadId,
        ),
      );
    } catch (error) {
      if (_stopped || _turnId != turnId) return;
      _interruptingTurnId = null;
      _emitInterruptError(error);
    }
  }

  void _emitInterruptError(Object error) {
    _emit(
      CodexSessionEvent(
        type: CodexSessionEventType.error,
        text: '$error',
        method: 'turn/interrupt-error',
      ),
    );
  }

  Future<void> _writeEnvelope(Map<String, dynamic> envelope) async {
    final process = _process;
    if (process == null || _stopped) {
      throw const CodexSessionException('Codex process is not running');
    }
    await process.write('${jsonEncode(envelope)}\n');
  }

  void _handleExecutionEvent(ExecutionEvent event) {
    if (event.stdout != null) _consumeStdout(event.stdout!);
    if (event.stderr != null) {
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.stderr,
          text: event.stderr,
          method: 'process/stderr',
        ),
      );
    }
    if (event.error != null) {
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.error,
          text: event.error,
          method: 'process/error',
        ),
      );
    }
    if (event.exitCode != null) {
      if (_exitEventEmitted) return;
      _exitEventEmitted = true;
      // The process may emit buffered events after its terminal event. Make
      // all of them stale before the next session can reuse this client.
      _processGeneration++;
      _stopped = true;
      _turnId = null;
      _interruptingTurnId = null;
      _assistantDeltaReceivedForTurn = false;
      _assistantItemsWithDeltas.clear();
      _completePendingWithError('Codex process exited: ${event.exitCode}');
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.exit,
          exitCode: event.exitCode,
        ),
      );
    }
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
        if (decoded is Map) _handleEnvelope(_asMap(decoded));
      } catch (error) {
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.error,
            text: 'Invalid app-server JSON: $error',
            method: 'protocol/invalid-json',
          ),
        );
      }
    }
  }

  void _handleEnvelope(Map<String, dynamic> envelope) {
    final method = envelope['method'];
    if (method is String) {
      final id = envelope['id'];
      if (id != null) {
        _handleServerRequest(id, method, _asMap(envelope['params']));
      } else {
        _handleNotification(method, _asMap(envelope['params']));
      }
      return;
    }
    final id = envelope['id'];
    if (id == null) return;
    final pending = _pending.remove('$id');
    if (pending == null || pending.isCompleted) return;
    final error = envelope['error'];
    if (error != null) {
      pending.completeError(
        CodexSessionException('RPC error for request $id: ${_asMap(error)}'),
      );
    } else {
      pending.complete(envelope['result']);
    }
  }

  void _handleServerRequest(
    Object requestId,
    String method,
    Map<String, dynamic> params,
  ) {
    if (method == 'currentTime/read') {
      unawaited(
        respondToRequest(requestId, <String, dynamic>{
          'currentTimeAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      );
      return;
    }
    if (method == 'mcpServer/elicitation/request') {
      // MCP form/URL elicitations are user-facing requests, not JSON-RPC
      // approval decisions. Keep the original params intact so the CC Pocket
      // presentation adapter can render the requested schema and return the
      // MCP action/content envelope without translating or auto-accepting it.
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.approval,
          requestId: requestId,
          requestMethod: method,
          params: params,
        ),
      );
      return;
    }
    if (!_approvalMethods.contains(method)) {
      unawaited(_respondToRequestError(requestId, -32601, method));
      _emit(
        CodexSessionEvent(
          type: CodexSessionEventType.error,
          text: 'Unsupported app-server request: $method',
          requestId: requestId,
          requestMethod: method,
          params: params,
        ),
      );
      return;
    }
    _emit(
      CodexSessionEvent(
        type: CodexSessionEventType.approval,
        requestId: requestId,
        requestMethod: method,
        params: params,
      ),
    );
  }

  Future<void> _respondToRequestError(
    Object requestId,
    int code,
    String method,
  ) async {
    try {
      await _writeEnvelope(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': requestId,
        'error': <String, dynamic>{
          'code': code,
          'message': 'Unsupported server request: $method',
        },
      });
    } catch (_) {
      // The process may be stopping while the fail-closed response is sent.
    }
  }

  void _handleNotification(String method, Map<String, dynamic> params) {
    if (_handleAutomaticTitleNotification(method, params)) return;
    if (_handleCommandOutputNotification(method, params)) return;
    switch (method) {
      case 'mcpServer/oauthLogin/completed':
        final name = params['name'];
        if (name is String && name.isNotEmpty) {
          final notificationThreadId = params['threadId'];
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.mcpOAuth,
              method: method,
              params: <String, dynamic>{
                'name': name,
                'success': params['success'] == true,
              },
              threadId: notificationThreadId is String
                  ? notificationThreadId
                  : _threadId,
            ),
          );
        }
      case 'thread/started':
        final id = _asMap(params['thread'])['id'];
        if (id is String && (_threadId == null || id == _threadId)) {
          _threadId ??= id;
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.status,
              text: 'ready',
              method: method,
              threadId: _threadId,
            ),
          );
        }
      case 'thread/name/updated':
        final threadId = params['threadId'];
        final threadName = params['threadName'];
        if (threadId is String &&
            threadId == _threadId &&
            threadName is String &&
            threadName.trim().isNotEmpty) {
          _threadName = threadName.trim();
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.threadName,
              text: threadName.trim(),
              method: method,
              params: params,
              threadId: threadId,
            ),
          );
        }
      case 'turn/started':
        final turnId = _asMap(params['turn'])['id'];
        if (turnId is String && turnId.isNotEmpty) _turnId = turnId;
        _assistantDeltaReceivedForTurn = false;
        _assistantItemsWithDeltas.clear();
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.status,
            text: 'running',
            method: method,
            threadId: _threadId,
          ),
        );
      case 'turn/completed':
      case 'turn/failed':
      case 'turn/interrupted':
      case 'turn/aborted':
        _turnId = null;
        _interruptingTurnId = null;
        _emit(
          CodexSessionEvent(
            type: method == 'turn/failed'
                ? CodexSessionEventType.error
                : CodexSessionEventType.status,
            text: method == 'turn/failed' ? 'turn failed' : 'idle',
            method: method,
            threadId: _threadId,
          ),
        );
      case 'item/agentMessage/delta':
        final delta = params['delta'] ?? params['textDelta'];
        if (delta is String && delta.isNotEmpty) {
          _assistantDeltaReceivedForTurn = true;
          final itemId = params['itemId'];
          if (itemId is String && itemId.isNotEmpty) {
            _assistantItemsWithDeltas.add(itemId);
          }
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.assistantDelta,
              text: delta,
              method: method,
              params: params,
              threadId: _threadId,
            ),
          );
        }
      case 'item/reasoning/summaryTextDelta':
      case 'item/reasoning/textDelta':
      case 'item/plan/delta':
        final delta = params['delta'] ?? params['textDelta'];
        if (delta is String && delta.isNotEmpty) {
          _emit(
            CodexSessionEvent(
              type: CodexSessionEventType.reasoningDelta,
              text: delta,
              method: method,
              params: params,
              threadId: _threadId,
            ),
          );
        }
      case 'thread/tokenUsage/updated':
        final notificationThreadId = params['threadId'];
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.usage,
            method: method,
            params: params,
            threadId:
                notificationThreadId is String &&
                    notificationThreadId.isNotEmpty
                ? notificationThreadId
                : _threadId,
          ),
        );
      case 'item/started':
      case 'item/completed':
      case 'item/updated':
        final item = _asMap(params['item']);
        final itemType = item['type'];
        if (itemType == 'agentMessage') {
          // Some compatible app-server builds emit the completed assistant
          // item without any delta notifications. Preserve that final text,
          // while avoiding duplication when the normal delta stream was
          // already delivered for this item/turn.
          final completedText = item['text'];
          final itemId = item['id'];
          final alreadyStreamed = itemId is String && itemId.isNotEmpty
              ? _assistantItemsWithDeltas.contains(itemId)
              : _assistantDeltaReceivedForTurn;
          if (method == 'item/completed' &&
              completedText is String &&
              completedText.isNotEmpty &&
              !alreadyStreamed) {
            _assistantDeltaReceivedForTurn = true;
            if (itemId is String && itemId.isNotEmpty) {
              _assistantItemsWithDeltas.add(itemId);
            }
            _emit(
              CodexSessionEvent(
                type: CodexSessionEventType.assistantDelta,
                text: completedText,
                method: method,
                params: params,
                threadId: _threadId,
              ),
            );
          }
          return;
        }
        // User/assistant/reasoning items are protocol bookkeeping. The
        // client already renders the user prompt and consumes assistant and
        // reasoning deltas, so forwarding these lifecycle notifications as
        // tool cards duplicates the CC Pocket message stream.
        if (itemType == 'userMessage' ||
            itemType == 'reasoning' ||
            itemType == 'contextCompaction') {
          return;
        }
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.tool,
            text: jsonEncode(item.isEmpty ? params : item),
            method: method,
            params: params,
            threadId: _threadId,
          ),
        );
      case 'error':
      case 'warning':
        final error = _asMap(params['error']);
        _emit(
          CodexSessionEvent(
            type: CodexSessionEventType.error,
            text:
                params['message']?.toString() ??
                error['message']?.toString() ??
                method,
            method: method,
            params: params,
          ),
        );
    }
  }

  bool _handleCommandOutputNotification(
    String method,
    Map<String, dynamic> params,
  ) {
    if (method != 'command/exec/outputDelta') return false;
    final processId = params['processId'];
    if (processId != _activeCommandProcessId) return true;
    final encoded = params['deltaBase64'];
    final stream = params['stream'];
    if (encoded is! String || (stream != 'stdout' && stream != 'stderr')) {
      return true;
    }
    String decoded;
    try {
      decoded = utf8.decode(base64.decode(encoded), allowMalformed: true);
    } on Object {
      return true;
    }
    if (stream == 'stderr') {
      _activeCommandStderr += decoded;
    } else {
      _activeCommandStdout += decoded;
    }
    _commandOutputCallback?.call(decoded, stream == 'stderr');
    return true;
  }

  void _completePendingWithError(String message) {
    final error = CodexSessionException(message);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
  }

  void _emit(CodexSessionEvent event, {String? text}) {
    if (_disposed) return;
    if (text == null || event.text != null) {
      _eventController.add(event);
      return;
    }
    _eventController.add(
      CodexSessionEvent(
        type: event.type,
        text: text,
        requestId: event.requestId,
        requestMethod: event.requestMethod,
        method: event.method,
        params: event.params,
        threadId: event.threadId,
        exitCode: event.exitCode,
      ),
    );
  }

  static bool _legacyApprovalSupports(
    CodexSessionEvent approval,
    String decision,
  ) {
    switch (approval.requestMethod) {
      case 'item/permissions/requestApproval':
        return decision == 'accept' || decision == 'acceptForSession';
      case 'item/fileChange/requestApproval':
        return decision == 'accept' ||
            decision == 'acceptForSession' ||
            decision == 'decline' ||
            decision == 'cancel';
      case 'item/commandExecution/requestApproval':
        if (decision == 'accept' ||
            decision == 'decline' ||
            decision == 'cancel') {
          return true;
        }
        return decision == 'acceptForSession' &&
            approval.params?['networkApprovalContext'] is Map &&
            approval.params?['additionalPermissions'] == null;
      default:
        return false;
    }
  }

  static bool _legacyApprovalAmendmentSupports(
    CodexSessionEvent approval,
    Map<String, dynamic> decision,
  ) {
    final params = approval.params ?? const <String, dynamic>{};
    if (decision.length != 1) return false;
    final kind = decision.keys.single;
    final payload = _asMap(decision[kind]);
    if (kind == 'acceptWithExecpolicyAmendment') {
      final command = payload['execpolicy_amendment'];
      return params['networkApprovalContext'] == null &&
          params['additionalPermissions'] == null &&
          _sameJsonValue(params['proposedExecpolicyAmendment'], command);
    }
    if (kind == 'applyNetworkPolicyAmendment') {
      final networkRule = _asMap(payload['network_policy_amendment']);
      final proposed = params['proposedNetworkPolicyAmendments'];
      return params['networkApprovalContext'] is Map &&
          networkRule['action'] == 'allow' &&
          proposed is List &&
          proposed.any((candidate) => _sameJsonValue(candidate, networkRule));
    }
    return false;
  }

  static bool _sameJsonValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length ||
          !left.keys.every((key) => right.containsKey(key))) {
        return false;
      }
      return left.keys.every((key) => _sameJsonValue(left[key], right[key]));
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameJsonValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is! Map) return <String, dynamic>{};
    return <String, dynamic>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static Map<String, dynamic> _mcpServersFromConfig(
    Map<String, dynamic> config,
  ) {
    final additional = _asMap(config['additional']);
    final nested = additional['mcp_servers'];
    if (nested is Map) return _asMap(nested);
    final flattened = config['mcp_servers'];
    return flattened is Map ? _asMap(flattened) : <String, dynamic>{};
  }
}

class CodexSessionException implements Exception {
  const CodexSessionException(this.message);

  final String message;

  @override
  String toString() => 'CodexSessionException: $message';
}
