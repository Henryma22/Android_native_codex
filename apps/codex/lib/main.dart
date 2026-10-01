import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'backends/local/local_android_backend.dart';
import 'backends/compatibility/linux_compatibility_backend.dart';
import 'core/application/backend_selector.dart';
import 'core/application/auth_status_summary.dart';
import 'core/application/agent_file_change_preview.dart';
import 'core/application/app_metadata.dart';
import 'core/application/change_set_service.dart';
import 'core/application/codex_auth_client.dart';
import 'core/application/codex_cli_auth_client.dart';
import 'core/application/codex_model_catalog.dart';
import 'core/application/codex_mcp_server_summary.dart';
import 'core/application/codex_network_probe.dart';
import 'core/application/codex_usage.dart';
import 'core/application/codex_session_client.dart';
import 'core/application/codex_permission_profile_summary.dart';
import 'core/application/codex_provider_launch_configuration.dart';
import 'core/application/provider_network_error_summary.dart';
import 'core/application/codex_cli_arguments.dart';
import 'core/application/codex_plugin_summary.dart';
import 'core/domain/backend.dart';
import 'core/domain/change_set.dart';
import 'core/domain/custom_provider.dart';
import 'core/domain/execution.dart';
import 'core/domain/image_attachment.dart';
import 'core/domain/runtime.dart';
import 'core/domain/root_access_policy.dart';
import 'core/domain/session.dart';
import 'core/domain/transcript.dart';
import 'core/domain/workspace.dart';
import 'services/codex_runtime_probe.dart';
import 'services/codex_cli_updater.dart';
import 'services/codex_model_catalog_cache.dart';
import 'services/app_host_access_probe.dart';
import 'services/session_lifecycle.dart';
import 'services/session_history.dart';
import 'services/auth_binding_store.dart';
import 'services/backend_preference_store.dart';
import 'services/app_settings_store.dart';
import 'services/custom_provider_store.dart';
import 'services/local_image_picker.dart';
import 'services/compatibility_rootfs_installer.dart';

import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';

import 'ccpocket_native_home.dart';
import 'ccpocket_native_session.dart';
import 'ccpocket_local_settings.dart';
import 'batch_text_change_page.dart';
import 'codex_mcp_settings.dart';
import 'custom_provider_settings.dart';
import 'ccpocket_usage.dart';

import 'package:ccpocket_ui/features/session_list/widgets/session_list_app_bar.dart';
import 'package:ccpocket_ui/features/chat_session/widgets/usage_summary_bar.dart';

const bool _frameTimingQaEnabled = bool.fromEnvironment(
  'CODEX_FRAME_TIMING_QA',
);
const int _frameTimingQaWindowSize = 120;
final List<FrameTiming> _frameTimingQaWindow = <FrameTiming>[];

/// Converts provider/runtime failures into user-facing copy without leaking
/// raw URLs or English service diagnostics into the localized conversation.
/// Keep this pure so provider responses can be regression-tested without
/// starting a session or a platform runtime.
String localizeCodexRuntimeFailure(
  String reason, {
  required String languageCode,
}) {
  final normalized = reason.trim().replaceAll(RegExp(r'\s+'), ' ');
  final normalizedLower = normalized.toLowerCase();
  final usageLimit =
      normalizedLower.contains('usage limit') ||
      normalizedLower.contains('hit your usage') ||
      normalizedLower.contains('purchase more credits');
  if (usageLimit) {
    return switch (languageCode) {
      'zh' => '已达到 Codex 使用额度上限。请等待额度恢复，或升级 Pro/购买额外额度后重试。',
      'ja' =>
        'Codex の利用上限に達しました。上限が回復するまで待つか、Pro へアップグレードまたは追加クレジットを購入して再試行してください。',
      'ko' => 'Codex 사용 한도에 도달했습니다. 한도가 갱신될 때까지 기다리거나 Pro로 업그레이드 또는 추가 크레딧을 구매한 뒤 다시 시도하세요.',
      _ => 'Codex usage limit reached. Wait for the limit to reset, or upgrade to Pro or purchase more credits before retrying.',
    };
  }
  if (languageCode != 'zh') return reason;
  if (normalized.startsWith(
    'The saved Codex thread is no longer available in this local runtime.',
  )) {
    return '已保存的 Codex 会话在此本地运行环境中已不可用。缓存消息已保留；请开始新的本地会话。';
  }
  if (normalized.contains('No legacy App UID Codex binary is installed') ||
      normalized.contains(
        'No App UID Android-native Codex runtime is installed',
      ) ||
      normalized.contains('未安装应用 UID 可执行的 Android 原生 Codex') ||
      normalized.contains('恢复 Android 原生运行时')) {
    return '当前没有可用的 Codex 执行环境。请在设置中安装或验证 Linux/PRoot 兼容环境。';
  }
  return switch (normalized) {
    'Linux compatibility runtime is not verified.' => 'Linux 兼容运行环境尚未验证。',
    'Codex runtime is not verified.' => 'Codex 运行环境尚未验证。',
    _ => reason,
  };
}

/// Localizes only the display projection of a persisted transcript row.
///
/// New rows are stored as JSON, so checking for the legacy `error:` prefix
/// alone misses restored provider errors. The stored row is never rewritten
/// here; callers can safely use this during rebuilds and locale changes.
String localizeCodexTranscriptEntry(
  String entry, {
  required String languageCode,
}) {
  final trimmed = entry.trim();
  if (trimmed.startsWith('{')) {
    final parsed = CodexTranscriptEntry.fromStored(trimmed);
    if (parsed.kind == CodexTranscriptKind.error) {
      final localized = localizeCodexRuntimeFailure(
        parsed.text,
        languageCode: languageCode,
      );
      if (localized != parsed.text) {
        return parsed.copyWith(text: localized).toStored();
      }
    }
  }
  if (languageCode == 'zh' &&
      trimmed == 'System: Saved thread expired; local messages were kept.') {
    return 'System: 已保存的 Codex 会话已过期；本地消息已保留。';
  }
  if (languageCode == 'zh') {
    final verified = RegExp(
      r'^Agent file change verified: (\d+) file\(s\) match the approved content\.$',
    ).firstMatch(trimmed);
    if (verified != null) {
      return 'System: 文件变更已验证：${verified.group(1)} 个文件与批准内容一致。';
    }
    if (trimmed.startsWith('Agent file change verification failed: ')) {
      return 'System: 文件变更验证失败：${trimmed.substring('Agent file change verification failed: '.length)}';
    }
    if (trimmed.startsWith('Agent file change verification error: ')) {
      return 'System: 文件变更验证出错：${trimmed.substring('Agent file change verification error: '.length)}';
    }
    final backups = RegExp(
      r'^Agent file change: (\d+) pre-change backup\(s\) created\.$',
    ).firstMatch(trimmed);
    if (backups != null) {
      return 'System: 文件变更：已创建 ${backups.group(1)} 个变更前备份。';
    }
    if (trimmed.startsWith('Agent file change: no pre-change backup;')) {
      return 'System: 文件变更：此请求没有完整的托管文本预览，未创建变更前备份。';
    }
    if (trimmed ==
        'The active backend owns the approved change but does not expose versioned pre-change backups.') {
      return 'System: 当前后端负责已批准的变更，但不提供带版本的变更前备份。';
    }
    if (trimmed.startsWith('file-change preview error: ')) {
      return 'System: 文件变更预览失败：${trimmed.substring('file-change preview error: '.length)}';
    }
    if (trimmed == 'User input submitted') return 'System: 已提交用户输入。';
    if (trimmed == 'User input canceled') return 'System: 已取消用户输入。';
    if (trimmed == 'System: MCP request accepted.') {
      return 'System: MCP 请求已接受。';
    }
    if (trimmed == 'System: MCP request declined.') {
      return 'System: MCP 请求已拒绝。';
    }
    if (trimmed == 'System: MCP request canceled.') {
      return 'System: MCP 请求已取消。';
    }
  }
  if (!trimmed.toLowerCase().startsWith('error:')) return entry;
  final message = trimmed.substring('error:'.length).trimLeft();
  final localized = localizeCodexRuntimeFailure(
    message,
    languageCode: languageCode,
  );
  return localized == message ? entry : 'error: $localized';
}

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (_frameTimingQaEnabled) {
    binding.addTimingsCallback(_collectFrameTimingQaSamples);
  }
  runApp(const CodexApp());
}

void _collectFrameTimingQaSamples(List<FrameTiming> timings) {
  _frameTimingQaWindow.addAll(timings);
  if (_frameTimingQaWindow.length < _frameTimingQaWindowSize) return;

  final window = _frameTimingQaWindow
      .take(_frameTimingQaWindowSize)
      .toList(growable: false);
  _frameTimingQaWindow.removeRange(0, _frameTimingQaWindowSize);
  final build =
      window
          .map((timing) => timing.buildDuration.inMicroseconds)
          .toList(growable: false)
        ..sort();
  final raster =
      window
          .map((timing) => timing.rasterDuration.inMicroseconds)
          .toList(growable: false)
        ..sort();
  final vsync =
      window
          .map((timing) => timing.vsyncOverhead.inMicroseconds)
          .toList(growable: false)
        ..sort();
  final total =
      window
          .map((timing) => timing.totalSpan.inMicroseconds)
          .toList(growable: false)
        ..sort();
  int percentile(List<int> values, int numerator) =>
      values[((values.length - 1) * numerator / 100).ceil()];
  final buildOver8ms = build.where((value) => value > 8000).length;
  final rasterOver8ms = raster.where((value) => value > 8000).length;
  final vsyncOver8ms = vsync.where((value) => value > 8000).length;
  final totalOver8ms = total.where((value) => value > 8000).length;
  final totalOver16ms = total.where((value) => value > 16000).length;
  final totalOver32ms = total.where((value) => value > 32000).length;
  debugPrint(
    'CODEX_FRAME_TIMING_QA frames=${window.length} '
    'build_p50_p95_p99_us=${percentile(build, 50)}/${percentile(build, 95)}/${percentile(build, 99)} '
    'raster_p50_p95_p99_us=${percentile(raster, 50)}/${percentile(raster, 95)}/${percentile(raster, 99)} '
    'vsync_p50_p95_p99_us=${percentile(vsync, 50)}/${percentile(vsync, 95)}/${percentile(vsync, 99)} '
    'total_p50_p95_p99_us=${percentile(total, 50)}/${percentile(total, 95)}/${percentile(total, 99)} '
    'build_gt8ms=$buildOver8ms raster_gt8ms=$rasterOver8ms vsync_gt8ms=$vsyncOver8ms '
    'total_gt8ms=$totalOver8ms total_gt16ms=$totalOver16ms total_gt32ms=$totalOver32ms',
  );
}

String _uiText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String _friendlyBackendError(Object error, {required bool chinese}) {
  final message = '$error'.replaceFirst('BackendException: ', '');
  final normalized = message.toLowerCase();
  if (normalized.contains('permission_denied') &&
      normalized.contains('host workspace root')) {
    return chinese
        ? '当前应用 UID 无法直接访问固定 Android 工作区；这不代表 Root/PRoot 不可用。请导入文件夹，或在 Root 会话中使用宿主目录。'
        : 'The App UID cannot access the fixed Android workspace right now; this does not mean Root/PRoot is unavailable. Import a folder, or use the host directory from a Root session.';
  }
  return message;
}

class CodexApp extends StatefulWidget {
  const CodexApp({super.key, this.selector});

  final BackendSelector? selector;

  @override
  State<CodexApp> createState() => _CodexAppState();
}

class _CodexAppState extends State<CodexApp> {
  final _settingsStore = AppSettingsStore();
  var _themeMode = ThemeMode.system;
  // Chinese is the persisted app default.  Start with it synchronously so
  // the first frame does not briefly expose the untranslated system locale
  // while the Android preference channel is loading.
  Locale? _locale = const Locale('zh');
  String? _compatibilityCliVersion;
  String _defaultCodexModel = 'gpt-6-luna';
  String _defaultCodexEffort = 'low';
  String _defaultCodexApprovalPolicy = 'never';
  String _defaultCodexSandbox = 'danger-full-access';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppSettings());
  }

  Future<void> _loadAppSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _themeMode = switch (settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _locale = switch (settings.locale) {
        'zh' => const Locale('zh'),
        'en' => const Locale('en'),
        _ => null,
      };
      _compatibilityCliVersion = settings.compatibilityCliVersion;
      _defaultCodexModel = settings.codexModel;
      _defaultCodexEffort = settings.codexEffort;
      _defaultCodexApprovalPolicy = settings.codexApprovalPolicy;
      _defaultCodexSandbox = settings.codexSandbox;
    });
  }

  Future<void> _saveAppSettings() => _settingsStore.save(
    AppSettingsSnapshot(
      themeMode: switch (_themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
      locale: _locale?.languageCode ?? 'system',
      compatibilityCliVersion: _compatibilityCliVersion,
      codexModel: _defaultCodexModel,
      codexEffort: _defaultCodexEffort,
      codexApprovalPolicy: _defaultCodexApprovalPolicy,
      codexSandbox: _defaultCodexSandbox,
    ),
  );

  void _setThemeMode(ThemeMode value) {
    setState(() => _themeMode = value);
    unawaited(
      _settingsStore.save(
        AppSettingsSnapshot(
          themeMode: switch (value) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          },
          locale: _locale?.languageCode ?? 'system',
          compatibilityCliVersion: _compatibilityCliVersion,
          codexModel: _defaultCodexModel,
          codexEffort: _defaultCodexEffort,
          codexApprovalPolicy: _defaultCodexApprovalPolicy,
          codexSandbox: _defaultCodexSandbox,
        ),
      ),
    );
  }

  void _setLocale(Locale? value) {
    setState(() => _locale = value);
    unawaited(
      _settingsStore.save(
        AppSettingsSnapshot(
          themeMode: switch (_themeMode) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          },
          locale: value?.languageCode ?? 'system',
          compatibilityCliVersion: _compatibilityCliVersion,
          codexModel: _defaultCodexModel,
          codexEffort: _defaultCodexEffort,
          codexApprovalPolicy: _defaultCodexApprovalPolicy,
          codexSandbox: _defaultCodexSandbox,
        ),
      ),
    );
  }

  void _setDefaultCodexModel(String value) {
    setState(() => _defaultCodexModel = value);
    unawaited(_saveAppSettings());
  }

  void _setDefaultCodexEffort(String value) {
    setState(() => _defaultCodexEffort = value);
    unawaited(_saveAppSettings());
  }

  void _setDefaultCodexApprovalPolicy(String value) {
    setState(() => _defaultCodexApprovalPolicy = value);
    unawaited(_saveAppSettings());
  }

  void _setDefaultCodexSandbox(String value) {
    setState(() => _defaultCodexSandbox = value);
    unawaited(_saveAppSettings());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: CodexAppMetadata.displayName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      locale: _locale,
      home: CodexHomePage(
        selector: widget.selector,
        themeMode: _themeMode,
        locale: _locale,
        compatibilityCliVersion: _compatibilityCliVersion,
        defaultCodexModel: _defaultCodexModel,
        defaultCodexEffort: _defaultCodexEffort,
        defaultCodexApprovalPolicy: _defaultCodexApprovalPolicy,
        defaultCodexSandbox: _defaultCodexSandbox,
        onThemeModeChanged: _setThemeMode,
        onLocaleChanged: _setLocale,
        onDefaultCodexModelChanged: _setDefaultCodexModel,
        onDefaultCodexEffortChanged: _setDefaultCodexEffort,
        onDefaultCodexApprovalPolicyChanged: _setDefaultCodexApprovalPolicy,
        onDefaultCodexSandboxChanged: _setDefaultCodexSandbox,
        onCompatibilityCliVersionChanged: (version) {
          setState(() => _compatibilityCliVersion = version);
          unawaited(_saveAppSettings());
        },
      ),
    );
  }
}

class CodexHomePage extends StatefulWidget {
  const CodexHomePage({
    super.key,
    this.selector,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.compatibilityCliVersion,
    this.defaultCodexModel = 'gpt-6-luna',
    this.defaultCodexEffort = 'low',
    this.defaultCodexApprovalPolicy = 'never',
    this.defaultCodexSandbox = 'danger-full-access',
    this.onThemeModeChanged,
    this.onLocaleChanged,
    this.onDefaultCodexModelChanged,
    this.onDefaultCodexEffortChanged,
    this.onDefaultCodexApprovalPolicyChanged,
    this.onDefaultCodexSandboxChanged,
    this.onCompatibilityCliVersionChanged,
  });

  final BackendSelector? selector;
  final ThemeMode themeMode;
  final Locale? locale;
  final String? compatibilityCliVersion;
  final String defaultCodexModel;
  final String defaultCodexEffort;
  final String defaultCodexApprovalPolicy;
  final String defaultCodexSandbox;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<Locale?>? onLocaleChanged;
  final ValueChanged<String>? onDefaultCodexModelChanged;
  final ValueChanged<String>? onDefaultCodexEffortChanged;
  final ValueChanged<String>? onDefaultCodexApprovalPolicyChanged;
  final ValueChanged<String>? onDefaultCodexSandboxChanged;
  final ValueChanged<String?>? onCompatibilityCliVersionChanged;

  @override
  State<CodexHomePage> createState() => _CodexHomePageState();
}

/// Runtime ownership for one local session.
///
/// The process is a session resource, not a route resource. Keeping this
/// handle in the home-level session entry means a page rebuild or a temporary
/// route detach cannot cancel the app-server just because its widget state was
/// replaced.
class _LocalSessionRuntimeHandle {
  final StreamController<CodexSessionEvent> _events =
      StreamController<CodexSessionEvent>.broadcast();
  SessionClient? client;
  StreamSubscription<CodexSessionEvent>? clientSubscription;
  var _clientGeneration = 0;
  bool sessionForegroundOwned = false;
  bool authForegroundOwned = false;
  String? rootApprovalGrantedForSession;

  Stream<CodexSessionEvent> get events => _events.stream;

  void attachClient(SessionClient value) {
    if (identical(client, value)) return;
    final previous = clientSubscription;
    clientSubscription = null;
    unawaited(previous?.cancel());
    final generation = ++_clientGeneration;
    client = value;
    clientSubscription = value.events.listen(
      (event) {
        if (generation != _clientGeneration) return;
        if (!_events.isClosed) _events.add(event);
      },
      onError: (Object error, StackTrace stack) {
        if (generation != _clientGeneration) return;
        if (!_events.isClosed) _events.addError(error, stack);
      },
    );
  }

  Future<void> detachClient([SessionClient? expected]) async {
    if (expected != null && client != null && !identical(client, expected)) {
      return;
    }
    client = null;
    _clientGeneration++;
    final subscription = clientSubscription;
    clientSubscription = null;
    // This can be called from the page's own forwarded event callback (most
    // notably after an unexpected process exit). Awaiting cancellation there
    // can deadlock a broadcast stream while its callback is still unwinding.
    // Invalidate the generation synchronously, then cancel in the background;
    // a later client can attach without inheriting stale events.
    unawaited(subscription?.cancel());
  }

  Future<void> disposeClient() async {
    final value = client;
    await detachClient(value);
    await value?.dispose();
  }
}

class _LocalSessionEntry {
  _LocalSessionEntry({
    required this.id,
    required this.backend,
    required this.workspace,
    required this.pageKey,
    this.sessionId,
    this.threadId,
    this.history,
    required this.startsFresh,
    this.customProvider,
    this.missingCustomProviderId,
    this.providerModeExplicit = false,
    this.executionIdentity = ExecutionIdentity.root,
    this.initialModel = 'gpt-6-luna',
    this.initialEffort = 'low',
    this.initialApprovalPolicy = 'never',
    this.initialSandbox = 'danger-full-access',
    this.settingsOnly = false,
  });

  final String id;
  final Backend backend;
  final WorkspaceRef workspace;
  final GlobalKey<_LocalSessionPageState> pageKey;
  final _LocalSessionRuntimeHandle runtime = _LocalSessionRuntimeHandle();
  String? sessionId;
  String? threadId;
  SessionHistoryRecord? history;
  bool startsFresh;
  CustomProviderConfig? customProvider;
  String? missingCustomProviderId;
  bool providerModeExplicit;

  /// Settings owns authentication without creating a visible Codex thread.
  final ExecutionIdentity executionIdentity;
  final String initialModel;
  final String initialEffort;
  final String initialApprovalPolicy;
  final String initialSandbox;
  final bool settingsOnly;
  LocalSessionSnapshot? snapshot;

  // Keep the session widget instance stable while the shell rebuilds for
  // another session's streaming snapshot. Recreating these widgets on every
  // shell frame made every hidden IndexedStack page rebuild as well.
  LocalSessionPage? page;
  String? pageModelCatalogCliVersion;
}

class _CodexHomePageState extends State<CodexHomePage>
    with WidgetsBindingObserver {
  late final bool _ownsSelector = widget.selector == null;
  late final BackendSelector _selector =
      widget.selector ?? BackendSelector.device();
  late Backend _backend = _selector.backends.first;
  final _backendPreferences = BackendPreferenceStore();
  var _backendSelectionChanged = false;
  late Future<List<WorkspaceRef>> _workspaces;
  late Future<List<SessionHistoryRecord>> _sessionHistories;
  final _sessionHistoryStore = SessionHistoryStore();
  var _workspaceItems = const <WorkspaceRef>[];
  late Future<AppHostAccessResult> _appHostAccess;
  late Future<CodexRuntimeDescriptor> _runtime;
  Future<CompatibilityRuntimeDescriptor>? _compatibilityRuntimeProbe;
  String? _activeCompatibilityCliVersion;
  final Map<String, _LocalSessionEntry> _sessionEntries =
      <String, _LocalSessionEntry>{};
  var _authGeneration = AuthBindingStore.defaultGeneration;
  late final Future<void> _authBindingLoaded;
  String? _selectedSessionEntryId;
  var _sessionEntrySequence = 0;
  var _sessionVisible = false;
  var _sessionSnapshotRefreshScheduled = false;
  Timer? _sessionSnapshotRefreshTimer;
  var _rehydratingPersistedSessions = false;
  var _sessionNavigationTouched = false;
  CodexUsageSnapshot? _homeUsage;
  Future<void>? _homeUsageLoad;
  final _customProviderStore = CustomProviderStore();
  CustomProviderConfig? _activeCustomProvider;
  CustomProviderConfig? _selectedCustomProvider;
  String? _activeCustomProviderId;
  String? _modelProviderMode;
  String? _missingActiveCustomProviderId;
  List<CustomProviderConfig> _customProviders = const <CustomProviderConfig>[];
  var _customProvidersLoaded = false;
  Future<void>? _activeCustomProviderLoad;
  var _customProviderSelectionRevision = 0;

  _LocalSessionEntry? get _selectedSessionEntry =>
      _selectedSessionEntryId == null
      ? null
      : _sessionEntries[_selectedSessionEntryId];

  WorkspaceRef? get _sessionWorkspace => _selectedSessionEntry?.workspace;
  LocalSessionSnapshot? get _sessionSnapshot => _selectedSessionEntry?.snapshot;

  @override
  void initState() {
    super.initState();
    AuthBindingStore.currentGeneration.addListener(
      _handleAuthGenerationChanged,
    );
    _authBindingLoaded = _loadAuthBinding();
    _activeCompatibilityCliVersion = widget.compatibilityCliVersion;
    _refreshLocalCapabilities();
    _workspaces = _listWorkspacesFor(_backend);
    _sessionHistories = _sessionHistoryStore.list();
    unawaited(_restoreBackendSelection());
    unawaited(_refreshHomeUsage());
    unawaited(_loadActiveCustomProvider());
    // Session pages are normally created when a Home row is tapped. That is
    // correct for navigation, but it used to mean that an Android process
    // restart left every non-stopped worker disconnected until the user
    // opened each row manually. Recreate the durable entries once at launch;
    // each page then uses its existing automatic thread-resume path.
    unawaited(_rehydratePersistedSessions());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant CodexHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compatibilityCliVersion != widget.compatibilityCliVersion) {
      _activeCompatibilityCliVersion = widget.compatibilityCliVersion;
    }
  }

  Future<void> _loadActiveCustomProvider({bool refresh = false}) async {
    final pending = _activeCustomProviderLoad;
    if (pending != null) {
      await pending;
      if (!refresh || !mounted) return;
    }
    if (!refresh && _customProvidersLoaded) return;
    final selectionRevision = _customProviderSelectionRevision;
    final operation = _loadActiveCustomProviderImpl(selectionRevision);
    _activeCustomProviderLoad = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeCustomProviderLoad, operation)) {
        _activeCustomProviderLoad = null;
      }
    }
  }

  Future<void> _loadActiveCustomProviderImpl(int selectionRevision) async {
    try {
      // These are independent SharedPreferences reads. Dispatch together so
      // opening provider settings never serially pays three platform-channel
      // round trips.
      final providersFuture = _customProviderStore.load();
      final activeIdFuture = _customProviderStore.loadActiveId();
      final modeFuture = _customProviderStore.loadProviderMode();
      final providers = await providersFuture;
      final activeId = await activeIdFuture;
      final storedMode = await modeFuture;
      final mode = storedMode ?? (activeId == null ? null : 'third_party');
      if (!mounted) return;
      // A settings tap can update the source while startup restoration is
      // still in flight. Never let that older read overwrite the user's
      // explicit selection.
      if (selectionRevision != _customProviderSelectionRevision) {
        _customProvidersLoaded = true;
        return;
      }
      final selected = providers
          .where((provider) => provider.id == activeId)
          .firstOrNull;
      final active = mode == 'openai' ? null : selected;
      _customProviders = providers;
      _customProvidersLoaded = true;
      _selectedCustomProvider = selected;
      _activeCustomProviderId = activeId;
      _modelProviderMode = mode;
      _missingActiveCustomProviderId = mode == 'third_party' && active == null
          ? activeId
          : null;
      setState(() {
        _activeCustomProvider = active;
        for (final entry in _sessionEntries.values) {
          if (entry.startsFresh &&
              entry.customProvider == null &&
              entry.missingCustomProviderId == null) {
            entry.customProvider = active;
          }
        }
      });
    } catch (_) {
      // Provider persistence is optional for opening a local thread. A
      // platform-channel failure must not turn the New session action into a
      // dead button.
      if (!mounted) return;
      setState(() => _customProvidersLoaded = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthBindingStore.currentGeneration.removeListener(
      _handleAuthGenerationChanged,
    );
    _sessionSnapshotRefreshTimer?.cancel();
    if (_ownsSelector) {
      for (final backend in _selector.backends) {
        if (backend is LocalAndroidBackend) unawaited(backend.dispose());
      }
    }
    super.dispose();
  }

  Future<void> _loadAuthBinding() async {
    final generation = await AuthBindingStore.loadCurrent();
    if (!mounted) return;
    if (_authGeneration == generation) return;
    setState(() => _authGeneration = generation);
  }

  void _handleAuthGenerationChanged() {
    if (!mounted) return;
    final generation = AuthBindingStore.currentGeneration.value;
    if (_authGeneration == generation) return;
    setState(() => _authGeneration = generation);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocalCapabilities();
      unawaited(_reloadWorkspaces());
      unawaited(_reloadSessionHistories());
      unawaited(_refreshHomeUsage());
    }
  }

  void _refreshLocalCapabilities() {
    _appHostAccess = AppHostAccessProbe().run();
    _runtime = CodexRuntimeProbe().run();
    final compatibilityBackend = _selector.backends
        .whereType<LinuxCompatibilityBackend>()
        .firstOrNull;
    if (compatibilityBackend != null) {
      _compatibilityRuntimeProbe = _refreshCompatibilityBackend(
        compatibilityBackend,
      );
    }
    if (mounted) setState(() {});
  }

  Future<CompatibilityRuntimeDescriptor> _refreshCompatibilityBackend(
    LinuxCompatibilityBackend backend,
  ) async {
    try {
      final descriptor = await backend.refresh();
      if (mounted) setState(() {});
      return descriptor;
    } catch (_) {
      // The backend retains its last descriptor and remains fail-closed. The
      // native probe already reports a user-facing Failed reason when one is
      // available; a transient lifecycle probe error must not hide workspaces.
      if (mounted) setState(() {});
      return backend.runtimeProbeResult;
    }
  }

  Future<void> _restoreBackendSelection() async {
    final backendId = await _backendPreferences.loadPreferredBackendId();
    if (!mounted || _backendSelectionChanged || backendId == null) return;

    Backend next;
    try {
      next = _selector.select(backendId);
    } on BackendException {
      return;
    }

    // The home shell remains on Local Android because workspace creation,
    // SAF access, and host-file ownership belong to the Android host. Codex
    // sessions always use the verified Linux/PRoot guest; restore that view
    // only when its runtime is available.
    if (next is LinuxCompatibilityBackend) {
      try {
        final descriptor = await next.refresh();
        if (!descriptor.usable) return;
      } catch (_) {
        return;
      }
    }
    if (!mounted || _backendSelectionChanged) return;
    setState(() {
      _backend = next;
      _workspaceItems = const <WorkspaceRef>[];
      _workspaces = _listWorkspacesFor(_backend);
      _homeUsage = null;
    });
    unawaited(_refreshHomeUsage());
  }

  Future<List<WorkspaceRef>> _listWorkspacesFor(Backend backend) =>
      backend.listWorkspaces();

  Backend? _fallbackBackendFor(Backend active) {
    final activeKind = active.descriptor.kind;
    for (final backend in _selector.backends) {
      if (backend.descriptor.id == active.descriptor.id) continue;
      if (activeKind == BackendKind.localAndroid &&
          backend.descriptor.kind == BackendKind.linuxCompatibility) {
        return backend;
      }
      if (activeKind == BackendKind.linuxCompatibility &&
          backend.descriptor.kind == BackendKind.localAndroid) {
        return backend;
      }
    }
    return null;
  }

  LocalAndroidBackend? _localAndroidStorageBackend() {
    for (final backend in _selector.backends) {
      if (backend is LocalAndroidBackend) return backend;
    }
    return null;
  }

  WorkspaceRef _asLocalAndroidWorkspace(
    WorkspaceRef workspace,
    LocalAndroidBackend backend,
  ) {
    if (workspace.backendId == backend.descriptor.id) return workspace;
    return WorkspaceRef(
      backendId: backend.descriptor.id,
      filesystemOwnerId: workspace.filesystemOwnerId,
      displayPath: workspace.displayPath,
      hostPath: workspace.hostPath,
      backendLocator: workspace.backendLocator,
    );
  }

  Future<void> _reloadWorkspaces() async {
    if (!mounted) return;
    try {
      final workspaces = await _listWorkspacesFor(_backend);
      if (!mounted) return;
      setState(() {
        _workspaceItems = workspaces;
        _workspaces = Future<List<WorkspaceRef>>.value(workspaces);
      });
      unawaited(_refreshHomeUsage());
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(
        () => _workspaces = Future<List<WorkspaceRef>>.error(error, stackTrace),
      );
    }
  }

  Future<List<WorkspaceRef>> _currentWorkspaceItems() async {
    if (_workspaceItems.isNotEmpty) return _workspaceItems;
    try {
      final loaded = await _workspaces;
      return _workspaceItems.isNotEmpty ? _workspaceItems : loaded;
    } catch (_) {
      return _workspaceItems;
    }
  }

  /// Loads the compact usage summary used by the current CC Pocket home.
  ///
  /// The summary is deliberately best-effort: CC Pocket hides it when the
  /// provider has not returned usage data, so a local runtime/auth failure
  /// must not turn the Home session list into an error state.
  Future<void> _refreshHomeUsage() async {
    final previous = _homeUsageLoad;
    if (previous != null) {
      await previous;
      return;
    }

    final operation = () async {
      final backend = _backend;
      if (backend.descriptor.kind != BackendKind.localAndroid) return;
      try {
        final workspaces = _workspaceItems.isNotEmpty
            ? _workspaceItems
            : await _workspaces;
        if (!mounted || workspaces.isEmpty) return;
        final runtime = await _runtime;
        final command = runtime.command;
        if (!runtime.usable || command == null) return;
        final usage = await CodexUsageClient.load(
          backend: backend,
          workspace: workspaces.first,
          command: command,
          identity: ExecutionIdentity.app,
          environment: _homeRuntimeEnvironment(
            runtime,
            runtimeScope:
                'op-home-usage-${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        if (!mounted || !identical(backend, _backend)) return;
        setState(() => _homeUsage = usage.hasData ? usage : null);
      } catch (_) {
        // Home follows CC Pocket's compact-summary behavior: no data means no
        // header widget. The full Settings card remains the diagnostic path.
      }
    }();
    _homeUsageLoad = operation;
    try {
      await operation;
    } finally {
      if (identical(_homeUsageLoad, operation)) _homeUsageLoad = null;
    }
  }

  Map<String, String> _homeRuntimeEnvironment(
    CodexRuntimeDescriptor runtime, {
    String? runtimeScope,
  }) {
    final home = runtime.home;
    if (home == null) return const <String, String>{};
    const filesMarker = '/files/';
    final filesIndex = home.lastIndexOf(filesMarker);
    final cache = filesIndex >= 0
        ? '${home.substring(0, filesIndex)}/cache'
        : null;
    final environment = <String, String>{
      'HOME': home,
      'CODEX_HOME': home,
      'BROWSER': '/system/bin/true',
      if (cache != null) ...{'TMPDIR': cache, 'TMP': cache, 'TEMP': cache},
    };
    if (runtimeScope != null) {
      final scopedHome = '$home/sessions/${_safeRuntimeScope(runtimeScope)}';
      environment['CODEX_HOME'] = scopedHome;
      environment['CODEX_SQLITE_HOME'] = '$scopedHome/state';
      environment['TMPDIR'] = '$scopedHome/tmp';
      environment['TMP'] = '$scopedHome/tmp';
      environment['TEMP'] = '$scopedHome/tmp';
    }
    return environment;
  }

  String _safeRuntimeScope(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.length <= 96 ? safe : safe.substring(0, 96);
  }

  Future<void> _reloadSessionHistories() async {
    try {
      final histories = await _sessionHistoryStore.list();
      if (!mounted) return;
      setState(() {
        _sessionHistories = Future<List<SessionHistoryRecord>>.value(histories);
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(
        () => _sessionHistories = Future<List<SessionHistoryRecord>>.error(
          error,
          stackTrace,
        ),
      );
    }
  }

  Future<void> _rehydratePersistedSessions() async {
    _rehydratingPersistedSessions = true;
    try {
      await _authBindingLoaded;
      final histories = await _sessionHistories;
      await _loadActiveCustomProvider();
      if (!mounted) return;

      final resumable = histories
          .where(
            (history) =>
                history.canAutoResumeForAuthGeneration(_authGeneration),
          )
          .toList(growable: false);
      if (resumable.isEmpty) return;

      final workspaceCache = <String, List<WorkspaceRef>>{};
      for (final history in resumable) {
        if (!mounted) return;
        final historySessionId = history.sessionId!.trim();
        if (_sessionEntries.values.any(
          (entry) => entry.sessionId?.trim() == historySessionId,
        )) {
          continue;
        }

        Backend backend;
        try {
          backend = _selector.select(history.backendId);
        } on BackendException {
          continue;
        }

        // Root/PRoot history can be restored during the same startup window
        // in which the compatibility backend is still probing its rootfs and
        // worker. Starting the page before that probe finishes turns a
        // recoverable `disconnected` row into a false startup failure. Refresh
        // this backend before constructing the page; if it is not verified,
        // leave the durable row untouched for an explicit retry after the
        // runtime becomes available.
        if (backend is LinuxCompatibilityBackend) {
          if (!await _waitForVerifiedCompatibilityBackend(backend)) continue;
        }

        final workspaces = workspaceCache.putIfAbsent(
          history.backendId,
          () => const <WorkspaceRef>[],
        );
        var available = workspaces;
        if (available.isEmpty) {
          try {
            available = await _listWorkspacesFor(backend);
            workspaceCache[history.backendId] = available;
          } catch (_) {
            continue;
          }
        }
        final workspace = available
            .where((candidate) => candidate.hostPath == history.workspacePath)
            .firstOrNull;
        if (workspace == null) continue;

        // `_openLocalSession` intentionally owns provider resolution and page
        // construction. Calling it here keeps startup recovery on exactly the
        // same backend/session path as an explicit Home tap.
        await _openLocalSession(workspace, history: history);
      }

      if (!mounted) return;
      // Auto-rehydrated pages must remain alive in the IndexedStack, but Home
      // is the visible surface after startup. A selected hidden entry is used
      // as the stack anchor; it does not expose an active-session card until
      // the user explicitly opens that session.
      if (_sessionEntries.isNotEmpty && !_sessionNavigationTouched) {
        setState(() => _sessionVisible = false);
      }
    } catch (_) {
      // The history index is optional. A later explicit Home open still uses
      // the normal load path, so startup recovery must not block Home.
    } finally {
      _rehydratingPersistedSessions = false;
    }
  }

  Future<bool> _waitForVerifiedCompatibilityBackend(
    LinuxCompatibilityBackend backend,
  ) async {
    // The native app process and the rootfs probe start independently. Keep
    // this retry bounded so a missing/incompatible runtime never holds Home
    // hostage, while still covering the normal cold-start race.
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 750),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 1500),
    ];
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelays[attempt]);
      try {
        final descriptor = await backend.refresh();
        if (descriptor.usable) return true;
      } catch (_) {
        // A later attempt can observe a rootfs/worker that finished starting.
      }
    }
    return false;
  }

  Future<void> _updateSessionHistoryFlags(
    SessionHistoryRecord history, {
    bool? pinned,
  }) async {
    try {
      await _sessionHistoryStore.updateFlags(history, pinned: pinned);
      await _reloadSessionHistories();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _uiText(
              context,
              '无法更新会话：$error',
              'Could not update session: $error',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _updateSessionHistoryTitle(
    SessionHistoryRecord history,
    String? title,
  ) async {
    try {
      await _sessionHistoryStore.updateTitle(history, title);
      await _reloadSessionHistories();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _uiText(
              context,
              '无法重命名会话：$error',
              'Could not rename session: $error',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _deleteSessionHistory(SessionHistoryRecord history) async {
    try {
      await _sessionHistoryStore.delete(history);
      await _reloadSessionHistories();
    } catch (error) {
      if (!mounted) return;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '无法删除会话：$error' : 'Could not delete session: $error',
          ),
        ),
      );
    }
  }

  Future<void> _addSafWorkspace() async {
    final backend = _localAndroidStorageBackend();
    if (backend == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      final workspace = await backend.pickSafWorkspace();
      if (!mounted) return;
      if (workspace != null) {
        final currentWorkspaces = await _currentWorkspaceItems();
        if (!mounted) return;
        final merged = <WorkspaceRef>[
          ...currentWorkspaces.where(
            (item) => !_sameWorkspace(item, workspace),
          ),
          workspace,
        ];
        setState(() {
          _workspaceItems = merged;
          _workspaces = Future.value(merged);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              zh
                  ? '已添加文件夹：${workspace.displayPath}'
                  : 'SAF workspace added: ${workspace.displayPath}',
            ),
          ),
        );
      } else {
        await _reloadWorkspaces();
      }
    } on BackendException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyBackendError(error, chinese: zh))),
      );
    }
  }

  Future<void> _createHostWorkspace() async {
    final backend = _localAndroidStorageBackend();
    if (backend == null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateHostWorkspaceDialog(),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    try {
      final workspace = await backend.createHostWorkspace(name);
      final currentWorkspaces = await _currentWorkspaceItems();
      if (!mounted) return;
      final merged = <WorkspaceRef>[
        ...currentWorkspaces.where((item) => !_sameWorkspace(item, workspace)),
        workspace,
      ];
      setState(() {
        _workspaceItems = merged;
        _workspaces = Future.value(merged);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh
                ? '已创建本地工作区：${workspace.displayPath}'
                : 'Host workspace created: ${workspace.displayPath}',
          ),
        ),
      );
    } on BackendException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyBackendError(error, chinese: zh))),
      );
    }
  }

  Future<void> _removeWorkspace(WorkspaceRef removed) async {
    final localBackend = _localAndroidStorageBackend();
    final localWorkspace = localBackend == null
        ? null
        : _asLocalAndroidWorkspace(removed, localBackend);
    final safWorkspace = removed.backendLocator.startsWith('saf://');
    if (localBackend != null && !safWorkspace) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(zh ? '删除本地工作区？' : 'Delete local workspace?'),
          content: Text(
            zh
                ? '将删除“${removed.displayPath}”及其中的本地文件，且无法从应用内恢复。'
                : 'This permanently deletes ${removed.displayPath} and its local files.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(zh ? '取消' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: Text(zh ? '删除' : 'Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final currentWorkspaces = await _currentWorkspaceItems();
    if (!mounted) return;
    final relatedEntries = _sessionEntries.values
        .where((entry) => _sameWorkspace(entry.workspace, removed))
        .toList(growable: false);
    for (final entry in relatedEntries) {
      await entry.pageKey.currentState?.stopFromHome();
    }

    try {
      if (localBackend != null) {
        if (safWorkspace) {
          await localBackend.forgetSafWorkspace(localWorkspace!);
        } else {
          await localBackend.deleteHostWorkspace(localWorkspace!);
        }
      }
    } on BackendException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyBackendError(
              error,
              chinese: Localizations.localeOf(context).languageCode == 'zh',
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final remaining = currentWorkspaces
        .where((item) => !_sameWorkspace(item, removed))
        .toList(growable: false);
    setState(() {
      _workspaceItems = remaining;
      _workspaces = Future.value(remaining);
      for (final entry in relatedEntries) {
        _sessionEntries.remove(entry.id);
      }
      if (relatedEntries.any((entry) => entry.id == _selectedSessionEntryId)) {
        _selectedSessionEntryId = null;
        _sessionVisible = false;
      }
    });
    unawaited(_reloadWorkspaces());
  }

  Future<void> _openFirstWorkspaceSession() async {
    List<WorkspaceRef> workspaces;
    try {
      workspaces = _workspaceItems.isNotEmpty
          ? _workspaceItems
          : await _workspaces;
    } catch (_) {
      workspaces = const <WorkspaceRef>[];
    }
    if (!mounted) return;
    if (workspaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _uiText(
              context,
              '请先添加一个 workspace，再开始 Codex 会话。',
              'Add a workspace before starting a Codex session.',
            ),
          ),
        ),
      );
      return;
    }
    await _openLocalSession(workspaces.first, newSession: true);
  }

  Future<void> _openLocalSession(
    WorkspaceRef workspace, {
    SessionHistoryRecord? history,
    bool newSession = false,
    ExecutionIdentity? initialIdentity,
    bool settingsOnly = false,
  }) async {
    await _authBindingLoaded;
    if (!mounted) return;
    if (!_rehydratingPersistedSessions) _sessionNavigationTouched = true;
    // Provider source is a global, mutually-exclusive app setting. Resolve it
    // before constructing any saved or fresh session so a stale provider ID
    // in an older history record cannot override an explicit OpenAI choice.
    if (!_customProvidersLoaded) {
      await _loadActiveCustomProvider();
    }
    if (!mounted) return;
    final providerModeExplicit = _modelProviderMode != null;
    // The source settings page can finish restoring the selected provider
    // while its active-provider cache is still being refreshed. In that
    // window the UI already has the user's explicit third-party selection in
    // `_selectedCustomProvider`; do not construct a missing-provider session
    // when that selected configuration is available.
    final activeCustomProvider = _modelProviderMode == 'third_party'
        ? (_activeCustomProvider ?? _selectedCustomProvider)
        : null;
    CustomProviderConfig? historyProvider;
    String? missingProviderId;
    if (_modelProviderMode == 'openai') {
      historyProvider = null;
    } else if (_modelProviderMode == 'third_party') {
      historyProvider = activeCustomProvider;
      if (historyProvider == null) {
        missingProviderId =
            _missingActiveCustomProviderId ??
            _activeCustomProviderId ??
            'active-third-party-provider';
      }
    } else {
      final requiredProviderId = history?.customProviderId;
      historyProvider = _providerForHistory(history, requiredProviderId);
      if (requiredProviderId != null && historyProvider == null) {
        missingProviderId = requiredProviderId;
      }
    }
    final missingProviderForSession =
        history == null &&
            _modelProviderMode == 'third_party' &&
            activeCustomProvider == null
        ? (missingProviderId ?? 'active-third-party-provider')
        : null;
    Backend? nextBackend;
    if (workspace.backendId != _backend.descriptor.id) {
      try {
        nextBackend = _selector.select(workspace.backendId);
      } on BackendException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backend ${workspace.backendId} is unavailable: $error',
            ),
          ),
        );
        return;
      }
    }
    final selected = settingsOnly
        ? null
        : _findSessionEntry(workspace, history, newSession);
    final entry =
        selected ??
        _LocalSessionEntry(
          id: _newSessionEntryId(),
          backend: nextBackend ?? _backend,
          workspace: workspace,
          pageKey: GlobalKey<_LocalSessionPageState>(),
          sessionId: history?.sessionId,
          threadId: history?.threadId,
          history: history,
          startsFresh: newSession && history == null,
          customProvider: history == null
              ? activeCustomProvider
              : historyProvider,
          missingCustomProviderId: history == null
              ? missingProviderForSession
              : missingProviderId,
          providerModeExplicit: providerModeExplicit,
          executionIdentity:
              history?.executionIdentity ??
              initialIdentity ??
              ExecutionIdentity.root,
          initialModel: widget.defaultCodexModel,
          initialEffort: widget.defaultCodexEffort,
          initialApprovalPolicy: widget.defaultCodexApprovalPolicy,
          initialSandbox: widget.defaultCodexSandbox,
          settingsOnly: settingsOnly,
        );
    if (selected == null) _sessionEntries[entry.id] = entry;
    if (history != null) {
      entry.history = history;
      entry.sessionId = history.sessionId ?? entry.sessionId;
      entry.threadId = history.threadId ?? entry.threadId;
      entry.startsFresh = false;
      if (selected == null || providerModeExplicit) {
        entry.customProvider = historyProvider;
        entry.missingCustomProviderId = missingProviderId;
        entry.providerModeExplicit = providerModeExplicit;
        if (selected != null && providerModeExplicit) {
          entry.pageKey.currentState?.setCustomProvider(historyProvider);
        }
      }
    } else if (newSession) {
      entry.history = null;
      entry.startsFresh = true;
    }
    if (!mounted) return;
    setState(() {
      if (!settingsOnly && nextBackend != null) {
        _backendSelectionChanged = true;
        _backend = nextBackend!;
        _workspaceItems = const <WorkspaceRef>[];
        _workspaces = _listWorkspacesFor(_backend);
      }
      if (!settingsOnly) {
        _selectedSessionEntryId = entry.id;
        _sessionVisible = true;
      }
    });
  }

  CustomProviderConfig? _providerForHistory(
    SessionHistoryRecord? history,
    String? requiredProviderId,
  ) {
    if (history == null) return null;
    if (requiredProviderId != null) {
      return _customProviders
          .where((provider) => provider.id == requiredProviderId)
          .firstOrNull;
    }

    // Older history records predate customProviderId. Recover them only when
    // the model name identifies exactly one configured provider; this avoids
    // accidentally converting an OpenAI session merely because a custom
    // provider is currently active.
    final model = history.codexModel.trim();
    if (model.isEmpty) return null;
    final matches = _customProviders
        .where((provider) => provider.model.trim() == model)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> _openHistorySession(
    WorkspaceRef workspace,
    SessionHistoryRecord history,
  ) => _openLocalSession(workspace, history: history);

  Future<void> _openWorkspaceFiles(WorkspaceRef workspace) async {
    Backend backend = _backend;
    if (workspace.backendId != backend.descriptor.id) {
      try {
        backend = _selector.select(workspace.backendId);
      } on BackendException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backend ${workspace.backendId} is unavailable: $error',
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            WorkspaceFilesPage(backend: backend, workspace: workspace),
      ),
    );
  }

  Future<void> _openForkedSession(
    WorkspaceRef workspace,
    SessionHistoryRecord history,
  ) => _openLocalSession(workspace, history: history);

  void _showLocalSession() {
    if (!mounted || _sessionWorkspace == null) return;
    setState(() => _sessionVisible = true);
  }

  void _hideLocalSession() {
    if (!mounted) return;
    setState(() {
      _sessionVisible = false;
    });
    // The session page is kept alive so CC Pocket's Running card can reopen
    // it without losing the app-server. Refresh the lightweight history index
    // when the page is hidden so a completed turn or a changed draft is
    // immediately reflected on Home.
    unawaited(_reloadSessionHistories());
  }

  String _newSessionEntryId() {
    _sessionEntrySequence++;
    return 'local-tab-${DateTime.now().microsecondsSinceEpoch}-$_sessionEntrySequence';
  }

  _LocalSessionEntry? _findSessionEntry(
    WorkspaceRef workspace,
    SessionHistoryRecord? history,
    bool newSession,
  ) {
    if (newSession) return null;
    if (history != null) {
      final historySessionId = history.sessionId?.trim();
      final hasStableSessionId =
          historySessionId != null && historySessionId.isNotEmpty;
      for (final entry in _sessionEntries.values) {
        if (!_sameWorkspace(entry.workspace, workspace)) continue;
        if (_sameHistoryRecord(entry.history, history)) return entry;
        final snapshot = entry.snapshot;
        if (hasStableSessionId) {
          if (snapshot?.sessionId == historySessionId ||
              entry.sessionId == historySessionId) {
            return entry;
          }
          // A durable local session id is the app's conversation identity.
          // Do not fall back to the provider thread id here: old/broken
          // records can share a thread id, and doing so reopens the first
          // session when the user taps a different card in the same workspace.
          continue;
        }
        final historyThreadId = history.threadId?.trim();
        if (historyThreadId != null &&
            historyThreadId.isNotEmpty &&
            (snapshot?.threadId == historyThreadId ||
                entry.threadId == historyThreadId)) {
          return entry;
        }
      }
      return null;
    }
    final selected = _selectedSessionEntry;
    if (selected != null && _sameWorkspace(selected.workspace, workspace)) {
      return selected;
    }
    return null;
  }

  void _updateSessionSnapshot(String? entryId, LocalSessionSnapshot? snapshot) {
    if (!mounted) return;
    final entry = entryId == null ? null : _sessionEntries[entryId];
    if (entry == null) return;
    // Session pages publish snapshots while streaming. Mutate the entry
    // immediately so a later callback observes the newest state, but rebuild
    // the shell at most once per frame. Without this coalescing, two active
    // sessions turn every token/tool event into a full Home + IndexedStack
    // rebuild and make the UI input-latency grow with the number of sessions.
    final wasTurning = entry.snapshot?.turnActive == true;
    entry.snapshot = snapshot;
    if (snapshot != null) {
      entry.sessionId = snapshot.sessionId ?? entry.sessionId;
      entry.threadId = snapshot.threadId ?? entry.threadId;
    }
    // The visible conversation owns its own stream rendering. Rebuilding the
    // Home/IndexedStack shell for every token while that page is on screen
    // adds work to every retained session page without changing visible UI.
    // The latest snapshot is already stored above and will be painted when
    // Home is shown again.
    if (_sessionVisible) return;
    // The selected session paints its own stream at frame cadence. Home only
    // needs a compact status update, so refresh at most about 3-4 times a
    // second while a turn is streaming. Flush lifecycle transitions
    // immediately so a stop, failure, or completion is reflected promptly.
    _scheduleSessionSnapshotRefresh(
      immediate: wasTurning && snapshot?.turnActive != true,
    );
  }

  void _scheduleSessionSnapshotRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      _sessionSnapshotRefreshTimer?.cancel();
      _sessionSnapshotRefreshTimer = null;
      _sessionSnapshotRefreshScheduled = false;
      setState(() {});
      return;
    }
    if (_sessionSnapshotRefreshScheduled) return;
    _sessionSnapshotRefreshScheduled = true;
    _sessionSnapshotRefreshTimer = Timer(const Duration(milliseconds: 300), () {
      _sessionSnapshotRefreshScheduled = false;
      _sessionSnapshotRefreshTimer = null;
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopLocalSession() async {
    await _stopSessionByEntryId(_selectedSessionEntryId);
    await _reloadSessionHistories();
  }

  Future<void> _toggleActiveSessionPinned() async {
    await _toggleSessionPinnedByEntryId(_selectedSessionEntryId);
    await _reloadSessionHistories();
  }

  _LocalSessionEntry? _entryForSessionId(String sessionId) {
    for (final entry in _sessionEntries.values) {
      if (entry.snapshot?.sessionId == sessionId) return entry;
    }
    return null;
  }

  void _showSessionById(String sessionId) {
    final entry = _entryForSessionId(sessionId);
    if (entry == null || !mounted) return;
    setState(() {
      _selectedSessionEntryId = entry.id;
      _sessionVisible = true;
    });
  }

  Future<void> _stopSessionById(String sessionId) async {
    await _stopSessionByEntryId(_entryForSessionId(sessionId)?.id);
    await _reloadSessionHistories();
  }

  Future<void> _stopSessionByEntryId(String? entryId) async {
    await _sessionEntries[entryId]?.pageKey.currentState?.stopFromHome();
  }

  Future<void> _toggleSessionPinnedById(String sessionId) async {
    await _toggleSessionPinnedByEntryId(_entryForSessionId(sessionId)?.id);
    await _reloadSessionHistories();
  }

  Future<void> _toggleSessionPinnedByEntryId(String? entryId) async {
    await _sessionEntries[entryId]?.pageKey.currentState
        ?.togglePinnedFromHome();
  }

  static bool _sameWorkspace(WorkspaceRef left, WorkspaceRef right) {
    return left.backendId == right.backendId &&
        left.filesystemOwnerId == right.filesystemOwnerId &&
        left.hostPath == right.hostPath;
  }

  static bool _sameHistoryRecord(
    SessionHistoryRecord? left,
    SessionHistoryRecord right,
  ) {
    if (left == null) return false;
    return left.backendId == right.backendId &&
        left.workspacePath == right.workspacePath &&
        left.sessionId == right.sessionId &&
        left.threadId == right.threadId &&
        left.title == right.title &&
        left.updatedAtEpochMs == right.updatedAtEpochMs;
  }

  Future<void> _openHostAccessSettings() async {
    try {
      await AppHostAccessProbe.openSettings();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${error.code}: ${error.message ?? error.code}'),
        ),
      );
    }
  }

  Future<void> _openModelProviderSettings() async {
    if (!_customProvidersLoaded) await _loadActiveCustomProvider();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ModelProviderSettingsPage(
          selectedProvider: _selectedCustomProvider,
          thirdPartyEnabled:
              _modelProviderMode == 'third_party' ||
              (_modelProviderMode == null && _activeCustomProvider != null),
          onSelectionChanged: (mode, selectedProvider) {
            if (!mounted) return;
            _customProviderSelectionRevision++;
            _customProvidersLoaded = true;
            // Choosing OpenAI disables the third-party route; it must not
            // erase which third-party configuration the user had saved.
            final selected =
                selectedProvider ??
                (mode == 'openai' ? _selectedCustomProvider : null);
            final activeProvider = mode == 'third_party'
                ? (selectedProvider ?? _activeCustomProvider)
                : null;
            if (selectedProvider != null) {
              _customProviders = <CustomProviderConfig>[
                for (final provider in _customProviders)
                  if (provider.id != selectedProvider.id) provider,
                selectedProvider,
              ];
            }
            final openPages = <_LocalSessionPageState>[];
            setState(() {
              _selectedCustomProvider = selected;
              _activeCustomProvider = activeProvider;
              _activeCustomProviderId = activeProvider?.id ?? selected?.id;
              _modelProviderMode = mode;
              _missingActiveCustomProviderId = null;
              for (final entry in _sessionEntries.values) {
                entry.customProvider = activeProvider;
                entry.missingCustomProviderId = null;
                entry.providerModeExplicit = true;
                // Rebuild cached page widgets with the global selection too.
                // The GlobalKey retains mounted state; provider-specific
                // threads are stopped/reset by setCustomProvider below.
                entry.page = null;
                final page = entry.pageKey.currentState;
                if (page != null) openPages.add(page);
              }
            });
            for (final page in openPages) {
              page.setCustomProvider(activeProvider);
            }
          },
        ),
      ),
    );
    if (mounted) await _loadActiveCustomProvider(refresh: true);
  }

  Future<void> _openSettingsPage() async {
    if (!mounted) return;
    final wasSessionVisible = _sessionVisible;
    _LocalSessionEntry? settingsEntry;
    for (final entry in _sessionEntries.values) {
      if (entry.settingsOnly) {
        settingsEntry = entry;
        break;
      }
    }
    var authSession = settingsEntry?.pageKey.currentState;
    if (authSession == null) {
      List<WorkspaceRef> workspaces;
      try {
        workspaces = _workspaceItems.isNotEmpty
            ? _workspaceItems
            : await _workspaces;
      } catch (_) {
        workspaces = const <WorkspaceRef>[];
      }
      if (workspaces.isNotEmpty) {
        // Authentication must live in the same compatibility home that Root
        // sessions seed into their isolated CODEX_HOME. The login process
        // itself remains App UID, so opening Settings never asks for Root;
        // only the runtime path is shared with the real Root/PRoot turn.
        var authWorkspace = workspaces.first;
        LinuxCompatibilityBackend? compatibilityBackend;
        for (final backend in _selector.backends) {
          if (backend is LinuxCompatibilityBackend &&
              backend.descriptor.capabilities.usable) {
            compatibilityBackend = backend;
            break;
          }
        }
        if (compatibilityBackend != null) {
          try {
            final compatibilityWorkspaces = await compatibilityBackend
                .listWorkspaces();
            for (final candidate in compatibilityWorkspaces) {
              if (candidate.hostPath == authWorkspace.hostPath) {
                authWorkspace = candidate;
                break;
              }
            }
          } catch (_) {
            // Keep the App UID backend if the compatibility workspace probe
            // is temporarily unavailable. Settings can still be opened.
          }
        }
        await _openLocalSession(
          authWorkspace,
          newSession: true,
          initialIdentity: ExecutionIdentity.app,
          settingsOnly: true,
        );
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        for (final entry in _sessionEntries.values) {
          if (entry.settingsOnly &&
              entry.workspace.hostPath == authWorkspace.hostPath &&
              entry.workspace.backendId == authWorkspace.backendId) {
            settingsEntry = entry;
            break;
          }
        }
        // A settings-only entry is intentionally not selected as a visible
        // conversation. When Home has no selected thread yet, however, the
        // IndexedStack would otherwise omit every session child and the
        // settings page could not obtain its login owner. Select it only as
        // the hidden stack anchor; `selectedSessionIsVisible` keeps Home on
        // screen and the entry remains excluded from the session list.
        if (settingsEntry != null && _selectedSessionEntryId == null) {
          setState(() {
            _selectedSessionEntryId = settingsEntry!.id;
            _sessionVisible = false;
          });
          await WidgetsBinding.instance.endOfFrame;
        }
        authSession = settingsEntry?.pageKey.currentState;
        if (!wasSessionVisible && _sessionVisible) {
          setState(() {
            _sessionVisible = false;
          });
        }
      }
    }
    if (authSession != null) {
      // Settings is the single authentication surface. Refresh its status as
      // it opens so a valid local login is not shown as "Not checked" until
      // the user discovers the secondary refresh button.
      unawaited(authSession.refreshAuthStatus());
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CodexPocketSettingsPage(
          runtime: _runtime,
          compatibilityRuntime: _probeCompatibilityRuntime(),
          compatibilityCliVersion: _activeCompatibilityCliVersion,
          hostAccess: _appHostAccess,
          onInstallCompatibilityRootfs: _installCompatibilityRootfs,
          onUpdateCompatibilityCodex:
              _selector.backends.any(
                (backend) => backend is LinuxCompatibilityBackend,
              )
              ? _updateCompatibilityCodex
              : null,
          onRollbackCompatibilityCodex:
              _selector.backends.any(
                (backend) => backend is LinuxCompatibilityBackend,
              )
              ? _rollbackCompatibilityCodex
              : null,
          onOpenHostAccessSettings: _openHostAccessSettings,
          onOpenModelProviders: _openModelProviderSettings,
          onOpenMcpSettings: authSession == null
              ? null
              : () => _openMcpSettings(authSession!),
          onRefresh: () async {
            _refreshLocalCapabilities();
            await _reloadWorkspaces();
            await _reloadSessionHistories();
            return _runtime;
          },
          loginRevision: authSession?.authRevision,
          loginBuilder: authSession == null
              ? null
              : (_) => authSession!.buildAuthControls(),
          // Do not start an asynchronous CLI process while this route is being
          // constructed. The model tile loads on tap and immediately observes
          // the result, so an unavailable runtime becomes a retryable UI state
          // instead of an unhandled error before FutureBuilder subscribes.
          modelCatalog: authSession?.cachedModelCatalog,
          onRefreshModelCatalog: authSession == null
              ? null
              : () => authSession!.refreshModelCatalog(),
          model: widget.defaultCodexModel,
          effort: widget.defaultCodexEffort,
          approvalPolicy: widget.defaultCodexApprovalPolicy,
          sandbox: widget.defaultCodexSandbox,
          themeMode: widget.themeMode,
          locale: widget.locale,
          onThemeModeChanged: widget.onThemeModeChanged,
          onLocaleChanged: widget.onLocaleChanged,
          onModelChanged: widget.onDefaultCodexModelChanged,
          onEffortChanged: widget.onDefaultCodexEffortChanged,
          onApprovalPolicyChanged: widget.onDefaultCodexApprovalPolicyChanged,
          onSandboxChanged: widget.onDefaultCodexSandboxChanged,
        ),
      ),
    );
    if (mounted && !wasSessionVisible && _sessionVisible) {
      setState(() => _sessionVisible = false);
    }
  }

  Future<void> _openMcpSettings(_LocalSessionPageState session) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CodexMcpSettingsPage(
          onLoadServers: session.readMcpServersForSettings,
          onLoadStatuses: session.readMcpServerStatusesForSettings,
          onAddServer: session.addMcpServerForSettings,
          onRemoveServer: session.removeMcpServerForSettings,
          onLogin: session.loginMcpServerForSettings,
          onLoadPlugins: session.readPluginsForSettings,
          onInstallPlugin: session.installPluginForSettings,
          onRemovePlugin: session.removePluginForSettings,
          onSetPluginEnabled: session.setPluginEnabledForSettings,
          onLoadPluginMarketplaces: session.readPluginMarketplacesForSettings,
          onAddPluginMarketplace: session.addPluginMarketplaceForSettings,
          onRemovePluginMarketplace: session.removePluginMarketplaceForSettings,
          onUpgradePluginMarketplace:
              session.upgradePluginMarketplaceForSettings,
        ),
      ),
    );
  }

  Future<CodexCliUpdater> _compatibilityCodexUpdater() async {
    final backend = _selector.backends
        .whereType<LinuxCompatibilityBackend>()
        .firstOrNull;
    if (backend == null) {
      throw const BackendException(
        'Linux compatibility runtime is not configured.',
      );
    }
    final runtime = await backend.refresh();
    if (!runtime.usable) {
      throw BackendException(
        runtime.reason ?? 'Linux compatibility runtime is not verified.',
      );
    }
    // CLI updates are runtime maintenance, not workspace work. Use the
    // hidden app-private maintenance cwd exposed by the verified native
    // runtime so a clean install can update the independent CLI before the
    // user creates a project workspace.
    final workspace = backend.runtimeMaintenanceWorkspace();
    return CodexCliUpdater(backend: backend, workspace: workspace);
  }

  Future<CompatibilityRuntimeDescriptor> _probeCompatibilityRuntime() async {
    final existingProbe = _compatibilityRuntimeProbe;
    if (existingProbe != null) return existingProbe;
    final backend = _selector.backends
        .whereType<LinuxCompatibilityBackend>()
        .firstOrNull;
    if (backend == null) {
      return const CompatibilityRuntimeDescriptor.missing(
        reason: 'Linux compatibility runtime is not configured.',
      );
    }
    return _compatibilityRuntimeProbe = _refreshCompatibilityBackend(backend);
  }

  Future<CompatibilityRuntimeDescriptor?> _installCompatibilityRootfs() async {
    final runtime = await const CompatibilityRootfsInstaller().pickAndInstall();
    if (runtime == null) return null;
    _selector.backends
        .whereType<LinuxCompatibilityBackend>()
        .firstOrNull
        ?.acceptRuntimeProbe(runtime);
    return runtime;
  }

  Future<CodexCliUpdateResult> _updateCompatibilityCodex() async {
    final result = await (await _compatibilityCodexUpdater()).update();
    if (mounted) {
      setState(() => _activeCompatibilityCliVersion = result.installedVersion);
      widget.onCompatibilityCliVersionChanged?.call(result.installedVersion);
    }
    return result;
  }

  Future<CodexCliUpdateResult> _rollbackCompatibilityCodex() async {
    final result = await (await _compatibilityCodexUpdater())
        .rollbackToPrevious();
    if (mounted) {
      setState(() => _activeCompatibilityCliVersion = result.installedVersion);
      widget.onCompatibilityCliVersionChanged?.call(result.installedVersion);
    }
    return result;
  }

  CcpocketHomeSessionSnapshot _toHomeSessionSnapshot(
    LocalSessionSnapshot snapshot,
  ) {
    return CcpocketHomeSessionSnapshot(
      workspace: snapshot.workspace,
      status: snapshot.status,
      active: snapshot.active,
      busy: snapshot.busy,
      turnActive: snapshot.turnActive,
      queuedPrompts: snapshot.queuedPrompts,
      sessionId: snapshot.sessionId,
      title: snapshot.title,
      pinned: snapshot.pinned,
      model: snapshot.model,
      effort: snapshot.effort,
      sandbox: snapshot.sandbox,
      approvalPolicy: snapshot.approvalPolicy,
      planMode: snapshot.planMode,
      createdAtEpochMs: snapshot.createdAtEpochMs,
      lastActivityAtEpochMs: snapshot.lastActivityAtEpochMs,
      lastMessage: snapshot.lastMessage,
    );
  }

  LocalSessionPage _pageForEntry(_LocalSessionEntry entry) {
    final cliVersion = _activeCompatibilityCliVersion;
    if (entry.page != null && entry.pageModelCatalogCliVersion == cliVersion) {
      return entry.page!;
    }
    // Keep the same GlobalKey/state for normal shell rebuilds, but replace the
    // widget when the compatibility CLI changes. That is the lifecycle edge
    // that makes LocalSessionPage.didUpdateWidget invalidate its in-flight
    // model catalog future after an updater or rollback operation.
    entry.pageModelCatalogCliVersion = cliVersion;
    return entry.page = LocalSessionPage(
      key: entry.pageKey,
      backend: entry.backend,
      fallbackBackend: _fallbackBackendFor(entry.backend),
      workspace: entry.workspace,
      runtime: _runtime,
      initialUsage: _homeUsage,
      initialHistory: entry.history,
      initialIdentity: entry.executionIdentity,
      initialModel: entry.initialModel,
      initialEffort: entry.initialEffort,
      initialApprovalPolicy: entry.initialApprovalPolicy,
      initialSandbox: entry.initialSandbox,
      customProvider: entry.customProvider,
      missingCustomProviderId: entry.missingCustomProviderId,
      providerModeExplicit: entry.providerModeExplicit,
      modelCatalogCliVersion: cliVersion,
      restoreHistory: !entry.startsFresh,
      initialAuthGeneration: _authGeneration,
      settingsOnly: entry.settingsOnly,
      sessionRuntime: entry.runtime,
      onClose: _hideLocalSession,
      onFork: _openForkedSession,
      onSnapshotChanged: (snapshot) =>
          _updateSessionSnapshot(entry.id, snapshot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = _backend.descriptor;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final homeSessionSnapshots = _sessionEntries.values
        .where((entry) => !entry.settingsOnly)
        .map((entry) => entry.snapshot)
        .whereType<LocalSessionSnapshot>()
        .map(_toHomeSessionSnapshot)
        .toList(growable: false);
    final selectedSessionEntry = _selectedSessionEntry;
    final selectedSessionIsVisible =
        selectedSessionEntry != null && !selectedSessionEntry.settingsOnly;
    final home = Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SessionListPaneHeader(
              onTitleTap: () {},
              onOpenSettings: _openSettingsPage,
              onOpenGallery: null,
              onDisconnect: null,
              runtimeLabel: null,
            ),
            Expanded(
              child: CcpocketNativeHome(
                backend: _backend,
                fallbackBackend: _fallbackBackendFor(_backend),
                descriptor: descriptor,
                workspaces: _workspaces,
                sessionHistories: _sessionHistories,
                hostAccess: _appHostAccess,
                usage: _homeUsage,
                onOpenUsageSettings: _openSettingsPage,
                onCreateHostWorkspace: _createHostWorkspace,
                onAddSafWorkspace: _addSafWorkspace,
                onRefresh: _reloadWorkspaces,
                onWorkspaceChanged: _removeWorkspace,
                onHistoryFlagsChanged: _updateSessionHistoryFlags,
                onDeleteSession: _deleteSessionHistory,
                onHistoryTitleChanged: _updateSessionHistoryTitle,
                activeSession:
                    !selectedSessionIsVisible || _sessionSnapshot == null
                    ? null
                    : _toHomeSessionSnapshot(_sessionSnapshot!),
                activeSessions: homeSessionSnapshots,
                onOpenSession: (workspace) =>
                    _openLocalSession(workspace, newSession: true),
                onOpenFiles: _openWorkspaceFiles,
                onOpenHistory: _openHistorySession,
                onOpenActiveSession: _showLocalSession,
                onStopActiveSession: _stopLocalSession,
                onToggleActiveSessionPinned: _toggleActiveSessionPinned,
                onOpenActiveSessionById: _showSessionById,
                onStopActiveSessionById: _stopSessionById,
                onToggleActiveSessionPinnedById: _toggleSessionPinnedById,
              ),
            ),
          ],
        ),
      ),
      // CC Pocket's session list creates a new session from the outer shell,
      // not from HomeContent. Keep that interaction intact while routing the
      // action to the single local Android workspace.
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _openFirstWorkspaceSession,
              icon: const Icon(Icons.add),
              label: Text(zh ? '新建' : 'New'),
            ),
    );
    if (_sessionEntries.isEmpty || selectedSessionEntry == null) return home;
    final sessionEntries = _sessionEntries.values.toList(growable: false);
    final selectedIndex = sessionEntries.indexWhere(
      (entry) => entry.id == selectedSessionEntry.id,
    );
    return IndexedStack(
      index: _sessionVisible ? selectedIndex + 1 : 0,
      children: [
        home,
        for (final entry in sessionEntries) _pageForEntry(entry),
      ],
    );
  }
}

class _CreateHostWorkspaceDialog extends StatefulWidget {
  const _CreateHostWorkspaceDialog();

  @override
  State<_CreateHostWorkspaceDialog> createState() =>
      _CreateHostWorkspaceDialogState();
}

class _CreateHostWorkspaceDialogState
    extends State<_CreateHostWorkspaceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
      title: Text(zh ? '创建本地工作区' : 'Create Host workspace'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: zh ? '文件夹名称' : 'Folder name',
          hintText: 'my-project',
          helperText: zh
              ? '将在 Codex/Workspaces 下创建一级文件夹。'
              : 'A new single-level folder below Codex/Workspaces.',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(zh ? '创建' : 'Create')),
      ],
    );
  }
}

class WorkspaceFilesPage extends StatefulWidget {
  const WorkspaceFilesPage({
    required this.backend,
    required this.workspace,
    super.key,
  });

  final Backend backend;
  final WorkspaceRef workspace;

  @override
  State<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends State<WorkspaceFilesPage> {
  WorkspaceHandle? _handle;
  String _relativePath = '';
  late Future<List<WorkspaceEntry>> _entries = _loadEntries('');

  Future<List<WorkspaceEntry>> _loadEntries(String relativePath) async {
    final handle = _handle ??= await widget.backend.openWorkspace(
      widget.workspace,
    );
    return widget.backend.listDirectory(handle, relativePath: relativePath);
  }

  void _reload() {
    setState(() {
      _entries = _loadEntries(_relativePath);
    });
  }

  void _openDirectory(WorkspaceEntry entry) {
    setState(() {
      _relativePath = entry.relativePath;
      _entries = _loadEntries(_relativePath);
    });
  }

  void _openFile(WorkspaceEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeSetPage(
          backend: widget.backend,
          workspace: widget.workspace,
          initialRelativePath: entry.relativePath,
        ),
      ),
    );
  }

  void _goUp() {
    if (_relativePath.isEmpty) return;
    final segments = _relativePath.split('/');
    segments.removeLast();
    final parent = segments.join('/');
    setState(() {
      _relativePath = parent;
      _entries = _loadEntries(parent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_uiText(context, '文件', 'Files')),
        actions: [
          IconButton(
            key: const ValueKey('batch_text_change_button'),
            tooltip: _uiText(context, '批量替换', 'Batch replace'),
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => BatchTextChangePage(
                    backend: widget.backend,
                    workspace: widget.workspace,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.find_replace_outlined),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('workspace_tools_menu'),
            tooltip: _uiText(context, '工作区工具', 'Workspace tools'),
            icon: const Icon(Icons.build_outlined),
            onSelected: (value) {
              switch (value) {
                case 'host':
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => HostExecutionPage(
                        backend: widget.backend,
                        workspace: widget.workspace,
                      ),
                    ),
                  );
                case 'backups':
                  final backend = widget.backend;
                  if (backend is! LocalAndroidBackend) return;
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => BackupHistoryPage(backend: backend),
                    ),
                  );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'host',
                child: Text(_uiText(context, '宿主命令', 'Host command')),
              ),
              if (widget.backend is LocalAndroidBackend)
                PopupMenuItem<String>(
                  value: 'backups',
                  child: Text(_uiText(context, '备份历史', 'Backup history')),
                ),
            ],
          ),
          IconButton(
            tooltip: _uiText(context, '刷新', 'Refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            widget.workspace.displayPath,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: _uiText(context, '上级目录', 'Parent directory'),
                onPressed: _relativePath.isEmpty ? null : _goUp,
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(
                child: Text(
                  _relativePath.isEmpty ? '/' : '/$_relativePath',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const Divider(),
          FutureBuilder<List<WorkspaceEntry>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(
                      _uiText(
                        context,
                        '无法读取此目录',
                        'Could not list this directory',
                      ),
                    ),
                    subtitle: Text('${snapshot.error}'),
                    trailing: IconButton(
                      tooltip: _uiText(context, '重试', 'Retry'),
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final entries = snapshot.data ?? const <WorkspaceEntry>[];
              if (entries.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(
                      _uiText(context, '此目录为空', 'Directory is empty'),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final entry in entries)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          entry.isDirectory
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          entry.isDirectory
                              ? _uiText(context, '文件夹', 'Directory')
                              : '${entry.sizeBytes} ${_uiText(context, '字节', 'bytes')} · ${entry.relativePath}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => entry.isDirectory
                            ? _openDirectory(entry)
                            : _openFile(entry),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class BackupHistoryPage extends StatefulWidget {
  const BackupHistoryPage({required this.backend, super.key});

  final LocalAndroidBackend backend;

  @override
  State<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends State<BackupHistoryPage> {
  late Future<List<LocalBackupRecord>> _backups = widget.backend.listBackups();
  String? _error;
  String? _restoring;

  void _reload() {
    setState(() {
      _error = null;
      _backups = widget.backend.listBackups();
    });
  }

  Future<void> _restore(LocalBackupRecord backup) async {
    if (!backup.isValid || _restoring != null) return;
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_uiText(context, '恢复备份？', 'Restore backup?')),
            content: Text(
              _uiText(
                context,
                '将 ${backup.workspace!.displayPath} 中的 ${backup.relativePath} 恢复为备份版本？恢复前会检查当前文件是否仍可读取。',
                'Restore ${backup.relativePath} from ${backup.workspace!.displayPath}? The current file must still be readable and will be checked before the restore.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_uiText(context, '取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_uiText(context, '恢复', 'Restore')),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    setState(() {
      _error = null;
      _restoring = backup.backupId;
    });
    try {
      await widget.backend.restoreBackup(backup);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _uiText(
              context,
              '已恢复备份：${backup.relativePath}',
              'Backup restored: ${backup.relativePath}',
            ),
          ),
        ),
      );
      setState(() => _restoring = null);
      _reload();
    } on BackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = null;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = null;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_uiText(context, '备份历史', 'Backup history')),
        actions: [
          IconButton(
            tooltip: _uiText(context, '刷新', 'Refresh'),
            onPressed: _restoring == null ? _reload : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<LocalBackupRecord>>(
        future: _backups,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _MessageCard(message: '${snapshot.error}'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: Text(_uiText(context, '重试', 'Retry')),
                ),
              ],
            );
          }
          final backups = snapshot.data ?? const <LocalBackupRecord>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                _uiText(
                  context,
                  '备份保存在应用私有目录。此列表仅展示元数据；恢复时会重新检查当前文件版本。',
                  'Backups are stored in app-private storage. The list exposes metadata only; restore re-checks the current file version.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _MessageCard(message: 'BackendException: $_error'),
              ],
              const SizedBox(height: 12),
              if (backups.isEmpty)
                _MessageCard(
                  message: _uiText(
                    context,
                    '未找到应用私有备份。',
                    'No app-private backups found.',
                  ),
                )
              else
                for (final backup in backups)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        backup.isValid
                            ? Icons.restore_outlined
                            : Icons.error_outline,
                      ),
                      title: Text(
                        backup.isValid
                            ? backup.relativePath
                            : _uiText(
                                context,
                                '备份不可用 ${backup.backupId}',
                                'Unavailable backup ${backup.backupId}',
                              ),
                      ),
                      subtitle: Text(
                        [
                          if (backup.workspace != null)
                            backup.workspace!.displayPath,
                          '${backup.sizeBytes} ${_uiText(context, '字节', 'bytes')} · ${backup.kind}',
                          if (backup.createdAtMs > 0)
                            DateTime.fromMillisecondsSinceEpoch(
                              backup.createdAtMs,
                            ).toLocal().toIso8601String(),
                          if (backup.reason != null) backup.reason!,
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: backup.isValid
                          ? FilledButton(
                              onPressed: _restoring == null
                                  ? () => _restore(backup)
                                  : null,
                              child: Text(
                                _restoring == backup.backupId
                                    ? _uiText(context, '正在恢复…', 'Restoring…')
                                    : _uiText(context, '恢复', 'Restore'),
                              ),
                            )
                          : null,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class ChangeSetPage extends StatefulWidget {
  const ChangeSetPage({
    required this.backend,
    required this.workspace,
    this.initialRelativePath = 'README.md',
    super.key,
  });

  final Backend backend;
  final WorkspaceRef workspace;
  final String initialRelativePath;

  @override
  State<ChangeSetPage> createState() => _ChangeSetPageState();
}

class _ChangeSetPageState extends State<ChangeSetPage> {
  final _service = ChangeSetService();
  late final TextEditingController _pathController;
  final _contentController = TextEditingController();

  WorkspaceHandle? _workspace;
  TextFileSnapshot? _snapshot;
  TextChangeSet? _changeSet;
  WriteReceipt? _receipt;
  String? _error;
  bool _busy = false;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.initialRelativePath);
    _loadSnapshot();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadSnapshot() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _showError(_text('必须填写相对路径。', 'A relative path is required.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _changeSet = null;
      _receipt = null;
    });
    try {
      final workspace = await widget.backend.openWorkspace(widget.workspace);
      final snapshot = await widget.backend.snapshotText(workspace, path);
      if (!mounted) return;
      _workspace = workspace;
      _snapshot = snapshot;
      _contentController.value = TextEditingValue(
        text: snapshot.content,
        selection: TextSelection.collapsed(offset: snapshot.content.length),
      );
      setState(() => _busy = false);
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _preview() async {
    final workspace = _workspace;
    final snapshot = _snapshot;
    if (workspace == null || snapshot == null) {
      _showError(
        _text(
          '请先加载文本文件，再创建变更预览。',
          'Load a text file before creating a change preview.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _receipt = null;
    });
    try {
      final changeSet = await _service.preview(
        backend: widget.backend,
        workspace: workspace,
        relativePath: snapshot.relativePath,
        proposedContent: _contentController.text,
      );
      if (!mounted) return;
      setState(() {
        _changeSet = changeSet;
        _busy = false;
      });
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _backupOnly() async {
    if (!widget.backend.descriptor.capabilities.managedChangesSupported) return;
    final workspace = _workspace;
    final snapshot = _snapshot;
    if (workspace == null || snapshot == null) {
      _showError(
        _text('请先加载文本文件，再创建备份。', 'Load a text file before creating a backup.'),
      );
      return;
    }
    final approved = await _confirm(
      title: _text('创建备份但不写入？', 'Create backup without writing?'),
      message: _text(
        '为 ${snapshot.relativePath} 创建可恢复备份。文件内容不会改变。',
        'Create a recoverable backup for ${snapshot.relativePath}. '
            'The file contents will not change.',
      ),
      confirmLabel: _text('创建备份', 'Create backup'),
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _receipt = null;
    });
    try {
      final receipt = await widget.backend.backupText(
        workspace,
        snapshot.relativePath,
        expectedVersion: snapshot.version,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _changeSet = TextChangeSet(
          backendId: widget.backend.descriptor.id,
          workspace: workspace,
          relativePath: snapshot.relativePath,
          before: snapshot,
          proposedContent: snapshot.content,
          diff: '',
        ).withReceipt(receipt);
        _busy = false;
      });
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _commit() async {
    if (!widget.backend.descriptor.capabilities.managedChangesSupported) return;
    final changeSet = _changeSet;
    if (changeSet == null || !changeSet.hasChanges) return;
    final approved = await _confirm(
      title: _text('批准托管写入？', 'Approve managed write?'),
      message: _text(
        '写入 ${changeSet.relativePath} 前会先创建备份。本次写入绑定到该路径和这份精确差异。',
        'A backup will be created before writing ${changeSet.relativePath}. '
            'The write is bound to this path and this exact diff.',
      ),
      confirmLabel: _text('批准写入', 'Approve write'),
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await _service.commit(
        backend: widget.backend,
        changeSet: changeSet,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _changeSet = changeSet.withReceipt(receipt);
        _busy = false;
      });
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _restore() async {
    if (!widget.backend.descriptor.capabilities.managedChangesSupported) return;
    final changeSet = _changeSet;
    final receipt = _receipt;
    if (changeSet == null || receipt == null || _workspace == null) return;
    late final TextFileSnapshot current;
    try {
      current = await widget.backend.snapshotText(
        _workspace!,
        changeSet.relativePath,
      );
    } on BackendException catch (error) {
      _showError(error.message);
      return;
    } catch (error) {
      _showError('$error');
      return;
    }
    final restoreDiff = buildUnifiedDiff(
      path: changeSet.relativePath,
      before: current.content,
      after: changeSet.before.content,
    );
    final approved = await _confirm(
      title: _text('恢复备份？', 'Restore backup?'),
      message: _text(
        '恢复 ${changeSet.relativePath} 变更前的备份？后端会再次检查当前版本。',
        'Restore the pre-change backup for ${changeSet.relativePath}? '
            'The current version will be checked again by the backend.',
      ),
      confirmLabel: _text('恢复', 'Restore'),
      diff: restoreDiff.isEmpty
          ? _text('没有可恢复的内容变更。', 'No content changes to restore.')
          : restoreDiff,
    );
    if (!approved || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.restore(
        backend: widget.backend,
        changeSet: changeSet,
        receipt: receipt,
        expectedVersion: current.version,
      );
      if (!mounted) return;
      await _loadSnapshot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('备份已恢复。', 'Backup restored.'))),
        );
      }
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String? diff,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  if (diff != null) ...[
                    const SizedBox(height: 16),
                    Text(_text('恢复预览', 'Restore preview')),
                    const SizedBox(height: 8),
                    SelectableText(
                      diff,
                      style: TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final changeSet = _changeSet;
    final receipt = _receipt;
    final supportsManagedChanges =
        widget.backend.descriptor.capabilities.managedChangesSupported;
    return Scaffold(
      appBar: AppBar(title: Text(_text('变更', 'Changes'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            _text('托管文本变更', 'Managed text change'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(widget.workspace.displayPath),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: _text('相对文件路径', 'Relative file path'),
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _busy ? null : _loadSnapshot,
                child: Text(_text('加载', 'Load')),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _MessageCard(
              message: '${_text('后端异常', 'BackendException')}: $_error',
            ),
          ],
          if (_snapshot != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('当前快照', 'Current snapshot'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _text(
                        '版本：${_snapshot!.version} · 字节数：${_snapshot!.sizeBytes}',
                        'version: ${_snapshot!.version} · '
                            'bytes: ${_snapshot!.sizeBytes}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _contentController,
                      minLines: 10,
                      maxLines: 18,
                      decoration: InputDecoration(
                        labelText: _text('拟写入文本', 'Proposed text'),
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _preview,
                      icon: const Icon(Icons.difference_outlined),
                      label: Text(_text('预览差异', 'Preview diff')),
                    ),
                    const SizedBox(height: 8),
                    if (supportsManagedChanges)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _backupOnly,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(_text('仅创建备份', 'Create backup only')),
                      )
                    else ...[
                      const SizedBox(height: 8),
                      Text(
                        _text(
                          '当前后端只提供快照和差异预览；备份、提交和恢复不可用。',
                          'This backend exposes snapshot and diff preview only; '
                              'backup, commit, and restore are unavailable.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (changeSet != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text('差异预览', 'Diff preview'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      changeSet.hasChanges
                          ? changeSet.diff
                          : _text('没有变更。', 'No changes.'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    if (supportsManagedChanges && changeSet.hasChanges) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _commit,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_text('使用备份提交', 'Commit with backup')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (receipt != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(
                  receipt.restored
                      ? _text('备份已恢复', 'Backup restored')
                      : _text('备份已创建', 'Backup created'),
                ),
                subtitle: Text(
                  _text(
                    '备份 ID：${receipt.backupId}',
                    'backup id: ${receipt.backupId}',
                  ),
                ),
                trailing: receipt.restored || !supportsManagedChanges
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : _restore,
                        child: Text(_text('恢复', 'Restore')),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _MessageCard(
            message: supportsManagedChanges
                ? _text(
                    '写入需要批准，并使用乐观版本检查。目标文件发生变化时会报告冲突。',
                    'Writes are approval-gated and use optimistic version '
                        'checks. A changed target is reported as a conflict.',
                  )
                : _text(
                    '当前后端在此处只提供只读快照和差异界面，没有修改文件。',
                    'This backend exposes a read-only snapshot and diff surface '
                        'here. No file was changed.',
                  ),
          ),
        ],
      ),
    );
  }
}

class HostExecutionPage extends StatefulWidget {
  const HostExecutionPage({
    required this.backend,
    required this.workspace,
    super.key,
  });

  final Backend backend;
  final WorkspaceRef workspace;

  @override
  State<HostExecutionPage> createState() => _HostExecutionPageState();
}

class _HostExecutionPageState extends State<HostExecutionPage> {
  final _commandController = TextEditingController(text: 'id');
  final _argumentsController = TextEditingController();
  ExecutionIdentity _identity = ExecutionIdentity.app;
  String _output = '';
  bool _running = false;
  InteractiveExecution? _execution;
  StreamSubscription<ExecutionEvent>? _subscription;

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void dispose() {
    _subscription?.cancel();
    final execution = _execution;
    _execution = null;
    unawaited(execution?.stop());
    _commandController.dispose();
    _argumentsController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      _showError(_text('必须填写 argv 命令。', 'An argv command is required.'));
      return;
    }
    if (_running) return;
    if (_identity == ExecutionIdentity.root && !await _confirmRootRun()) {
      return;
    }
    final argv = <String>[
      command,
      ..._argumentsController.text
          .split('\n')
          .map((argument) => argument.trim())
          .where((argument) => argument.isNotEmpty),
    ];
    setState(() {
      _output = '\$ ${argv.join(' ')}\n';
      _running = true;
    });
    try {
      final handle = await widget.backend.openWorkspace(widget.workspace);
      final execution = widget.backend.startInteractive(
        ExecutionRequest(
          argv: argv,
          cwd: handle.ref.hostPath,
          identity: _identity,
        ),
      );
      _execution = execution;
      _subscription = execution.events.listen(
        (event) {
          if (!mounted) return;
          setState(() {
            if (event.stdout != null) _output += event.stdout!;
            if (event.stderr != null) _output += event.stderr!;
            if (event.error != null) _output += 'error: ${event.error}\n';
            if (event.exitCode != null) {
              _output += '\n[exit ${event.exitCode}]\n';
              _running = false;
              _execution = null;
            }
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _output += 'error: $error\n';
            _running = false;
          });
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _running = false;
              _execution = null;
            });
          }
        },
      );
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _stop() async {
    final execution = _execution;
    if (execution == null) return;
    setState(() => _running = false);
    try {
      await execution.stop();
      if (mounted) {
        setState(() => _output += '\n[stopped]\n');
      }
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    } finally {
      if (identical(_execution, execution)) _execution = null;
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  Future<bool> _confirmRootRun() async {
    if (_identity != ExecutionIdentity.root) return true;
    // Root is the normal execution identity. The explicit Run/Probe button
    // is already the user's action for this panel; do not add a second
    // per-command approval dialog. Session-level Root authorization belongs
    // to LocalSessionPage and is reused by the Codex app-server session.
    return true;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _output += 'error: $message\n';
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_text('宿主命令', 'Host command'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            _text('显式 argv 执行', 'Explicit argv execution'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(widget.workspace.displayPath),
          const SizedBox(height: 16),
          TextField(
            controller: _commandController,
            decoration: InputDecoration(
              labelText: _text('命令（argv[0]）', 'Command (argv[0])'),
              border: OutlineInputBorder(),
            ),
            enabled: !_running,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _argumentsController,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: _text(
                '参数（每行一个；不使用 shell 语法）',
                'Arguments (one per line; no shell syntax)',
              ),
              border: OutlineInputBorder(),
            ),
            enabled: !_running,
          ),
          const SizedBox(height: 12),
          SegmentedButton<ExecutionIdentity>(
            segments: [
              ButtonSegment(
                value: ExecutionIdentity.app,
                label: Text(_text('应用 UID', 'App UID')),
              ),
              ButtonSegment(
                value: ExecutionIdentity.root,
                label: Text(_text('Root 助手', 'Root helper')),
              ),
            ],
            selected: {_identity},
            onSelectionChanged: _running
                ? null
                : (selection) => setState(() => _identity = selection.single),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              _running
                  ? _text('运行中…', 'Running…')
                  : _text('运行命令', 'Run command'),
            ),
          ),
          if (_running && _execution != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: Text(_text('停止', 'Stop')),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _output.isEmpty ? _text('暂无输出。', 'No output yet.') : _output,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MessageCard(
            message: _text(
              '这是 Android 宿主命令通道（App UID/Root）；git、node、npm、npx、python 等开发工具由 Linux/PRoot guest 提供，请在 Codex 会话中使用。执行器接受 argv，并将 cwd 保持在所选宿主工作区内。',
              'This runs commands on the Android host (App UID/Root). Developer tools such as git, node, npm, npx, and python come from the Linux/PRoot guest; use a Codex session for those. Commands use argv and stay within the selected host workspace.',
            ),
          ),
        ],
      ),
    );
  }
}

class LocalSessionSnapshot {
  const LocalSessionSnapshot({
    required this.workspace,
    required this.status,
    required this.active,
    required this.busy,
    required this.turnActive,
    required this.queuedPrompts,
    required this.transcriptCount,
    this.sessionId,
    this.threadId,
    this.title,
    this.pinned = false,
    this.phase = SessionState.stopped,
    this.model = 'gpt-6-luna',
    this.effort = 'low',
    this.sandbox = 'workspace-write',
    this.approvalPolicy = 'on-request',
    this.planMode = false,
    this.createdAtEpochMs = 0,
    this.lastActivityAtEpochMs = 0,
    this.lastMessage = '',
  });

  final WorkspaceRef workspace;
  final String status;
  final bool active;
  final bool busy;
  final bool turnActive;
  final List<String> queuedPrompts;
  final int transcriptCount;
  final String? sessionId;
  final String? threadId;
  final String? title;
  final bool pinned;
  final SessionState phase;
  final String model;
  final String effort;
  final String sandbox;
  final String approvalPolicy;
  final bool planMode;
  final int createdAtEpochMs;
  final int lastActivityAtEpochMs;
  final String lastMessage;

  String get workspaceName {
    return workspaceNameFromPath(workspace.displayPath);
  }

  String get displayTitle => title ?? workspaceName;
}

class _RenameSessionDialog extends StatefulWidget {
  const _RenameSessionDialog({required this.initialTitle});

  final String? initialTitle;

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle ?? '');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.renameSession),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 128,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: l.sessionNameHint,
          suffixIcon: const Icon(Icons.label_outline),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l.save),
        ),
      ],
    );
  }
}

class LocalSessionPage extends StatefulWidget {
  const LocalSessionPage({
    required this.backend,
    this.fallbackBackend,
    required this.workspace,
    this.runtime,
    this.initialUsage,
    this.initialHistory,
    this.initialIdentity = ExecutionIdentity.app,
    this.initialModel = 'gpt-6-luna',
    this.initialEffort = 'low',
    this.initialApprovalPolicy = 'never',
    this.initialSandbox = 'danger-full-access',
    this.customProvider,
    this.missingCustomProviderId,
    this.providerModeExplicit = false,
    this.modelCatalogCliVersion,
    this.restoreHistory = true,
    this.initialAuthGeneration,
    this.settingsOnly = false,
    this.sessionRuntime,
    this.onClose,
    this.onSnapshotChanged,
    this.onFork,
    super.key,
  });

  final Backend backend;
  final Backend? fallbackBackend;
  final WorkspaceRef workspace;
  final Future<CodexRuntimeDescriptor>? runtime;
  final CodexUsageSnapshot? initialUsage;
  final SessionHistoryRecord? initialHistory;
  final ExecutionIdentity initialIdentity;
  final String initialModel;
  final String initialEffort;
  final String initialApprovalPolicy;
  final String initialSandbox;
  final CustomProviderConfig? customProvider;
  final String? missingCustomProviderId;
  final bool providerModeExplicit;
  final String? modelCatalogCliVersion;
  final bool restoreHistory;
  final int? initialAuthGeneration;
  final bool settingsOnly;
  final _LocalSessionRuntimeHandle? sessionRuntime;
  final VoidCallback? onClose;
  final ValueChanged<LocalSessionSnapshot?>? onSnapshotChanged;
  final Future<void> Function(
    WorkspaceRef workspace,
    SessionHistoryRecord history,
  )?
  onFork;

  @override
  State<LocalSessionPage> createState() => _LocalSessionPageState();
}

class _CodexInvocation {
  const _CodexInvocation({required this.command, required this.environment});

  final String command;
  final Map<String, String> environment;
}

class _OneShotCommandResult {
  const _OneShotCommandResult({required this.output, required this.exitCode});

  final String output;
  final int? exitCode;
}

class _LocalSessionPageState extends State<LocalSessionPage>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<LocalSessionPage> {
  var _sessionId = '';
  String? _historyKeySessionId;
  var _historyUsesLegacyKey = false;
  var _historyPinned = false;
  String? _sessionTitle;
  String? _threadName;
  String? _firstPromptForAutomaticTitle;
  var _automaticTitleAttempted = false;
  var _sessionTitleManuallySet = false;
  final _commandController = TextEditingController(text: 'codex');
  final _argumentsController = TextEditingController(
    text: 'app-server\n--listen\nstdio://',
  );
  final _promptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _transcript = <String>[];
  final _promptHistory = <String>[];
  final _queuedPrompts = <String>[];
  final _queuedImageAttachments = <List<ImageAttachment>>[];
  final _attachedImages = <ImageAttachment>[];
  final _agentChangePreviewService = AgentFileChangePreviewService();
  final _historyStore = SessionHistoryStore();
  final _historyWrites = SessionHistoryWriteQueue();
  late final Future<void> _historyLoaded;
  // Opening a saved row is an action on the session itself. Once its local
  // history is loaded, reconnect the provider thread automatically instead
  // of stopping at a separate "Resume" confirmation card.
  var _automaticResumeAttempted = false;
  CustomProviderConfig? _customProvider;
  String? _openAiModelBeforeProvider;
  String? _openAiEffortBeforeProvider;
  String? _missingCustomProviderId;
  ExecutionIdentity _identity = ExecutionIdentity.app;
  String? _lastThreadId;
  String? _lastThreadPath;
  StreamSubscription<CodexSessionEvent>? _subscription;
  CodexLoginClient? _authClient;
  StreamSubscription<CodexAuthEvent>? _authSubscription;
  CodexAuthChallenge? _authChallenge;
  String? _authLoginStatus;
  CodexAuthMode _authMode = CodexAuthMode.deviceAuth;
  String? _autoOpenedAuthUrl;
  String? _openingAuthUrl;
  String _codexModel = 'gpt-6-luna';
  var _modelSelectionExplicit = false;
  String _codexEffort = 'low';
  String _codexSandbox = 'workspace-write';
  String? _codexPermissions;
  String _codexApprovalPolicy = 'on-request';
  var _planMode = false;
  final StringBuffer _streamingAssistantBuffer = StringBuffer();
  final StringBuffer _streamingThinkingBuffer = StringBuffer();
  final ValueNotifier<CcpocketNativeStreamingSnapshot> _streamingSnapshot =
      ValueNotifier(const CcpocketNativeStreamingSnapshot());
  var _streamingSnapshotDirty = false;
  String? _commandTranscriptId;
  var _commandOutputBuffer = '';
  var _conversationInputTokens = 0;
  var _conversationCachedInputTokens = 0;
  var _conversationOutputTokens = 0;
  var _conversationContextTokens = 0;
  int? _conversationContextWindow;
  var _conversationToolCalls = 0;
  var _conversationFileEdits = 0;
  var _conversationDuration = Duration.zero;
  DateTime? _turnStartedAt;
  CodexUsageSnapshot? _accountUsage;
  Future<void>? _accountUsageLoad;
  Future<CodexSessionClient>? _settingsClientLoad;
  var _accountUsageAttempted = false;
  CodexSessionEvent? _approval;
  List<AgentFileChangePreview>? _agentFileChanges;
  List<TextChangeSet>? _pendingAgentVerification;
  final Map<String, TextEditingController> _userInputControllers =
      <String, TextEditingController>{};
  final Map<String, String?> _userInputSelections = <String, String?>{};
  String _status = 'stopped';
  String? _error;
  bool _busy = false;
  bool _sending = false;
  bool _turnActive = false;
  bool _providerSwitching = false;
  bool _hasPendingProviderSelection = false;
  bool _threadNeedsProviderReset = false;
  CustomProviderConfig? _pendingProviderSelection;
  bool _legacyChatOnlyHistory = false;
  bool _connectionLost = false;
  String? _connectionLostReason;
  String? _inFlightPrompt;
  String? _retryPrompt;
  List<ImageAttachment> _retryImages = const <ImageAttachment>[];
  String? _retryingPromptTranscript;
  bool _mcpWarningShown = false;
  bool _providerNetworkWarningShown = false;
  String? _providerNetworkDiagnostic;
  Timer? _draftPersistenceTimer;
  Timer? _historyPersistenceTimer;
  Timer? _automaticReconnectTimer;
  var _sessionOperationGeneration = 0;
  var _explicitlyStopped = false;
  var _handlingSessionEvent = false;
  var _sessionFrameRefreshScheduled = false;
  var _sessionFrameRefreshNeedsRebuild = false;
  var _lastVisibleTranscriptCacheValid = false;
  String? _lastVisibleTranscriptSourceRaw;
  var _lastVisibleTranscriptMessageCache = '';
  var _snapshotPublishScheduled = false;
  String? _authStatus;
  final _authRevision = ValueNotifier<int>(0);
  int? _sessionAuthGeneration;
  var _accountBindingStale = false;
  var _accountStaleNoticeShown = false;
  Future<CodexModelCatalog>? _modelCatalogFuture;
  final _modelCatalogCache = CodexModelCatalogCache();
  late Future<CodexRuntimeDescriptor> _runtime;
  late Backend _activeBackend;
  late WorkspaceRef _activeWorkspace;
  late final _LocalSessionRuntimeHandle _sessionRuntime;
  var _usingFallback = false;
  var _automaticReconnectAttempted = false;
  late SessionInteractionState _interaction;
  late int _sessionCreatedAtEpochMs;
  var _sessionLastActivityAtEpochMs = 0;
  SessionClient? get _client => _sessionRuntime.client;
  set _client(SessionClient? value) {
    if (value == null) {
      // The caller that clears the client owns the awaited detach/dispose
      // sequence. Do not cancel the forwarding subscription synchronously
      // from this setter, because that would make a page transition race the
      // exact process cleanup boundary.
      _sessionRuntime.client = null;
    } else {
      _explicitlyStopped = false;
      _sessionRuntime.attachClient(value);
    }
  }

  bool get _sessionForegroundOwned => _sessionRuntime.sessionForegroundOwned;
  set _sessionForegroundOwned(bool value) {
    _sessionRuntime.sessionForegroundOwned = value;
  }

  bool get _authForegroundOwned => _sessionRuntime.authForegroundOwned;
  set _authForegroundOwned(bool value) {
    _sessionRuntime.authForegroundOwned = value;
  }

  bool get _isCompatibility =>
      _activeBackend.descriptor.kind == BackendKind.linuxCompatibility;

  /// OpenAI account generations only bind first-party sessions. A configured
  /// third-party Responses provider has its own endpoint and credential, so a
  /// later OpenAI login/logout must not invalidate that provider's thread.
  bool get _usesOpenAiAuthBinding =>
      _customProvider == null && _missingCustomProviderId == null;

  bool get _mayUseCompatibilityFallback =>
      widget.fallbackBackend?.descriptor.kind == BackendKind.linuxCompatibility;

  bool get _canQueueForReconnect =>
      _interaction.canQueuePrompt &&
      _connectionLost &&
      !_legacyChatOnlyHistory &&
      _client == null &&
      !_busy &&
      (_lastThreadId?.isNotEmpty ?? false);

  bool get _shouldPreferCompatibilityRuntime =>
      !_isCompatibility && _mayUseCompatibilityFallback;

  bool get _usesForegroundService => true;

  /// Changes the provider selected in Settings for future turns.
  ///
  /// If a turn is active, switching sources stops its current app-server turn
  /// and preserves the transcript. The next prompt starts with the explicitly
  /// selected provider instead of silently retaining the old one.
  void setCustomProvider(CustomProviderConfig? provider) {
    if (!mounted) return;
    final currentSelection = _providerSwitching && _hasPendingProviderSelection
        ? _pendingProviderSelection
        : _customProvider;
    final unchanged =
        (provider == null && currentSelection == null) ||
        provider?.hasSameConfigurationAs(currentSelection) == true;
    if (unchanged && _missingCustomProviderId == null) {
      return;
    }
    if (_providerSwitching) {
      _pendingProviderSelection = provider;
      _hasPendingProviderSelection = true;
      return;
    }
    if (_client != null) {
      _pendingProviderSelection = provider;
      _hasPendingProviderSelection = true;
      unawaited(_switchCustomProvider());
      return;
    }
    _applyCustomProvider(provider);
  }

  void _applyCustomProvider(CustomProviderConfig? provider) {
    if (!mounted) return;
    final previousProvider = _customProvider;
    final providerChanged = provider == null
        ? previousProvider != null
        : previousProvider == null ||
              !provider.hasSameConfigurationAs(previousProvider);
    final hasExistingThread =
        (_client?.threadId ?? _lastThreadId)?.trim().isNotEmpty == true;
    final resetExistingThread = providerChanged && hasExistingThread;
    if (resetExistingThread) {
      // App-server rollouts contain provider-specific response items. Do not
      // resume a third-party rollout against OpenAI (or vice versa); keep the
      // visible transcript, but start a clean provider thread on the next
      // prompt.
      _threadNeedsProviderReset = true;
      _lastThreadId = null;
      _lastThreadPath = null;
      _restoredHistory = null;
    }
    final recoveringMissingProvider = _missingCustomProviderId != null;
    final staleMissingProviderWarning = 'error: $_missingCustomProviderMessage';
    setState(() {
      _customProvider = provider;
      _missingCustomProviderId = null;
      if (recoveringMissingProvider) {
        _transcript.removeWhere(
          (entry) => entry.trim() == staleMissingProviderWarning,
        );
        if (_error == _missingCustomProviderMessage) _error = null;
      }
      if (provider != null) {
        if (previousProvider == null) {
          _openAiModelBeforeProvider ??= _codexModel;
          _openAiEffortBeforeProvider ??= _codexEffort;
        }
        _codexModel = provider.model;
        if (!provider.reasoningEfforts.contains(_codexEffort)) {
          _codexEffort = provider.reasoningEfforts.contains('low')
              ? 'low'
              : provider.reasoningEfforts.isNotEmpty
              ? provider.reasoningEfforts.first
              : widget.initialEffort;
        }
      } else if (previousProvider != null) {
        // The model name from a third-party config is not an OpenAI model.
        // Restore the session's last OpenAI selection, or its configured
        // global default when this was a restored provider-only history.
        _codexModel = _openAiModelBeforeProvider ?? widget.initialModel;
        _codexEffort = _openAiEffortBeforeProvider ?? widget.initialEffort;
        _modelSelectionExplicit = true;
        _openAiModelBeforeProvider = null;
        _openAiEffortBeforeProvider = null;
      }
      _modelCatalogFuture = null;
      _providerSwitching = false;
    });
    if (resetExistingThread) {
      _syncInteractionIdentity();
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        _uiText(
          '模型来源已切换。历史消息会保留；发送新消息将使用当前来源创建新 thread，不会自动迁移旧来源的上下文。',
          'Provider source changed. Visible history is preserved; a new prompt starts a thread with the selected provider, without migrating prior provider context.',
        ),
      );
    }
    unawaited(_persistHistory());
  }

  Future<void> _switchCustomProvider() async {
    if (!mounted || _providerSwitching) return;
    final interruptedTurn = _turnActive || _sending;
    setState(() => _providerSwitching = true);
    try {
      await _stopClient(keepConversation: true);
      if (!mounted) return;
      final provider = _pendingProviderSelection;
      _pendingProviderSelection = null;
      _hasPendingProviderSelection = false;
      _applyCustomProvider(provider);
      if (interruptedTurn && !_threadNeedsProviderReset) {
        _addStructuredTranscript(
          CodexTranscriptKind.system,
          _uiText(
            '模型来源已切换，当前生成已停止；下一条消息将使用新来源。',
            'Provider source changed. The current response was stopped; the next prompt will use the new source.',
          ),
        );
      }
      _publishSnapshot();
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      _pendingProviderSelection = null;
      _hasPendingProviderSelection = false;
      setState(() => _providerSwitching = false);
      _showError('切换模型来源失败：$error');
    }
  }

  @override
  bool get wantKeepAlive => true;

  static const _providerNetworkError =
      'Provider network connection failed. Check Android Wi-Fi, mobile data, '
      'VPN, or proxy settings and retry. The local session remains available.';

  String _localizedProviderNetworkErrorFor(String? diagnostic) =>
      ProviderNetworkErrorSummary.message(
        diagnostic: diagnostic,
        languageCode: Localizations.localeOf(context).languageCode,
      );

  String _uiText(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String get _legacyChatOnlyHistoryMessage =>
      Localizations.localeOf(context).languageCode == 'zh'
      ? '此历史会话来自已移除的旧版聊天传输，不能由 Codex app-server 恢复。历史内容仍保留；请开始新会话并选择 Responses API provider 后继续。'
      : 'This history uses the retired chat-only transport and cannot be resumed by Codex app-server. Its transcript is preserved; start a new session with a Responses API provider to continue.';

  String get _rootProfileUnavailableMessage =>
      switch (Localizations.localeOf(context).languageCode) {
        'zh' => 'Root 会话未启动：KernelSU 没有返回可用的 UID 0。应用使用 KernelSU 当前配置的正常 Root profile，不要求自定义 SELinux 域或固定附加组；请检查 KernelSU 是否允许本应用取得 Root。',
        'ja' => 'Root セッションを開始できませんでした。KernelSU が使用可能な UID 0 を返しませんでした。アプリは KernelSU の通常の Root profile を使用し、専用 SELinux ドメインや固定補助グループを要求しません。',
        'ko' => 'Root 세션을 시작하지 못했습니다. KernelSU가 사용 가능한 UID 0을 반환하지 않았습니다. 앱은 KernelSU의 일반 Root 프로필을 사용하며 사용자 지정 SELinux 도메인이나 고정 보조 그룹을 요구하지 않습니다.',
        _ => 'The Root session did not start because KernelSU did not return a usable UID 0. The app uses KernelSU’s normal configured Root profile and does not require a custom SELinux domain or fixed supplementary groups.',
      };

  String get _missingCustomProviderMessage =>
      switch (Localizations.localeOf(context).languageCode) {
        'zh' => '此会话需要的第三方模型配置已不存在。请在模型来源设置中恢复该配置，或明确切换此会话到 OpenAI 登录。为避免错误地使用其他账号，本会话不会自动切换提供商。',
        'ja' => 'このセッションで必要なカスタムプロバイダー設定が見つかりません。プロバイダー設定を復元するか、このセッションを OpenAI ログインへ明示的に切り替えてください。別のアカウントで誤送信しないよう、自動切り替えは行いません。',
        'ko' => '이 세션에 필요한 사용자 지정 제공자 설정이 없습니다. 제공자 설정을 복원하거나 이 세션을 OpenAI 로그인으로 명시적으로 전환하세요. 다른 계정으로 잘못 전송되지 않도록 자동 전환하지 않습니다.',
        _ => 'The custom provider required by this session is unavailable. Restore it in provider settings or explicitly switch this session to OpenAI login. The provider will not be changed automatically.',
      };

  String get _accountBindingStaleMessage => _uiText(
    '登录账号已切换。为避免使用旧账号，此 session 的旧 Codex thread 不会自动恢复；历史消息仍保留。发送新消息会为当前账号创建新的 thread。',
    'The Codex account changed. The old provider thread will not be resumed against the new account; local history is preserved. Sending a new message starts a new thread for the current account.',
  );

  @override
  void initState() {
    super.initState();
    _sessionRuntime = widget.sessionRuntime ?? _LocalSessionRuntimeHandle();
    _subscription = _sessionRuntime.events.listen(_handleEvent);
    _customProvider = widget.customProvider;
    _missingCustomProviderId = widget.missingCustomProviderId;
    final currentAuthGeneration =
        widget.initialAuthGeneration ??
        AuthBindingStore.currentGeneration.value;
    _sessionAuthGeneration =
        widget.initialHistory?.authGeneration ??
        (widget.initialHistory == null && widget.initialAuthGeneration != null
            ? currentAuthGeneration
            : null);
    _accountBindingStale =
        !widget.settingsOnly &&
        _usesOpenAiAuthBinding &&
        widget.initialAuthGeneration != null &&
        (_sessionAuthGeneration == null ||
            _sessionAuthGeneration != currentAuthGeneration);
    if (widget.initialAuthGeneration != null && !widget.settingsOnly) {
      AuthBindingStore.currentGeneration.addListener(
        _handleAuthGenerationChanged,
      );
    }
    _lastThreadId = _sessionRuntime.client?.threadId;
    final historyTimestamp = widget.initialHistory?.updatedAtEpochMs ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    _sessionCreatedAtEpochMs = historyTimestamp > 0 ? historyTimestamp : now;
    _sessionLastActivityAtEpochMs = historyTimestamp > 0
        ? historyTimestamp
        : now;
    _sessionId = widget.initialHistory?.sessionId ?? _newLocalSessionId();
    _modelSelectionExplicit = widget.initialHistory != null;
    _lastThreadPath = widget.initialHistory?.threadPath;
    _identity =
        widget.initialHistory?.executionIdentity ?? widget.initialIdentity;
    if (widget.initialHistory == null) {
      _codexModel = widget.initialModel;
      _codexEffort = widget.initialEffort;
      _codexSandbox = widget.initialSandbox;
      _codexApprovalPolicy = widget.initialApprovalPolicy;
    }
    _codexPermissions = _permissionProfileForCurrentPolicy();
    if (widget.initialHistory?.rootApprovalGranted == true) {
      _sessionRuntime.rootApprovalGrantedForSession = _sessionId;
    }
    if (_customProvider != null) _codexModel = _customProvider!.model;
    final initialHistory = widget.initialHistory;
    _sessionTitle =
        initialHistory?.title ??
        (initialHistory?.firstUserPrompt.isNotEmpty == true
            ? initialHistory!.generatedTitle
            : null);
    _threadName = initialHistory?.threadName;
    _sessionTitleManuallySet = initialHistory?.titleIsManual ?? false;
    _firstPromptForAutomaticTitle = initialHistory?.firstUserPrompt;
    _automaticTitleAttempted =
        _sessionTitleManuallySet ||
        initialHistory?.threadName?.trim().isNotEmpty == true;
    _historyUsesLegacyKey =
        widget.initialHistory != null &&
        widget.initialHistory!.sessionId == null;
    _historyKeySessionId =
        widget.initialHistory?.sessionId ??
        (widget.initialHistory == null ? _sessionId : null);
    _activeBackend = widget.backend;
    _accountUsage = widget.initialUsage;
    // A history row can be opened while the home page is currently showing
    // the other execution backend. Normalize the workspace identity at the
    // session boundary so the backend never receives a ref owned by its
    // sibling backend, even if an older caller passed one through.
    _activeWorkspace = _workspaceForBackend(_activeBackend);
    _interaction = SessionInteractionState.initial(
      workspaceId: _workspaceIdentity(_activeWorkspace),
      sessionId: _sessionId,
      threadId: widget.initialHistory?.threadId,
    );
    _runtime = widget.runtime ?? CodexRuntimeProbe().run();
    _promptController.addListener(_handlePromptChanged);
    _historyLoaded = _loadHistory();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishSnapshot();
      if (_missingCustomProviderId != null) {
        _showError(_missingCustomProviderMessage);
      } else {
        unawaited(_autoResumeSavedSession());
      }
    });
  }

  void _handleAuthGenerationChanged() {
    if (!mounted || widget.settingsOnly || !_usesOpenAiAuthBinding) return;
    final generation = AuthBindingStore.currentGeneration.value;
    if (_sessionAuthGeneration == generation && !_accountBindingStale) return;
    // Model visibility is account-scoped as well as CLI-version-scoped. Do
    // not let an already opened picker retain the previous account's catalog.
    _modelCatalogFuture = null;
    _markAccountBindingStale();
  }

  void _markAccountBindingStale() {
    if (!mounted || widget.settingsOnly) return;
    final client = _client;
    _accountBindingStale = true;
    _automaticReconnectAttempted = true;
    _automaticReconnectTimer?.cancel();
    _automaticReconnectTimer = null;
    final message = _accountBindingStaleMessage;
    setState(() {
      _connectionLost = true;
      _connectionLostReason = message;
      if (_client == null) _status = 'disconnected';
      _error = message;
    });
    if (!_accountStaleNoticeShown) {
      _accountStaleNoticeShown = true;
      _addStructuredTranscript(CodexTranscriptKind.system, message);
    }
    // A provider-auth failure or an account switch must not leave the old
    // app-server alive behind the history-only session. Dispose it while
    // keeping the local transcript; the next prompt will create a clean
    // thread under the current account.
    if (client != null) {
      unawaited(_stopClient(keepConversation: true));
    }
    _publishSnapshot();
    unawaited(_persistHistory());
  }

  Future<void> _autoResumeSavedSession() async {
    await _historyLoaded;
    if (!mounted ||
        _automaticResumeAttempted ||
        !widget.restoreHistory ||
        _client != null ||
        _busy ||
        _missingCustomProviderId != null) {
      return;
    }
    if (_accountBindingStale) {
      _automaticResumeAttempted = true;
      _markAccountBindingStale();
      return;
    }
    final threadId = _restoredHistory?.threadId ?? _lastThreadId;
    if (threadId == null || threadId.trim().isEmpty) return;
    if (threadId.startsWith('custom:')) {
      _automaticResumeAttempted = true;
      final message = _legacyChatOnlyHistoryMessage;
      setState(() {
        _legacyChatOnlyHistory = true;
        _connectionLost = true;
        _connectionLostReason = message;
        _status = 'disconnected';
      });
      _publishSnapshot();
      return;
    }
    if (_threadNeedsProviderReset) {
      _automaticResumeAttempted = true;
      setState(() {
        _lastThreadId = null;
        _lastThreadPath = null;
        _restoredHistory = null;
        _connectionLost = false;
        _connectionLostReason = null;
        _status = 'stopped';
        _syncInteractionIdentity();
      });
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        _uiText(
          '模型来源与此 thread 创建时不同。历史消息会保留；发送新消息将使用当前来源创建新 thread，不会自动迁移旧来源的上下文。',
          'The selected provider differs from the one that created this thread. Visible history is preserved; a new prompt starts a fresh thread with the selected provider, without migrating prior provider context.',
        ),
      );
      _publishSnapshot();
      unawaited(_persistHistory());
      return;
    }
    _automaticResumeAttempted = true;
    await _resumeSavedSession();
  }

  /// Reconnect once after an unexpected app-server exit.
  ///
  /// CC Pocket keeps the local session as the durable owner of the
  /// conversation. The process is only a transport, so an unexpected exit
  /// should not turn a live session into a manual "Resume" workflow. This is
  /// deliberately bounded to one attempt per disconnect; a provider/runtime
  /// failure still leaves the explicit recovery banner visible.
  void _scheduleAutomaticReconnect() {
    if (_automaticReconnectAttempted ||
        _accountBindingStale ||
        _explicitlyStopped ||
        _lastThreadId == null ||
        _lastThreadId!.trim().isEmpty ||
        !mounted) {
      return;
    }
    _automaticReconnectAttempted = true;
    final operationGeneration = _sessionOperationGeneration;
    _automaticReconnectTimer?.cancel();
    _automaticReconnectTimer = Timer(const Duration(milliseconds: 250), () {
      _automaticReconnectTimer = null;
      if (!mounted ||
          _explicitlyStopped ||
          operationGeneration != _sessionOperationGeneration ||
          !_connectionLost ||
          _legacyChatOnlyHistory ||
          _client != null ||
          _busy ||
          _lastThreadId == null) {
        return;
      }
      unawaited(
        _resumeSavedSession(expectedOperationGeneration: operationGeneration),
      );
    });
  }

  @override
  void didUpdateWidget(covariant LocalSessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelCatalogCliVersion != widget.modelCatalogCliVersion) {
      _modelCatalogFuture = null;
    }
    final incomingUsage = widget.initialUsage;
    if (!identical(incomingUsage, oldWidget.initialUsage) &&
        incomingUsage?.hasData == true) {
      setState(() => _accountUsage = incomingUsage);
    }
    final incomingProvider = widget.customProvider;
    final providerChanged = incomingProvider == null
        ? _customProvider != null
        : _customProvider == null ||
              !incomingProvider.hasSameConfigurationAs(_customProvider!);
    if (providerChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setCustomProvider(incomingProvider);
      });
    }
  }

  String _newLocalSessionId() =>
      'local-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  String _workspaceIdentity(WorkspaceRef workspace) =>
      '${workspace.backendId}|${workspace.hostPath}';

  void _syncInteractionIdentity() {
    _interaction = _interaction.withIdentity(
      workspaceId: _workspaceIdentity(_activeWorkspace),
      sessionId: _sessionId,
      threadId: _client?.threadId ?? _lastThreadId,
    );
  }

  void _transitionInteraction(
    SessionLifecycleEvent event, {
    String? threadId,
    String? error,
    bool clearThread = false,
  }) {
    _interaction = _interaction.transition(
      event,
      threadId: threadId,
      error: error,
      clearThread: clearThread,
    );
  }

  void _publishSnapshot() {
    _sessionLastActivityAtEpochMs = DateTime.now().millisecondsSinceEpoch;
    // The home adapter expects a display-ready summary. New transcript rows
    // are stored as codex.transcript.v1 JSON, so forwarding the raw row here
    // leaks implementation data into CC Pocket's running-session card.
    final lastMessage = _lastVisibleTranscriptMessage();
    widget.onSnapshotChanged?.call(
      LocalSessionSnapshot(
        workspace: _activeWorkspace,
        status: _status,
        active: _interaction.isActive || _commandTranscriptId != null,
        busy: _busy || _sending,
        // /exec is a session-level command, not a provider turn, but it still
        // owns this session's live worker. Surface it as active on Home so a
        // hidden command is not shown as idle and another session cannot look
        // like the only running one.
        turnActive: _interaction.isTurnActive || _commandTranscriptId != null,
        queuedPrompts: List<String>.unmodifiable(_queuedPrompts),
        transcriptCount: _transcript.length,
        sessionId: _sessionId,
        threadId: _client?.threadId ?? _lastThreadId,
        title: _effectiveSessionTitle,
        pinned: _historyPinned,
        phase: _interaction.phase,
        model: _codexModel,
        effort: _codexEffort,
        sandbox: _codexSandbox,
        approvalPolicy: _codexApprovalPolicy,
        planMode: _planMode,
        createdAtEpochMs: _sessionCreatedAtEpochMs,
        lastActivityAtEpochMs: _sessionLastActivityAtEpochMs,
        lastMessage: lastMessage,
      ),
    );
  }

  /// Coalesce high-frequency app-server events into one Flutter frame.
  ///
  /// Streaming assistant/reasoning deltas can arrive much faster than the
  /// display refresh rate. Rebuilding the complete session tree for every
  /// delta causes input latency and scroll jank, while the underlying state
  /// can still be updated immediately.
  void _requestSessionFrameRefresh({bool rebuildSession = true}) {
    if (!mounted || _handlingSessionEvent || _sessionFrameRefreshScheduled) {
      if (mounted && !_handlingSessionEvent) {
        _sessionFrameRefreshNeedsRebuild =
            _sessionFrameRefreshNeedsRebuild || rebuildSession;
      }
      return;
    }
    _sessionFrameRefreshNeedsRebuild = rebuildSession;
    _sessionFrameRefreshScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _sessionFrameRefreshScheduled = false;
      if (!mounted) return;
      final rebuildSession = _sessionFrameRefreshNeedsRebuild;
      _sessionFrameRefreshNeedsRebuild = false;
      if (_streamingSnapshotDirty) {
        // Delta events can arrive much faster than frames. Accumulate them
        // amortized in StringBuffers and materialize the visible snapshot
        // once per frame. The notifier is scoped to the message list, so a
        // live token stream does not rebuild the session chrome or siblings.
        _streamingSnapshot.value = CcpocketNativeStreamingSnapshot(
          assistant: _streamingAssistantBuffer.toString(),
          thinking: _streamingThinkingBuffer.toString(),
        );
        _streamingSnapshotDirty = false;
      }
      if (rebuildSession) setState(() {});
    });
  }

  /// Home only needs the newest live snapshot once per rendered frame.
  void _scheduleSnapshotPublish({bool immediate = false}) {
    if (immediate) {
      _snapshotPublishScheduled = false;
      if (mounted) _publishSnapshot();
      return;
    }
    if (!mounted || _snapshotPublishScheduled) return;
    _snapshotPublishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapshotPublishScheduled = false;
      if (mounted) _publishSnapshot();
    });
  }

  /// Persist live transcript state after a quiet period, but flush terminal
  /// state immediately so completed turns remain durable before navigation.
  void _scheduleHistoryPersist({bool immediate = false}) {
    _historyPersistenceTimer?.cancel();
    _historyPersistenceTimer = null;
    if (immediate) {
      if (mounted) unawaited(_persistHistory());
      return;
    }
    _historyPersistenceTimer = Timer(const Duration(milliseconds: 350), () {
      _historyPersistenceTimer = null;
      if (mounted) unawaited(_persistHistory());
    });
  }

  String? get _effectiveSessionTitle {
    final currentTitle = _sessionTitle?.trim();
    if (_sessionTitleManuallySet &&
        currentTitle != null &&
        currentTitle.isNotEmpty) {
      return currentTitle;
    }
    final codexTitle = _threadName?.trim();
    if (codexTitle != null && codexTitle.isNotEmpty) return codexTitle;
    if (currentTitle != null && currentTitle.isNotEmpty) return currentTitle;
    return null;
  }

  String _lastVisibleTranscriptMessage() {
    if (_lastVisibleTranscriptCacheValid && _transcript.isNotEmpty) {
      final lastRaw = _transcript.last;
      if (lastRaw == _lastVisibleTranscriptSourceRaw) {
        return _lastVisibleTranscriptMessageCache;
      }
    }
    for (final raw in _transcript.reversed) {
      final entry = CodexTranscriptEntry.fromStored(raw);
      if (_isBenignArg0CleanupWarning(entry.displayLine) ||
          _isTransientLifecycleEntry(entry.displayLine)) {
        continue;
      }
      final text = entry.text.trim();
      if (text.isNotEmpty) {
        _lastVisibleTranscriptCacheValid = true;
        _lastVisibleTranscriptSourceRaw = raw;
        _lastVisibleTranscriptMessageCache = text;
        return text;
      }
    }
    _lastVisibleTranscriptCacheValid = true;
    _lastVisibleTranscriptSourceRaw = null;
    _lastVisibleTranscriptMessageCache = '';
    return '';
  }

  Future<void> stopFromHome() => _stopClient();

  ValueListenable<int> get authRevision => _authRevision;
  String get codexModel => _codexModel;
  String get codexEffort => _codexEffort;
  String get codexApprovalPolicy => _codexApprovalPolicy;
  String get codexSandbox => _codexSandbox;
  ExecutionIdentity get executionIdentity => _identity;

  String _permissionProfileForCurrentPolicy() {
    if (_codexSandbox == 'read-only') return ':read-only';
    if (_identity == ExecutionIdentity.root ||
        _codexSandbox == 'danger-full-access') {
      return ':danger-full-access';
    }
    return ':workspace';
  }

  Future<CodexSessionClient> _ensureClientForSettings() async {
    final existing = _client;
    if (existing is CodexSessionClient) return existing;
    final pending = _settingsClientLoad;
    if (pending != null) return pending;
    final operation = _startClientForSettings();
    _settingsClientLoad = operation;
    try {
      return await operation;
    } finally {
      if (identical(_settingsClientLoad, operation)) {
        _settingsClientLoad = null;
      }
    }
  }

  Future<CodexSessionClient> _startClientForSettings() async {
    if (_legacyChatOnlyHistory) {
      throw CodexSessionException(_legacyChatOnlyHistoryMessage);
    }
    await _start();
    final client = _client;
    if (client is CodexSessionClient) return client;
    throw CodexSessionException(
      _error ?? 'The local Codex app-server is not running for this session.',
    );
  }

  Future<List<CodexMcpServerSummary>> readMcpServersForSettings() async {
    final client = await _ensureClientForSettings();
    return client.readMcpServers();
  }

  Future<List<CodexMcpServerStatusSummary>>
  readMcpServerStatusesForSettings() async {
    final client = await _ensureClientForSettings();
    return client.readMcpServerStatuses();
  }

  Future<void> addMcpServerForSettings(CodexMcpAddRequest request) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot add MCP configuration.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('add MCP server "${request.name}"')) {
      throw const CodexSessionException('MCP server addition was cancelled.');
    }
    final client = await _ensureClientForSettings();
    await client.addMcpServer(request);
  }

  Future<void> removeMcpServerForSettings(String name) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot remove MCP configuration.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('remove MCP server "$name"')) {
      throw const CodexSessionException('MCP server removal was cancelled.');
    }
    final client = await _ensureClientForSettings();
    await client.removeMcpServer(name);
  }

  Future<void> loginMcpServerForSettings(String name) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot write MCP login credentials.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('authenticate with MCP server "$name"')) {
      throw const CodexSessionException('MCP login was cancelled.');
    }
    final client = await _ensureClientForSettings();
    final url = await client.beginMcpOAuthLogin(name);
    final opened = await _openAuthUrlValue(url.toString(), showFailure: false);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: url.toString()));
    throw const CodexSessionException(
      'The browser could not be opened; the authorization link was copied to the clipboard.',
    );
  }

  Future<List<CodexPluginSummary>> readPluginsForSettings({
    bool forceRefetch = false,
  }) async {
    final client = await _ensureClientForSettings();
    return client.readPlugins(forceRefetch: forceRefetch);
  }

  Future<List<CodexPluginMarketplaceSummary>>
  readPluginMarketplacesForSettings({bool forceRefetch = false}) async {
    final client = await _ensureClientForSettings();
    return client.readPluginMarketplaces(forceRefetch: forceRefetch);
  }

  Future<void> installPluginForSettings(
    String pluginName,
    String marketplaceName,
  ) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot install plugins.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'install plugin "$pluginName@$marketplaceName"',
        )) {
      throw const CodexSessionException('Plugin installation was cancelled.');
    }
    final client = await _ensureClientForSettings();
    await client.installPlugin(
      CodexPluginInstallRequest(
        pluginName: pluginName,
        marketplaceName: marketplaceName,
        jsonOutput: false,
      ),
    );
  }

  Future<void> removePluginForSettings(String pluginId) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot uninstall plugins.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('uninstall plugin "$pluginId"')) {
      throw const CodexSessionException('Plugin removal was cancelled.');
    }
    final client = await _ensureClientForSettings();
    await client.uninstallPlugin(pluginId);
  }

  Future<void> setPluginEnabledForSettings(
    String pluginId,
    bool enabled,
  ) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot change plugin enablement.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          '${enabled ? 'enable' : 'disable'} plugin "$pluginId"',
        )) {
      throw const CodexSessionException('Plugin enablement was cancelled.');
    }
    final client = await _ensureClientForSettings();
    final response = await client.setPluginEnabled(pluginId, enabled);
    final status = response['status']?.toString().toLowerCase();
    if (status != null && status != 'ok') {
      throw CodexSessionException(
        'Codex did not apply the plugin enablement change (status: $status).',
      );
    }
  }

  Future<void> addPluginMarketplaceForSettings(
    CodexPluginMarketplaceAddRequest request,
  ) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot add plugin marketplaces.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'add plugin marketplace "${request.source}"',
        )) {
      throw const CodexSessionException(
        'Plugin marketplace addition was cancelled.',
      );
    }
    final client = await _ensureClientForSettings();
    await client.addPluginMarketplace(request);
  }

  Future<void> removePluginMarketplaceForSettings(
    String marketplaceName,
  ) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot remove plugin marketplaces.',
      );
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'remove plugin marketplace "$marketplaceName"',
        )) {
      throw const CodexSessionException(
        'Plugin marketplace removal was cancelled.',
      );
    }
    final client = await _ensureClientForSettings();
    await client.removePluginMarketplace(marketplaceName);
  }

  Future<void> upgradePluginMarketplaceForSettings(
    String? marketplaceName,
  ) async {
    if (_codexSandbox == 'read-only') {
      throw const CodexSessionException(
        'A read-only session cannot upgrade plugin marketplaces.',
      );
    }
    final target = marketplaceName?.trim();
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          target == null || target.isEmpty
              ? 'upgrade all plugin marketplaces'
              : 'upgrade plugin marketplace "$target"',
        )) {
      throw const CodexSessionException(
        'Plugin marketplace upgrade was cancelled.',
      );
    }
    final client = await _ensureClientForSettings();
    await client.upgradePluginMarketplace(
      target == null || target.isEmpty ? null : target,
    );
  }

  /// Changes the Android process identity for the next start.
  ///
  /// An existing app-server is never silently replaced while the user is in
  /// a turn. Root sessions retain the user's selected permission and approval
  /// policy; ordinary operations stay direct while high-risk targets surface
  /// the soft-routing guidance instead of being permanently blocked.
  bool updateExecutionIdentity(ExecutionIdentity identity) {
    if (_busy || _client != null) {
      final message = _uiText(
        '请先停止当前 session，再切换执行身份。',
        'Stop the current session before switching execution identity.',
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
    setState(() {
      _identity = identity;
    });
    unawaited(_persistHistory());
    return true;
  }

  Future<CodexModelCatalog> get modelCatalog {
    final provider = _customProvider;
    if (provider != null) {
      return Future<CodexModelCatalog>.value(
        _modelCatalogForProvider(provider),
      );
    }
    return _modelCatalogFuture ??= _loadCachedModelCatalog();
  }

  /// Reads only the persisted catalog for Settings. It never starts Codex;
  /// the Settings model tile can therefore render a warm cache immediately
  /// and invoke [refreshModelCatalog] explicitly when no cache is available.
  Future<CodexModelCatalog>? get cachedModelCatalog {
    final provider = _customProvider;
    if (provider != null) {
      return Future<CodexModelCatalog>.value(
        _modelCatalogForProvider(provider),
      );
    }
    return _modelCatalogFuture ??= _loadPersistedModelCatalog();
  }

  Future<CodexModelCatalog> _loadPersistedModelCatalog() async {
    final cached = await _modelCatalogCache.load(
      cliVersion: widget.modelCatalogCliVersion,
      authGeneration: AuthBindingStore.currentGeneration.value,
    );
    if (cached == null) {
      throw const BackendException('No cached CLI model catalog.');
    }
    return _modelSelectionExplicit
        ? cached.withCurrentModel(_codexModel)
        : cached;
  }

  CodexModelCatalog _modelCatalogForProvider(CustomProviderConfig provider) {
    final model = provider.model.trim();
    return CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: model,
          displayName: model,
          reasoningEfforts: provider.reasoningEfforts,
        ),
      ],
    );
  }

  Future<CodexModelCatalog> refreshModelCatalog() {
    final provider = _customProvider;
    if (provider != null) {
      final future = Future<CodexModelCatalog>.value(
        _modelCatalogForProvider(provider),
      );
      _modelCatalogFuture = future;
      return future;
    }
    final authGeneration = AuthBindingStore.currentGeneration.value;
    final future = _loadAndCacheModelCatalog(
      cliVersion: widget.modelCatalogCliVersion,
      authGeneration: authGeneration,
    );
    _modelCatalogFuture = future;
    return future;
  }

  Future<CodexModelCatalog> _loadCachedModelCatalog() async {
    final cliVersion = widget.modelCatalogCliVersion;
    final authGeneration = AuthBindingStore.currentGeneration.value;
    final cached = await _modelCatalogCache.load(
      cliVersion: cliVersion,
      authGeneration: authGeneration,
    );
    if (cliVersion != widget.modelCatalogCliVersion ||
        authGeneration != AuthBindingStore.currentGeneration.value) {
      return _loadCachedModelCatalog();
    }
    if (cached != null) {
      return _modelSelectionExplicit
          ? cached.withCurrentModel(_codexModel)
          : cached;
    }
    return _loadAndCacheModelCatalog(
      cliVersion: cliVersion,
      authGeneration: authGeneration,
    );
  }

  Future<CodexModelCatalog> _loadAndCacheModelCatalog({
    required String? cliVersion,
    required int authGeneration,
  }) async {
    final requestedVersion = cliVersion;
    final catalog = await _loadModelCatalog();
    final currentAuthGeneration = AuthBindingStore.currentGeneration.value;
    if (authGeneration != currentAuthGeneration) {
      return _loadAndCacheModelCatalog(
        cliVersion: widget.modelCatalogCliVersion,
        authGeneration: currentAuthGeneration,
      );
    }
    if (_customProvider == null &&
        requestedVersion == widget.modelCatalogCliVersion) {
      await _modelCatalogCache.save(
        cliVersion: requestedVersion,
        authGeneration: authGeneration,
        catalog: catalog,
      );
    }
    return catalog;
  }

  Future<CodexUsageSnapshot> loadUsage() async {
    try {
      final invocation =
          await _resolveCodexInvocation(
            runtimeScope: _newRuntimeOperationScope('usage'),
          ).timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw const BackendException(
              'Local Codex runtime invocation resolution timed out.',
            ),
          );
      if (invocation == null) {
        return const CodexUsageSnapshot.error(
          'Codex runtime is not ready for usage data.',
        );
      }
      // Usage is an account-level read from the selected local app-server.
      // Root sessions select their preferred runtime before this probe; a
      // quota failure itself must not switch runtimes or restart a session.
      return await CodexUsageClient.load(
        backend: _activeBackend,
        workspace: _activeWorkspace,
        command: invocation.command,
        identity: _identity,
        environment: invocation.environment,
      ).timeout(
        const Duration(seconds: 22),
        onTimeout: () => const CodexUsageSnapshot.error(
          'Direct local Codex app-server usage request timed out.',
        ),
      );
    } catch (error) {
      return CodexUsageSnapshot.error(
        _identity == ExecutionIdentity.root && _isRootProfileRejection(error)
            ? _rootProfileUnavailableMessage
            : '$error',
      );
    }
  }

  Future<void> _refreshConversationAccountUsage({bool force = false}) async {
    if (_customProvider != null) return;
    if (_accountUsageLoad != null) return;
    if (_accountUsageAttempted && !force) return;
    _accountUsageAttempted = true;
    final operation = () async {
      CodexUsageSnapshot? snapshot;
      final client = _client;
      if (client is CodexSessionClient) {
        try {
          snapshot = CodexUsageSnapshot.fromRpcResponse(
            await client.readAccountRateLimits(),
          );
        } catch (_) {
          // A stopped/restarting thread can reject this auxiliary read. The
          // standalone local client remains the direct Android fallback.
        }
      }
      snapshot ??= await loadUsage();
      if (!mounted || !snapshot!.hasData) return;
      setState(() => _accountUsage = snapshot);
    }();
    _accountUsageLoad = operation;
    try {
      await operation;
    } finally {
      if (identical(_accountUsageLoad, operation)) _accountUsageLoad = null;
    }
  }

  Widget? _conversationAccountUsageSummary() {
    if (_customProvider != null) return null;
    final usage = _accountUsage;
    return SizedBox(
      key: const ValueKey('codex_account_usage_slot'),
      height: 24,
      child: usage == null || !usage.hasData
          ? null
          : CcpocketCodexUsageSummary(
              usage: usage,
              zh: Localizations.localeOf(context).languageCode == 'zh',
              onTap: () =>
                  unawaited(_refreshConversationAccountUsage(force: true)),
            ),
    );
  }

  Future<CodexModelCatalog> _loadModelCatalog({
    bool allowFallback = true,
  }) async {
    try {
      final activeClient = _client;
      if (activeClient is CodexSessionClient &&
          activeClient.threadId?.trim().isNotEmpty == true) {
        try {
          final catalog = await activeClient.readModelCatalog();
          _applyRecommendedModel(catalog);
          return _modelSelectionExplicit
              ? catalog.withCurrentModel(_codexModel)
              : catalog;
        } on Object {
          // An older app-server may not implement model/list. The one-shot
          // runtime catalog below remains the compatibility fallback.
        }
      }
      final invocation = await _resolveCodexInvocation(
        runtimeScope: _newRuntimeOperationScope('models'),
      );
      if (invocation == null) {
        throw const BackendException(
          'Codex runtime is not ready for model list.',
        );
      }
      final catalog = await CodexModelCatalogClient.load(
        backend: _activeBackend,
        workspace: _activeWorkspace,
        command: invocation.command,
        identity: _identity,
        environment: invocation.environment,
        preferCliCatalog:
            !(activeClient is CodexSessionClient &&
                activeClient.threadId?.trim().isNotEmpty == true),
      );
      _applyRecommendedModel(catalog);
      return _modelSelectionExplicit
          ? catalog.withCurrentModel(_codexModel)
          : catalog;
    } on BackendException catch (error) {
      if (_identity == ExecutionIdentity.root &&
          _isRootProfileRejection(error)) {
        _showError(_rootProfileUnavailableMessage);
        rethrow;
      }
      // A local one-shot query may expose a concrete process or network
      // capability failure before the first conversation turn. Retry once in
      // the verified Linux/PRoot runtime; provider HTTP errors stay terminal.
      if (allowFallback && !_usingFallback && !_isCompatibility) {
        final switched = await _activateCompatibilityFallback(
          reason: 'CLI model catalog failed: ${error.message}',
        );
        if (switched) return _loadModelCatalog(allowFallback: false);
      }
      rethrow;
    }
  }

  void _applyRecommendedModel(CodexModelCatalog catalog) {
    if (_modelSelectionExplicit || _customProvider != null || _client != null) {
      return;
    }
    final recommended = catalog.recommendedDefaultModel;
    if (recommended == null) return;
    final efforts = recommended.reasoningEfforts;
    final effort = efforts.contains(_codexEffort)
        ? _codexEffort
        : efforts.contains('low')
        ? 'low'
        : efforts.isEmpty
        ? 'low'
        : efforts.first;
    if (_codexModel == recommended.id && _codexEffort == effort) return;
    if (!mounted) return;
    setState(() {
      _codexModel = recommended.id;
      _codexEffort = effort;
    });
    unawaited(_persistHistory());
  }

  Widget buildAuthControls() => _buildCodexControls(showAuthChallenge: true);

  Future<void> refreshAuthStatus() => _checkAuthStatus();

  void updateCodexSettings({
    String? model,
    String? effort,
    String? approvalPolicy,
    String? sandbox,
    String? permissions,
  }) {
    if (!mounted) return;
    setState(() {
      if (model != null) {
        _codexModel = model;
        _modelSelectionExplicit = true;
      }
      if (effort != null) _codexEffort = effort;
      if (approvalPolicy != null) _codexApprovalPolicy = approvalPolicy;
      if (sandbox != null) {
        _codexSandbox = sandbox;
        if (permissions == null) {
          _codexPermissions = _permissionProfileForCurrentPolicy();
        }
      }
      if (permissions != null) _codexPermissions = permissions;
    });
    final client = _client;
    if (client is CodexSessionClient) {
      client.updateSettings(
        CodexTurnSettings(
          model: _codexModel,
          reasoningEffort: _codexEffort,
          approvalPolicy: _codexApprovalPolicy,
          sandbox: _codexSandbox,
          permissions: _codexPermissions,
          collaborationMode: _planMode ? 'plan' : 'default',
        ),
      );
    }
    unawaited(_persistHistory());
  }

  void _togglePlanMode() {
    if (!mounted) return;
    setState(() => _planMode = !_planMode);
    final client = _client;
    if (client is CodexSessionClient) {
      client.updateSettings(
        CodexTurnSettings(
          model: _codexModel,
          reasoningEffort: _codexEffort,
          approvalPolicy: _codexApprovalPolicy,
          sandbox: _codexSandbox,
          permissions: _codexPermissions,
          collaborationMode: _planMode ? 'plan' : 'default',
        ),
      );
    }
    unawaited(_persistHistory());
  }

  Future<void> togglePinnedFromHome() async {
    if (!mounted) return;
    setState(() => _historyPinned = !_historyPinned);
    _publishSnapshot();
    await _persistHistory();
  }

  WorkspaceRef _workspaceForBackend(Backend backend) {
    if (backend.descriptor.id == widget.workspace.backendId) {
      return widget.workspace;
    }
    return WorkspaceRef(
      backendId: backend.descriptor.id,
      filesystemOwnerId: widget.workspace.filesystemOwnerId,
      displayPath: widget.workspace.displayPath,
      hostPath: widget.workspace.hostPath,
      backendLocator: widget.workspace.backendLocator,
    );
  }

  Future<bool> _activateCompatibilityFallback({String? reason}) async {
    final fallback = widget.fallbackBackend;
    if (fallback == null ||
        fallback.descriptor.kind != BackendKind.linuxCompatibility) {
      return false;
    }
    if (!fallback.descriptor.capabilities.usable) {
      try {
        if (fallback is LinuxCompatibilityBackend) await fallback.refresh();
      } catch (_) {
        return false;
      }
    }
    if (!fallback.descriptor.capabilities.usable) return false;
    final fallbackWorkspace = _workspaceForBackend(fallback);
    // Linux Compatibility owns only direct Host workspaces. A SAF tree can
    // still be used for local file operations, but it must never be silently
    // handed to the guest process as if it were a mapped /workspace.
    if (!fallbackWorkspace.hostPath.startsWith(
      '/storage/emulated/0/Codex/Workspaces/',
    )) {
      return false;
    }
    // A backend switch can happen after the composer has already queued the
    // first prompt (host-workspace start -> Linux/PRoot runtime). Do not
    // replace that in-flight session with the workspace's latest unrelated
    // history row, and keep the transient composer state across the switch.
    final transientDraft = _promptController.text;
    final transientQueuedPrompts = List<String>.from(_queuedPrompts);
    final transientPromptHistory = List<String>.from(_promptHistory);
    final transientLastThreadId = _lastThreadId;
    final transientLastThreadPath = _lastThreadPath;
    SessionHistoryRecord? fallbackHistory;
    try {
      await _historyLoaded;
      // Preserve the exact row the user opened. Falling back to the old
      // workspace-only lookup here could silently replace a multi-session
      // record with another session from the same workspace.
      fallbackHistory = _restoredHistory ?? widget.initialHistory;
    } catch (_) {
      // A fallback history cache is optional. The new backend can still start
      // a clean local session when the native store is unavailable.
    }
    _activeBackend = fallback;
    _activeWorkspace = fallbackWorkspace;
    _usingFallback = true;
    if (mounted) {
      setState(() {
        if (fallbackHistory != null) _transcript.clear();
        if (fallbackHistory != null) {
          _applyHistoryRecord(fallbackHistory);
        } else {
          _restoredHistory = null;
        }
        if (transientLastThreadId != null) {
          _lastThreadId = transientLastThreadId;
          _lastThreadPath = transientLastThreadPath;
        } else if (fallbackHistory == null) {
          _lastThreadId = null;
          _lastThreadPath = null;
        }
        _promptController.text = transientDraft;
        _queuedPrompts
          ..clear()
          ..addAll(transientQueuedPrompts);
        _promptHistory
          ..clear()
          ..addAll(transientPromptHistory);
        _syncInteractionIdentity();
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        final normalizedReason = reason?.trim();
        if (normalizedReason != null && normalizedReason.isNotEmpty) {
          _transcript.add(
            zh
                ? '系统：切换到 Linux/PRoot 运行环境：${_localizedRuntimeFailure(normalizedReason)}'
                : 'System: switched to Linux/PRoot after runtime issue: $normalizedReason',
          );
        }
        _error = null;
      });
      _publishSnapshot();
    }
    return true;
  }

  String get _compatibilityUnavailableReason {
    final reason = widget.fallbackBackend?.descriptor.capabilities.reason;
    if (_identity == ExecutionIdentity.root &&
        reason != null &&
        _isRootProfileRejection(reason)) {
      return reason;
    }
    return 'Linux compatibility runtime is not verified.';
  }

  @override
  void dispose() {
    // The runtime handle is the authoritative ownership boundary. The close
    // callback is only a navigation affordance and can be absent during a
    // rebuild/reattach; using it as the lifetime test lets a route teardown
    // accidentally dispose the app-server that the home shell still owns.
    final parentOwnsSession =
        widget.sessionRuntime != null || widget.onClose != null;
    WidgetsBinding.instance.removeObserver(this);
    if (widget.initialAuthGeneration != null && !widget.settingsOnly) {
      AuthBindingStore.currentGeneration.removeListener(
        _handleAuthGenerationChanged,
      );
    }
    _draftPersistenceTimer?.cancel();
    _automaticReconnectTimer?.cancel();
    _promptController.removeListener(_handlePromptChanged);
    unawaited(_persistHistory());
    // A parent-owned session is kept in the home-level runtime handle. Its
    // widget may be detached while the user switches sessions, but that is
    // not an instruction to stop the native app-server.
    _subscription?.cancel();
    _subscription = null;
    _authSubscription?.cancel();
    _historyPersistenceTimer?.cancel();
    _historyPersistenceTimer = null;
    if (!parentOwnsSession) {
      unawaited(_sessionRuntime.disposeClient());
      unawaited(_authClient?.dispose());
    }
    _authRevision.dispose();
    _streamingSnapshot.dispose();
    final sessionForegroundOwned = _sessionForegroundOwned;
    final authForegroundOwned = _authForegroundOwned;
    if (!parentOwnsSession) {
      _sessionForegroundOwned = false;
      _authForegroundOwned = false;
      if (sessionForegroundOwned) unawaited(SessionLifecycle.stop());
      if (authForegroundOwned) unawaited(SessionLifecycle.stop());
    }
    _commandController.dispose();
    _argumentsController.dispose();
    _promptController.dispose();
    _apiKeyController.dispose();
    _disposeUserInputControllers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _runtime = CodexRuntimeProbe().run();
      });
      unawaited(_reconcilePendingBrowserLogin());
    }
  }

  Future<void> _reconcilePendingBrowserLogin() async {
    if (_authMode != CodexAuthMode.browser) return;
    final client = _authClient;
    if (client == null || !client.isLoginPending) return;

    try {
      final account = await client.readAccount().timeout(
        const Duration(seconds: 3),
      );
      if (!mounted || !identical(_authClient, client)) return;
      if (account != CodexAuthMode.browser) return;
      _handleAuthEvent(
        const CodexAuthEvent(
          type: CodexAuthEventType.exit,
          exitCode: 0,
          message: 'Browser authorization completed.',
        ),
      );
    } catch (_) {
      // The callback may still be settling. The normal app-server event path
      // remains authoritative and will complete the flow when available.
    }
  }

  Future<void> _loadHistory() async {
    if (!widget.restoreHistory && widget.initialHistory == null) return;
    try {
      final history =
          widget.initialHistory ??
          await _historyStore.loadLatest(_activeWorkspace);
      if (!mounted || history == null) return;
      // A session page can be created as an IndexedStack child while the home
      // page is still building. Defer the first state/snapshot mutation so
      // the parent never receives an update from inside its build phase.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      setState(() {
        _applyHistoryRecord(history);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishSnapshot();
      });
    } catch (error) {
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      setState(() {
        final message = 'Could not restore local session history: $error';
        _error = message;
        _appendTranscriptError(message);
      });
    }
  }

  SessionHistoryRecord? _restoredHistory;

  void _applyHistoryRecord(SessionHistoryRecord history) {
    if (history.sessionId != null && history.sessionId!.isNotEmpty) {
      _sessionId = history.sessionId!;
      _historyKeySessionId = history.sessionId;
      _historyUsesLegacyKey = false;
    } else {
      _historyKeySessionId = null;
      _historyUsesLegacyKey = true;
    }
    _identity = history.executionIdentity;
    _sessionRuntime.rootApprovalGrantedForSession = history.rootApprovalGranted
        ? _sessionId
        : null;
    // Do not rehydrate the known non-fatal Android arg0 janitor diagnostic
    // into the live transcript. Older records may contain it, and keeping it
    // would make Home's last-message snapshot and the first restored bubble
    // point at an implementation warning instead of the session history.
    var previousRestoredEntry = '';
    var restoredOptionalMcpWarning = false;
    for (final entry in history.entries) {
      if (_isBenignArg0CleanupWarning(entry) ||
          _isTransientLifecycleEntry(entry)) {
        continue;
      }
      // Keep the durable row in its original language/format. Localization is
      // a presentation concern handled by CcpocketNativeMessageList; storing
      // the localized projection here would make a later history save replace
      // the source text and prevent locale changes from re-projecting it.
      final normalized = entry.trim();
      if (_isRepeatedErrorEntry(previousRestoredEntry, normalized)) continue;
      if (_isOptionalMcpWarningTranscriptEntry(entry)) {
        if (restoredOptionalMcpWarning) continue;
        restoredOptionalMcpWarning = true;
        _mcpWarningShown = true;
      }
      _transcript.add(entry);
      previousRestoredEntry = normalized;
    }
    _restoredHistory = history;
    _sessionAuthGeneration = history.authGeneration;
    if (widget.initialAuthGeneration != null &&
        !widget.settingsOnly &&
        _usesOpenAiAuthBinding) {
      _accountBindingStale =
          history.authGeneration != AuthBindingStore.currentGeneration.value;
    }
    _threadNeedsProviderReset =
        widget.providerModeExplicit &&
        history.customProviderId != widget.customProvider?.id;
    _lastThreadId = history.threadId;
    _lastThreadPath = history.threadPath;
    _promptController.text = history.draft;
    _queuedPrompts
      ..clear()
      ..addAll(history.queuedPrompts);
    _promptHistory
      ..clear()
      ..addAll(history.promptHistory);
    _modelSelectionExplicit = true;
    if (_customProvider != null) {
      _codexModel = _customProvider!.model;
      _codexEffort =
          _customProvider!.reasoningEfforts.contains(history.codexEffort)
          ? history.codexEffort
          : _customProvider!.reasoningEfforts.contains('low')
          ? 'low'
          : _customProvider!.reasoningEfforts.isNotEmpty
          ? _customProvider!.reasoningEfforts.first
          : widget.initialEffort;
    } else if (widget.providerModeExplicit) {
      _codexModel = widget.initialModel;
      _codexEffort = widget.initialEffort;
    } else {
      _codexModel = history.codexModel;
      _codexEffort = history.codexEffort;
    }
    _codexSandbox = history.codexSandbox;
    _codexApprovalPolicy = history.codexApprovalPolicy;
    _codexPermissions =
        history.codexPermissions ?? _permissionProfileForCurrentPolicy();
    _planMode = history.codexPlanMode;
    _historyPinned = history.pinned;
    _sessionTitle =
        history.title ??
        (history.firstUserPrompt.isNotEmpty ? history.generatedTitle : null);
    _threadName = history.threadName;
    _sessionTitleManuallySet = history.titleIsManual;
    _firstPromptForAutomaticTitle = history.firstUserPrompt;
    _automaticTitleAttempted =
        history.titleIsManual || history.threadName?.trim().isNotEmpty == true;
    if (history.updatedAtEpochMs > 0) {
      _sessionCreatedAtEpochMs = history.updatedAtEpochMs;
      _sessionLastActivityAtEpochMs = history.updatedAtEpochMs;
    }
    _syncInteractionIdentity();
  }

  Future<void> _persistHistory() {
    final entries = List<String>.unmodifiable(_transcript);
    final status = _status;
    final threadId = _client?.threadId ?? _lastThreadId;
    final threadPath = _client is CodexSessionClient
        ? (_client as CodexSessionClient).threadPath ?? _lastThreadPath
        : _lastThreadPath;
    final workspace = _activeWorkspace;
    final sessionId = _historyUsesLegacyKey
        ? null
        : (_historyKeySessionId ?? _sessionId);
    final draft = _promptController.text;
    final queuedPrompts = List<String>.unmodifiable(_queuedPrompts);
    return _historyWrites.enqueue(() async {
      try {
        await _historyLoaded;
        await _historyStore.save(
          workspace: workspace,
          sessionId: sessionId,
          entries: entries,
          status: status,
          threadId: threadId,
          threadPath: threadPath,
          authGeneration: _sessionAuthGeneration,
          draft: draft,
          queuedPrompts: queuedPrompts,
          codexModel: _codexModel,
          customProviderId: _customProvider?.id,
          codexEffort: _codexEffort,
          executionIdentity: _identity,
          rootApprovalGranted:
              _sessionRuntime.rootApprovalGrantedForSession == _sessionId,
          codexSandbox: _codexSandbox,
          codexPermissions: _codexPermissions,
          codexApprovalPolicy: _codexApprovalPolicy,
          codexPlanMode: _planMode,
          promptHistory: List<String>.unmodifiable(_promptHistory),
          pinned: _historyPinned,
          title: _sessionTitle,
          threadName: _threadName,
          titleIsManual: _sessionTitleManuallySet,
        );
      } catch (_) {
        // History is a convenience cache; it must not break the active session.
      }
    });
  }

  void _handlePromptChanged() {
    _draftPersistenceTimer?.cancel();
    _draftPersistenceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_persistHistory());
    });
  }

  void _indentPrompt() {
    _editPromptLines(indent: true);
  }

  void _dedentPrompt() {
    _editPromptLines(indent: false);
  }

  void _editPromptLines({required bool indent}) {
    final value = _promptController.value;
    final text = value.text;
    final start = value.selection.start < 0
        ? text.length
        : value.selection.start;
    final end = value.selection.end < 0 ? start : value.selection.end;
    final rangeStart = text.lastIndexOf('\n', start - 1) + 1;
    final rangeEnd = text.indexOf('\n', end);
    final lineEnd = rangeEnd < 0 ? text.length : rangeEnd;
    final selected = text.substring(rangeStart, lineEnd);
    final lines = selected.split('\n');
    final changed = lines
        .map(
          (line) => indent
              ? '    ' + line
              : (line.startsWith('    ')
                    ? line.substring(4)
                    : line.startsWith('  ')
                    ? line.substring(2)
                    : line.startsWith(' ')
                    ? line.substring(1)
                    : line),
        )
        .join('\n');
    final nextText =
        text.substring(0, rangeStart) + changed + text.substring(lineEnd);
    final delta = changed.length - selected.length;
    _promptController.value = value.copyWith(
      text: nextText,
      selection: TextSelection(
        baseOffset: (start + (indent ? 4 : delta)).clamp(0, nextText.length),
        extentOffset: (end + delta).clamp(0, nextText.length),
      ),
      composing: TextRange.empty,
    );
  }

  Future<_CodexInvocation?> _resolveCodexInvocation({
    String? runtimeScope,
  }) async {
    if (_shouldPreferCompatibilityRuntime) {
      if (await _activateCompatibilityFallback()) {
        return _resolveCodexInvocation(runtimeScope: runtimeScope);
      }
      _showError(_compatibilityUnavailableReason);
      return null;
    }
    if (_isCompatibility) {
      final descriptor = _activeBackend.descriptor;
      if (!descriptor.capabilities.usable) {
        _showError(
          descriptor.capabilities.reason ??
              'Linux compatibility runtime is not verified.',
        );
        return null;
      }
      return _CodexInvocation(
        command: 'codex',
        // The compatibility worker injects its own fixed BROWSER value. It
        // is reserved there, so only forward the per-session state home.
        environment: _compatibilityRuntimeEnvironment(
          runtimeScope: runtimeScope,
        ),
      );
    }

    final runtime = await _runtime;
    if (!runtime.usable || runtime.command == null) {
      final runtimeReason = runtime.reason ?? 'Codex runtime is not verified.';
      if (_identity == ExecutionIdentity.root &&
          _isRootProfileRejection(runtimeReason)) {
        throw BackendException('root_profile_rejected: $runtimeReason');
      }
      if (!_isCompatibility &&
          await _activateCompatibilityFallback(reason: runtimeReason)) {
        return _resolveCodexInvocation(runtimeScope: runtimeScope);
      }
      _showError(runtimeReason);
      return null;
    }
    if (runtime.identity == 'root' && _identity != ExecutionIdentity.root) {
      if (await _activateCompatibilityFallback()) {
        return _resolveCodexInvocation(runtimeScope: runtimeScope);
      }
      _showError(
        'This Codex runtime is verified for Root helper execution. '
        'Select Root helper before using Codex controls.',
      );
      return null;
    }
    return _CodexInvocation(
      command: runtime.command!,
      environment: _runtimeEnvironment(runtime, runtimeScope: runtimeScope),
    );
  }

  Future<_OneShotCommandResult> _runOneShotCommand({
    required _CodexInvocation invocation,
    required List<String> arguments,
    required Duration timeout,
    Backend? backend,
  }) async {
    final targetBackend = backend ?? _activeBackend;
    final targetWorkspace = backend == null
        ? _activeWorkspace
        : _workspaceForBackend(targetBackend);
    final workspace = await targetBackend.openWorkspace(targetWorkspace);
    final execution = targetBackend.startInteractive(
      ExecutionRequest(
        argv: <String>[invocation.command, ...arguments],
        cwd: workspace.ref.hostPath,
        identity: _identity,
        timeout: timeout,
        environment: invocation.environment,
      ),
    );
    final output = StringBuffer();
    int? exitCode;
    final completed = Completer<void>();
    late final StreamSubscription<ExecutionEvent> subscription;
    subscription = execution.events.listen(
      (event) {
        if (event.stdout != null) output.write(event.stdout);
        if (event.stderr != null) output.write(event.stderr);
        if (event.error != null) output.write(event.error);
        if (event.exitCode != null) {
          exitCode = event.exitCode;
          if (!completed.isCompleted) completed.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      },
      onDone: () {
        if (!completed.isCompleted) completed.complete();
      },
    );
    try {
      // `/cli` is deliberately a non-interactive argv boundary.  Closing
      // stdin is required for commands such as `codex debug models`, which
      // otherwise keep waiting for EOF on Android/PRoot even though they do
      // not consume any input.  App-server and auth clients use the same
      // process abstraction directly and keep their stdin open.
      if (execution case final StdinClosableExecution closable) {
        await closable.closeStdin();
      }
      await completed.future.timeout(timeout);
    } on TimeoutException {
      await execution.stop();
      throw BackendException(
        'Codex command timed out after ${timeout.inSeconds} seconds.',
      );
    } finally {
      await subscription.cancel();
    }
    if (exitCode == null) {
      throw const BackendException(
        'Codex command stream ended without an exit status.',
      );
    }
    return _OneShotCommandResult(output: output.toString(), exitCode: exitCode);
  }

  Future<Backend?> _networkProbeBackend() async {
    final activeKind = _activeBackend.descriptor.kind;
    // Fake and compatibility backends already know how to execute guest-side
    // Python. Keeping the fake path intact is also important for deterministic
    // widget tests and development fixtures.
    if (activeKind == BackendKind.fake ||
        activeKind == BackendKind.linuxCompatibility) {
      return _activeBackend;
    }

    // Android host commands do not imply that Python exists in the host app
    // process. Prefer the Linux guest for this auxiliary probe, but do not
    // switch the session's active backend just to run it.
    final fallback = widget.fallbackBackend;
    if (fallback is! LinuxCompatibilityBackend) return null;
    if (!fallback.descriptor.capabilities.usable) {
      try {
        await fallback.refresh();
      } catch (_) {
        return null;
      }
    }
    if (!fallback.descriptor.capabilities.usable) return null;
    final workspace = _workspaceForBackend(fallback);
    if (!workspace.hostPath.startsWith(
      '/storage/emulated/0/Codex/Workspaces/',
    )) {
      return null;
    }
    return fallback;
  }

  Future<void> _start({
    String? resumeThreadId,
    String? resumeThreadPath,
    bool allowFallback = true,
    String? retryTranscriptMarker,
    int? expectedOperationGeneration,
  }) async {
    if (_busy) return;
    if (expectedOperationGeneration != null &&
        expectedOperationGeneration != _sessionOperationGeneration) {
      return;
    }
    final operationGeneration = ++_sessionOperationGeneration;
    bool operationIsCurrent() =>
        operationGeneration == _sessionOperationGeneration;
    await _historyLoaded;
    if (!operationIsCurrent()) return;
    if (_accountBindingStale) {
      _showError(_accountBindingStaleMessage);
      return;
    }
    if (_legacyChatOnlyHistory) {
      _showError(_legacyChatOnlyHistoryMessage);
      return;
    }
    if (_missingCustomProviderId != null) {
      _showError(_missingCustomProviderMessage);
      return;
    }
    final keepConversationOnFailure = resumeThreadId != null || _connectionLost;
    final effectiveResumeThreadPath =
        resumeThreadPath ?? _restoredHistory?.threadPath ?? _lastThreadPath;
    if (_identity == ExecutionIdentity.root) {
      final confirmed = await _confirmRootSession();
      if (!operationIsCurrent() || !confirmed) return;
    }
    if (allowFallback && _shouldPreferCompatibilityRuntime) {
      final activated = await _activateCompatibilityFallback();
      if (!operationIsCurrent()) return;
      if (activated) {
        await _start(
          resumeThreadId: resumeThreadId,
          resumeThreadPath: effectiveResumeThreadPath,
          allowFallback: false,
          retryTranscriptMarker: retryTranscriptMarker,
        );
      } else {
        _showError(_compatibilityUnavailableReason);
      }
      return;
    }
    await _stopClient(
      keepConversation: keepConversationOnFailure,
      invalidatePendingOperations: false,
    );
    if (!operationIsCurrent()) return;
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      _showError('An app-server command is required.');
      return;
    }
    final CodexRuntimeDescriptor? runtime = _isCompatibility
        ? null
        : await _runtime;
    if (!operationIsCurrent()) return;
    var effectiveCommand = command;
    final environment = Map<String, String>.from(
      _isCompatibility
          ? _compatibilityRuntimeEnvironment(runtimeScope: _runtimeSessionKey())
          : _runtimeEnvironment(runtime!, runtimeScope: _runtimeSessionKey()),
    );
    final customProvider = _customProvider;
    if (command == 'codex') {
      if (_isCompatibility) {
        if (!_activeBackend.descriptor.capabilities.usable) {
          _showError(
            _activeBackend.descriptor.capabilities.reason ??
                'Linux compatibility runtime is not verified.',
          );
          return;
        }
      } else {
        if (!runtime!.usable) {
          if (_identity == ExecutionIdentity.root &&
              _isRootProfileRejection(
                runtime.reason ?? runtime.appProbeReason ?? '',
              )) {
            _showError(_rootProfileUnavailableMessage);
            return;
          }
          final activated = allowFallback
              ? await _activateCompatibilityFallback(
                  reason:
                      'runtime=${runtime.label}, identity=${runtime.identity ?? 'unknown'}, '
                      'command=${runtime.command ?? 'none'}, '
                      'reason=${runtime.reason ?? 'none'}',
                )
              : false;
          if (!operationIsCurrent()) return;
          if (activated) {
            await _start(
              resumeThreadId: resumeThreadId,
              resumeThreadPath: effectiveResumeThreadPath,
              allowFallback: false,
            );
            return;
          }
          _showError(
            runtime.reason ??
                'Codex runtime is not verified in an app or root runtime slot.',
          );
          return;
        }
        if (runtime.identity == 'root' && _identity != ExecutionIdentity.root) {
          final activated = allowFallback
              ? await _activateCompatibilityFallback(
                  reason:
                      'runtime identity is root while the session identity is '
                      '${_identity.name}',
                )
              : false;
          if (!operationIsCurrent()) return;
          if (activated) {
            await _start(
              resumeThreadId: resumeThreadId,
              resumeThreadPath: effectiveResumeThreadPath,
              allowFallback: false,
            );
            return;
          }
          _showError(
            'This Codex runtime is verified for Root helper execution. '
            'Select Root helper before starting the session.',
          );
          return;
        }
        effectiveCommand = runtime.command!;
      }
    }
    var argv = <String>[
      effectiveCommand,
      ..._argumentsController.text
          .split('\n')
          .map((argument) => argument.trim())
          .where((argument) => argument.isNotEmpty),
    ];
    // The Android package intentionally does not ship the separate
    // codex-code-mode-host executable. Disable the optional JavaScript Code
    // Mode feature for local app-server sessions so a desktop config cannot
    // turn every Android turn into a missing-host failure.
    final executableName = effectiveCommand
        .split(RegExp(r'[/\\]'))
        .last
        .toLowerCase();
    final isCodexExecutable = executableName == 'codex';
    if (isCodexExecutable && argv.contains('app-server')) {
      // A copied config.toml can contain absolute sqlite_home/log_dir values.
      // Codex gives those config entries precedence over CODEX_SQLITE_HOME and
      // CODEX_HOME, so force both paths at the CLI layer for this session.
      argv = codexArgumentsWithSessionIsolation(argv, environment);
      if (!argv.contains('features.code_mode=false')) {
        final index = argv.indexOf('app-server');
        argv.insertAll(index, <String>['-c', 'features.code_mode=false']);
      }
      if (!argv.contains('features.code_mode_only=false')) {
        final index = argv.indexOf('app-server');
        argv.insertAll(index, <String>['-c', 'features.code_mode_only=false']);
      }
      if (!argv.contains('features.respect_system_proxy=true')) {
        final index = argv.indexOf('app-server');
        argv.insertAll(index, <String>[
          '-c',
          'features.respect_system_proxy=true',
        ]);
      }
      if (!argv.contains('suppress_unstable_features_warning=true')) {
        final index = argv.indexOf('app-server');
        argv.insertAll(index, <String>[
          '-c',
          'suppress_unstable_features_warning=true',
        ]);
      }
      // Keep OpenAI OAuth/API-key sessions on the CLI's standard first-party
      // auth and endpoint routing, but use HTTP/SSE. A WebSocket handshake
      // failure in Android's PRoot network path is not consistently retried
      // over HTTP by upstream Codex. Custom third-party providers below keep
      // their own native provider configuration.
      if (customProvider == null) {
        argv = CodexProviderLaunchConfiguration.forAndroidOpenAiHttp().applyTo(
          argv,
        );
      }
    }
    if (customProvider != null) {
      if (!isCodexExecutable || !argv.contains('app-server')) {
        _showError(
          'A Codex app-server command is required for the selected model provider.',
        );
        return;
      }
      try {
        final baseInstructions =
            await CodexModelCatalogClient.loadBaseInstructions(
              backend: _activeBackend,
              workspace: _activeWorkspace,
              command: effectiveCommand,
              identity: _identity,
              environment: environment,
              preferredModel: _codexModel,
            );
        if (!operationIsCurrent()) return;
        final providerLaunch = CodexProviderLaunchConfiguration.forProvider(
          customProvider,
          codexHome: environment['CODEX_HOME'] ?? '',
          baseInstructions: baseInstructions,
        );
        environment.addAll(providerLaunch.environment);
        argv = providerLaunch.applyTo(argv);
      } on FormatException catch (error) {
        _showError(error.message.toString());
        return;
      } on BackendException catch (error) {
        _showError('Unable to load Codex model instructions: ${error.message}');
        return;
      }
    }
    if (!operationIsCurrent()) return;
    final SessionClient client = CodexSessionClient(
      backend: _activeBackend,
      workspace: _activeWorkspace,
      argv: argv,
      identity: _identity,
      environment: environment,
      resumeThreadId: resumeThreadId,
      resumeThreadPath: effectiveResumeThreadPath,
      automaticTitleModel: customProvider == null
          ? 'gpt-6-luna'
          : customProvider.model,
      automaticTitleEffort: customProvider == null
          ? 'low'
          : customProvider.reasoningEfforts.contains('low')
          ? 'low'
          : customProvider.reasoningEfforts.isEmpty
          ? 'low'
          : customProvider.reasoningEfforts.first,
      settings: CodexTurnSettings(
        model: _codexModel,
        reasoningEffort: _codexEffort,
        approvalPolicy: _codexApprovalPolicy,
        sandbox: _codexSandbox,
        permissions: _codexPermissions,
        collaborationMode: _planMode ? 'plan' : 'default',
      ),
    );
    _client = client;
    setState(() {
      _transitionInteraction(
        SessionLifecycleEvent.startRequested,
        clearThread: resumeThreadId == null,
      );
      _busy = true;
      _error = null;
      _authStatus = null;
      _approval = null;
      _turnActive = false;
      _status = 'starting';
      _connectionLostReason = null;
      _mcpWarningShown = false;
      _providerNetworkWarningShown = false;
      _providerNetworkDiagnostic = null;
      // Session start/reconnect is represented by the CC Pocket status line.
      // It is not conversation content and must not be inserted into the
      // persisted message list, otherwise restoring an old session places a
      // fresh lifecycle bubble above its historical messages.
    });
    _publishSnapshot();
    unawaited(_persistHistory());
    try {
      if (_usesForegroundService) {
        // Claim the owner before the asynchronous Android service transition.
        // If the page is disposed or explicitly stopped while the request is
        // still pending, the matching cleanup must still release this owner.
        _sessionForegroundOwned = true;
        await SessionLifecycle.start();
        if (!operationIsCurrent()) {
          await client.dispose();
          return;
        }
      }
      await client.start();
      if (!operationIsCurrent()) {
        await client.dispose();
        return;
      }
      if (mounted) {
        _lastThreadId = client.threadId ?? _lastThreadId;
        _threadNeedsProviderReset = false;
        if (client is CodexSessionClient) {
          _lastThreadPath = client.threadPath ?? _lastThreadPath;
        }
        setState(() {
          _transitionInteraction(
            SessionLifecycleEvent.ready,
            threadId: client.threadId,
          );
          _automaticReconnectAttempted = false;
          _busy = false;
          _connectionLost = false;
          _connectionLostReason = null;
        });
        _publishSnapshot();
        // Fetch account quota only for the real local runtime. Fake backends
        // intentionally do not implement the auxiliary rate-limit RPC; a
        // background request there would leave a pending two-minute RPC in
        // widget tests and make the session look like it is still running.
        if (_activeBackend.descriptor.kind != BackendKind.fake &&
            _customProvider == null) {
          unawaited(_refreshConversationAccountUsage(force: true));
        }
        if (retryTranscriptMarker != null) {
          // The failed native first turn already added the user bubble. The
          // compatibility retry is the same logical message, so suppress its
          // second app-server user event before the queued prompt is drained.
          _retryingPromptTranscript = retryTranscriptMarker;
        }
        if (_queuedPrompts.isNotEmpty) {
          // Match CC Pocket's composer flow: prompts entered before a new
          // session is ready, or while a saved thread is reconnecting, are
          // sent after the thread is ready and retain their original order.
          unawaited(_drainQueuedPrompt());
        }
      }
    } on CodexSessionException catch (error) {
      if (!operationIsCurrent()) return;
      await _stopClient(
        keepConversation: keepConversationOnFailure,
        invalidatePendingOperations: false,
      );
      if (resumeThreadId != null && _isStaleResumeError(error.message)) {
        _discardStaleResume();
        return;
      }
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback(
          reason: error.message,
        );
        if (!operationIsCurrent()) return;
        if (switched) {
          await _start(
            resumeThreadId: resumeThreadId,
            resumeThreadPath: effectiveResumeThreadPath,
            allowFallback: false,
          );
          return;
        }
      }
      _showError(
        _identity == ExecutionIdentity.root &&
                _isRootProfileRejection(error.message)
            ? _rootProfileUnavailableMessage
            : error.message,
      );
    } catch (error) {
      if (!operationIsCurrent()) return;
      await _stopClient(
        keepConversation: keepConversationOnFailure,
        invalidatePendingOperations: false,
      );
      if (resumeThreadId != null && _isStaleResumeError('$error')) {
        _discardStaleResume();
        return;
      }
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback(
          reason: error.toString(),
        );
        if (!operationIsCurrent()) return;
        if (switched) {
          await _start(
            resumeThreadId: resumeThreadId,
            resumeThreadPath: effectiveResumeThreadPath,
            allowFallback: false,
          );
          return;
        }
      }
      _showError(
        _identity == ExecutionIdentity.root && _isRootProfileRejection(error)
            ? _rootProfileUnavailableMessage
            : '$error',
      );
    }
  }

  bool _isStaleResumeError(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('no rollout found') ||
        normalized.contains('rollout not found') ||
        normalized.contains('thread not found');
  }

  bool _shouldFallbackToCompatibility(Object error) {
    final normalized = '$error'.toLowerCase();
    if (_identity == ExecutionIdentity.root &&
        _isRootProfileRejection(normalized)) {
      return false;
    }
    const capabilityMarkers = <String>[
      'cannot run program',
      'permission denied',
      'operation not permitted',
      'no such file or directory',
      'failed to start process',
      'executable format error',
      'exec format error',
      'direct runtime',
      'app uid runtime',
      // Transport errors can be retried in the verified guest; provider
      // response errors are intentionally not runtime failures.
      'failed to lookup address information',
      'temporary failure in name resolution',
      'name or service not known',
      'network is unreachable',
      'tls handshake eof',
      'failed to connect to websocket',
      'stream disconnected before completion',
      'connection reset',
      'connection refused',
      'connection timed out',
      'timed out connecting to',
    ];
    return capabilityMarkers.any(normalized.contains);
  }

  bool _isRootProfileRejection(Object error) {
    final normalized = '$error'.toLowerCase();
    return normalized.contains('root_profile_rejected') ||
        (normalized.contains('kernelsu root profile') &&
            (normalized.contains('did not pass') ||
                normalized.contains('rejected')));
  }

  void _discardStaleResume() {
    if (!mounted) return;
    setState(() {
      _restoredHistory = null;
      _lastThreadId = null;
      _lastThreadPath = null;
      _connectionLost = false;
      _connectionLostReason = null;
      _status = 'stopped';
      final message = _localizedRuntimeFailure(
        'The saved Codex thread is no longer available in this local runtime. '
        'The cached messages remain; start a new local session.',
      );
      _error = message;
      _transcript.add(
        Localizations.localeOf(context).languageCode == 'zh'
            ? 'System: 已保存的 Codex 会话已过期；本地消息已保留。'
            : 'System: Saved thread expired; local messages were kept.',
      );
      _appendTranscriptError(message);
    });
    unawaited(_persistHistory());
  }

  Future<void> _resumeSavedSession({int? expectedOperationGeneration}) async {
    if (expectedOperationGeneration != null &&
        expectedOperationGeneration != _sessionOperationGeneration) {
      return;
    }
    if (_accountBindingStale) {
      _markAccountBindingStale();
      return;
    }
    if (_legacyChatOnlyHistory) {
      _showError(_legacyChatOnlyHistoryMessage);
      return;
    }
    final threadId = _restoredHistory?.threadId ?? _lastThreadId;
    if (threadId == null || threadId.isEmpty) {
      _showError('No saved provider thread is available to resume.');
      return;
    }
    if (mounted) {
      setState(() {
        _transitionInteraction(
          SessionLifecycleEvent.reconnectRequested,
          threadId: threadId,
        );
        _status = 'reconnecting';
        _error = null;
      });
      _publishSnapshot();
    }
    await _start(
      resumeThreadId: threadId,
      resumeThreadPath: _restoredHistory?.threadPath ?? _lastThreadPath,
      expectedOperationGeneration: expectedOperationGeneration,
    );
  }

  Future<void> _startNewThreadForCurrentAccount() async {
    if (!mounted || !_accountBindingStale) return;
    await _stopClient(keepConversation: true);
    if (!mounted || !_accountBindingStale) return;
    setState(() {
      // Keep the visible transcript, but discard only the provider-thread
      // identity. The next prompt therefore starts a clean thread under the
      // current account instead of retrying the revoked/old thread.
      _lastThreadId = null;
      _lastThreadPath = null;
      _restoredHistory = null;
      _sessionAuthGeneration = AuthBindingStore.currentGeneration.value;
      _accountBindingStale = false;
      _connectionLost = false;
      _connectionLostReason = null;
      _error = null;
      _status = 'stopped';
      _syncInteractionIdentity();
    });
    _addStructuredTranscript(
      CodexTranscriptKind.system,
      _uiText(
        '账号已切换；这条消息将创建当前账号的新 thread，不会恢复旧账号上下文。',
        'The account changed; this message starts a new thread for the current account and does not resume the old account context.',
      ),
    );
    _publishSnapshot();
    unawaited(_persistHistory());
    // Keep the explanatory reason out of the retry path while retaining it in
    // the transcript for a clear audit of why the old thread was not reused.
    _accountStaleNoticeShown = true;
  }

  void _startFreshConversation() {
    if (!mounted) return;
    setState(() {
      _sessionId = _newLocalSessionId();
      _historyKeySessionId = _sessionId;
      _historyUsesLegacyKey = false;
      _legacyChatOnlyHistory = false;
      _accountBindingStale = false;
      _accountStaleNoticeShown = false;
      _sessionAuthGeneration = AuthBindingStore.currentGeneration.value;
      _connectionLost = false;
      _connectionLostReason = null;
      _restoredHistory = null;
      _lastThreadId = null;
      _lastThreadPath = null;
      _inFlightPrompt = null;
      _retryPrompt = null;
      _retryImages = const <ImageAttachment>[];
      _retryingPromptTranscript = null;
      _historyPinned = false;
      _sessionTitle = null;
      _threadName = null;
      _sessionTitleManuallySet = false;
      _transcript.clear();
      _queuedPrompts.clear();
      _promptController.clear();
      _conversationInputTokens = 0;
      _conversationCachedInputTokens = 0;
      _conversationOutputTokens = 0;
      _conversationContextTokens = 0;
      _conversationContextWindow = null;
      _conversationToolCalls = 0;
      _conversationFileEdits = 0;
      _conversationDuration = Duration.zero;
      _turnStartedAt = null;
      _error = null;
      _status = 'stopped';
      _interaction = SessionInteractionState.initial(
        workspaceId: _workspaceIdentity(_activeWorkspace),
        sessionId: _sessionId,
      );
    });
    _publishSnapshot();
    unawaited(_persistHistory());
  }

  Future<String> _forkDestinationHome(String sessionId) async {
    final scope = _safeRuntimeScope(sessionId);
    if (_isCompatibility) {
      return '/home/codex/sessions/$scope';
    }
    final runtime = await _runtime;
    final home = _runtimeEnvironment(
      runtime,
      runtimeScope: sessionId,
    )['CODEX_HOME'];
    if (home == null || home.isEmpty) {
      throw const BackendException(
        'The local runtime did not expose an isolated CODEX_HOME for the fork.',
      );
    }
    return home;
  }

  String _forkRelativeRolloutPath(String sourceHome, String sourcePath) {
    final normalizedHome = sourceHome
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final normalizedPath = sourcePath.replaceAll('\\', '/');
    final prefix = '$normalizedHome/';
    if (!normalizedPath.startsWith(prefix)) {
      throw const BackendException(
        'Codex returned a rollout path outside the current isolated CODEX_HOME.',
      );
    }
    final relative = normalizedPath.substring(prefix.length);
    final segments = relative.split('/');
    if (relative.isEmpty ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const BackendException(
        'Codex returned an invalid fork rollout path.',
      );
    }
    return relative;
  }

  Future<void> _copyForkRollout({
    required String sourcePath,
    required String destinationPath,
    required String destinationHome,
    required CodexSessionClient client,
  }) async {
    final destinationSlash = destinationPath.replaceAll('\\', '/');
    final separator = destinationSlash.lastIndexOf('/');
    final destinationDirectory = separator <= 0
        ? destinationHome
        : destinationSlash.substring(0, separator);
    final environment = client.runtimeEnvironment;

    Future<void> run(List<String> argv, String label) async {
      int? exitCode;
      try {
        await for (final event in _activeBackend.execute(
          ExecutionRequest(
            argv: argv,
            cwd: _activeWorkspace.hostPath,
            identity: _identity,
            timeout: const Duration(minutes: 2),
            environment: environment,
          ),
        )) {
          if (event.exitCode != null) exitCode = event.exitCode;
        }
      } catch (error) {
        throw BackendException('Could not prepare the fork ($label): $error');
      }
      if (exitCode != 0) {
        throw BackendException(
          'Could not prepare the fork ($label); exit code ${exitCode ?? 'unknown'}.',
        );
      }
    }

    await run(<String>[
      'mkdir',
      '-p',
      destinationDirectory,
    ], 'create destination');
    await run(<String>[
      'cp',
      '-p',
      sourcePath,
      destinationPath,
    ], 'copy rollout');
  }

  Future<void> _forkCurrentSession() async {
    if (_turnActive || _sending || _busy || _approval != null) {
      _showError('请先停止或等待当前 turn 完成，再分叉会话。');
      return;
    }
    if (widget.onFork == null) {
      _showError('当前页面没有可用的会话分叉入口。');
      return;
    }
    if (_legacyChatOnlyHistory || _missingCustomProviderId != null) {
      _showError(
        _legacyChatOnlyHistory
            ? _legacyChatOnlyHistoryMessage
            : _missingCustomProviderMessage,
      );
      return;
    }

    try {
      if (_client == null) {
        final threadId = _restoredHistory?.threadId ?? _lastThreadId;
        if (threadId == null || threadId.trim().isEmpty) {
          _showError('当前 session 还没有可分叉的 Codex thread。');
          return;
        }
        await _start(
          resumeThreadId: threadId,
          resumeThreadPath: _restoredHistory?.threadPath ?? _lastThreadPath,
        );
      }
      final client = _client;
      if (client is! CodexSessionClient) {
        _showError('当前运行时没有提供 thread/fork 协议。');
        return;
      }
      final sourceHome = client.codexHome?.trim();
      final fork = await client.forkThread();
      final sourcePath = fork.threadPath?.trim();
      if (sourceHome == null ||
          sourceHome.isEmpty ||
          sourcePath == null ||
          sourcePath.isEmpty) {
        throw const CodexSessionException(
          '当前 Codex 版本没有返回可复制的 fork rollout 路径，未创建伪分叉会话。',
        );
      }

      final newSessionId = _newLocalSessionId();
      final destinationHome = await _forkDestinationHome(newSessionId);
      final relativePath = _forkRelativeRolloutPath(
        sourceHome,
        fork.threadPath!,
      );
      final destinationPath = '$destinationHome/$relativePath';
      await _copyForkRollout(
        sourcePath: fork.threadPath!,
        destinationPath: destinationPath,
        destinationHome: destinationHome,
        client: client,
      );

      final sourceTitle =
          _effectiveSessionTitle ??
          workspaceNameFromPath(_activeWorkspace.displayPath);
      final history = SessionHistoryRecord(
        backendId: _activeWorkspace.backendId,
        workspacePath: _activeWorkspace.hostPath,
        status: 'stopped',
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        sessionId: newSessionId,
        threadId: fork.threadId,
        threadPath: destinationPath,
        customProviderId: _customProvider?.id,
        title: _uiText('分叉自 $sourceTitle', 'Fork of $sourceTitle'),
        titleIsManual: false,
        draft: '',
        entries: List<String>.unmodifiable(_transcript),
        queuedPrompts: const <String>[],
        codexModel: _codexModel,
        codexEffort: _codexEffort,
        executionIdentity: _identity,
        rootApprovalGranted: false,
        codexSandbox: _codexSandbox,
        codexPermissions: _codexPermissions,
        codexApprovalPolicy: _codexApprovalPolicy,
        codexPlanMode: _planMode,
        promptHistory: List<String>.unmodifiable(_promptHistory),
        pinned: false,
      );
      await widget.onFork!(_activeWorkspace, history);
    } on Object catch (error) {
      _showError('分叉会话失败：$error');
    }
  }

  Future<void> _stopClient({
    bool keepConversation = false,
    bool invalidatePendingOperations = true,
  }) async {
    if (invalidatePendingOperations) {
      _sessionOperationGeneration++;
      if (!keepConversation) _explicitlyStopped = true;
    }
    _automaticReconnectTimer?.cancel();
    _automaticReconnectTimer = null;
    final client = _client;
    _lastThreadId = client?.threadId ?? _lastThreadId;
    if (client is CodexSessionClient) {
      _lastThreadPath = client.threadPath ?? _lastThreadPath;
    }
    if (client != null) {
      _transitionInteraction(SessionLifecycleEvent.stopRequested);
    }
    _client = null;
    final foregroundOwned = _sessionForegroundOwned;
    _sessionForegroundOwned = false;
    // _subscription listens to the session runtime handle, not directly to
    // one client. Keep it alive across an explicit restart/reconnect so the
    // next client is still rendered by the same page.
    await _sessionRuntime.detachClient(client);
    if (client != null) await client.dispose();
    _disposeUserInputControllers();
    if (foregroundOwned) await SessionLifecycle.stop();
    if (mounted) {
      setState(() {
        _busy = false;
        _sending = false;
        _turnActive = false;
        _approval = null;
        _agentFileChanges = null;
        _pendingAgentVerification = null;
        _clearStreaming();
        _inFlightPrompt = null;
        _retryPrompt = null;
        _retryImages = const <ImageAttachment>[];
        _retryingPromptTranscript = null;
        if (!keepConversation) {
          _connectionLost = false;
          _connectionLostReason = null;
        }
        _status = keepConversation && _connectionLost
            ? 'disconnected'
            : 'stopped';
        _transitionInteraction(
          keepConversation && _connectionLost
              ? SessionLifecycleEvent.disconnected
              : SessionLifecycleEvent.stopped,
          threadId: _lastThreadId,
        );
      });
      _publishSnapshot();
      unawaited(_persistHistory());
    }
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    var client = _client;
    final images = List<ImageAttachment>.unmodifiable(_attachedImages);
    if (prompt.isEmpty && images.isEmpty) return;
    if (_firstPromptForAutomaticTitle?.trim().isNotEmpty != true &&
        prompt.isNotEmpty) {
      _firstPromptForAutomaticTitle = prompt;
    }
    if (_legacyChatOnlyHistory) {
      _showError(_legacyChatOnlyHistoryMessage);
      return;
    }
    if (_accountBindingStale) {
      await _startNewThreadForCurrentAccount();
      client = _client;
    }
    if (images.isEmpty &&
        prompt.startsWith('/') &&
        await _handleLocalSlashCommand(prompt)) {
      _promptController.clear();
      return;
    }
    if (_sessionTitle == null || _sessionTitle!.trim().isEmpty) {
      final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
      final title = normalized.isEmpty
          ? (Localizations.localeOf(context).languageCode == 'zh'
                ? '图片会话'
                : 'Image session')
          : String.fromCharCodes(normalized.runes.take(36)) +
                (normalized.runes.length > 36 ? '…' : '');
      setState(() {
        _sessionTitle = title;
        _sessionTitleManuallySet = false;
      });
    }
    if (client == null) {
      _promptController.clear();
      _attachedImages.clear();
      _promptHistory.remove(prompt);
      _promptHistory.insert(0, prompt);
      if (_promptHistory.length > 30) _promptHistory.removeLast();
      setState(() {
        _queuedPrompts.add(prompt);
        _queuedImageAttachments.add(images);
      });
      _publishSnapshot();
      unawaited(_persistHistory());
      if (!_canQueueForReconnect) {
        // A new CC Pocket-style session starts from the first submitted
        // prompt. The setup/runtime details stay behind settings; users do
        // not have to press a debug-oriented Start button before composing.
        unawaited(_start());
      }
      return;
    }
    _promptController.clear();
    _attachedImages.clear();
    _promptHistory.remove(prompt);
    _promptHistory.insert(0, prompt);
    if (_promptHistory.length > 30) _promptHistory.removeLast();
    if (_turnActive || _sending) {
      setState(() {
        _queuedPrompts.add(prompt);
        _queuedImageAttachments.add(images);
      });
      _publishSnapshot();
      unawaited(_persistHistory());
      return;
    }
    await _sendPromptNow(prompt, images: images);
  }

  Future<void> _sendPromptNow(
    String prompt, {
    List<ImageAttachment> images = const <ImageAttachment>[],
  }) async {
    final client = _client;
    if (client == null) return;
    final canFallbackFirstTurn =
        client is CodexSessionClient &&
        !_usingFallback &&
        !_isCompatibility &&
        _mayUseCompatibilityFallback &&
        widget.initialHistory == null &&
        _restoredHistory == null &&
        !_transcript.any(_isConversationTranscriptEntry);
    _inFlightPrompt = prompt;
    setState(() {
      _transitionInteraction(SessionLifecycleEvent.turnStarted);
      _sending = true;
      _turnActive = true;
      _error = null;
      _retryPrompt = null;
      _retryImages = const <ImageAttachment>[];
      _providerNetworkWarningShown = false;
      _providerNetworkDiagnostic = null;
    });
    // Persist the prompt-history entry before the provider turn completes so
    // a disconnect does not lose the CC Pocket-style quick history.
    unawaited(_persistHistory());
    _publishSnapshot();
    try {
      await client.sendPrompt(prompt, images: images);
    } on CodexSessionException catch (error) {
      _turnActive = false;
      if (canFallbackFirstTurn &&
          _shouldFallbackToCompatibility(error) &&
          await _retryFirstTurnInCompatibility(prompt, images, error.message)) {
        return;
      }
      if (_isProviderNetworkFailure(error.message)) {
        _retryPrompt = prompt;
        _retryImages = List<ImageAttachment>.unmodifiable(images);
      }
      _showError(error.message);
    } catch (error) {
      _turnActive = false;
      if (canFallbackFirstTurn &&
          _shouldFallbackToCompatibility(error) &&
          await _retryFirstTurnInCompatibility(prompt, images, '$error')) {
        return;
      }
      if (_isProviderNetworkFailure('$error')) {
        _retryPrompt = prompt;
        _retryImages = List<ImageAttachment>.unmodifiable(images);
      }
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _publishSnapshot();
        if (!_turnActive && _approval == null && _queuedPrompts.isNotEmpty) {
          unawaited(_drainQueuedPrompt());
        }
      }
    }
  }

  bool _isConversationTranscriptEntry(String stored) {
    final kind = CodexTranscriptEntry.fromStored(stored).kind;
    return kind == CodexTranscriptKind.user ||
        kind == CodexTranscriptKind.assistant ||
        kind == CodexTranscriptKind.reasoning ||
        kind == CodexTranscriptKind.tool ||
        kind == CodexTranscriptKind.toolResult;
  }

  Future<bool> _retryFirstTurnInCompatibility(
    String prompt,
    List<ImageAttachment> images,
    String failure,
  ) async {
    final switched = await _activateCompatibilityFallback(reason: failure);
    if (!switched) return false;

    // This is safe only for an empty local thread: the native and guest
    // runtimes intentionally have separate CODEX_HOME/SQLite stores, so never
    // attempt to migrate or resume a thread across this boundary.
    await _stopClient(keepConversation: true);
    _queuedPrompts.insert(0, prompt);
    _queuedImageAttachments.insert(
      0,
      List<ImageAttachment>.unmodifiable(images),
    );
    final transcriptMarker = prompt.trim().isEmpty
        ? '[图片 ${images.length} 张]'
        : prompt.trim();
    await _start(allowFallback: false, retryTranscriptMarker: transcriptMarker);
    return true;
  }

  Future<bool> _handleLocalSlashCommand(String raw) async {
    late final List<String> parts;
    try {
      parts = tokenizeCodexCommand(raw.trim());
    } on FormatException {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '命令参数中的引号没有闭合。'
            : 'A quote in the command arguments is not closed.',
      );
      unawaited(_persistHistory());
      return true;
    }
    if (parts.isEmpty) return false;
    final command = parts.first.toLowerCase();
    final argument = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    switch (command) {
      case '/status':
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        _addStructuredTranscript(
          CodexTranscriptKind.system,
          zh
              ? '会话状态：${_statusLabel(_status)}；运行环境：${_activeBackend.descriptor.displayName}；'
                    '传输：Codex app-server${_customProvider == null ? '' : '（${_customProvider!.name} Responses provider）'}；'
                    '消息数：${_transcript.length}。'
              : 'Session ${_statusLabel(_status)}; ${_activeBackend.descriptor.id}; '
                    'Codex app-server${_customProvider == null ? '' : ' with ${_customProvider!.name} Responses provider'}; '
                    '${_transcript.length} messages.',
        );
        unawaited(_persistHistory());
        return true;
      case '/clear':
        setState(() {
          _transcript.clear();
          _clearStreaming();
        });
        unawaited(_persistHistory());
        return true;
      case '/help':
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        _addStructuredTranscript(
          CodexTranscriptKind.system,
          zh
              ? '本地命令：/status /clear /plan /permissions /interrupt /new /exec <argv...> /exec --tty <argv...> '
                    '/model <模型ID> /effort <档位> /refresh-models /network-test /cli-help /version。'
              : 'Local commands: /status /clear /plan /permissions /interrupt '
                    '/new /exec <argv...> /exec --tty <argv...> /model <id> /effort <level> /refresh-models /network-test /cli-help /version.',
        );
        unawaited(_persistHistory());
        return true;
      case '/plan':
        _togglePlanMode();
        return true;
      case '/permissions':
        await _showPermissionsPicker();
        return true;
      case '/interrupt':
        await _interruptSession();
        return true;
      case '/exec':
        if (parts.length < 2) {
          final zh = Localizations.localeOf(context).languageCode == 'zh';
          _addStructuredTranscript(
            CodexTranscriptKind.system,
            zh
                ? '用法：/exec <argv...>。命令通过当前 app-server 执行，不支持 shell 管道、重定向或命令替换。'
                : 'Usage: /exec <argv...>. Runs through the active app-server; shell pipes, redirects, and substitution are not supported.',
          );
          unawaited(_persistHistory());
        } else {
          final commandArgs = parts.sublist(1);
          if (commandArgs.first == '--tty') {
            if (commandArgs.length == 1) {
              final zh = Localizations.localeOf(context).languageCode == 'zh';
              _addStructuredTranscript(
                CodexTranscriptKind.system,
                zh ? '用法：/exec --tty <argv...>。打开当前 session 的交互式 PTY。' : 'Usage: /exec --tty <argv...>. Open an interactive PTY in the current session.',
              );
              unawaited(_persistHistory());
            } else {
              await _executeInteractiveSessionCommand(commandArgs.sublist(1));
            }
          } else {
            await _executeSessionCommand(commandArgs);
          }
        }
        return true;
      case '/new':
        _startFreshConversation();
        return true;
      case '/model':
        if (argument.isEmpty) {
          await _openSessionSettings();
        } else {
          updateCodexSettings(model: argument);
          _addStructuredTranscript(
            CodexTranscriptKind.status,
            Localizations.localeOf(context).languageCode == 'zh'
                ? '模型已切换为 $argument。'
                : 'Model changed to $argument.',
          );
          unawaited(_persistHistory());
        }
        return true;
      case '/effort':
        if (argument.isEmpty) {
          await _openSessionSettings();
        } else {
          updateCodexSettings(effort: argument.toLowerCase());
          _addStructuredTranscript(
            CodexTranscriptKind.status,
            Localizations.localeOf(context).languageCode == 'zh'
                ? '推理档位已切换为 ${argument.toLowerCase()}。'
                : 'Reasoning effort changed to ${argument.toLowerCase()}.',
          );
          unawaited(_persistHistory());
        }
        return true;
      case '/refresh-models':
        try {
          await refreshModelCatalog();
          _addStructuredTranscript(
            CodexTranscriptKind.system,
            Localizations.localeOf(context).languageCode == 'zh'
                ? _customProvider == null
                      ? '已从当前 Codex CLI 刷新模型列表。'
                      : '第三方 provider 未提供模型目录；当前配置模型保持不变。'
                : _customProvider == null
                ? 'Model catalog refreshed from the installed Codex CLI.'
                : 'The custom provider has no model catalog; its configured model is unchanged.',
          );
          unawaited(_persistHistory());
        } catch (error) {
          _showError('$error');
        }
        return true;
      case '/compact':
        final client = _client;
        if (client is CodexSessionClient) {
          try {
            await client.compact();
          } catch (error) {
            _showError('$error');
          }
        } else {
          _addStructuredTranscript(
            CodexTranscriptKind.system,
            Localizations.localeOf(context).languageCode == 'zh'
                ? '当前没有可压缩的活动 Codex thread。'
                : 'There is no active Codex thread to compact.',
          );
          unawaited(_persistHistory());
        }
        return true;
      case '/cli-help':
        await _showCliHelp();
        return true;
      case '/cli':
        if (argument.isEmpty) {
          _addStructuredTranscript(
            CodexTranscriptKind.system,
            Localizations.localeOf(context).languageCode == 'zh'
                ? '用法：/cli <Codex CLI 参数>。仅运行非交互命令；Codex 对话请直接发送消息。'
                : 'Usage: /cli <Codex CLI arguments>. Only non-interactive commands run here; send a message for a Codex turn.',
          );
          unawaited(_persistHistory());
        } else {
          await _showCliCommand(
            parts.sublist(1),
            'codex ${parts[1]}',
            timeout: const Duration(minutes: 2),
          );
        }
        return true;
      case '/version':
        await _showCliCommand(const <String>['--version'], 'codex --version');
        return true;
      case '/network-test':
        if (parts.length != 1) {
          final zh = Localizations.localeOf(context).languageCode == 'zh';
          _addStructuredTranscript(
            CodexTranscriptKind.system,
            zh ? '用法：/network-test' : 'Usage: /network-test',
          );
          unawaited(_persistHistory());
        } else {
          await _showNetworkProbe();
        }
        return true;
      default:
        return false;
    }
  }

  void _appendCommandOutput(String text, bool isStderr) {
    if (!mounted || text.isEmpty) return;
    final id = _commandTranscriptId;
    if (id == null) return;
    setState(() {
      _commandOutputBuffer += text;
      _upsertCommandTranscript(
        id: id,
        text: _commandOutputBuffer,
        kind: CodexTranscriptKind.toolResult,
        data: <String, dynamic>{
          'streaming': true,
          'stream': isStderr ? 'stderr' : 'stdout',
        },
      );
    });
  }

  void _upsertCommandTranscript({
    required String id,
    required String text,
    required CodexTranscriptKind kind,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    final entry = CodexTranscriptEntry(
      id: id,
      kind: kind,
      text: text.trimRight(),
      timestamp: DateTime.now(),
      model: _codexModel,
      toolName: 'command/exec',
      data: data,
    ).toStored();
    final index = _transcript.indexWhere(
      (raw) => CodexTranscriptEntry.fromStored(raw).id == id,
    );
    if (index < 0) {
      _transcript.add(entry);
    } else {
      _transcript[index] = entry;
    }
  }

  Future<void> _executeSessionCommand(List<String> argv) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '当前没有可用的 Codex session app-server。'
            : 'There is no active Codex session app-server.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (!mounted || _sending) return;
    setState(() {
      _sending = true;
      // command/exec owns the session worker while it is in flight. Keep the
      // CC Pocket status line and Home snapshot consistent with a provider
      // turn instead of leaving the thread visually idle during a long-lived
      // host command.
      _status = 'running';
    });
    final label = '/exec ${argv.join(' ')}';
    final commandId = 'command-exec-${DateTime.now().microsecondsSinceEpoch}';
    _commandTranscriptId = commandId;
    _commandOutputBuffer = '';
    _publishSnapshot();
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在通过当前会话执行：$label' : 'Running through this session: $label',
    );
    unawaited(_persistHistory());
    try {
      final result = await client.executeCommand(
        argv,
        onOutput: _appendCommandOutput,
      );
      final output = result.combinedOutput;
      final detail = output.trim().isEmpty
          ? (zh ? '退出码 ${result.exitCode}' : 'exit ${result.exitCode}')
          : output.length <= 6000
          ? output
          : '${output.substring(0, 6000)}…';
      if (mounted) {
        setState(() {
          _commandOutputBuffer = output;
          _upsertCommandTranscript(
            id: commandId,
            text: detail,
            kind: CodexTranscriptKind.toolResult,
            data: <String, dynamic>{
              'streaming': false,
              'exitCode': result.exitCode,
            },
          );
        });
      }
      if (output.trim().isEmpty) {
        _addStructuredTranscript(
          result.exitCode == 0
              ? CodexTranscriptKind.system
              : CodexTranscriptKind.error,
          result.exitCode == 0
              ? '$label\n$detail'
              : (zh
                    ? '$label\n命令失败：$detail'
                    : '$label\nCommand failed: $detail'),
        );
      }
      unawaited(_persistHistory());
    } on Object catch (error) {
      final message = error is CodexSessionException ? '$error' : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '会话命令失败：$message' : 'Session command failed: $message',
      );
      unawaited(_persistHistory());
    } finally {
      _commandTranscriptId = null;
      _commandOutputBuffer = '';
      if (mounted) {
        setState(() {
          _sending = false;
          if (_connectionLost) {
            _status = 'disconnected';
          } else if (_client == null) {
            _status = 'stopped';
          } else if (_turnActive) {
            _status = 'running';
          } else {
            _status = 'ready';
          }
        });
        _publishSnapshot();
      }
    }
  }

  Future<void> _executeInteractiveSessionCommand(List<String> argv) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '当前没有可用的 Codex session app-server。'
            : 'There is no active Codex session app-server.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (!mounted || _sending) return;
    setState(() {
      _sending = true;
      _status = 'running';
    });
    final label = '/exec --tty ${argv.join(' ')}';
    final commandId = 'command-tty-${DateTime.now().microsecondsSinceEpoch}';
    _commandTranscriptId = commandId;
    _commandOutputBuffer = '';
    _publishSnapshot();
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在打开交互式命令：$label' : 'Opening interactive command: $label',
    );
    unawaited(_persistHistory());

    final output = ValueNotifier<String>('');
    final result = ValueNotifier<CodexCommandExecResult?>(null);
    final failure = ValueNotifier<Object?>(null);
    final commandFuture = client.executeCommand(
      argv,
      tty: true,
      onOutput: (text, isStderr) {
        _appendCommandOutput(text, isStderr);
        output.value += text;
      },
    );
    unawaited(
      commandFuture.then<void>(
        (value) => result.value = value,
        onError: (Object error, StackTrace stack) => failure.value = error,
      ),
    );
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _InteractiveCommandDialog(
          command: argv,
          output: output,
          result: result,
          error: failure,
          chinese: zh,
          onWrite: client.writeCommandInput,
          onResize: client.resizeCommand,
          onInterrupt: client.interrupt,
        ),
      );
      final completed = await commandFuture;
      final combinedOutput = completed.combinedOutput;
      final detail = combinedOutput.trim().isEmpty
          ? (zh ? '退出码 ${completed.exitCode}' : 'exit ${completed.exitCode}')
          : combinedOutput.length <= 6000
          ? combinedOutput
          : '${combinedOutput.substring(0, 6000)}…';
      if (mounted) {
        setState(() {
          _commandOutputBuffer = combinedOutput;
          _upsertCommandTranscript(
            id: commandId,
            text: detail,
            kind: CodexTranscriptKind.toolResult,
            data: <String, dynamic>{
              'streaming': false,
              'exitCode': completed.exitCode,
              'tty': true,
            },
          );
        });
      }
      if (combinedOutput.trim().isEmpty) {
        _addStructuredTranscript(
          completed.exitCode == 0
              ? CodexTranscriptKind.system
              : CodexTranscriptKind.error,
          completed.exitCode == 0
              ? '$label\n$detail'
              : (zh
                    ? '$label\n命令失败：$detail'
                    : '$label\nCommand failed: $detail'),
        );
      }
      unawaited(_persistHistory());
    } on Object catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '交互式命令失败：$error' : 'Interactive command failed: $error',
      );
      unawaited(_persistHistory());
    } finally {
      output.dispose();
      result.dispose();
      failure.dispose();
      _commandTranscriptId = null;
      _commandOutputBuffer = '';
      if (mounted) {
        setState(() {
          _sending = false;
          if (_connectionLost) {
            _status = 'disconnected';
          } else if (_client == null) {
            _status = 'stopped';
          } else if (_turnActive) {
            _status = 'running';
          } else {
            _status = 'ready';
          }
        });
        _publishSnapshot();
      }
    }
  }

  Future<void> _showNetworkProbe() async {
    if (!mounted || _sending) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      _customProvider == null
          ? zh
                ? '正在检查当前 Root/App 执行环境和 Codex app-server 网络；会读取账户额度，不发送模型请求…'
                : 'Checking this Root/App runtime and Codex app-server network; account limits are read, no model request is sent…'
          : zh
          ? '正在检查第三方服务商地址的 DNS/TLS；不发送 API key 或模型请求…'
          : 'Checking the third-party provider DNS/TLS; no API key or model request is sent…',
    );
    unawaited(_persistHistory());
    try {
      final invocation = await _resolveCodexInvocation(
        runtimeScope: _newRuntimeOperationScope('network-test'),
      );
      if (invocation == null) return;
      if (_identity == ExecutionIdentity.root &&
          !await _confirmRootExecution('probe provider network connectivity')) {
        _addStructuredTranscript(
          CodexTranscriptKind.status,
          zh ? '已取消网络检查。' : 'Network check cancelled.',
        );
        unawaited(_persistHistory());
        return;
      }
      final endpoints = CodexNetworkProbe.endpointsFor(_customProvider);
      final probeBackend = await _networkProbeBackend();
      final pythonProbeSkipped = probeBackend == null;
      _OneShotCommandResult? result;
      String? skippedPythonDetail;
      if (probeBackend == null) {
        skippedPythonDetail = _customProvider == null
            ? zh
                  ? '未找到已验证的 Linux Compatibility Python 环境，已跳过 Python guest 网络探测；OpenAI 连接仍以 Codex RPC 结果为准。'
                  : 'No verified Linux Compatibility Python runtime was found; the guest Python probe was skipped. OpenAI connectivity is still judged by Codex RPC.'
            : zh
            ? '未找到已验证的 Linux Compatibility Python 环境，无法检查第三方服务商地址。'
            : 'No verified Linux Compatibility Python runtime was found; the third-party provider endpoint could not be checked.';
      } else {
        final probeEnvironment =
            probeBackend.descriptor.kind == BackendKind.linuxCompatibility
            ? _compatibilityRuntimeEnvironment(
                runtimeScope: _newRuntimeOperationScope('network-probe-python'),
              )
            : invocation.environment;
        result = await _runOneShotCommand(
          invocation: _CodexInvocation(
            command: 'python',
            environment: probeEnvironment,
          ),
          arguments: CodexNetworkProbe.argumentsFor(endpoints),
          timeout: Duration(seconds: 10 * endpoints.length + 5),
          backend: probeBackend,
        );
      }
      final probeResults = result == null
          ? const <CodexNetworkProbeResult>[]
          : CodexNetworkProbe.parseOutput(result.output);
      final pythonDetail = probeResults.isEmpty
          ? (result?.output.trim() ?? skippedPythonDetail ?? '')
          : probeResults
                .map((value) => _formatNetworkProbeResult(value, zh))
                .join('\n');
      final pythonProbeSucceeded =
          result != null &&
          result.exitCode == 0 &&
          probeResults.length == endpoints.length &&
          probeResults.every((value) => value.reachedServer);
      var appServerProbeSucceeded = true;
      String? appServerDetail;
      if (_customProvider == null) {
        try {
          final activeClient = _client;
          if (activeClient is CodexSessionClient) {
            await activeClient.readAccountRateLimits(
              timeout: const Duration(seconds: 18),
            );
          } else {
            // A fresh session may not own a thread/app-server yet. Reuse the
            // same resolved runtime and identity to probe Codex's real RPC
            // transport without creating a thread or sending a model turn.
            final usage = await CodexUsageClient.load(
              backend: _activeBackend,
              workspace: _activeWorkspace,
              command: invocation.command,
              identity: _identity,
              environment: invocation.environment,
            ).timeout(const Duration(seconds: 22));
            if (!usage.hasData) {
              throw FormatException(
                usage.error ?? 'Codex returned no account quota data.',
              );
            }
          }
          appServerDetail = zh
              ? 'Codex RPC：可达（未发模型请求）'
              : 'Codex RPC: reachable (no model request)';
        } catch (error) {
          appServerProbeSucceeded = false;
          appServerDetail = _formatAppServerNetworkProbeFailure(error, zh);
        }
      }
      // For OpenAI mode the authenticated RPC from Codex's own Rust app-server
      // is the decisive signal; the Python result remains useful for separating
      // guest DNS/proxy/CA problems. A third-party provider is never routed
      // through OpenAI auth or quota RPCs.
      final probeSucceeded = _customProvider == null
          ? appServerProbeSucceeded
          : pythonProbeSucceeded;
      if (pythonProbeSkipped) {
        _addStructuredTranscript(
          _customProvider == null
              ? CodexTranscriptKind.status
              : CodexTranscriptKind.error,
          pythonDetail,
        );
      } else if (probeResults.isNotEmpty) {
        for (final endpoint in probeResults) {
          _addStructuredTranscript(
            result!.exitCode == 0 && endpoint.reachedServer
                ? CodexTranscriptKind.system
                : CodexTranscriptKind.error,
            _formatNetworkProbeResult(endpoint, zh),
          );
        }
      } else if (pythonDetail.isNotEmpty) {
        _addStructuredTranscript(CodexTranscriptKind.error, pythonDetail);
      } else {
        _addStructuredTranscript(
          CodexTranscriptKind.error,
          zh
              ? '网络检查没有返回结果，退出码 ${result!.exitCode}。'
              : 'Network check returned no result (exit ${result!.exitCode}).',
        );
      }
      if (appServerDetail != null) {
        _addStructuredTranscript(
          appServerProbeSucceeded
              ? CodexTranscriptKind.system
              : CodexTranscriptKind.error,
          appServerDetail,
        );
      }
      if (!probeSucceeded && appServerDetail == null && pythonDetail.isEmpty) {
        _addStructuredTranscript(
          CodexTranscriptKind.error,
          zh ? '网络检查失败。' : 'Network check failed.',
        );
      }
      unawaited(_persistHistory());
    } on Object catch (error) {
      final message = error is BackendException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '网络检查失败：$message' : 'Network check failed: $message',
      );
      _showError(message);
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatAppServerNetworkProbeFailure(Object error, bool zh) {
    final text = error.toString().toLowerCase();
    final category = text.contains('timeout') || text.contains('timed out')
        ? (zh ? 'RPC 超时' : 'RPC timed out')
        : text.contains('401') ||
              text.contains('unauthorized') ||
              text.contains('unauthorised')
        ? (zh ? '认证被拒绝（HTTP 401）' : 'authentication rejected (HTTP 401)')
        : text.contains('403') || text.contains('forbidden')
        ? (zh ? '服务端拒绝访问（HTTP 403）' : 'server rejected access (HTTP 403)')
        : text.contains('tls') ||
              text.contains('certificate') ||
              text.contains('handshake')
        ? (zh ? 'TLS/证书握手失败' : 'TLS/certificate handshake failed')
        : text.contains('dns') ||
              text.contains('resolve') ||
              text.contains('gaierror')
        ? (zh ? 'DNS 解析失败' : 'DNS resolution failed')
        : text.contains('method not found') ||
              text.contains('unsupported method') ||
              text.contains('-32601')
        ? (zh
              ? '当前 app-server 不支持额度 RPC'
              : 'quota RPC is unsupported by this app-server')
        : text.contains('connection') ||
              text.contains('socket') ||
              text.contains('network') ||
              text.contains('errno')
        ? (zh ? '连接失败' : 'connection failed')
        : (zh
              ? 'RPC 失败（${error.runtimeType}）'
              : 'RPC failed (${error.runtimeType})');
    return zh ? 'Codex RPC：$category' : 'Codex RPC: $category';
  }

  String _formatNetworkProbeResult(CodexNetworkProbeResult result, bool zh) {
    final host = result.host;
    final route = result.proxyScheme == null
        ? (zh ? '未注入显式 HTTP 代理' : 'no explicit HTTP proxy injected')
        : result.proxyHost == null
        ? (zh ? '已配置代理（地址隐藏）' : 'proxy configured (address hidden)')
        : (zh ? '经代理 ' : 'via proxy ') +
              result.proxyHost! +
              (result.proxyPort == null ? '' : ':${result.proxyPort}');
    if (result.reachedServer) {
      final transport = result.secure
          ? (zh ? 'DNS、连接与 TLS 可达' : 'DNS, connection, and TLS reachable')
          : (zh ? 'DNS 与连接可达' : 'DNS and connection reachable');
      final status = result.statusCode;
      final authNote = status == 401 || status == 403
          ? (zh ? '；服务端要求认证' : '; server requires authentication')
          : '';
      return '$host：HTTP $status（$transport；$route$authNote）';
    }
    final error = switch (result.errorType) {
      'gaierror' => zh ? 'DNS 解析失败' : 'DNS resolution failed',
      'TimeoutError' || 'timeout' => zh ? '连接超时' : 'connection timed out',
      'SSLError' || 'SSLCertVerificationError' =>
        zh ? 'TLS/证书握手失败' : 'TLS/certificate handshake failed',
      'ConnectionRefusedError' => zh ? '连接被拒绝' : 'connection refused',
      'ConnectionResetError' => zh ? '连接被重置' : 'connection reset',
      final type when type != null =>
        zh ? '连接错误（$type）' : 'connection error ($type)',
      _ => zh ? '未收到网络响应' : 'no network response',
    };
    final errno = result.errorNumber == null
        ? ''
        : ' (errno ${result.errorNumber})';
    return '$host：$error$errno（$route）';
  }

  String _statusLabel(String status) {
    if (Localizations.localeOf(context).languageCode != 'zh') return status;
    if (status.startsWith('exited ')) return '已退出 ${status.substring(7)}';
    return switch (status) {
      'stopped' => '已停止',
      'starting' => '启动中',
      'ready' => '就绪',
      'running' => '运行中',
      'reconnecting' => '重新连接中',
      'interrupting' => '正在停止生成',
      'waiting approval' => '等待审批',
      'failed' => '失败',
      'disconnected' => '已断开',
      _ => status,
    };
  }

  Future<void> _showCliHelp() =>
      _showCliCommand(const <String>['--help'], 'codex --help');

  Future<void> _showCliCommand(
    List<String> arguments,
    String label, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (arguments.isEmpty) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final route = codexCliCommandRoute(arguments);
    if (route == CodexCliCommandRoute.mcpAuthentication) {
      if (arguments.length > 1 && arguments[1].toLowerCase() == 'login') {
        await _showMcpOAuthLoginCommand(zh: zh, arguments: arguments);
      } else {
        await _showMcpOAuthLogoutCommand(zh: zh, arguments: arguments);
      }
      return;
    }
    if (route == CodexCliCommandRoute.accountSettings &&
        arguments.length == 2 &&
        arguments[0].toLowerCase() == 'login' &&
        arguments[1].toLowerCase() == 'status') {
      await _showLoginStatusCommand(zh: zh);
      return;
    }
    if (route == CodexCliCommandRoute.mcpList ||
        route == CodexCliCommandRoute.mcpGet) {
      await _showMcpServerCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.pluginList) {
      await _showPluginListCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.pluginMarketplaceList) {
      await _showPluginMarketplaceListCommand(
        zh: zh,
        jsonOutput: arguments.contains('--json'),
      );
      return;
    }
    if (route == CodexCliCommandRoute.pluginConfiguration) {
      await _runPluginConfigurationCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.mcpStatus) {
      await _showMcpServerStatusCommand(
        zh: zh,
        jsonOutput: arguments.contains('--json'),
      );
      return;
    }
    if (route == CodexCliCommandRoute.mcpAdd) {
      await _addMcpServerCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.mcpRemove) {
      await _removeMcpServerCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.threadList) {
      await _showThreadListCommand(zh: zh, arguments: arguments);
      return;
    }
    if (route == CodexCliCommandRoute.appSessionUi) {
      final command = arguments.first.toLowerCase();
      final requestedThread =
          arguments.length == 2 && !arguments[1].startsWith('-')
          ? arguments[1].trim()
          : null;
      final currentThread = (_restoredHistory?.threadId ?? _lastThreadId)
          ?.trim();
      final isResume = command == 'resume' || command == 'r';
      final resumesCurrentThread =
          isResume &&
          (arguments.length == 1 ||
              (arguments.length == 2 && arguments[1] == '--last') ||
              (requestedThread != null && requestedThread == currentThread));
      if (resumesCurrentThread) {
        await _resumeSavedSession();
        return;
      }
      if (command == 'fork') {
        await _forkCurrentSession();
        return;
      }
      final message = switch (command) {
        'resume' || 'r' =>
          zh
              ? '只能在当前 app-owned session 中恢复已保存的 thread；其他 session 请从首页打开，避免跨 CODEX_HOME 导入导致并发会话互相影响。'
              : 'Only the saved thread belonging to this app session can be resumed here. Open another session from Home instead of importing across CODEX_HOME boundaries.',
        _ =>
          zh
              ? '归档、恢复归档和删除针对应用自己的 workspace/session 历史；请使用首页会话菜单，不运行未绑定的 CLI 会话库命令。'
              : 'Archive, unarchive, and delete operate on the app-owned workspace/session history. Use the Home session menu instead of an unbound CLI session-store command.',
      };
      _addStructuredTranscript(CodexTranscriptKind.system, message);
      _scheduleHistoryPersist();
      return;
    }
    if (route != CodexCliCommandRoute.execute) {
      final message = switch (route) {
        CodexCliCommandRoute.execute => '',
        CodexCliCommandRoute.mcpList => '',
        CodexCliCommandRoute.mcpGet => '',
        CodexCliCommandRoute.mcpStatus => '',
        CodexCliCommandRoute.mcpAdd => '',
        CodexCliCommandRoute.mcpRemove => '',
        CodexCliCommandRoute.appServerOwned =>
          zh ? 'app-server 由当前会话独占管理；请使用会话界面，不要另开未绑定的 server。' : 'The active session owns its app-server. Use the session UI instead of starting an unbound server.',
        CodexCliCommandRoute.accountSettings =>
          zh ? 'Codex 登录和退出请在应用“设置 → 账户”中操作，以保持 Android 登录状态一致。' : 'Sign in or out from Settings → Account so Android authentication state stays in sync.',
        CodexCliCommandRoute.updaterSettings =>
          zh ? '请从“设置 → 更新 Codex”更新 CLI；该流程会校验新版本并在失败时回滚。' : 'Update the CLI from Settings → Update Codex; that flow verifies the staged version and rolls back on failure.',
        CodexCliCommandRoute.appSessionUi =>
          zh ? '该命令访问的是独立 CLI 会话库，不是应用中的 workspace/session；请使用首页会话列表操作。' : 'This command targets the standalone CLI session store, not the app workspace/session list. Use the Home session actions.',
        CodexCliCommandRoute.appServerDaemon =>
          zh ? '该命令需要共享常驻 app-server；本应用为每个会话隔离进程，请直接使用当前会话界面。' : 'This command requires a shared persistent app-server. The app isolates one process per session; use the current session UI.',
        CodexCliCommandRoute.mcpAuthentication =>
          zh ? 'MCP OAuth 请从“设置 → MCP 与插件”进入；该一次性 CLI 命令不会改写当前应用 session。' : 'Start MCP OAuth from Settings → MCP & plugins; the one-shot CLI command does not update the app session.',
        CodexCliCommandRoute.threadList => '',
        CodexCliCommandRoute.pluginList => '',
        CodexCliCommandRoute.pluginMarketplaceList => '',
        CodexCliCommandRoute.mcpConfiguration =>
          zh ? 'MCP 配置已接入“设置 → MCP 与插件”；此一次性 CLI 命令不会改写当前应用 session，因此未执行。' : 'MCP configuration is available in Settings → MCP & plugins; this one-shot CLI command does not update the app session, so it was not run.',
        CodexCliCommandRoute.pluginConfiguration =>
          zh ? '插件市场的高级配置仍使用当前 session 的 /cli plugin 命令。' : 'Advanced plugin marketplace configuration remains available through /cli plugin in the current session.',
      };
      _addStructuredTranscript(CodexTranscriptKind.system, message);
      _scheduleHistoryPersist();
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在准备本地命令：$label' : 'Preparing local command: $label',
    );
    unawaited(_persistHistory());
    try {
      final invocation = await _resolveCodexInvocation(
        runtimeScope: _newRuntimeOperationScope('cli'),
      );
      if (invocation == null) return;
      if (_identity == ExecutionIdentity.root) {
        final assessment = RootAccessPolicy.assessCommand(
          '${invocation.command} ${arguments.join(' ')}',
        );
        final rootReadOnly = _codexSandbox == 'read-only';
        if (assessment.route == RootWriteRoute.denied ||
            (rootReadOnly && !assessment.readOnlyOperation)) {
          final reason = rootReadOnly && !assessment.readOnlyOperation
              ? (zh
                    ? '只读 Root 会话会拒绝可能产生写入或副作用的 CLI 命令。'
                    : 'Read-only Root sessions reject CLI commands that may write or cause side effects.')
              : assessment.reason;
          final message = zh
              ? 'Root CLI 命令已拦截：$reason'
              : 'Root CLI command blocked: $reason';
          _addStructuredTranscript(CodexTranscriptKind.error, message);
          unawaited(_persistHistory());
          return;
        }
        if (!await _confirmRootExecution('run the local Codex CLI command')) {
          _addStructuredTranscript(
            CodexTranscriptKind.status,
            zh ? '已取消本地命令。' : 'Local command cancelled.',
          );
          unawaited(_persistHistory());
          return;
        }
      }
      if (!mounted) return;
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        zh ? '正在执行本地命令：$label' : 'Running local command: $label',
      );
      final result = await _runOneShotCommand(
        invocation: invocation,
        arguments: arguments,
        timeout: timeout,
      );
      final output = result.output.trim();
      final detail = output.isEmpty
          ? (zh ? '退出码 ${result.exitCode}' : 'exit ${result.exitCode}')
          : output.length <= 6000
          ? output
          : '${output.substring(0, 5997)}…';
      _addStructuredTranscript(
        result.exitCode == 0
            ? CodexTranscriptKind.system
            : CodexTranscriptKind.error,
        result.exitCode == 0
            ? '$label\n$detail'
            : (zh ? '$label\n命令失败：$detail' : '$label\nCommand failed: $detail'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      final message = error is BackendException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '本地命令失败：$message' : 'Local command failed: $message',
      );
      _showError(message);
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMcpServerCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    final isGet = arguments.length > 1 && arguments[1].toLowerCase() == 'get';
    final serverName = isGet && arguments.length > 2 ? arguments[2] : null;
    final jsonOutput = arguments.contains('--json');
    if (isGet && (serverName == null || serverName.startsWith('-'))) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '用法：/cli mcp get <服务器名> [--json]'
            : 'Usage: /cli mcp get <name> [--json]',
      );
      unawaited(_persistHistory());
      return;
    }

    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh ? '当前会话没有可读取的本地 Codex MCP 配置。' : 'The current session has no local Codex MCP configuration to read.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在读取当前会话的 MCP 配置…' : 'Reading MCP config for this session…',
    );
    unawaited(_persistHistory());
    try {
      final servers = await client.readMcpServers();
      if (!mounted) return;
      final selected = isGet
          ? servers.where((server) => server.name == serverName).toList()
          : servers;
      if (isGet && selected.isEmpty) {
        _addStructuredTranscript(
          CodexTranscriptKind.error,
          zh
              ? '当前会话未配置 MCP 服务器“$serverName”。'
              : 'No MCP server named "$serverName" is configured for this session.',
        );
        unawaited(_persistHistory());
        return;
      }
      final output = jsonOutput
          ? const JsonEncoder.withIndent('  ').convert(
              isGet
                  ? selected.single.toSafeJsonMap()
                  : selected
                        .map((server) => server.toSafeJsonMap())
                        .toList(growable: false),
            )
          : isGet
          ? selected.single.displayLine(chinese: zh)
          : selected.isEmpty
          ? (zh ? '未配置 MCP 服务器。' : 'No MCP servers configured.')
          : selected
                .map((server) => server.displayLine(chinese: zh))
                .join('\n');
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        jsonOutput
            ? output
            : isGet
            ? (zh ? 'MCP 服务器：\n$output' : 'MCP server:\n$output')
            : (zh
                  ? '当前会话的 MCP 服务器：\n$output'
                  : 'MCP servers for this session:\n$output'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '读取 MCP 配置失败：$message' : 'Could not read MCP config: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showLoginStatusCommand({required bool zh}) async {
    if (!mounted) return;
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在读取 Codex 登录状态…' : 'Reading Codex login status…',
    );
    unawaited(_persistHistory());

    await _checkAuthStatus();
    if (!mounted) return;

    final status = _authStatus;
    final error = _error;
    if (status != null && status.trim().isNotEmpty) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh ? 'Codex 登录状态：$status' : 'Codex login status: $status',
      );
    } else if (error != null && error.trim().isNotEmpty) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '读取 Codex 登录状态失败：$error'
            : 'Could not read Codex login status: $error',
      );
    } else {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh ? '未读取到 Codex 登录状态；请在设置 → 账户中重试。' : 'Codex login status was not returned; retry from Settings → Account.',
      );
    }
    unawaited(_persistHistory());
  }

  Future<void> _showThreadListCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    late final CodexThreadListRequest request;
    try {
      request = CodexThreadListRequest.parse(arguments);
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? 'thread 列表命令无效：${error.message}'
            : 'Invalid thread list command: ${error.message}',
      );
      unawaited(_persistHistory());
      return;
    }
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可读取的本地 Codex thread 列表。'
            : 'The current session has no local Codex thread list to read.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      request.archived
          ? (zh ? '正在读取已归档 thread…' : 'Reading archived threads…')
          : (zh ? '正在读取当前 thread 列表…' : 'Reading current threads…'),
    );
    unawaited(_persistHistory());
    try {
      final threads = await client.readThreads(
        archived: request.archived,
        searchTerm: request.searchTerm,
      );
      if (!mounted) return;
      final output = request.jsonOutput
          ? const JsonEncoder.withIndent(
              '  ',
            ).convert(threads.map((thread) => thread.toSafeJsonMap()).toList())
          : threads.isEmpty
          ? (zh ? '未发现 thread。' : 'No threads found.')
          : threads.map((thread) => thread.displayLine(chinese: zh)).join('\n');
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        request.jsonOutput
            ? output
            : (zh
                  ? '当前会话的 thread（${threads.length}）：\n$output'
                  : 'Threads in the current session (${threads.length}):\n$output'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '读取 thread 列表失败：$message' : 'Could not read thread list: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showPluginListCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    late final CodexPluginListRequest request;
    try {
      request = CodexPluginListRequest.parse(arguments);
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '插件列表命令无效：${error.message}'
            : 'Invalid plugin list command: ${error.message}',
      );
      unawaited(_persistHistory());
      return;
    }
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可读取的本地 Codex 插件列表。'
            : 'The current session has no local Codex plugin list to read.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在读取当前会话的插件列表…' : 'Reading plugins for this session…',
    );
    unawaited(_persistHistory());
    try {
      final allPlugins = await client.readPlugins(
        forceRefetch: request.available,
      );
      final plugins = allPlugins
          .where(
            (plugin) =>
                (request.marketplaceName == null ||
                    plugin.marketplaceName == request.marketplaceName) &&
                (request.available || plugin.installed),
          )
          .toList(growable: false);
      if (!mounted) return;
      final output = request.jsonOutput
          ? const JsonEncoder.withIndent('  ').convert(
              plugins
                  .map((plugin) => plugin.toSafeJsonMap())
                  .toList(growable: false),
            )
          : plugins.isEmpty
          ? (zh ? '未发现插件。' : 'No plugins found.')
          : plugins.map((plugin) => plugin.displayLine(chinese: zh)).join('\n');
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        request.jsonOutput
            ? output
            : (zh ? '当前会话的插件：\n$output' : 'Plugins for this session:\n$output'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '读取插件列表失败：$message' : 'Could not read plugin list: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showPluginMarketplaceListCommand({
    required bool zh,
    required bool jsonOutput,
  }) async {
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可读取的本地 Codex 插件市场。'
            : 'The current session has no local Codex marketplace list.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final plugins = await client.readPlugins();
      final byMarketplace = <String, List<CodexPluginSummary>>{};
      for (final plugin in plugins) {
        byMarketplace.putIfAbsent(plugin.marketplaceName, () => []).add(plugin);
      }
      final output = jsonOutput
          ? const JsonEncoder.withIndent('  ').convert(
              byMarketplace.entries
                  .map(
                    (entry) => <String, Object?>{
                      'name': entry.key,
                      'pluginCount': entry.value.length,
                      'installedCount': entry.value
                          .where((plugin) => plugin.installed)
                          .length,
                    },
                  )
                  .toList(growable: false),
            )
          : byMarketplace.isEmpty
          ? (zh ? '未发现插件市场。' : 'No plugin marketplaces found.')
          : byMarketplace.entries
                .map(
                  (entry) =>
                      '${entry.key} · ${entry.value.length} '
                      '${zh ? '个插件' : 'plugins'}',
                )
                .join('\n');
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        jsonOutput
            ? output
            : (zh ? '当前插件市场：\n$output' : 'Plugin marketplaces:\n$output'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '读取插件市场失败：$message'
            : 'Could not read plugin marketplaces: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _runPluginConfigurationCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可修改的本地 Codex 插件配置。'
            : 'The current session has no local Codex plugin configuration.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_codexSandbox == 'read-only') {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '只读会话不能修改插件或插件市场。'
            : 'A read-only session cannot change plugins or marketplaces.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('modify Codex plugins or marketplaces')) {
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        zh ? '已取消插件配置操作。' : 'Plugin configuration operation cancelled.',
      );
      unawaited(_persistHistory());
      return;
    }

    late final Object operation;
    try {
      if (arguments.length > 1 && arguments[1].toLowerCase() == 'add') {
        operation = CodexPluginInstallRequest.parse(arguments);
      } else if (arguments.length > 1 &&
          arguments[1].toLowerCase() == 'remove') {
        operation = CodexPluginRemoveRequest.parse(arguments);
      } else if (arguments.length > 1 &&
          arguments[1].toLowerCase() == 'enable') {
        operation = CodexPluginToggleRequest.parse(arguments, enabled: true);
      } else if (arguments.length > 1 &&
          arguments[1].toLowerCase() == 'disable') {
        operation = CodexPluginToggleRequest.parse(arguments, enabled: false);
      } else if (arguments.length > 2 &&
          arguments[1].toLowerCase() == 'marketplace') {
        operation = switch (arguments[2].toLowerCase()) {
          'add' => CodexPluginMarketplaceAddRequest.parse(arguments),
          'remove' => CodexPluginMarketplaceRemoveRequest.parse(arguments),
          'upgrade' => CodexPluginMarketplaceUpgradeRequest.parse(arguments),
          _ => throw FormatException(
            zh
                ? '不支持的插件市场操作：${arguments[2]}'
                : 'Unsupported plugin marketplace operation: ${arguments[2]}',
          ),
        };
      } else {
        throw const FormatException(
          'Usage: plugin add/remove/enable/disable or plugin marketplace add/remove/upgrade.',
        );
      }
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '插件配置命令无效：${error.message}'
            : 'Invalid plugin command: ${error.message}',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    try {
      late final Map<String, dynamic> response;
      late final bool jsonOutput;
      late final String description;
      late final Map<String, Object?> safeResult;
      switch (operation) {
        case CodexPluginInstallRequest request:
          response = await client.installPlugin(request);
          jsonOutput = request.jsonOutput;
          description = zh
              ? '已安装插件 ${request.pluginName}@${request.marketplaceName}'
              : 'Installed plugin ${request.pluginName}@${request.marketplaceName}';
          safeResult = <String, Object?>{
            'operation': 'plugin.add',
            'plugin': '${request.pluginName}@${request.marketplaceName}',
            'authPolicy': response['authPolicy'],
            'appsNeedingAuth': response['appsNeedingAuth'] is List
                ? (response['appsNeedingAuth'] as List).length
                : 0,
          };
        case CodexPluginRemoveRequest request:
          response = await client.uninstallPlugin(request.pluginId);
          jsonOutput = request.jsonOutput;
          description = zh
              ? '已卸载插件 ${request.pluginId}'
              : 'Uninstalled plugin ${request.pluginId}';
          safeResult = <String, Object?>{
            'operation': 'plugin.remove',
            'plugin': request.pluginId,
            'removed': true,
          };
        case CodexPluginToggleRequest request:
          response = await client.setPluginEnabled(
            request.pluginId,
            request.enabled,
          );
          jsonOutput = request.jsonOutput;
          description = request.enabled
              ? (zh
                    ? '已启用插件 ${request.pluginId}'
                    : 'Enabled plugin ${request.pluginId}')
              : (zh
                    ? '已停用插件 ${request.pluginId}'
                    : 'Disabled plugin ${request.pluginId}');
          safeResult = <String, Object?>{
            'operation': request.enabled ? 'plugin.enable' : 'plugin.disable',
            'plugin': request.pluginId,
            'enabled': request.enabled,
            'status': response['status'],
          };
        case CodexPluginMarketplaceAddRequest request:
          response = await client.addPluginMarketplace(request);
          jsonOutput = request.jsonOutput;
          final name =
              response['marketplaceName']?.toString() ?? request.source;
          description = zh ? '已添加插件市场 $name' : 'Added plugin marketplace $name';
          safeResult = <String, Object?>{
            'operation': 'plugin.marketplace.add',
            'marketplaceName': response['marketplaceName'] ?? name,
            'alreadyAdded': response['alreadyAdded'] == true,
          };
        case CodexPluginMarketplaceRemoveRequest request:
          response = await client.removePluginMarketplace(
            request.marketplaceName,
          );
          jsonOutput = request.jsonOutput;
          description = zh
              ? '已移除插件市场 ${request.marketplaceName}'
              : 'Removed plugin marketplace ${request.marketplaceName}';
          safeResult = <String, Object?>{
            'operation': 'plugin.marketplace.remove',
            'marketplaceName': request.marketplaceName,
            'removed': true,
          };
        case CodexPluginMarketplaceUpgradeRequest request:
          response = await client.upgradePluginMarketplace(
            request.marketplaceName,
          );
          jsonOutput = request.jsonOutput;
          final errors = response['errors'] is List
              ? response['errors'] as List
              : const <Object?>[];
          description = zh
              ? '插件市场刷新完成：${errors.isEmpty ? '无错误' : '${errors.length} 个错误'}'
              : 'Plugin marketplace refresh completed: ${errors.isEmpty ? 'no errors' : '${errors.length} error(s)'}';
          safeResult = <String, Object?>{
            'operation': 'plugin.marketplace.upgrade',
            if (request.marketplaceName != null)
              'marketplaceName': request.marketplaceName,
            'selectedCount': response['selectedMarketplaces'] is List
                ? (response['selectedMarketplaces'] as List).length
                : 0,
            'upgradedCount': response['upgradedRoots'] is List
                ? (response['upgradedRoots'] as List).length
                : 0,
            'errors': errors
                .whereType<Map>()
                .map(
                  (error) => <String, Object?>{
                    'marketplaceName': error['marketplaceName'],
                    'message': error['message'],
                  },
                )
                .toList(growable: false),
          };
      }
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        jsonOutput
            ? const JsonEncoder.withIndent('  ').convert(safeResult)
            : description,
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '插件配置失败：$message' : 'Plugin configuration failed: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removeMcpServerCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    final serverName = arguments.length == 3 ? arguments[2] : null;
    if (serverName == null ||
        serverName.startsWith('-') ||
        serverName.trim().isEmpty) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '用法：/cli mcp remove <服务器名>' : 'Usage: /cli mcp remove <name>',
      );
      unawaited(_persistHistory());
      return;
    }

    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可修改的本地 Codex MCP 配置。'
            : 'The current session has no local Codex MCP config to modify.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh
          ? '正在从当前会话配置中移除 MCP 服务器…'
          : 'Removing the MCP server from this session config…',
    );
    unawaited(_persistHistory());
    try {
      await client.removeMcpServer(serverName);
      if (!mounted) return;
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '已从当前 Codex 会话配置中移除 MCP 服务器“$serverName”；其他会话不受影响。'
            : 'Removed MCP server "$serverName" from this Codex session config; other sessions are unchanged.',
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException
          ? error.message
          : (zh ? 'MCP 配置更新失败。' : 'MCP config update failed.');
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '移除 MCP 服务器失败：$message' : 'Could not remove MCP server: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addMcpServerCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    late final CodexMcpAddRequest request;
    try {
      request = CodexMcpAddRequest.parse(arguments);
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? 'MCP 添加命令无效：${error.message}\n用法：/cli mcp add <名称> -- <命令> [参数…]，或 /cli mcp add <名称> --url <HTTP(S) 地址> [--bearer-token-env-var 环境变量名]。'
            : 'Invalid MCP add command: ${error.message}\nUsage: /cli mcp add <name> -- <command> [args…], or /cli mcp add <name> --url <HTTP(S) URL> [--bearer-token-env-var ENV].',
      );
      unawaited(_persistHistory());
      return;
    }

    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可修改的本地 Codex MCP 配置。'
            : 'The current session has no local Codex MCP config to modify.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_codexSandbox == 'read-only') {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '只读会话不能添加 MCP 配置。'
            : 'A read-only session cannot add MCP configuration.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'add MCP server "${request.name}" to this session',
        )) {
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        zh ? '已取消添加 MCP 服务器。' : 'MCP server addition cancelled.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh
          ? '正在添加 MCP 服务器“${request.name}”…'
          : 'Adding MCP server "${request.name}"…',
    );
    unawaited(_persistHistory());
    try {
      await client.addMcpServer(request);
      if (!mounted) return;
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '已将 MCP 服务器“${request.name}”添加到当前 session 的本地 Codex 配置；其他 session 不受影响。'
            : 'Added MCP server "${request.name}" to this session’s local Codex config; other sessions are unchanged.',
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException
          ? error.message
          : (zh ? 'MCP 配置更新失败。' : 'MCP config update failed.');
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '添加 MCP 服务器失败：$message' : 'Could not add MCP server: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMcpOAuthLoginCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    late final CodexMcpLoginRequest request;
    try {
      request = CodexMcpLoginRequest.parse(arguments);
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? 'MCP 登录命令无效：${error.message}\n用法：/cli mcp login <服务器名>'
            : 'Invalid MCP login command: ${error.message}\nUsage: /cli mcp login <server-name>',
      );
      unawaited(_persistHistory());
      return;
    }

    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可执行 MCP OAuth 的本地 Codex app-server。'
            : 'This session has no local Codex app-server for MCP OAuth.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_codexSandbox == 'read-only') {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '只读会话不能写入 MCP 登录凭据。'
            : 'A read-only session cannot write MCP login credentials.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'authenticate with MCP server "${request.name}"',
        )) {
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        zh ? '已取消 MCP 登录。' : 'MCP login was canceled.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh
          ? '正在为 MCP 服务器“${request.name}”准备登录…'
          : 'Preparing sign-in for MCP server "${request.name}"…',
    );
    unawaited(_persistHistory());
    try {
      final authorizationUrl = await client.beginMcpOAuthLogin(request.name);
      if (!mounted) return;
      final opened = await _openAuthUrlValue(
        authorizationUrl.toString(),
        showFailure: false,
      );
      if (opened) {
        _addStructuredTranscript(
          CodexTranscriptKind.status,
          zh ? '已打开系统浏览器；完成授权后，此会话会自动更新 MCP 登录状态。' : 'The browser is open. This session will update MCP login status after authorization.',
        );
      } else {
        await Clipboard.setData(
          ClipboardData(text: authorizationUrl.toString()),
        );
        _addStructuredTranscript(
          CodexTranscriptKind.system,
          zh ? '无法打开浏览器，授权链接已复制到剪贴板。' : 'Could not open the browser; the authorization link was copied to the clipboard.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(zh ? '授权链接已复制' : 'Authorization link copied'),
              ),
            );
        }
      }
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is CodexSessionException
          ? error.message
          : (zh ? '无法启动 MCP OAuth 登录。' : 'Could not start MCP OAuth login.');
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? 'MCP 登录失败：$message' : 'MCP login failed: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMcpOAuthLogoutCommand({
    required bool zh,
    required List<String> arguments,
  }) async {
    late final CodexMcpLogoutRequest request;
    try {
      request = CodexMcpLogoutRequest.parse(arguments);
    } on FormatException catch (error) {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? 'MCP 登出命令无效：${error.message}\n用法：/cli mcp logout <服务器名>'
            : 'Invalid MCP logout command: ${error.message}\nUsage: /cli mcp logout <server-name>',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_codexSandbox == 'read-only') {
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh
            ? '只读会话不能删除 MCP 登录凭据。'
            : 'A read-only session cannot remove MCP login credentials.',
      );
      unawaited(_persistHistory());
      return;
    }
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'remove MCP credentials for server "${request.name}"',
        )) {
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        zh ? '已取消 MCP 登出。' : 'MCP logout was canceled.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh
          ? '正在移除 MCP 服务器“${request.name}”的登录凭据…'
          : 'Removing MCP login credentials for "${request.name}"…',
    );
    unawaited(_persistHistory());
    try {
      final invocation = await _resolveCodexInvocation(
        runtimeScope: _runtimeSessionKey(),
      );
      if (invocation == null) return;
      final result = await _runOneShotCommand(
        invocation: invocation,
        arguments: <String>['mcp', 'logout', request.name],
        timeout: const Duration(seconds: 30),
      );
      final output = result.output.trim();
      final detail = output.isEmpty
          ? (zh ? '退出码 ${result.exitCode}' : 'exit ${result.exitCode}')
          : output.length <= 4000
          ? output
          : '${output.substring(0, 3997)}…';
      _addStructuredTranscript(
        result.exitCode == 0
            ? CodexTranscriptKind.system
            : CodexTranscriptKind.error,
        result.exitCode == 0
            ? (zh
                  ? '已移除 MCP 服务器“${request.name}”的登录凭据。\n$detail'
                  : 'Removed MCP login credentials for "${request.name}".\n$detail')
            : (zh ? 'MCP 登出失败：$detail' : 'MCP logout failed: $detail'),
      );
      unawaited(_persistHistory());
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is BackendException ? error.message : '$error';
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? 'MCP 登出失败：$message' : 'MCP logout failed: $message',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMcpServerStatusCommand({
    required bool zh,
    required bool jsonOutput,
  }) async {
    final client = _client;
    if (client is! CodexSessionClient) {
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        zh
            ? '当前会话没有可查询状态的本地 Codex MCP 服务。'
            : 'This session has no local Codex MCP servers to query.',
      );
      unawaited(_persistHistory());
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);
    _addStructuredTranscript(
      CodexTranscriptKind.status,
      zh ? '正在查询当前会话的 MCP 连接状态…' : 'Checking MCP status for this session…',
    );
    unawaited(_persistHistory());
    try {
      final statuses = await client.readMcpServerStatuses();
      if (!mounted) return;
      final output = jsonOutput
          ? const JsonEncoder.withIndent('  ').convert(
              statuses
                  .map((status) => status.toSafeJsonMap())
                  .toList(growable: false),
            )
          : statuses.isEmpty
          ? (zh ? '未配置 MCP 服务器。' : 'No MCP servers configured.')
          : statuses
                .map((status) => status.displayLine(chinese: zh))
                .join('\n');
      _addStructuredTranscript(
        CodexTranscriptKind.system,
        jsonOutput
            ? output
            : (zh ? 'MCP 实时状态：\n$output' : 'Live MCP status:\n$output'),
      );
      unawaited(_persistHistory());
    } on Object {
      if (!mounted) return;
      _addStructuredTranscript(
        CodexTranscriptKind.error,
        zh ? '无法读取 MCP 实时状态；请检查本地 Codex app-server 和 MCP 配置。' : 'Could not read live MCP status. Check the local Codex app-server and MCP configuration.',
      );
      unawaited(_persistHistory());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showPermissionsPicker() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final isRoot = _identity == ExecutionIdentity.root;
    final client = _client;
    var serverProfiles = const <CodexPermissionProfileSummary>[];
    var profilesLoading = client is CodexSessionClient;
    var profilesLoadStarted = false;
    var profilesUnavailable = false;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (client is CodexSessionClient && !profilesLoadStarted) {
            profilesLoadStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(() async {
                try {
                  final profiles = await client.readPermissionProfiles();
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    serverProfiles = profiles;
                    profilesLoading = false;
                    profilesUnavailable = false;
                  });
                } on Object {
                  if (!sheetContext.mounted) return;
                  setSheetState(() {
                    profilesLoading = false;
                    profilesUnavailable = true;
                  });
                }
              }());
            });
          }

          final customProfileOptions = serverProfiles
              .where((profile) => profile.allowed && !profile.isBuiltIn)
              .map(
                (profile) => (
                  'profile:${profile.id}',
                  zh
                      ? 'CLI 配置：${profile.id}${profile.description == null ? '' : ' · ${profile.description}'}'
                      : 'CLI profile: ${profile.id}${profile.description == null ? '' : ' · ${profile.description}'}',
                ),
              )
              .toList(growable: false);
          final options = isRoot
              ? <(String, String)>[
                  (
                    'default',
                    zh ? 'Root 常规：完整宿主可见性；普通命令不逐条询问' : 'Root normal: full host visibility; ordinary commands do not ask one by one',
                  ),
                  (
                    'full',
                    zh
                        ? '完全访问：danger-full-access + 不询问'
                        : 'Full access: danger-full-access + no approval',
                  ),
                  (
                    'read-only',
                    zh
                        ? '只读（应用级）：拒绝 Codex 写入请求'
                        : 'Read-only (app-enforced): deny Codex write requests',
                  ),
                ]
              : <(String, String)>[
                  (
                    'default',
                    zh
                        ? '默认：工具需要权限时询问'
                        : 'Default: ask when a tool needs approval',
                  ),
                  (
                    'full',
                    zh
                        ? '完全访问：danger-full-access + 不询问'
                        : 'Full access: danger-full-access + no approval',
                  ),
                  (
                    'read-only',
                    zh ? '只读：不允许工作区写入' : 'Read only: no workspace writes',
                  ),
                ];

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(
                    isRoot
                        ? (zh ? 'Root 写入策略' : 'Root write policy')
                        : (zh ? '权限级别' : 'Permission level'),
                  ),
                  subtitle: Text(
                    isRoot
                        ? (zh
                              ? '选择本 session 的常态权限级别；普通 Root 命令无需逐条审批。'
                              : 'Choose this session’s default access level; ordinary Root commands do not require per-command approval.')
                        : (zh
                              ? '选择将应用于下一次 Codex turn。'
                              : 'The selection applies to the next Codex turn.'),
                  ),
                ),
                if (profilesLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LinearProgressIndicator(
                      semanticsLabel: zh
                          ? '读取 CLI 权限配置'
                          : 'Loading CLI profiles',
                    ),
                  ),
                for (final item in options)
                  ListTile(
                    title: Text(item.$2),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(item.$1),
                  ),
                if (isRoot)
                  ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text(
                      zh ? 'Root 目标软路由' : 'Root target-aware soft routing',
                    ),
                    subtitle: Text(
                      zh
                          ? 'RootAccessPolicy 是应用层提示与软路由，不是内核写隔离；启动链目标仍应先验证目标、恢复路径并取得具体授权。'
                          : 'RootAccessPolicy is app-side guidance and soft routing, not kernel write isolation; verify boot targets and recovery paths and obtain concrete authorization.',
                    ),
                  ),
                if (customProfileOptions.isNotEmpty)
                  ListTile(
                    title: Text(zh ? 'Codex CLI 配置' : 'Codex CLI profiles'),
                    subtitle: Text(
                      zh ? '以下选项来自当前 app-server 的 permissionProfile/list。' : 'These options come from permissionProfile/list on the active app-server.',
                    ),
                  ),
                if (profilesUnavailable)
                  ListTile(
                    title: Text(
                      zh ? 'CLI 配置暂不可用；内置权限选项仍可正常使用。' : 'CLI profiles are unavailable; built-in permission options remain available.',
                    ),
                  ),
                for (final item in customProfileOptions)
                  ListTile(
                    title: Text(item.$2),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(item.$1),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.startsWith('profile:')) {
      final profileId = selected.substring('profile:'.length);
      final lower = profileId.toLowerCase();
      final sandbox = lower.contains('read')
          ? 'read-only'
          : (lower.contains('full') || lower.contains('danger')
                ? 'danger-full-access'
                : _codexSandbox);
      updateCodexSettings(permissions: profileId, sandbox: sandbox);
      return;
    }
    switch (selected) {
      case 'full':
        updateCodexSettings(
          approvalPolicy: 'never',
          sandbox: 'danger-full-access',
          permissions: ':danger-full-access',
        );
        return;
      case 'read-only':
        updateCodexSettings(
          approvalPolicy: 'on-request',
          sandbox: 'read-only',
          permissions: ':read-only',
        );
        return;
      default:
        updateCodexSettings(
          approvalPolicy: isRoot ? 'never' : 'on-request',
          sandbox: isRoot ? 'danger-full-access' : 'workspace-write',
          permissions: isRoot ? ':danger-full-access' : ':workspace',
        );
        return;
    }
  }

  Future<void> _drainQueuedPrompt() async {
    if (_busy ||
        _turnActive ||
        _sending ||
        _approval != null ||
        _client == null) {
      return;
    }
    if (_queuedPrompts.isEmpty) return;
    final prompt = _queuedPrompts.removeAt(0);
    final images = _queuedImageAttachments.isEmpty
        ? const <ImageAttachment>[]
        : _queuedImageAttachments.removeAt(0);
    if (mounted) setState(() {});
    _scheduleSnapshotPublish();
    unawaited(_persistHistory());
    await _sendPromptNow(prompt, images: images);
  }

  void _removeQueuedPrompt(int index) {
    if (index < 0 || index >= _queuedPrompts.length) return;
    setState(() {
      _queuedPrompts.removeAt(index);
      if (index < _queuedImageAttachments.length) {
        _queuedImageAttachments.removeAt(index);
      }
    });
    _publishSnapshot();
    unawaited(_persistHistory());
  }

  Future<void> _retryLastPrompt() async {
    if (_accountBindingStale) return;
    final prompt = _retryPrompt;
    final images = List<ImageAttachment>.unmodifiable(_retryImages);
    if (_client == null ||
        (prompt?.trim().isNotEmpty != true && images.isEmpty)) {
      return;
    }
    final retryText = prompt ?? '';
    _retryingPromptTranscript = retryText.trim().isEmpty
        ? '[图片 ${images.length} 张]'
        : retryText;
    try {
      await _sendPromptNow(retryText, images: images);
      await Future<void>.delayed(Duration.zero);
    } finally {
      if (_retryingPromptTranscript != null) {
        _retryingPromptTranscript = null;
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final selected = await LocalImagePicker().pickImages();
      if (!mounted || selected.isEmpty) return;
      setState(() {
        _attachedImages
          ..addAll(selected.take(4 - _attachedImages.length))
          ..removeRange(
            _attachedImages.length > 4 ? 4 : _attachedImages.length,
            _attachedImages.length,
          );
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '无法导入图片：所选文件为空或图片数据无效。请重新选择。'
                : 'Unable to import images: the selected file is empty or invalid. Please select again.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _clearAttachedImage([int? index]) {
    if (!mounted) return;
    setState(() {
      if (index == null) {
        _attachedImages.clear();
      } else if (index >= 0 && index < _attachedImages.length) {
        _attachedImages.removeAt(index);
      }
    });
  }

  Future<void> _interruptSession() async {
    final client = _client;
    if (client == null) {
      _addStructuredTranscript(
        CodexTranscriptKind.status,
        Localizations.localeOf(context).languageCode == 'zh'
            ? '当前没有正在运行的 turn。'
            : 'There is no active turn to interrupt.',
      );
      unawaited(_persistHistory());
      return;
    }
    try {
      await client.interrupt();
    } on CodexSessionException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _showSlashCommands() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final commands = <(String, String)>[
      ('/status', zh ? '显示本地会话状态' : 'Show the local session status'),
      ('/clear', zh ? '清空当前可见的会话记录' : 'Clear the visible local transcript'),
      ('/plan', zh ? '切换后续 turn 的计划模式' : 'Toggle plan mode for the next turn'),
      (
        '/permissions',
        zh ? '选择默认、只读或完全访问' : 'Choose default, read-only, or full access',
      ),
      ('/interrupt', zh ? '停止当前生成' : 'Interrupt the current turn'),
      (
        '/new',
        zh
            ? '在当前 session 中开始新对话'
            : 'Start a fresh conversation in this session',
      ),
      (
        '/model',
        zh
            ? '打开模型选择，或使用 /model <模型ID>'
            : 'Open the model picker or use /model <id>',
      ),
      (
        '/effort',
        zh
            ? '打开推理档位，或使用 /effort <档位>'
            : 'Open effort settings or use /effort <level>',
      ),
      (
        '/refresh-models',
        zh ? '从当前 CLI 刷新模型列表' : 'Refresh models from the installed CLI',
      ),
      (
        '/network-test',
        zh ? '检查本地 Codex 与网络连接' : 'Check local Codex and network connectivity',
      ),
      (
        '/compact',
        zh ? '请求压缩当前对话上下文' : 'Request context compaction for this thread',
      ),
      (
        '/cli-help',
        zh
            ? '运行 CLI --help 并显示命令帮助'
            : 'Run the installed CLI --help and show its commands',
      ),
      (
        '/cli <args>',
        zh
            ? '运行非交互式 Codex CLI 命令'
            : 'Run a non-interactive installed Codex CLI command',
      ),
      (
        '/exec <argv>',
        zh ? '通过当前 app-server 执行 argv 命令，不启动第二个 Codex' : 'Run argv through the active app-server without a second Codex process',
      ),
      (
        '/exec --tty <argv>',
        zh
            ? '打开当前 session 的交互式 PTY'
            : 'Open an interactive PTY in the active session',
      ),
      ('/version', zh ? '显示已安装 CLI 版本' : 'Show the installed CLI version'),
      ('/help', zh ? '显示本地会话命令' : 'Show local session commands'),
    ];
    final command = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(zh ? '会话命令' : 'Session commands'),
              subtitle: Text(
                zh ? '选择后会填入输入框；按发送执行。' : 'Selecting a command fills the composer; press send to run it.',
              ),
            ),
            for (final item in commands)
              ListTile(
                leading: const Icon(Icons.chevron_right),
                title: Text(item.$1),
                subtitle: Text(item.$2),
                onTap: () => Navigator.of(context).pop(item.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || command == null) return;
    _promptController.text = command;
    _promptController.selection = TextSelection.collapsed(
      offset: _promptController.text.length,
    );
  }

  void _insertMention() {
    final selection = _promptController.selection;
    final cursor = selection.isValid && selection.baseOffset >= 0
        ? selection.baseOffset
        : _promptController.text.length;
    final value = _promptController.text;
    _promptController.text =
        '${value.substring(0, cursor)}@${value.substring(cursor)}';
    _promptController.selection = TextSelection.collapsed(offset: cursor + 1);
  }

  Future<void> _showPromptHistory() async {
    if (_promptHistory.isEmpty) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '当前会话没有历史提示词。' : 'No prompt history in this local session.',
          ),
        ),
      );
      return;
    }
    final prompt = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _promptHistory.length,
          itemBuilder: (context, index) => ListTile(
            leading: const Icon(Icons.history),
            title: Text(
              _promptHistory[index],
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).pop(_promptHistory[index]),
          ),
        ),
      ),
    );
    if (!mounted || prompt == null) return;
    _promptController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
  }

  Future<void> _openCustomProviderEffortSettings() async {
    final provider = _customProvider;
    if (provider == null) return;
    await showCcpocketNativeProviderEffortSettings(
      context: context,
      model: provider.model,
      effort: _codexEffort,
      onEffortChanged: (effort) => updateCodexSettings(effort: effort),
    );
  }

  Future<void> _openSessionSettings() async {
    final customProvider = _customProvider;
    await showCcpocketNativeCodexSettings(
      context: context,
      model: _codexModel,
      effort: _codexEffort,
      models: customProvider == null
          ? const <CodexModelDescriptor>[]
          : _modelCatalogForProvider(customProvider).models,
      // Present the CC Pocket sheet immediately. Runtime discovery and CLI
      // model enumeration run after its first frame; opening a small menu must
      // never block behind a slow Android/PRoot process start.
      loadModelCatalog: customProvider == null ? () => modelCatalog : null,
      onModelChanged: (model) {
        updateCodexSettings(model: model);
      },
      onEffortChanged: (effort) {
        final settings = CodexTurnSettings(
          model: _codexModel,
          reasoningEffort: effort,
          approvalPolicy: _codexApprovalPolicy,
          sandbox: _codexSandbox,
          permissions: _codexPermissions,
          collaborationMode: _planMode ? 'plan' : 'default',
        );
        setState(() => _codexEffort = effort);
        final client = _client;
        if (client is CodexSessionClient) {
          client.updateSettings(settings);
        }
        unawaited(_persistHistory());
      },
    );
  }

  void _notifyAuthRevision() {
    _authRevision.value++;
  }

  Future<void> _checkAuthStatus({
    bool allowFallback = true,
    bool settleAfterLogin = false,
  }) async {
    if (_busy || _authClient != null) return;
    final invocation = await _resolveCodexInvocation();
    if (invocation == null) return;
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('read Codex login status')) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _authStatus = null;
      _authLoginStatus = null;
    });
    _notifyAuthRevision();
    try {
      var summary = 'Login status checked (details redacted)';
      var statusOutput = '';
      // Codex emits account/login/completed before the surrounding process is
      // torn down. Give its credential writer a short settle window before a
      // status probe, otherwise a successful login can briefly look like the
      // previous unauthenticated state on Android's slower storage.
      // A successful login can briefly race credential persistence, but an
      // invalid API key must not leave Settings disabled for the old six
      // attempts x 15 seconds path. Keep the post-login settle probe bounded
      // while retaining a single retry for slower Android storage.
      final maxAttempts = settleAfterLogin ? 2 : 1;
      final statusTimeout = settleAfterLogin
          ? const Duration(seconds: 8)
          : const Duration(seconds: 15);
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final result = await _runOneShotCommand(
          invocation: invocation,
          arguments: const <String>['login', 'status'],
          timeout: statusTimeout,
        );
        statusOutput = result.output;
        summary = summarizeAuthStatus(
          output: result.output,
          exitCode: result.exitCode,
        );
        if (!settleAfterLogin || summary != 'Not logged in') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (settleAfterLogin && summary == 'Logged in') {
        // A completed login may replace the account behind every existing
        // session. Advance the binding before the settings page publishes its
        // final status so old pages stop attempting reconnects immediately.
        await AuthBindingStore.advance();
        _modelCatalogFuture = null;
      }
      if (mounted) {
        final authMode = summarizeAuthMode(output: statusOutput);
        setState(() {
          _authStatus = summary;
          if (summary == 'Logged in') {
            _authMode = switch (authMode) {
              'api-key' => CodexAuthMode.apiKey,
              'chatgpt' => CodexAuthMode.browser,
              _ => _authMode,
            };
          }
        });
        if (mounted) _notifyAuthRevision();
      }
    } on BackendException catch (error) {
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback(
          reason: error.toString(),
        );
        if (switched) {
          if (mounted) {
            setState(() => _busy = false);
            _notifyAuthRevision();
          }
          await _checkAuthStatus(allowFallback: false);
          return;
        }
      }
      _showError(error.message);
    } catch (error) {
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback();
        if (switched) {
          if (mounted) {
            setState(() => _busy = false);
            _notifyAuthRevision();
          }
          await _checkAuthStatus(allowFallback: false);
          return;
        }
      }
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (mounted) _notifyAuthRevision();
      }
    }
  }

  Future<void> _logout() async {
    if (_busy || _authClient != null) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(zh ? '退出 Codex 登录？' : 'Log out of Codex?'),
            content: Text(
              zh
                  ? '这会从选定的运行时中移除 Codex 登录状态，不会删除工作区文件或本地会话历史。'
                  : 'This removes the Codex login state from the selected runtime. '
                        'It does not delete workspace files or local session history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(zh ? '退出登录' : 'Log out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final invocation = await _resolveCodexInvocation();
    if (invocation == null) return;
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution('log out of Codex')) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _authStatus = null;
    });
    _notifyAuthRevision();
    try {
      final result = await _runOneShotCommand(
        invocation: invocation,
        arguments: const <String>['logout'],
        timeout: const Duration(seconds: 30),
      );
      if (mounted) {
        setState(
          () => _authStatus = summarizeAuthLogout(exitCode: result.exitCode),
        );
        if (result.exitCode == 0) {
          await AuthBindingStore.advance();
          _modelCatalogFuture = null;
        }
        if (mounted) _notifyAuthRevision();
      }
    } on BackendException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (mounted) _notifyAuthRevision();
      }
    }
  }

  Future<void> _startAuth({bool allowFallback = true}) async {
    if (_busy || _authClient != null) return;
    final apiKey = _authMode == CodexAuthMode.apiKey
        ? _apiKeyController.text.trim()
        : null;
    if (_authMode == CodexAuthMode.apiKey &&
        (apiKey == null || apiKey.isEmpty)) {
      _showError(
        _uiText(
          '请先输入 API key，再开始 API key 登录。',
          'Enter an API key before starting API key login.',
        ),
      );
      return;
    }
    final invocation = await _resolveCodexInvocation();
    if (invocation == null) return;
    if (_identity == ExecutionIdentity.root &&
        !await _confirmRootExecution(
          'start Codex ${_authMode.displayName.toLowerCase()}',
        )) {
      return;
    }

    // Authentication uses the shared base home while every conversation uses
    // its own seeded session home. It therefore must not stop the hidden
    // conversation owner merely because Settings is open or a login method is
    // being changed.
    // Codex rejects account/login/start while another external credential is
    // active. Settings presents this as a login-method switch, so clear the
    // existing login before starting the requested method.
    if (_authStatus == 'Logged in') {
      final cleared = await _clearAuthForLoginSwitch(invocation);
      if (!cleared) return;
    }

    _apiKeyController.clear();
    _autoOpenedAuthUrl = null;
    _openingAuthUrl = null;
    final CodexLoginClient client = _authMode == CodexAuthMode.browser
        ? CodexAuthClient(
            backend: _activeBackend,
            workspace: _activeWorkspace,
            command: invocation.command,
            identity: _identity,
            environment: invocation.environment,
          )
        : CodexCliAuthClient(
            backend: _activeBackend,
            workspace: _activeWorkspace,
            command: invocation.command,
            identity: _identity,
            environment: invocation.environment,
          );
    final subscription = client.events.listen(_handleAuthEvent);
    setState(() {
      _authClient = client;
      _authSubscription = subscription;
      _authChallenge = null;
      _authLoginStatus = _uiText(
        '正在启动 ${_authMode.displayName.toLowerCase()}…',
        'Starting ${_authMode.displayName.toLowerCase()}…',
      );
      _authStatus = null;
      _error = null;
      _busy = true;
    });
    _notifyAuthRevision();
    try {
      if (_usesForegroundService) {
        _authForegroundOwned = true;
        await SessionLifecycle.start();
      }
      await client.start(mode: _authMode, apiKey: apiKey);
    } on BackendException catch (error) {
      await _finishAuthClient(
        status: _uiText('登录无法启动。', 'Login could not start.'),
      );
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback();
        if (switched) {
          await _startAuth(allowFallback: false);
          return;
        }
      }
      _showError(error.message);
    } catch (error) {
      await _finishAuthClient(
        status: _uiText('登录无法启动。', 'Login could not start.'),
      );
      if (allowFallback &&
          !_usingFallback &&
          !_isCompatibility &&
          _shouldFallbackToCompatibility(error)) {
        final switched = await _activateCompatibilityFallback();
        if (switched) {
          await _startAuth(allowFallback: false);
          return;
        }
      }
      final message = error is StateError ? error.message : '$error';
      _showError(
        message is String && message.isNotEmpty
            ? message
            : 'Could not start the login process.',
      );
    }
  }

  Future<bool> _clearAuthForLoginSwitch(_CodexInvocation invocation) async {
    try {
      final result = await _runOneShotCommand(
        invocation: invocation,
        arguments: const <String>['logout'],
        timeout: const Duration(seconds: 30),
      );
      if (result.exitCode != 0) {
        _showError(
          _uiText(
            'Codex 未能清除现有登录状态，请在设置中退出登录后重试。',
            'Codex did not clear the existing login. '
                'Use Log out in Settings and try again.',
          ),
        );
        return false;
      }
      if (mounted) {
        setState(() {
          _authStatus = 'Logged out';
          _authLoginStatus = _uiText(
            '现有登录已清除，正在开始新的登录。',
            'Existing login cleared; starting a new login.',
          );
          _error = null;
        });
        await AuthBindingStore.advance();
        _modelCatalogFuture = null;
        if (mounted) _notifyAuthRevision();
      }
      return true;
    } on BackendException catch (error) {
      _showError(error.message);
      return false;
    } catch (error) {
      _showError('$error');
      return false;
    }
  }

  Future<void> _cancelAuth() async {
    if (_authClient == null) return;
    await _finishAuthClient(status: _uiText('登录已取消。', 'Login canceled.'));
  }

  void _handleAuthEvent(CodexAuthEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case CodexAuthEventType.status:
        setState(
          () => _authLoginStatus =
              event.message ??
              _uiText(
                '正在启动 ${_authMode.displayName.toLowerCase()}…',
                'Starting ${_authMode.displayName.toLowerCase()}…',
              ),
        );
        _notifyAuthRevision();
      case CodexAuthEventType.challenge:
        setState(() {
          _authChallenge = event.challenge;
          _authLoginStatus =
              event.message ??
              (_authMode == CodexAuthMode.browser
                  ? _uiText(
                      '浏览器授权等待完成。',
                      'Browser authorization is waiting for completion.',
                    )
                  : _uiText(
                      '设备授权等待完成。',
                      'Device authorization is waiting for completion.',
                    ));
        });
        _notifyAuthRevision();
        if (_authMode == CodexAuthMode.browser) {
          unawaited(_maybeOpenAuthUrl(event.challenge));
        }
      case CodexAuthEventType.error:
        setState(
          () => _error =
              event.message ?? _uiText('登录过程失败。', 'Login process failed.'),
        );
        _notifyAuthRevision();
        unawaited(_finishAuthClient(status: _uiText('登录失败。', 'Login failed.')));
      case CodexAuthEventType.exit:
        final status = event.exitCode == 0
            ? _uiText(
                '登录过程已完成；请检查登录状态。',
                'Login process completed; check login status.',
              )
            : _uiText('登录过程失败。', 'Login process failed.');
        unawaited(
          _finishAuthClient(status: status).then((_) {
            if (event.exitCode == 0 && mounted) {
              return _checkAuthStatus(settleAfterLogin: true);
            }
          }),
        );
      case CodexAuthEventType.stopped:
        unawaited(
          _finishAuthClient(status: _uiText('登录已取消。', 'Login canceled.')),
        );
    }
  }

  Future<void> _maybeOpenAuthUrl(CodexAuthChallenge? challenge) async {
    final value = challenge?.verificationUrl;
    if (value == null ||
        _authMode != CodexAuthMode.browser ||
        _autoOpenedAuthUrl == value ||
        _openingAuthUrl == value) {
      return;
    }
    _openingAuthUrl = value;
    try {
      final opened = await _openAuthUrlValue(value);
      if (opened) _autoOpenedAuthUrl = value;
    } finally {
      if (_openingAuthUrl == value) _openingAuthUrl = null;
    }
  }

  Future<bool> _openAuthUrlValue(
    String value, {
    bool showFailure = true,
  }) async {
    try {
      final opened = await const MethodChannel(
        'io.henry.codex/browser',
      ).invokeMethod<bool>('openExternalUrl', <String, String>{'url': value});
      return opened == true;
    } catch (_) {
      if (showFailure && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _uiText(
                  '无法打开浏览器，请手动复制已验证的 URL。',
                  'Could not open a browser. Copy the verified URL manually.',
                ),
              ),
            ),
          );
      }
      return false;
    }
  }

  Future<void> _openAuthUrl() async {
    final value = _authChallenge?.verificationUrl;
    if (value != null) await _openAuthUrlValue(value);
  }

  Future<void> _copyAuthCode() async {
    final value = _authChallenge?.oneTimeCode;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_uiText('代码已复制', 'Code copied'))));
  }

  Future<void> _finishAuthClient({String? status}) async {
    final subscription = _authSubscription;
    _authSubscription = null;
    final client = _authClient;
    _authClient = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _apiKeyController.clear();
        _authChallenge = null;
        if (status != null) {
          _authLoginStatus = status;
        }
      });
      _notifyAuthRevision();
    }
    final cancelFuture = subscription?.cancel();
    await client?.dispose();
    await cancelFuture;
    final foregroundOwned = _authForegroundOwned;
    _authForegroundOwned = false;
    if (foregroundOwned) await SessionLifecycle.stop();
  }

  void _commitStreaming() {
    final assistant = _streamingAssistantBuffer.toString();
    final thinking = _streamingThinkingBuffer.toString();
    if (thinking.trim().isNotEmpty) {
      _addStructuredTranscript(CodexTranscriptKind.reasoning, thinking);
    }
    if (assistant.trim().isNotEmpty) {
      _addStructuredTranscript(
        CodexTranscriptKind.assistant,
        assistant,
        model: _codexModel,
      );
    }
    _clearStreaming();
  }

  void _clearStreaming() {
    _streamingAssistantBuffer.clear();
    _streamingThinkingBuffer.clear();
    _streamingSnapshotDirty = false;
    if (_streamingSnapshot.value.assistant.isNotEmpty ||
        _streamingSnapshot.value.thinking.isNotEmpty) {
      _streamingSnapshot.value = const CcpocketNativeStreamingSnapshot();
    }
  }

  void _addStructuredTranscript(
    CodexTranscriptKind kind,
    String text, {
    String? id,
    String? model,
    String? toolName,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    final normalized = text.trimRight();
    if (normalized.isEmpty && kind != CodexTranscriptKind.status) return;
    final now = DateTime.now();
    final storedEntry = CodexTranscriptEntry(
      id: id?.trim().isNotEmpty == true
          ? id!.trim()
          : 'local-${now.microsecondsSinceEpoch}',
      kind: kind,
      text: normalized,
      timestamp: now,
      model: model ?? _codexModel,
      toolName: toolName,
      data: data,
    ).toStored();
    _transcript.add(storedEntry);
    _requestSessionFrameRefresh();
  }

  void _upsertToolTranscript(CodexSessionEvent event) {
    final rawItem = event.params?['item'];
    final itemData = rawItem is Map
        ? <String, dynamic>{
            for (final entry in rawItem.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : const <String, dynamic>{};
    final toolId = _firstTranscriptText(itemData, const [
      'toolUseId',
      'callId',
      'id',
    ]);
    final toolName = _firstTranscriptText(itemData, const [
      'toolName',
      'name',
      'type',
    ]);
    final text = event.text ?? '';
    final completed = event.method == 'item/completed';

    if (toolId == null || toolId.isEmpty) {
      _addStructuredTranscript(
        completed ? CodexTranscriptKind.toolResult : CodexTranscriptKind.tool,
        text,
        toolName: toolName,
        data: itemData,
      );
      return;
    }

    int? toolIndex;
    int? resultIndex;
    for (var index = 0; index < _transcript.length; index++) {
      final entry = CodexTranscriptEntry.fromStored(_transcript[index]);
      final sameItem =
          entry.id == toolId ||
          _firstTranscriptText(entry.data, const [
                'toolUseId',
                'callId',
                'id',
              ]) ==
              toolId;
      if (!sameItem) continue;
      if (entry.kind == CodexTranscriptKind.toolResult) {
        resultIndex = index;
      } else if (entry.kind == CodexTranscriptKind.tool) {
        toolIndex = index;
      }
    }

    if (completed) {
      final result = CodexTranscriptEntry(
        id: '$toolId-result',
        kind: CodexTranscriptKind.toolResult,
        text: text,
        timestamp: DateTime.now(),
        model: _codexModel,
        toolName: toolName,
        data: itemData,
      );
      if (resultIndex != null) {
        _transcript[resultIndex] = result.toStored();
      } else {
        final insertAt = toolIndex == null
            ? _transcript.length
            : toolIndex! + 1;
        _transcript.insert(insertAt, result.toStored());
      }
      return;
    }

    if (toolIndex != null) {
      final current = CodexTranscriptEntry.fromStored(_transcript[toolIndex]);
      final merged = <String, dynamic>{...current.data, ...itemData};
      _transcript[toolIndex] = current
          .copyWith(
            text: text,
            toolName: toolName ?? current.toolName,
            data: merged,
          )
          .toStored();
      return;
    }

    _addStructuredTranscript(
      CodexTranscriptKind.tool,
      text,
      id: toolId,
      toolName: toolName,
      data: itemData,
    );
  }

  String? _firstTranscriptText(Map<String, dynamic> value, List<String> keys) {
    for (final key in keys) {
      final text = value[key]?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  bool _isOptionalMcpFailure(String? text) {
    final normalized = (text ?? '').toLowerCase();
    return normalized.contains('rmcp::transport::worker') ||
        (normalized.contains('mcp') &&
            (normalized.contains('http request failed') ||
                normalized.contains('transport channel closed')));
  }

  bool _isCodeModeFallbackNotice(String? text) {
    final normalized = (text ?? '').toLowerCase();
    return normalized.contains('code mode') &&
        normalized.contains('falling back to direct tools');
  }

  bool _isProviderNetworkFailure(String? text) {
    final normalized = (text ?? '').toLowerCase();
    return normalized.contains('tls handshake eof') ||
        normalized.contains('failed to connect to websocket') ||
        normalized.contains('stream disconnected before completion') ||
        normalized.contains('connection reset') ||
        normalized.contains('connection refused') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('failed to lookup address') ||
        normalized.contains('timed out connecting to') ||
        normalized.contains('rpc request timed out') ||
        normalized.contains('rpc timed out') ||
        normalized.contains('rpc timeout') ||
        normalized.contains('request timed out');
  }

  bool _isAccountAuthenticationFailure(String? text) {
    if (_customProvider != null) return false;
    final normalized = (text ?? '').toLowerCase();
    return (normalized.contains('refresh token') &&
            (normalized.contains('revoked') ||
                normalized.contains('could not be refreshed'))) ||
        normalized.contains('authentication required') ||
        normalized.contains('login required') ||
        normalized.contains('not authenticated') ||
        normalized.contains('please log in') ||
        normalized.contains('please login');
  }

  bool _isBenignArg0CleanupWarning(String? text) {
    return isBenignCodexRuntimeDiagnostic(text);
  }

  bool _isTransientLifecycleEntry(String? text) {
    final normalized = (text ?? '').trim().toLowerCase();
    return normalized == 'system: starting local codex session' ||
        normalized == 'system: resuming local codex session';
  }

  bool _isOptionalMcpWarningTranscriptEntry(String raw) {
    final text = CodexTranscriptEntry.fromStored(raw).text.toLowerCase();
    final hasMcp = text.contains('mcp');
    if (!hasMcp) return false;

    final englishOptionalNetworkWarning =
        text.contains('optional mcp unavailable') ||
        (text.contains('optional mcp') &&
            (text.contains('unavailable') || text.contains('not available')) &&
            (text.contains('network') || text.contains('worker')));
    final localizedOptionalNetworkWarning =
        (text.contains('可选') ||
            text.contains('ネットワーク') ||
            text.contains('オプション') ||
            text.contains('네트워크') ||
            text.contains('선택')) &&
        (text.contains('网络') ||
            text.contains('ネットワーク') ||
            text.contains('네트워크')) &&
        (text.contains('不可用') ||
            text.contains('无法连接') ||
            text.contains('无法使用') ||
            text.contains('利用できません') ||
            text.contains('사용할 수 없'));
    return englishOptionalNetworkWarning || localizedOptionalNetworkWarning;
  }

  void _appendProviderNetworkWarning(String? text) {
    // app-server startup and background model refresh can report transport
    // diagnostics on stderr without a conversation turn being active. Those
    // diagnostics must not make an otherwise usable local session look
    // failed. A real provider failure is still surfaced while sending or
    // while the turn is running; startup failures are handled by _showError.
    if ((!_turnActive && !_sending) ||
        !_isProviderNetworkFailure(text) ||
        _providerNetworkWarningShown) {
      return;
    }
    _providerNetworkWarningShown = true;
    _providerNetworkDiagnostic ??= text;
    _retryPrompt ??= _inFlightPrompt;
    _error ??= _providerNetworkError;
    _transcript.add(
      'System: ${_localizedProviderNetworkErrorFor(_providerNetworkDiagnostic)}',
    );
  }

  void _appendOptionalMcpWarning(String? text) {
    if (!_isOptionalMcpFailure(text) || _mcpWarningShown) return;
    _mcpWarningShown = true;
    if (_transcript.any(_isOptionalMcpWarningTranscriptEntry)) {
      return;
    }
    _transcript.add(
      'System: Optional MCP worker is unavailable on the current network. '
      'The local Codex session remains available without that worker.',
    );
  }

  void _handleEvent(CodexSessionEvent event) {
    if (!mounted) return;
    if (event.threadId != null) _lastThreadId = event.threadId;
    _syncInteractionIdentity();
    var processExited = false;
    var shouldDrainQueue = false;
    var autoApproveRoot = false;
    String? automaticTitlePrompt;
    _handlingSessionEvent = true;
    try {
      switch (event.type) {
        case CodexSessionEventType.status:
          if (event.text != null) {
            _status = event.text!;
            _interaction = _interaction.applyProviderStatus(
              event.text!,
              threadId: event.threadId,
            );
            final normalizedStatus = event.text!.toLowerCase();
            if (normalizedStatus == 'running' ||
                normalizedStatus == 'starting' ||
                normalizedStatus == 'waiting approval' ||
                normalizedStatus == 'interrupting') {
              _turnActive = true;
            }
            if (normalizedStatus == 'running' && _turnStartedAt == null) {
              _turnStartedAt = DateTime.now();
            }
            if (event.text == 'idle' || event.text == 'ready') {
              _turnActive = false;
              _finishConversationTurn();
              _inFlightPrompt = null;
              _commitStreaming();
              shouldDrainQueue = _queuedPrompts.isNotEmpty;
            }
            if (event.method == 'turn/completed' &&
                !_automaticTitleAttempted &&
                !_sessionTitleManuallySet &&
                _threadName?.trim().isNotEmpty != true &&
                _firstPromptForAutomaticTitle?.trim().isNotEmpty == true &&
                _client is CodexSessionClient) {
              _automaticTitleAttempted = true;
              automaticTitlePrompt = _firstPromptForAutomaticTitle!;
            }
            if (event.text == 'failed' || event.text == 'stopped') {
              _turnActive = false;
              _sending = false;
            }
            if (event.text == 'idle' && _pendingAgentVerification != null) {
              unawaited(_verifyPendingAgentChanges());
            }
          }
        case CodexSessionEventType.threadName:
          final name = event.text?.trim();
          final activeThreadId = _client?.threadId ?? _lastThreadId;
          if (!_sessionTitleManuallySet &&
              name != null &&
              name.isNotEmpty &&
              (event.threadId == null || event.threadId == activeThreadId)) {
            _threadName = name;
          }
        case CodexSessionEventType.user:
          _commitStreaming();
          if (_retryingPromptTranscript == event.text) {
            _retryingPromptTranscript = null;
            break;
          }
          _addStructuredTranscript(
            CodexTranscriptKind.user,
            event.text ?? '',
            id: event.params?['clientMessageId']?.toString(),
          );
        case CodexSessionEventType.assistantDelta:
          _streamingAssistantBuffer.write(event.text ?? '');
          _streamingSnapshotDirty = true;
        case CodexSessionEventType.reasoningDelta:
          _streamingThinkingBuffer.write(event.text ?? '');
          _streamingSnapshotDirty = true;
        case CodexSessionEventType.usage:
          _applyConversationUsage(event.params);
        case CodexSessionEventType.tool:
          _commitStreaming();
          if (event.method == 'item/started') {
            _conversationToolCalls++;
            final item = event.params?['item'];
            if (item is Map &&
                <Object?>[item['type'], item['itemType']].any(
                  (value) => value == 'fileChange' || value == 'file_change',
                )) {
              _conversationFileEdits++;
            }
          }
          _upsertToolTranscript(event);
        case CodexSessionEventType.mcpOAuth:
          break;
        case CodexSessionEventType.approval:
          _commitStreaming();
          _transitionInteraction(SessionLifecycleEvent.approvalRequested);
          _approval = event;
          _agentFileChanges = null;
          _prepareUserInput(event);
          _status = 'waiting approval';
          final languageCode = Localizations.localeOf(context).languageCode;
          final requestMessage = switch (event.requestMethod) {
            'item/tool/requestUserInput' => switch (languageCode) {
              'zh' => 'Codex 正在等待你的回答。',
              'ja' => 'Codex が回答を待っています。',
              'ko' => 'Codex가 답변을 기다리고 있습니다.',
              _ => 'Codex is waiting for your answer.',
            },
            'mcpServer/elicitation/request' => switch (languageCode) {
              'zh' => 'MCP 服务 ${event.params?['serverName'] ?? ''} 正在请求输入。',
              'ja' =>
                'MCP サーバー ${event.params?['serverName'] ?? ''} が入力を要求しています。',
              'ko' => 'MCP 서버 ${event.params?['serverName'] ?? ''}가 입력을 요청합니다.',
              _ =>
                'MCP server ${event.params?['serverName'] ?? ''} is requesting input.',
            },
            _ => switch (languageCode) {
              'zh' => 'Codex 正在等待权限审批。',
              'ja' => 'Codex が承認を待っています。',
              'ko' => 'Codex가 승인을 기다리고 있습니다.',
              _ => 'Codex is waiting for approval.',
            },
          };
          _transcript.add('System: $requestMessage');
          if (event.requestMethod == 'item/fileChange/requestApproval') {
            unawaited(_loadAgentFileChangePreview(event));
          }
          autoApproveRoot =
              _rootApprovalAssessment(event)?.route == RootWriteRoute.direct;
        case CodexSessionEventType.stderr:
          _commitStreaming();
          if (_isBenignArg0CleanupWarning(event.text)) {
            // Codex can report a stale helper directory left by a previous
            // root probe. It does not affect the app-server or the turn, and
            // must not become a red conversation error.
            break;
          }
          _appendOptionalMcpWarning(event.text);
          if (!_isOptionalMcpFailure(event.text) &&
              !_isProviderNetworkFailure(event.text)) {
            _transcript.add('stderr: ${event.text ?? ''}');
          }
        case CodexSessionEventType.error:
          _commitStreaming();
          if (_isBenignArg0CleanupWarning(event.text)) {
            break;
          }
          if (event.method == 'error' && event.params?['willRetry'] == true) {
            // App-server ErrorNotification is also used for transient stream
            // failures. The server keeps this turn alive and may fall back
            // from Responses WebSockets to HTTPS; do not turn it into a
            // failed session or a retry banner in the meantime.
            _turnActive = true;
            _status = 'running';
            break;
          }
          if (event.method == 'turn/failed' ||
              event.method == 'turn/interrupted' ||
              event.method == 'turn/aborted') {
            _finishConversationTurn();
          }
          if (_isCodeModeFallbackNotice(event.text)) {
            // The Android package deliberately does not ship the optional
            // desktop Code Mode host. Codex has already selected direct
            // tools, so this is a capability notice rather than a failed
            // session. Keep the transcript aligned with CC Pocket's neutral
            // system notices and do not transition the thread to failed.
            _addStructuredTranscript(
              CodexTranscriptKind.system,
              'Code Mode unavailable; using direct tools.',
            );
            break;
          }
          if (_isAccountAuthenticationFailure(event.text)) {
            _markAccountBindingStale();
            _turnActive = false;
            _sending = false;
            _status = 'failed';
            break;
          }
          _appendOptionalMcpWarning(event.text);
          _appendProviderNetworkWarning(event.text);
          if (_isOptionalMcpFailure(event.text)) {
            break;
          }
          final providerNetworkFailure =
              (_turnActive || _sending) &&
              _isProviderNetworkFailure(event.text);
          if (providerNetworkFailure) {
            _transitionInteraction(
              SessionLifecycleEvent.failed,
              error: _providerNetworkError,
            );
            _turnActive = false;
            _sending = false;
            _retryPrompt ??= _inFlightPrompt;
            _error = _providerNetworkError;
            _status = 'failed';
            break;
          }
          // Non-turn app-server warnings are not a failed conversation. Keep
          // the session usable and retain the diagnostic only when it is not
          // one of the known optional/housekeeping messages above.
          if (!_turnActive && !_sending) {
            break;
          }
          _turnActive = false;
          _sending = false;
          _transitionInteraction(
            SessionLifecycleEvent.failed,
            error: _localizedRuntimeFailure(event.text ?? ''),
          );
          _addStructuredTranscript(
            CodexTranscriptKind.error,
            _localizedRuntimeFailure(event.text ?? ''),
          );
          _error = _localizedRuntimeFailure(event.text ?? '');
          _status = 'failed';
        case CodexSessionEventType.exit:
          _commitStreaming();
          _finishConversationTurn();
          _turnActive = false;
          _status = 'exited ${event.exitCode ?? -1}';
          processExited = true;
        case CodexSessionEventType.stopped:
          _commitStreaming();
          _turnActive = false;
          _transitionInteraction(SessionLifecycleEvent.stopped);
          _status = 'stopped';
      }
    } finally {
      _handlingSessionEvent = false;
    }
    final streamingDelta =
        event.type == CodexSessionEventType.assistantDelta ||
        event.type == CodexSessionEventType.reasoningDelta;
    _requestSessionFrameRefresh(rebuildSession: !streamingDelta);
    if (event.type == CodexSessionEventType.mcpOAuth) {
      final name = event.params?['name']?.toString() ?? '';
      final success = event.params?['success'] == true;
      final languageCode = Localizations.localeOf(context).languageCode;
      final message = switch (languageCode) {
        'zh' =>
          success
              ? 'MCP 服务器“$name”已完成 OAuth 登录。'
              : 'MCP 服务器“$name”的 OAuth 登录未完成；可检查 MCP 状态后重试。',
        'ja' =>
          success
              ? 'MCP サーバー「$name」の OAuth ログインが完了しました。'
              : 'MCP サーバー「$name」の OAuth ログインは完了しませんでした。状態を確認して再試行してください。',
        'ko' =>
          success
              ? 'MCP 서버 "$name" OAuth 로그인이 완료되었습니다.'
              : 'MCP 서버 "$name" OAuth 로그인이 완료되지 않았습니다. 상태를 확인한 뒤 다시 시도하세요.',
        _ =>
          success
              ? 'OAuth login completed for MCP server "$name".'
              : 'OAuth login did not complete for MCP server "$name". Check its status and retry.',
      };
      _addStructuredTranscript(CodexTranscriptKind.system, message);
      _scheduleHistoryPersist();
    }
    if (automaticTitlePrompt != null) {
      unawaited(_generateAutomaticThreadTitle(automaticTitlePrompt!));
    }
    if (autoApproveRoot) unawaited(_respondToApproval(true));
    _scheduleSnapshotPublish();
    if (processExited) {
      final operationGeneration = _sessionOperationGeneration;
      final explicitlyStopped = _explicitlyStopped;
      final client = _client;
      _lastThreadId = client?.threadId ?? _lastThreadId;
      if (client is CodexSessionClient) {
        _lastThreadPath = client.threadPath ?? _lastThreadPath;
      }
      _client = null;
      setState(() {
        _busy = false;
        _sending = false;
        _turnActive = false;
        _approval = null;
        _agentFileChanges = null;
        _pendingAgentVerification = null;
        _clearStreaming();
        _inFlightPrompt = null;
        _retryPrompt = null;
        _retryImages = const <ImageAttachment>[];
        _retryingPromptTranscript = null;
        if (!explicitlyStopped) {
          _connectionLost = true;
          _connectionLostReason = _accountBindingStale
              ? _accountBindingStaleMessage
              : _uiText(
                  '本地 Codex app-server 已断开。',
                  'The local Codex app-server disconnected.',
                );
          _status = 'disconnected';
        }
      });
      _scheduleSnapshotPublish(immediate: true);
      unawaited(
        _releaseExitedClient(client, operationGeneration: operationGeneration),
      );
    }
    if (shouldDrainQueue && !processExited) {
      unawaited(_drainQueuedPrompt());
    }
    _scheduleHistoryPersist(
      immediate:
          processExited ||
          event.type == CodexSessionEventType.exit ||
          event.type == CodexSessionEventType.stopped ||
          (event.type == CodexSessionEventType.status &&
              (event.text == 'idle' ||
                  event.text == 'ready' ||
                  event.text == 'failed')),
    );
  }

  Future<void> _generateAutomaticThreadTitle(String prompt) async {
    final client = _client;
    if (client is! CodexSessionClient ||
        _sessionTitleManuallySet ||
        _threadName?.trim().isNotEmpty == true) {
      return;
    }
    final title = await client.generateAutomaticThreadTitle(prompt);
    if (!mounted ||
        title == null ||
        _sessionTitleManuallySet ||
        _threadName?.trim().isNotEmpty == true) {
      return;
    }
    setState(() => _threadName = title);
    _publishSnapshot();
    unawaited(_persistHistory());
  }

  void _finishConversationTurn() {
    final started = _turnStartedAt;
    if (started == null) return;
    _conversationDuration += DateTime.now().difference(started);
    _turnStartedAt = null;
  }

  void _applyConversationUsage(Map<String, dynamic>? params) {
    final rawUsage = params?['tokenUsage'];
    if (rawUsage is! Map) return;
    final rawTotal = rawUsage['total'];
    if (rawTotal is Map) {
      _conversationInputTokens = _usageCount(rawTotal['inputTokens']);
      _conversationCachedInputTokens = _usageCount(
        rawTotal['cachedInputTokens'],
      );
      _conversationOutputTokens = _usageCount(rawTotal['outputTokens']);
    }
    final rawLast = rawUsage['last'];
    final contextWindow = _usageCount(rawUsage['modelContextWindow']);
    if (contextWindow > 0 && rawLast is Map) {
      _conversationContextTokens =
          _usageCount(rawLast['inputTokens']) +
          _usageCount(rawLast['cachedInputTokens']);
      _conversationContextWindow = contextWindow;
    } else {
      _conversationContextTokens = 0;
      _conversationContextWindow = null;
    }
  }

  int _usageCount(Object? value) {
    if (value is! num) return 0;
    return value.toInt().clamp(0, 0x7fffffff).toInt();
  }

  Widget _conversationUsageSummary() {
    return SizedBox(
      height: 18,
      child: UsageSummaryBar(
        totalCost: 0,
        totalDuration: _conversationDuration > Duration.zero
            ? _conversationDuration
            : null,
        inputTokens: _conversationInputTokens,
        cachedInputTokens: _conversationCachedInputTokens,
        outputTokens: _conversationOutputTokens,
        toolCalls: _conversationToolCalls,
        fileEdits: _conversationFileEdits,
        contextTokens: _conversationContextTokens,
        contextWindow: _conversationContextWindow,
      ),
    );
  }

  Future<void> _releaseExitedClient(
    SessionClient? client, {
    required int operationGeneration,
  }) async {
    Object? cleanupError;
    try {
      await _sessionRuntime.detachClient(client);
      // A broken child/PTY must not keep the local session permanently in the
      // synthetic "exited" state. The Android process boundary is best
      // effort after the exit event; the UI still needs to become resumable.
      await client?.dispose().timeout(const Duration(seconds: 3));
      _disposeUserInputControllers();
    } catch (error) {
      cleanupError = error;
    }
    if (!mounted ||
        operationGeneration != _sessionOperationGeneration ||
        _explicitlyStopped) {
      return;
    }
    final foregroundOwned = _sessionForegroundOwned;
    _sessionForegroundOwned = false;
    if (foregroundOwned) {
      try {
        await SessionLifecycle.stop().timeout(const Duration(seconds: 2));
      } catch (error) {
        cleanupError ??= error;
      }
    }
    if (!mounted ||
        operationGeneration != _sessionOperationGeneration ||
        _explicitlyStopped) {
      return;
    }
    setState(() {
      _busy = false;
      _sending = false;
      _turnActive = false;
      _approval = null;
      _agentFileChanges = null;
      _pendingAgentVerification = null;
      if (cleanupError != null) {
        _error = _uiText(
          '无法释放已结束的会话：$cleanupError',
          'Could not release the ended session: $cleanupError',
        );
        _transcript.add('session cleanup error: $cleanupError');
      }
      _connectionLost = true;
      _connectionLostReason = _accountBindingStale
          ? _accountBindingStaleMessage
          : cleanupError == null
          ? _uiText(
              '本地 Codex app-server 已断开。',
              'The local Codex app-server disconnected.',
            )
          : _uiText(
              '本地 Codex app-server 已断开：$cleanupError',
              'The local Codex app-server disconnected: $cleanupError',
            );
      _status = 'disconnected';
      _transitionInteraction(
        SessionLifecycleEvent.disconnected,
        threadId: _lastThreadId,
      );
    });
    _publishSnapshot();
    unawaited(_persistHistory());
    if (!_accountBindingStale) _scheduleAutomaticReconnect();
  }

  Future<void> _respondToApproval(
    bool approved, {
    bool forSession = false,
    Map<String, dynamic>? decisionOverride,
  }) async {
    final approval = _approval;
    final client = _client;
    if (approval == null || client == null || approval.requestId == null) {
      return;
    }
    if ((forSession || decisionOverride != null) &&
        _identity == ExecutionIdentity.root) {
      final languageCode = Localizations.localeOf(context).languageCode;
      _showError(switch (languageCode) {
        'zh' => 'Root 会话不能应用跨请求生效的批准规则。',
        'ja' => 'Root セッションでは複数の要求に適用される承認ルールを設定できません。',
        'ko' => 'Root 세션에서는 여러 요청에 적용되는 승인 규칙을 설정할 수 없습니다.',
        _ => 'Root sessions cannot apply persistent approval rules.',
      });
      return;
    }
    final rootAssessment = _rootApprovalAssessment();
    if (approved &&
        rootAssessment != null &&
        rootAssessment.route == RootWriteRoute.denied) {
      _showError(rootAssessment.reason);
      return;
    }
    try {
      List<TextChangeSet>? verification;
      final autoApprovedRootWrite =
          _identity == ExecutionIdentity.root &&
          rootAssessment?.route == RootWriteRoute.direct;
      if (approved &&
          approval.requestMethod == 'item/fileChange/requestApproval' &&
          !autoApprovedRootWrite &&
          !await _prepareAgentBackups()) {
        return;
      }
      if (approved &&
          approval.requestMethod == 'item/fileChange/requestApproval') {
        final previews = _agentFileChanges;
        final managed = previews
            ?.map((preview) => preview.changeSet)
            .whereType<TextChangeSet>()
            .toList(growable: false);
        if (previews != null &&
            managed != null &&
            managed.isNotEmpty &&
            managed.length == previews.length) {
          verification = managed;
        }
      }
      await client.respondToApproval(
        approval,
        approved: approved,
        forSession: forSession,
        decisionOverride: decisionOverride,
      );
      _pendingAgentVerification = verification;
      if (mounted) {
        setState(() {
          _transitionInteraction(SessionLifecycleEvent.turnStarted);
          _approval = null;
          _agentFileChanges = null;
          _status = 'running';
          final languageCode = Localizations.localeOf(context).languageCode;
          final approvalText = decisionOverride != null
              ? switch ((languageCode, approved)) {
                  ('zh', true) => '已应用持久批准规则',
                  ('zh', false) => '已应用持久拒绝规则',
                  ('ja', true) => '継続適用する承認ルールを設定しました',
                  ('ja', false) => '継続適用する拒否ルールを設定しました',
                  ('ko', true) => '지속 승인 규칙을 적용했습니다',
                  ('ko', false) => '지속 거부 규칙을 적용했습니다',
                  (_, true) => 'Approval: persistent rule applied',
                  _ => 'Approval: persistent deny rule applied',
                }
              : forSession
              ? switch (languageCode) {
                  'zh' => '本次会话已允许',
                  'ja' => 'このセッション中は許可しました',
                  'ko' => '이 세션에서 허용했습니다',
                  _ => 'Approval: accepted for this session',
                }
              : approved
              ? 'Approval: accepted'
              : 'Approval: declined';
          _transcript.add(approvalText);
        });
        unawaited(_persistHistory());
      }
    } on CodexSessionException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  RootWriteAssessment? _rootApprovalAssessment([CodexSessionEvent? request]) {
    if (_identity != ExecutionIdentity.root) return null;
    final approval = request ?? _approval;
    if (approval == null) return null;
    if (approval.requestMethod == 'item/tool/requestUserInput' ||
        approval.requestMethod == 'mcpServer/elicitation/request') {
      return null;
    }
    RootWriteAssessment applySessionPermission(RootWriteAssessment assessment) {
      return _codexSandbox == 'read-only'
          ? RootAccessPolicy.enforceReadOnlySession(assessment)
          : assessment;
    }

    final params = approval.params ?? const <String, dynamic>{};
    if (approval.requestMethod == 'item/permissions/requestApproval') {
      return applySessionPermission(
        RootAccessPolicy.assessPermissionRequest(
          params['permissions'],
          workspacePath: _activeWorkspace.hostPath,
        ),
      );
    }
    if (approval.requestMethod == 'item/fileChange/requestApproval') {
      final previews = _agentFileChanges;
      if (previews != null && previews.isNotEmpty) {
        final base = _activeWorkspace.hostPath.endsWith('/')
            ? _activeWorkspace.hostPath.substring(
                0,
                _activeWorkspace.hostPath.length - 1,
              )
            : _activeWorkspace.hostPath;
        return applySessionPermission(
          RootAccessPolicy.assessPaths(
            previews.map(
              (preview) => preview.path.startsWith('/')
                  ? preview.path
                  : '$base/${preview.path}',
            ),
          ),
        );
      }
      final rawChanges = params['changes'];
      if (rawChanges is List) {
        final base = _activeWorkspace.hostPath.endsWith('/')
            ? _activeWorkspace.hostPath.substring(
                0,
                _activeWorkspace.hostPath.length - 1,
              )
            : _activeWorkspace.hostPath;
        final paths = rawChanges.whereType<Map>().map((change) {
          final path =
              change['path']?.toString() ??
              change['relativePath']?.toString() ??
              change['file']?.toString() ??
              '<unknown>';
          return path.startsWith('/') ? path : '$base/$path';
        });
        return applySessionPermission(RootAccessPolicy.assessPaths(paths));
      }
      return applySessionPermission(
        RootAccessPolicy.assessPaths(const <String>['<unknown>']),
      );
    }
    if (approval.requestMethod == 'item/commandExecution/requestApproval') {
      final rawCommand = params['command'];
      final command = rawCommand is List
          ? rawCommand.join(' ')
          : rawCommand?.toString() ??
                (params['argv'] is List
                    ? (params['argv'] as List).join(' ')
                    : '<unknown command>');
      return applySessionPermission(RootAccessPolicy.assessCommand(command));
    }
    return applySessionPermission(
      const RootWriteAssessment(
        risk: RootWriteRisk.medium,
        route: RootWriteRoute.userApproval,
        reason: 'Root request requires explicit user approval.',
      ),
    );
  }

  void _prepareUserInput(CodexSessionEvent event) {
    _disposeUserInputControllers();
    if (event.requestMethod != 'item/tool/requestUserInput') return;
    for (final question in _userInputQuestions(event)) {
      final id = question['id'];
      if (id is! String || id.isEmpty) continue;
      _userInputControllers[id] = TextEditingController();
      _userInputSelections[id] = null;
    }
  }

  void _disposeUserInputControllers() {
    for (final controller in _userInputControllers.values) {
      controller.dispose();
    }
    _userInputControllers.clear();
    _userInputSelections.clear();
  }

  List<Map<String, dynamic>> _userInputQuestions(CodexSessionEvent event) {
    final rawQuestions = event.params?['questions'];
    if (rawQuestions is! List) return const <Map<String, dynamic>>[];
    return rawQuestions
        .whereType<Map>()
        .map(
          (question) => <String, dynamic>{
            for (final entry in question.entries)
              if (entry.key is String) entry.key as String: entry.value,
          },
        )
        .where((question) => question['id'] is String)
        .toList(growable: false);
  }

  Future<void> _respondToUserInput({required bool cancelled}) async {
    final request = _approval;
    final client = _client;
    if (request == null || client == null || request.requestId == null) return;
    final answers = <String, dynamic>{};
    if (!cancelled) {
      final missing = <String>[];
      for (final question in _userInputQuestions(request)) {
        final id = question['id'];
        if (id is! String || id.isEmpty) continue;
        final selected = _userInputSelections[id];
        final typed = _userInputControllers[id]?.text.trim() ?? '';
        final answer = selected?.trim().isNotEmpty == true
            ? selected!.trim()
            : typed;
        if (answer.isEmpty) {
          final label = question['header'] ?? question['id'];
          missing.add('$label');
          continue;
        }
        answers[id] = <String, dynamic>{
          'answers': <String>[answer],
        };
      }
      if (missing.isNotEmpty) {
        _showError(
          _uiText(
            '提交前请回答每个问题：${missing.join('、')}',
            'Answer each question before submitting: ${missing.join(', ')}',
          ),
        );
        return;
      }
    }
    try {
      await client.respondToRequest(request.requestId!, <String, dynamic>{
        'answers': answers,
      });
      if (!mounted) return;
      setState(() {
        _approval = null;
        _status = 'running';
        _transcript.add(
          cancelled ? 'User input canceled' : 'User input submitted',
        );
        _disposeUserInputControllers();
      });
      unawaited(_persistHistory());
    } on CodexSessionException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  /// Converts the payload emitted by CC Pocket's question widget into the
  /// app-server v2 response shape.  The presentation widget emits a plain
  /// string for a single-choice question and a JSON object for multi-question
  /// flows; Codex expects every answer keyed by question id and wrapped in an
  /// `answers` list.
  Future<void> _respondToUserInputResult(String result) async {
    final request = _approval;
    final client = _client;
    if (request == null || client == null || request.requestId == null) return;

    final answers = <String, dynamic>{};
    Object? decoded;
    try {
      decoded = jsonDecode(result);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map && decoded['answers'] is Map) {
      final rawAnswers = decoded['answers'] as Map;
      for (final entry in rawAnswers.entries) {
        final id = entry.key.toString().trim();
        if (id.isEmpty) continue;
        final value = entry.value;
        final values = value is List
            ? value.whereType<String>().toList(growable: false)
            : value is String
            ? <String>[value]
            : const <String>[];
        answers[id] = <String, dynamic>{'answers': values};
      }
    } else {
      final firstQuestion = _userInputQuestions(request).firstOrNull;
      final id = firstQuestion?['id']?.toString().trim();
      if (id == null || id.isEmpty || result.trim().isEmpty) {
        _showError(
          _uiText('Codex 问题的回答不能为空。', 'The Codex question answer was empty.'),
        );
        return;
      }
      answers[id] = <String, dynamic>{
        'answers': <String>[result.trim()],
      };
    }

    try {
      await client.respondToRequest(request.requestId!, <String, dynamic>{
        'answers': answers,
      });
      if (!mounted) return;
      setState(() {
        _approval = null;
        _status = 'running';
        _transcript.add('User input submitted');
        _disposeUserInputControllers();
      });
      unawaited(_persistHistory());
    } on CodexSessionException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<void> _respondToMcpElicitation({
    required String action,
    Map<String, dynamic>? content,
    String? persist,
  }) async {
    final request = _approval;
    final client = _client;
    if (request?.requestMethod != 'mcpServer/elicitation/request' ||
        request?.requestId == null ||
        client == null) {
      return;
    }
    final response = <String, dynamic>{
      'action': action,
      'content': action == 'accept' ? (content ?? <String, dynamic>{}) : null,
      if (action == 'accept' && persist != null)
        '_meta': <String, String>{'persist': persist},
    };
    try {
      await client.respondToRequest(request!.requestId!, response);
      if (!mounted) return;
      setState(() {
        _approval = null;
        _status = 'running';
        _transcript.add(
          action == 'accept'
              ? 'System: MCP request accepted.'
              : action == 'decline'
              ? 'System: MCP request declined.'
              : 'System: MCP request canceled.',
        );
      });
      unawaited(_persistHistory());
    } on CodexSessionException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('$error');
    }
  }

  Future<bool> _openMcpElicitationUrl(String url) async {
    try {
      final opened = await const MethodChannel(
        'io.henry.codex/browser',
      ).invokeMethod<bool>('openMcpExternalUrl', <String, String>{'url': url});
      return opened == true;
    } catch (_) {
      _showError(
        _uiText('无法打开 MCP 授权页面。', 'Could not open the MCP authorization page.'),
      );
      return false;
    }
  }

  Future<void> _verifyPendingAgentChanges() async {
    final changes = _pendingAgentVerification;
    _pendingAgentVerification = null;
    if (changes == null || changes.isEmpty) return;
    try {
      final workspace = await _activeBackend.openWorkspace(_activeWorkspace);
      final mismatches = <String>[];
      for (final change in changes) {
        try {
          final snapshot = await _activeBackend.snapshotText(
            workspace,
            change.relativePath,
          );
          if (snapshot.content != change.proposedContent) {
            mismatches.add(change.relativePath);
          }
        } on BackendException {
          mismatches.add(change.relativePath);
        }
      }
      if (!mounted) return;
      setState(() {
        if (mismatches.isEmpty) {
          _transcript.add(
            'Agent file change verified: ${changes.length} file(s) '
            'match the approved content.',
          );
        } else {
          final paths = mismatches.join(', ');
          _error = _uiText(
            '文件变更验证失败：$paths',
            'Agent file change verification failed: $paths',
          );
          _status = 'failed';
          _transcript.add('Agent file change verification failed: $paths');
        }
      });
      unawaited(_persistHistory());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _uiText(
          '无法验证文件变更：$error',
          'Could not verify the agent file change: $error',
        );
        _status = 'failed';
        _transcript.add('Agent file change verification error: $error');
      });
      unawaited(_persistHistory());
    }
  }

  Future<bool> _prepareAgentBackups() async {
    final previews = _agentFileChanges;
    if (previews == null) {
      _showError(
        _uiText(
          '请先等待文件变更预览完成，再批准此请求。',
          'Wait for the file-change preview before approving it.',
        ),
      );
      return false;
    }
    final managed = previews
        .where((preview) => preview.changeSet != null)
        .toList(growable: false);
    if (managed.isEmpty || managed.length != previews.length) {
      if (mounted) {
        setState(() {
          _transcript.add(
            'Agent file change: no pre-change backup; the request had no '
            'complete managed text preview.',
          );
        });
        unawaited(_persistHistory());
      }
      return true;
    }
    if (!_activeBackend.descriptor.capabilities.managedChangesSupported) {
      if (mounted) {
        setState(() {
          _transcript.add(
            'The active backend owns the approved change but does not expose '
            'versioned pre-change backups.',
          );
        });
        unawaited(_persistHistory());
      }
      return true;
    }
    if (_activeBackend.descriptor.kind == BackendKind.localAndroid &&
        !await _confirmRootExecution('create pre-change agent backups')) {
      return false;
    }
    try {
      for (final preview in managed) {
        final changeSet = preview.changeSet!;
        await _activeBackend.backupText(
          changeSet.workspace,
          changeSet.relativePath,
          expectedVersion: changeSet.before.version,
        );
      }
      if (mounted) {
        setState(() {
          _transcript.add(
            'Agent file change: ${managed.length} pre-change backup(s) created.',
          );
        });
      }
      return true;
    } on BackendException catch (error) {
      _showError(
        _uiText(
          '无法创建 agent 备份：${error.message}',
          'Could not create the agent backup: ${error.message}',
        ),
      );
      return false;
    } catch (error) {
      _showError(
        _uiText(
          '无法创建 agent 备份：$error',
          'Could not create the agent backup: $error',
        ),
      );
      return false;
    }
  }

  Future<void> _loadAgentFileChangePreview(CodexSessionEvent approval) async {
    try {
      final workspace = await _activeBackend.openWorkspace(_activeWorkspace);
      final previews = await _agentChangePreviewService.prepare(
        backend: _activeBackend,
        workspace: workspace,
        params: approval.params ?? const <String, dynamic>{},
      );
      if (!mounted || !identical(_approval, approval)) return;
      setState(() => _agentFileChanges = previews);
    } catch (error) {
      if (!mounted || !identical(_approval, approval)) return;
      setState(() {
        _agentFileChanges = <AgentFileChangePreview>[
          AgentFileChangePreview(
            path: '<preview failed>',
            kind: 'unknown',
            diff: '',
            issue: _uiText(
              '无法为此请求准备宿主快照。',
              'Could not prepare a host snapshot for this request.',
            ),
          ),
        ];
      });
      _transcript.add('file-change preview error: $error');
    }
  }

  Widget _buildCodexControls({bool showAuthChallenge = true}) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (_isCompatibility) {
      final descriptor = _activeBackend.descriptor;
      return _buildCodexAuthActions(
        descriptor.capabilities.usable,
        showChallenge: showAuthChallenge,
      );
    }

    return FutureBuilder<CodexRuntimeDescriptor>(
      future: _runtime,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            child: ListTile(
              leading: CircularProgressIndicator(),
              title: Text(zh ? '正在准备本地登录' : 'Preparing local login'),
              subtitle: Text(
                zh
                    ? '正在检查设备上的 Codex 运行时…'
                    : 'Checking the on-device Codex runtime…',
              ),
            ),
          );
        }
        final auth = _buildCodexAuthActions(
          snapshot.data!.usable || _mayUseCompatibilityFallback,
          showChallenge: showAuthChallenge,
        );
        return auth;
      },
    );
  }

  Widget _buildCodexAuthActions(bool usable, {bool showChallenge = true}) {
    return CcpocketNativeAuthCard(
      status: _authStatus,
      loginStatus: _authLoginStatus,
      error: _error,
      // A hidden thread client may remain alive while Settings is open. It
      // must not disable the auth controls; starting a mutating auth flow
      // stops that client explicitly above.
      busy: !usable || _busy || _authClient != null,
      pending: _authClient != null,
      authenticated: _authStatus == 'Logged in',
      selectedMode: _authMode,
      apiKeyController: _apiKeyController,
      challenge: _authChallenge,
      onModeChanged: (mode) {
        setState(() {
          _authMode = mode;
          // A validation error belongs to the previous login mode. Keeping
          // it after switching modes makes the next mode look broken before
          // the user has started it.
          _error = null;
          _authChallenge = null;
          _authLoginStatus = null;
        });
        _notifyAuthRevision();
      },
      onStart: _startAuth,
      onRefresh: _checkAuthStatus,
      onCancel: _cancelAuth,
      onLogout: _logout,
      onCopyCode: _copyAuthCode,
      onOpenUrl: _openAuthUrl,
      showChallenge: showChallenge,
    );
  }

  Map<String, String> _runtimeEnvironment(
    CodexRuntimeDescriptor runtime, {
    String? runtimeScope,
  }) {
    final home = runtime.home;
    if (home == null) return const <String, String>{};
    // Keep the app-private runtime environment self-contained if a platform
    // test or older runtime descriptor supplies a direct command. The Android
    // product path uses `_compatibilityRuntimeEnvironment` instead.
    const filesMarker = '/files/';
    final filesIndex = home.lastIndexOf(filesMarker);
    final cache = filesIndex >= 0
        ? '${home.substring(0, filesIndex)}/cache'
        : null;
    final environment = <String, String>{
      'HOME': home,
      'CODEX_HOME': home,
      // The Android UI opens the verified OAuth URL itself. Keep the CLI
      // from invoking a desktop browser inside the native/PRoot runtime and
      // accidentally creating a second OAuth state/callback pair.
      'BROWSER': _isCompatibility ? '/usr/bin/true' : '/system/bin/true',
      if (cache != null) ...{
        // Codex uses a small temp area for its arg0/process-name helper. The
        // Android app sandbox cannot write /data/local/tmp, so keep that
        // helper inside the app-owned cache instead of emitting a harmless
        // but misleading cleanup warning on every direct probe/session.
        'TMPDIR': cache,
        'TMP': cache,
        'TEMP': cache,
      },
    };
    if (runtimeScope != null) {
      final sessionHome = '$home/sessions/${_safeRuntimeScope(runtimeScope)}';
      // Keep all home-relative Codex paths inside this session. CODEX_HOME is
      // the authoritative Codex directory, but a few libraries still resolve
      // auxiliary files through HOME when an explicit path is not available.
      // Leaving HOME at the shared login home lets those files reintroduce a
      // cross-session lock even when SQLite and logs are scoped.
      environment['HOME'] = sessionHome;
      environment['CODEX_HOME'] = sessionHome;
      environment['CODEX_SQLITE_HOME'] = '$sessionHome/state';
      environment['TMPDIR'] = '$sessionHome/tmp';
      environment['TMP'] = '$sessionHome/tmp';
      environment['TEMP'] = '$sessionHome/tmp';
    }
    return environment;
  }

  Map<String, String> _compatibilityRuntimeEnvironment({String? runtimeScope}) {
    if (runtimeScope == null) return const <String, String>{};
    const sessionRoot = '/home/codex/sessions';
    final sessionHome = '$sessionRoot/${_safeRuntimeScope(runtimeScope)}';
    return <String, String>{
      'CODEX_HOME': sessionHome,
      'CODEX_SQLITE_HOME': '$sessionHome/state',
    };
  }

  String _runtimeSessionKey() {
    final value = _sessionId.trim();
    final normalized = value.isEmpty ? 'pending' : value;
    final safe = normalized.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.length <= 96 ? safe : safe.substring(0, 96);
  }

  String _newRuntimeOperationScope(String label) =>
      'op-$label-${DateTime.now().microsecondsSinceEpoch}';

  String _safeRuntimeScope(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.length <= 96 ? safe : safe.substring(0, 96);
  }

  Future<bool> _confirmRootExecution(String operation) async {
    if (_identity != ExecutionIdentity.root) return true;
    if (_sessionRuntime.rootApprovalGrantedForSession == _sessionId) {
      return true;
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(zh ? '允许此会话使用 Root？' : 'Allow Root for this session?'),
            content: Text(
              zh
                  ? '授权仅绑定当前 session。普通 Root 操作、字体、hosts 和应用配置直接执行，不因所在分区或未知命令而逐条审批；仅启动链配置/模块、boot 镜像、raw block 和 KernelSU 控制目标走软路由，适合时优先使用可回退模块。路径预检是应用层规则，不是内核隔离。当前操作：$operation。'
                  : 'This grant is scoped to the current session. Ordinary Root operations, fonts, hosts, and app configuration remain direct; partition location or unknown syntax alone does not add per-command approval. Only startup-chain configuration/modules, boot images, raw blocks, and KernelSU control targets use soft routing, preferring a reversible module when appropriate. Path preflight is app logic, not kernel isolation. Current operation: $operation.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(zh ? '允许此会话' : 'Allow for session'),
              ),
            ],
          ),
        ) ??
        false;
    if (approved && mounted) {
      _sessionRuntime.rootApprovalGrantedForSession = _sessionId;
      unawaited(_persistHistory());
    }
    return approved;
  }

  Future<bool> _confirmRootSession() =>
      _confirmRootExecution('start the local app-server');

  void _showError(String message) {
    if (!mounted) return;
    final isProviderNetworkFailure = _isProviderNetworkFailure(message);
    final displayMessage = isProviderNetworkFailure
        ? _providerNetworkError
        : _localizedRuntimeFailure(message);
    final transcriptMessage = isProviderNetworkFailure
        ? _localizedProviderNetworkErrorFor(message)
        : _localizedRuntimeFailure(message);
    if (isProviderNetworkFailure) _providerNetworkDiagnostic = message;
    setState(() {
      _transitionInteraction(
        SessionLifecycleEvent.failed,
        error: displayMessage,
        threadId: _lastThreadId,
      );
      _busy = false;
      _sending = false;
      _turnActive = false;
      if (isProviderNetworkFailure) _appendProviderNetworkWarning(message);
      _error = displayMessage;
      _appendTranscriptError(transcriptMessage);
    });
    // Settings is hosted on a separate route and rebuilds the auth card from
    // this revision notifier. Keep validation errors visible there too;
    // otherwise an empty API-key submission looks like a dead button.
    _notifyAuthRevision();
    unawaited(_persistHistory());
  }

  void _appendTranscriptError(String message) {
    final entry = 'error: $message';
    if (_transcript.isNotEmpty &&
        _isRepeatedErrorEntry(_transcript.last.trim(), entry)) {
      return;
    }
    _transcript.add(entry);
  }

  static bool _isRepeatedErrorEntry(String previous, String current) {
    if (!previous.toLowerCase().startsWith('error:') ||
        !current.toLowerCase().startsWith('error:')) {
      return false;
    }
    return previous.trim() == current.trim();
  }

  // The previous debug/session setup surface was removed.  The page below is
  // the CC Pocket presentation surface backed by the local session client.

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final active = _client != null || _connectionLost;
    final content = active
        ? _buildActiveCcpocketSession(context)
        : _buildInactiveCcpocketSession(context);
    if (widget.onClose == null) return content;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose!.call();
      },
      child: content,
    );
  }

  Widget _buildInactiveCcpocketSession(BuildContext context) {
    final workspaceName = _workspaceName(_activeWorkspace.displayPath);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    // CC Pocket keeps the conversation surface as the single source of truth
    // for session messages. Errors are appended to that transcript by
    // _showError/_loadHistory/_discardStaleResume; rendering _error here as a
    // second header duplicates the same bubble and shifts restored history.
    final hasSetupHeader = _busy;
    final setupHeader = Column(
      key: const ValueKey('local_codex_session_setup_header'),
      children: [
        if (_busy)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(zh ? '正在打开会话…' : 'Opening session…'),
              subtitle: Text(
                zh ? '正在载入该会话的完整历史' : 'Loading the complete session history',
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        leading: IconButton(
          tooltip: zh ? '返回会话列表' : 'Back to sessions',
          onPressed: _leaveInactiveSession,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_effectiveSessionTitle ?? workspaceName),
        actions: [
          IconButton(
            key: const ValueKey('local_codex_session_settings_button'),
            tooltip: zh ? '会话设置' : 'Session settings',
            onPressed: _openSessionSettings,
            icon: const Icon(Icons.tune_outlined),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('local_codex_inactive_session_menu'),
            onSelected: (value) {
              switch (value) {
                case 'details':
                  _showSessionDetails();
                case 'rename':
                  _renameCurrentSession();
                case 'new':
                  _startFreshConversation();
                case 'fork':
                  unawaited(_forkCurrentSession());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'details',
                child: Text(zh ? '会话详情' : 'Session details'),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Text(zh ? '重命名会话' : 'Rename session'),
              ),
              PopupMenuItem(
                value: 'new',
                child: Text(zh ? '新会话' : 'New session'),
              ),
              PopupMenuItem(
                value: 'fork',
                child: Text(zh ? '分叉会话' : 'Fork session'),
              ),
            ],
          ),
        ],
        bottom: CcpocketNativeStatusLine(status: _status),
      ),
      body: KeyedSubtree(
        key: const ValueKey('local_codex_session_setup'),
        child: CcpocketNativeSessionSurface(
          // Authentication belongs to Settings. The thread surface remains
          // the CC Pocket conversation surface even before the first turn.
          header: hasSetupHeader
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(child: setupHeader),
                )
              : null,
          entries: _transcript,
          localizeEntry: _localizedTranscriptEntry,
          status: _historyPresentationStatus,
          controller: _promptController,
          accountUsageSummary: _conversationAccountUsageSummary(),
          usageSummary: _conversationUsageSummary(),
          streamingSnapshot: _streamingSnapshot,
          queuedPrompts: _queuedPrompts,
          onRemoveQueuedPrompt: _removeQueuedPrompt,
          modeBar: CcpocketNativeModeBar(
            model: _codexModel,
            effort: _codexEffort,
            approvalPolicy: _codexApprovalPolicy,
            sandbox: _codexSandbox,
            rootMode: _identity == ExecutionIdentity.root,
            planMode: _planMode,
            onOpenSettings: _openSessionSettings,
            onOpenPermissions: _showPermissionsPicker,
            onTogglePlan: _togglePlanMode,
            onOpenEffortSettings: _customProvider == null
                ? null
                : _openCustomProviderEffortSettings,
            showCodexControls: true,
          ),
          inputBlocked: _approval != null || _busy || _providerSwitching,
          onSend: _sendPrompt,
          onStop: _stopClient,
          onInterrupt: _interruptSession,
          onSlashCommand: _showSlashCommands,
          onMention: _insertMention,
          onShowPromptHistory: _showPromptHistory,
          onIndent: _indentPrompt,
          onDedent: _dedentPrompt,
          attachedImages: _attachedImages,
          onAttachImage: _pickImages,
          onClearImage: _clearAttachedImage,
          // CC Pocket keeps the newest message at the bottom through a
          // reverse list. The setup surface must use the same direction as
          // the active surface so opening a saved session does not preserve
          // a different viewport and make the bubbles appear displaced.
          reverse: true,
        ),
      ),
    );
  }

  Widget _buildActiveCcpocketSession(BuildContext context) {
    final workspaceName = _workspaceName(_activeWorkspace.displayPath);
    final threadLabel = _shortThreadId(_client?.threadId ?? _lastThreadId);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final rootAssessment = _rootApprovalAssessment();
    final rootPolicyNotice =
        rootAssessment == null || rootAssessment.route == RootWriteRoute.direct
        ? null
        : rootAssessment.reason;
    final rootApprovalBlocked =
        rootAssessment != null && rootAssessment.route == RootWriteRoute.denied;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        leading: IconButton(
          key: const ValueKey('local_codex_session_back_button'),
          tooltip: zh ? '返回会话列表' : 'Back to sessions',
          onPressed: () => unawaited(_leaveActiveSession()),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _effectiveSessionTitle ?? workspaceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              threadLabel == 'none'
                  ? (zh ? '本地 Codex' : 'Local Codex')
                  : '${zh ? '本地 Codex' : 'Local Codex'} · $threadLabel',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('local_codex_session_settings_button'),
            tooltip: zh ? '会话设置' : 'Session settings',
            onPressed: _openSessionSettings,
            icon: const Icon(Icons.tune_outlined),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('local_codex_session_menu'),
            onSelected: (value) {
              switch (value) {
                case 'details':
                  _showSessionDetails();
                case 'rename':
                  _renameCurrentSession();
                case 'clear':
                  setState(() => _transcript.clear());
                  unawaited(_persistHistory());
                case 'stop':
                  unawaited(_stopClient());
                case 'fork':
                  unawaited(_forkCurrentSession());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'details',
                child: Text(zh ? '会话详情' : 'Session details'),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Text(zh ? '重命名会话' : 'Rename session'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(zh ? '清除可见消息' : 'Clear visible messages'),
              ),
              PopupMenuItem(
                value: 'stop',
                child: Text(zh ? '停止会话' : 'Stop session'),
              ),
              PopupMenuItem(
                value: 'fork',
                child: Text(zh ? '分叉会话' : 'Fork session'),
              ),
            ],
          ),
          IconButton(
            key: const ValueKey('local_codex_stop_session_button'),
            tooltip: zh ? '停止会话' : 'Stop session',
            onPressed: _stopClient,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
        bottom: CcpocketNativeStatusLine(status: _status),
      ),
      body: Column(
        children: [
          if (_connectionLost && _client == null)
            CcpocketNativeRecoveryBanner(
              reason:
                  _connectionLostReason ??
                  _uiText(
                    '本地 Codex app-server 已断开。',
                    'The local Codex app-server disconnected.',
                  ),
              onResume:
                  _accountBindingStale ||
                      _legacyChatOnlyHistory ||
                      _lastThreadId == null
                  ? null
                  : () => unawaited(_resumeSavedSession()),
              onStartNew: _startFreshConversation,
            ),
          if (_retryPrompt != null &&
              _error == _providerNetworkError &&
              !_accountBindingStale)
            CcpocketNativeRetryBanner(
              reason: _localizedProviderNetworkErrorFor(
                _providerNetworkDiagnostic,
              ),
              onRetry: () => unawaited(_retryLastPrompt()),
            ),
          Expanded(
            child: CcpocketNativeSessionSurface(
              header: null,
              entries: _transcript,
              localizeEntry: _localizedTranscriptEntry,
              status: _status,
              controller: _promptController,
              accountUsageSummary: _conversationAccountUsageSummary(),
              usageSummary: _conversationUsageSummary(),
              streamingSnapshot: _streamingSnapshot,
              queuedPrompts: _queuedPrompts,
              onRemoveQueuedPrompt: _removeQueuedPrompt,
              approval:
                  _approval == null ||
                      _approval!.requestMethod == 'item/tool/requestUserInput'
                  ? null
                  : CcpocketNativeApprovalPanel(
                      approval: _approval!,
                      onApprove: () => _respondToApproval(true),
                      onApproveForSession: () =>
                          _respondToApproval(true, forSession: true),
                      onApplyPolicyAmendment: (decision) {
                        final amendment =
                            decision['applyNetworkPolicyAmendment'];
                        final networkRule = amendment is Map
                            ? amendment['network_policy_amendment']
                            : null;
                        final deniesCurrentRequest =
                            networkRule is Map &&
                            networkRule['action'] == 'deny';
                        unawaited(
                          _respondToApproval(
                            !deniesCurrentRequest,
                            decisionOverride: decision,
                          ),
                        );
                      },
                      allowPersistentApprovals:
                          _identity != ExecutionIdentity.root,
                      onReject: () => _respondToApproval(false),
                      fileChanges: _agentFileChanges,
                      policyNotice: rootPolicyNotice,
                      approvalBlocked: rootApprovalBlocked,
                    ),
              userInput:
                  _approval?.requestMethod == 'item/tool/requestUserInput'
                  ? CcpocketNativeUserInputPanel(
                      request: _approval!,
                      onAnswer: _respondToUserInputResult,
                      onCancel: () =>
                          unawaited(_respondToUserInput(cancelled: true)),
                    )
                  : _approval?.requestMethod == 'mcpServer/elicitation/request'
                  ? CcpocketNativeMcpElicitationPanel(
                      request: _approval!,
                      onRespond: _respondToMcpElicitation,
                      onOpenUrl: _openMcpElicitationUrl,
                      allowPersistentApprovals:
                          _identity != ExecutionIdentity.root,
                    )
                  : null,
              modeBar: CcpocketNativeModeBar(
                model: _codexModel,
                effort: _codexEffort,
                approvalPolicy: _codexApprovalPolicy,
                sandbox: _codexSandbox,
                rootMode: _identity == ExecutionIdentity.root,
                planMode: _planMode,
                onOpenSettings: _openSessionSettings,
                onOpenPermissions: _showPermissionsPicker,
                onTogglePlan: _togglePlanMode,
                onOpenEffortSettings: _customProvider == null
                    ? null
                    : _openCustomProviderEffortSettings,
                showCodexControls: true,
              ),
              inputBlocked:
                  _approval != null ||
                  _busy ||
                  _providerSwitching ||
                  (_client == null && !_canQueueForReconnect),
              onSend: _sendPrompt,
              onStop: _stopClient,
              onInterrupt: _interruptSession,
              onSlashCommand: _showSlashCommands,
              onMention: _insertMention,
              onShowPromptHistory: _showPromptHistory,
              onIndent: _indentPrompt,
              onDedent: _dedentPrompt,
              attachedImages: _attachedImages,
              onAttachImage: _pickImages,
              onClearImage: _clearAttachedImage,
            ),
          ),
        ],
      ),
    );
  }

  /// A restored transcript is a saved conversation, not a currently stopped
  /// process. Keep that distinction visible in the compact status line while
  /// preserving the real lifecycle value for the composer and runtime logic.
  String get _historyPresentationStatus =>
      _status == 'stopped' && _transcript.isNotEmpty ? 'saved' : _status;

  String _localizedRuntimeFailure(String reason) {
    return localizeCodexRuntimeFailure(
      reason,
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  String _localizedTranscriptEntry(String entry) {
    return localizeCodexTranscriptEntry(
      entry,
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  Future<void> _leaveActiveSession() async {
    if (widget.onClose != null) {
      // Returning to Home is a visibility change only. The page is an
      // IndexedStack child and remains the owner of its client, stream
      // subscription, transcript, draft, and in-flight turn.
      widget.onClose!.call();
      return;
    }
    // Standalone callers still own the route, so let Navigator handle the
    // route boundary. The parent-owned app path above is the one used by the
    // local multi-session shell and never disposes this state on leave.
    if (mounted) Navigator.of(context).maybePop();
  }

  void _leaveInactiveSession() {
    if (widget.onClose != null) {
      widget.onClose!.call();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _showSessionDetails() async {
    final languageCode = Localizations.localeOf(context).languageCode;
    String text({
      required String en,
      required String zh,
      required String ja,
      required String ko,
    }) => switch (languageCode) {
      'zh' => zh,
      'ja' => ja,
      'ko' => ko,
      _ => en,
    };
    final sessionTitle = text(
      en: 'Local Android session',
      zh: 'Android 本地会话',
      ja: 'Android ローカルセッション',
      ko: 'Android 로컬 세션',
    );
    final sessionDescription = text(
      en: 'The app-server process and transcript stay on this device.',
      zh: 'app-server 进程和会话记录均保存在此设备上。',
      ja: 'app-server のプロセスと会話履歴はこの端末に保存されます。',
      ko: 'app-server 프로세스와 대화 기록은 이 기기에 저장됩니다.',
    );
    final workspaceLabel = text(
      en: 'Workspace',
      zh: '工作区',
      ja: 'ワークスペース',
      ko: '작업 공간',
    );
    final identityLabel = text(
      en: 'Execution identity',
      zh: '执行身份',
      ja: '実行 ID',
      ko: '실행 ID',
    );
    final identityValue = _identity == ExecutionIdentity.root
        ? text(
            en: 'Root helper',
            zh: 'Root 辅助执行',
            ja: 'Root ヘルパー',
            ko: 'Root 도우미',
          )
        : text(en: 'App UID', zh: '应用 UID', ja: 'アプリ UID', ko: '앱 UID');
    final runtimeLabel = text(
      en: 'Runtime path',
      zh: '运行环境',
      ja: '実行環境',
      ko: '런타임 경로',
    );
    final runtimeValue = _isCompatibility
        ? text(
            en: 'Linux Compatibility / PRoot fallback',
            zh: 'Linux 兼容环境 / PRoot 回退',
            ja: 'Linux 互換環境 / PRoot フォールバック',
            ko: 'Linux 호환 환경 / PRoot 대체 경로',
          )
        : text(
            en: 'Local Android',
            zh: '本地 Android',
            ja: 'ローカル Android',
            ko: '로컬 Android',
          );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            ListTile(
              leading: Icon(Icons.phone_android_outlined),
              title: Text(sessionTitle),
              subtitle: Text(sessionDescription),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(workspaceLabel),
              subtitle: Text(_activeWorkspace.displayPath),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(identityLabel),
              subtitle: Text(identityValue),
            ),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(runtimeLabel),
              subtitle: Text(runtimeValue),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameCurrentSession() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameSessionDialog(initialTitle: _effectiveSessionTitle),
    );
    if (!mounted || title == null) return;
    setState(() {
      final normalized = title.trim();
      _sessionTitle = normalized.isEmpty ? null : normalized;
      _sessionTitleManuallySet = normalized.isNotEmpty;
      _automaticTitleAttempted = true;
    });
    _publishSnapshot();
    unawaited(_persistHistory());

    final normalized = title.trim();
    final client = _client;
    if (normalized.isEmpty || client is! CodexSessionClient) return;
    try {
      await client.setThreadName(normalized);
    } catch (_) {
      if (!mounted) return;
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            zh ? '本地会话名称已保存，但未能同步到 Codex thread。' : 'The local session name was saved, but Codex could not sync it.',
          ),
        ),
      );
    }
  }

  String _workspaceName(String path) {
    return workspaceNameFromPath(path);
  }

  String _shortThreadId(String? value) {
    if (value == null || value.isEmpty) return 'none';
    return value.length > 10 ? value.substring(0, 10) : value;
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _InteractiveCommandDialog extends StatefulWidget {
  const _InteractiveCommandDialog({
    required this.command,
    required this.output,
    required this.result,
    required this.error,
    required this.chinese,
    required this.onWrite,
    required this.onResize,
    required this.onInterrupt,
  });

  final List<String> command;
  final ValueListenable<String> output;
  final ValueListenable<CodexCommandExecResult?> result;
  final ValueListenable<Object?> error;
  final bool chinese;
  final Future<void> Function(String input, {bool closeStdin}) onWrite;
  final Future<void> Function({required int rows, required int cols}) onResize;
  final Future<void> Function() onInterrupt;

  @override
  State<_InteractiveCommandDialog> createState() =>
      _InteractiveCommandDialogState();
}

class _InteractiveCommandDialogState extends State<_InteractiveCommandDialog> {
  final _inputController = TextEditingController();
  bool _writing = false;
  bool _stopping = false;
  Object? _inputError;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _writeInput([String? submitted]) async {
    final input = (submitted ?? _inputController.text);
    if (input.isEmpty ||
        widget.result.value != null ||
        widget.error.value != null) {
      return;
    }
    setState(() {
      _writing = true;
      _inputError = null;
    });
    try {
      await widget.onWrite('$input\n');
      if (submitted == null) _inputController.clear();
    } on Object catch (error) {
      if (mounted) setState(() => _inputError = error);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _stop() async {
    if (_stopping || widget.result.value != null) return;
    setState(() => _stopping = true);
    try {
      await widget.onInterrupt();
    } on Object catch (error) {
      // A failed interrupt must remain recoverable. Leaving this flag set
      // permanently disables stdin and the interrupt action for the rest of
      // the dialog, which is especially confusing when the PTY is only
      // temporarily unavailable.
      if (mounted) {
        setState(() {
          _inputError = error;
          _stopping = false;
        });
      }
    }
  }

  Future<void> _resize(int rows, int cols) async {
    try {
      await widget.onResize(rows: rows, cols: cols);
    } on Object catch (error) {
      if (mounted) setState(() => _inputError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.command.join(' ');
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[widget.result, widget.error]),
      builder: (context, _) {
        final result = widget.result.value;
        final error = widget.error.value;
        final finished = result != null || error != null;
        final media = MediaQuery.of(context);
        final availableHeight = media.size.height - media.viewInsets.bottom;
        final contentHeight =
            (availableHeight - 190).clamp(180.0, 480.0).toDouble();
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.terminal_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.chinese ? '交互式命令' : 'Interactive command',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: widget.chinese ? '调整终端大小' : 'Resize terminal',
                enabled: !finished,
                onSelected: (value) {
                  final parts = value.split('x');
                  unawaited(_resize(int.parse(parts[0]), int.parse(parts[1])));
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: '24x80', child: Text('80 × 24')),
                  PopupMenuItem(value: '40x120', child: Text('120 × 40')),
                ],
                icon: const Icon(Icons.aspect_ratio_outlined),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: contentHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ValueListenableBuilder<String>(
                      valueListenable: widget.output,
                      builder: (context, text, _) => SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        reverse: true,
                        child: SelectableText(
                          text.isEmpty ? ' ' : text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (error != null)
                  Text(
                    '${widget.chinese ? '失败' : 'Failed'}: $error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else if (result != null)
                  Text(
                    '${widget.chinese ? '退出码' : 'Exit code'}: ${result.exitCode}',
                    style: Theme.of(context).textTheme.labelMedium,
                  )
                else if (_inputError != null)
                  Text(
                    '${widget.chinese ? '输入失败' : 'Input failed'}: $_inputError',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inputController,
                  enabled: !finished && !_writing && !_stopping,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _writeInput,
                  decoration: InputDecoration(
                    hintText: widget.chinese ? '发送 stdin…' : 'Send stdin…',
                    suffixIcon: IconButton(
                      tooltip: widget.chinese ? '发送输入' : 'Send input',
                      onPressed: finished || _writing || _stopping
                          ? null
                          : () => _writeInput(),
                      icon: const Icon(Icons.send_outlined),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!finished)
              TextButton(
                onPressed: _stopping ? null : _stop,
                child: Text(widget.chinese ? '中断' : 'Interrupt'),
              ),
            if (finished)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.chinese ? '关闭' : 'Close'),
              ),
          ],
        );
      },
    );
  }
}
