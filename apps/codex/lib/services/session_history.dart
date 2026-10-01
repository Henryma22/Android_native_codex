import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/domain/execution.dart';
import '../core/domain/transcript.dart';
import '../core/domain/workspace.dart';

class SessionHistoryRecord {
  const SessionHistoryRecord({
    required this.backendId,
    required this.workspacePath,
    required this.status,
    required this.updatedAtEpochMs,
    required this.entries,
    this.sessionId,
    this.threadId,
    this.threadPath,
    this.authGeneration,
    this.customProviderId,
    this.title,
    this.threadName,
    this.titleIsManual = false,
    this.draft = '',
    this.queuedPrompts = const <String>[],
    this.codexModel = 'gpt-6-luna',
    this.codexEffort = 'low',
    this.executionIdentity = ExecutionIdentity.app,
    this.rootApprovalGranted = false,
    this.codexSandbox = 'workspace-write',
    this.codexPermissions,
    this.codexApprovalPolicy = 'on-request',
    this.codexPlanMode = false,
    this.promptHistory = const <String>[],
    this.pinned = false,
    String? cachedFirstUserPrompt,
    String? cachedLatestUserPrompt,
  }) : _cachedFirstUserPrompt = cachedFirstUserPrompt,
       _cachedLatestUserPrompt = cachedLatestUserPrompt;

  factory SessionHistoryRecord.fromMap(Map<Object?, Object?> value) {
    final workspacePath = value['workspacePath'] as String? ?? '';
    final entries = (value['entries'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>()
        .toList(growable: false);
    final promptHistory =
        (value['promptHistory'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .where((prompt) => prompt.trim().isNotEmpty)
            .take(30)
            .toList(growable: false);
    final title = _titleFrom(value['title']);
    final userPrompts = _userPromptsFrom(entries, promptHistory);
    final localTitle = _compactTitle(
      userPrompts.first,
      workspaceNameFromPath(workspacePath),
    );
    final titleIsManual =
        value['titleIsManual'] == true ||
        (value['titleIsManual'] == null &&
            title != null &&
            title != localTitle);
    return SessionHistoryRecord(
      backendId: value['backendId'] as String? ?? '',
      workspacePath: workspacePath,
      status: value['status'] as String? ?? 'stopped',
      updatedAtEpochMs: (value['updatedAtEpochMs'] as num?)?.toInt() ?? 0,
      sessionId: value['sessionId'] as String?,
      threadId: value['threadId'] as String?,
      threadPath: _optionalText(value['threadPath']),
      authGeneration: _authGenerationFrom(value['authGeneration']),
      customProviderId: _optionalText(value['customProviderId']),
      title: title,
      threadName: _titleFrom(value['threadName']),
      titleIsManual: titleIsManual,
      draft: value['draft'] as String? ?? '',
      entries: entries,
      cachedFirstUserPrompt: userPrompts.first,
      cachedLatestUserPrompt: userPrompts.latest,
      queuedPrompts:
          (value['queuedPrompts'] as List<Object?>? ?? const <Object?>[])
              .whereType<String>()
              .toList(growable: false),
      // Keep the selected CLI model with the session. The catalog is loaded
      // separately and can still insert the current value when a model has
      // disappeared from the latest online list.
      codexModel: _modelFrom(value['codexModel']),
      codexEffort: _effortFrom(value['codexEffort']),
      executionIdentity: _executionIdentityFrom(value['executionIdentity']),
      rootApprovalGranted:
          value['rootApprovalGranted'] == true &&
          ((value['sessionId'] as String?)?.trim().isNotEmpty ?? false),
      codexSandbox: _sandboxFrom(value['codexSandbox']),
      codexPermissions: _permissionsFrom(value['codexPermissions']),
      codexApprovalPolicy: _approvalPolicyFrom(value['codexApprovalPolicy']),
      codexPlanMode: value['codexPlanMode'] == true,
      pinned: value['pinned'] == true,
      promptHistory: promptHistory,
    );
  }

  static String _sandboxFrom(Object? value) => switch (value) {
    'read-only' => 'read-only',
    'danger-full-access' => 'danger-full-access',
    _ => 'workspace-write',
  };

  static String _modelFrom(Object? value) {
    final model = (value as String?)?.trim();
    return model == null || model.isEmpty ? 'gpt-6-luna' : model;
  }

  static String _effortFrom(Object? value) {
    final effort = (value as String?)?.trim();
    return effort == null || effort.isEmpty ? 'low' : effort;
  }

  static int? _authGenerationFrom(Object? value) {
    final generation = (value as num?)?.toInt();
    return generation == null || generation <= 0 ? null : generation;
  }

  static ExecutionIdentity _executionIdentityFrom(Object? value) =>
      value == 'root' ? ExecutionIdentity.root : ExecutionIdentity.app;

  static String _approvalPolicyFrom(Object? value) => switch (value) {
    'on-failure' => 'on-failure',
    'never' => 'never',
    _ => 'on-request',
  };

  static String? _permissionsFrom(Object? value) {
    final permissions = (value as String?)?.trim();
    if (permissions == null ||
        permissions.isEmpty ||
        permissions.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    return permissions;
  }

  static String? _titleFrom(Object? value) {
    final title = (value as String?)?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  static String? _optionalText(Object? value) {
    final text = (value as String?)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static ({String first, String latest}) _userPromptsFrom(
    List<String> entries,
    List<String> promptHistory,
  ) {
    String? first;
    String? latest;
    for (final raw in entries) {
      final entry = CodexTranscriptEntry.fromStored(raw);
      if (entry.kind == CodexTranscriptKind.user &&
          entry.text.trim().isNotEmpty) {
        final prompt = entry.text.trim();
        first ??= prompt;
        latest = prompt;
      }
    }
    return (
      first: first ?? (promptHistory.isEmpty ? '' : promptHistory.last.trim()),
      latest:
          latest ?? (promptHistory.isEmpty ? '' : promptHistory.first.trim()),
    );
  }

  final String? _cachedFirstUserPrompt;
  final String? _cachedLatestUserPrompt;

  static String _compactTitle(String prompt, String workspaceName) {
    final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return workspaceName;
    final runes = normalized.runes.toList(growable: false);
    return String.fromCharCodes(runes.take(36)) +
        (runes.length > 36 ? '…' : '');
  }

  final String backendId;
  final String workspacePath;
  final String status;
  final int updatedAtEpochMs;
  final String? sessionId;
  final String? threadId;
  final String? threadPath;

  /// Authentication generation that created this provider thread.
  ///
  /// Null is retained for records written by older app versions. Those rows
  /// remain readable, but the home shell deliberately never auto-resumes them.
  final int? authGeneration;

  /// Identifies the encrypted provider config; credentials never belong here.
  final String? customProviderId;
  final String? title;
  final String? threadName;
  final bool titleIsManual;
  final String draft;
  final List<String> entries;
  final List<String> queuedPrompts;
  final String codexModel;
  final String codexEffort;
  final ExecutionIdentity executionIdentity;
  final bool rootApprovalGranted;
  final String codexSandbox;
  final String? codexPermissions;
  final String codexApprovalPolicy;
  final bool codexPlanMode;
  final List<String> promptHistory;
  final bool pinned;

  /// Whether this durable row represents a session that should be brought
  /// back after the app process is recreated. The only explicit opt-out is a
  /// persisted `stopped` state, which is written by the user-facing Stop
  /// action. A process death, app upgrade, or app-server exit must leave the
  /// row resumable so the next app instance can reconnect to its thread.
  bool get shouldAutoResume {
    final normalizedStatus = status.trim().toLowerCase();
    final stableSessionId = sessionId?.trim();
    final providerThreadId = threadId?.trim();
    return stableSessionId != null &&
        stableSessionId.isNotEmpty &&
        providerThreadId != null &&
        providerThreadId.isNotEmpty &&
        normalizedStatus != 'stopped';
  }

  bool canAutoResumeForAuthGeneration(int currentGeneration) {
    if (!shouldAutoResume) return false;
    // A custom provider owns its own endpoint and credential configuration;
    // changing the first-party OpenAI login generation must not invalidate a
    // third-party session. The provider id is still checked when Home opens
    // the row, so a deleted configuration becomes a visible history-only row
    // instead of silently switching to another provider.
    if (customProviderId?.trim().isNotEmpty == true) return true;
    return currentGeneration > 0 && authGeneration == currentGeneration;
  }

  String get firstUserPrompt {
    final cached = _cachedFirstUserPrompt;
    if (cached != null) return cached;
    for (final raw in entries) {
      final entry = CodexTranscriptEntry.fromStored(raw);
      if (entry.kind == CodexTranscriptKind.user &&
          entry.text.trim().isNotEmpty) {
        return entry.text.trim();
      }
    }
    return promptHistory.isEmpty ? '' : promptHistory.last.trim();
  }

  String get latestUserPrompt {
    final cached = _cachedLatestUserPrompt;
    if (cached != null) return cached;
    for (final raw in entries.reversed) {
      final entry = CodexTranscriptEntry.fromStored(raw);
      if (entry.kind == CodexTranscriptKind.user &&
          entry.text.trim().isNotEmpty) {
        return entry.text.trim();
      }
    }
    return promptHistory.isEmpty ? '' : promptHistory.first.trim();
  }

  /// A stable local title derived from the first user request. Never use the
  /// latest assistant answer as a session name; it changes on every turn.
  String get generatedTitle {
    return _compactTitle(firstUserPrompt, workspaceName);
  }

  /// The most recent non-empty transcript line. The history store keeps the
  /// transcript as display-ready text, so this is intentionally conservative
  /// and does not try to reconstruct provider messages.
  String get latestEntry {
    for (final entry in entries.reversed) {
      final value = CodexTranscriptEntry.fromStored(entry).displayLine.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String get preview {
    var value = latestEntry;
    // Codex can emit an optional-worker diagnostic after a successful turn.
    // Keep the Home card aligned with CC Pocket's conversation-first summary:
    // when a real user/assistant entry exists, do not let a trailing optional
    // transport notice hide the last useful exchange. A history containing
    // only that diagnostic still shows the readable fallback notice below.
    if (_isOptionalMcpDiagnostic(value)) {
      final conversational = entries.reversed.cast<String?>().firstWhere(
        (entry) => entry != null && _isConversationalEntry(entry),
        orElse: () => null,
      );
      if (conversational != null) value = conversational;
    }
    // Codex 0.154.0 can emit this non-fatal Android cleanup diagnostic before
    // the first real message. It is an implementation detail, not a session
    // preview, and should not become the latest row shown on Home.
    if (_isBenignArg0Diagnostic(value)) {
      final conversational = entries.reversed.cast<String?>().firstWhere(
        (entry) => entry != null && _isConversationalEntry(entry),
        orElse: () => null,
      );
      if (conversational != null) {
        value = conversational;
      } else {
        return 'Local Codex session';
      }
    }
    if (value.isEmpty) return 'No messages yet';
    value = _stripAnsi(value)
        .replaceFirst(
          RegExp(r'^(You|Codex|Thinking|Tool|System|stderr|error):\s*'),
          '',
        )
        .trim();
    final normalized = value.toLowerCase();
    if (normalized.contains('tls handshake eof') ||
        normalized.contains('failed to connect to websocket') ||
        normalized.contains('stream disconnected before completion')) {
      return 'Provider network connection failed. Check Android Wi-Fi, mobile data, VPN, or proxy settings and retry. The local session remains available.';
    }
    if (_isOptionalMcpDiagnostic(value)) {
      return 'Optional MCP worker unavailable; the local Codex session continues without it.';
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        for (final key in const ['text', 'message', 'output', 'summary']) {
          final candidate = decoded[key];
          if (candidate is String && candidate.trim().isNotEmpty) {
            return candidate.trim();
          }
        }
        final content = decoded['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
        if (content is List) {
          final parts = content
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toList(growable: false);
          if (parts.isNotEmpty) return parts.join('\n');
        }
      }
    } on FormatException {
      // Older records are display-ready plain text, not structured JSON.
    }
    return value;
  }

  static bool _isOptionalMcpDiagnostic(String value) {
    final normalized = _stripAnsi(value).toLowerCase();
    return normalized.contains('rmcp::transport::worker') ||
        normalized.contains('optional mcp worker') ||
        (normalized.contains('mcp') &&
            (normalized.contains('http request failed') ||
                normalized.contains('transport channel closed')));
  }

  static bool _isBenignArg0Diagnostic(String value) {
    return isBenignCodexRuntimeDiagnostic(value);
  }

  static bool _isConversationalEntry(String value) {
    final parsed = CodexTranscriptEntry.fromStored(value);
    if (parsed.kind == CodexTranscriptKind.user ||
        parsed.kind == CodexTranscriptKind.assistant) {
      return parsed.text.trim().isNotEmpty;
    }
    final cleaned = _stripAnsi(value).trimLeft();
    return RegExp(
      r'^(you|user|codex|assistant):',
      caseSensitive: false,
    ).hasMatch(cleaned);
  }

  static String _stripAnsi(String value) =>
      value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');

  String get workspaceName {
    return workspaceNameFromPath(workspacePath);
  }

  String get displayTitle {
    final currentTitle = title?.trim();
    if (titleIsManual && currentTitle != null && currentTitle.isNotEmpty) {
      return currentTitle;
    }
    final codexTitle = threadName?.trim();
    if (codexTitle != null && codexTitle.isNotEmpty) return codexTitle;
    if (currentTitle != null && currentTitle.isNotEmpty) return currentTitle;
    return generatedTitle;
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return <String>[
      backendId,
      workspacePath,
      ?title,
      ?threadName,
      ...entries.map(
        (entry) => CodexTranscriptEntry.fromStored(entry).displayLine,
      ),
    ].join('\n').toLowerCase().contains(normalized);
  }
}

typedef SessionHistoryWrite = Future<void> Function();

/// Serializes app-private history writes so an older snapshot cannot finish
/// after a newer one and overwrite it.
class SessionHistoryWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(SessionHistoryWrite write) {
    final next = _tail.then<void>(
      (_) => write(),
      onError: (Object _) => write(),
    );
    _tail = next.catchError((Object _) {});
    return next;
  }
}

/// App-private history only. It is not a provider-thread reconnect token.
class SessionHistoryStore {
  static const _channel = MethodChannel('io.henry.codex/session_history');

  Future<SessionHistoryRecord?> load(WorkspaceRef workspace) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'loadSessionHistory',
        <String, Object?>{'key': _key(workspace)},
      );
      if (raw is Map<Object?, Object?>) {
        return SessionHistoryRecord.fromMap(raw);
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  /// Returns the app-private local session index, newest first. This is a
  /// history index only; opening a row still goes through the normal backend
  /// capability checks and provider-thread resume rules.
  Future<List<SessionHistoryRecord>> list() async {
    // The store is an Android app-private index. Host-side Flutter tests and
    // non-Android tooling do not have an Android platform channel, so avoid
    // leaving an unhandled message (and its spinner) pending there.
    if (!Platform.isAndroid) return const <SessionHistoryRecord>[];
    try {
      final raw = await _channel
          .invokeMethod<List<Object?>>('listSessionHistories')
          .timeout(const Duration(seconds: 4));
      return (raw ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(SessionHistoryRecord.fromMap)
          .where((record) => record.workspacePath.isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const <SessionHistoryRecord>[];
    } on TimeoutException {
      // History is an optional local index. A stalled platform channel must
      // not leave the CC Pocket home screen in an endless loading state.
      return const <SessionHistoryRecord>[];
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> save({
    required WorkspaceRef workspace,
    required List<String> entries,
    required String status,
    String? sessionId,
    String? threadId,
    String? threadPath,
    int? authGeneration,
    String? customProviderId,
    String? title,
    String? threadName,
    bool titleIsManual = false,
    String draft = '',
    List<String> queuedPrompts = const <String>[],
    String codexModel = 'gpt-6-luna',
    String codexEffort = 'low',
    ExecutionIdentity executionIdentity = ExecutionIdentity.app,
    bool rootApprovalGranted = false,
    String codexSandbox = 'workspace-write',
    String? codexPermissions,
    String codexApprovalPolicy = 'on-request',
    bool codexPlanMode = false,
    List<String> promptHistory = const <String>[],
    bool pinned = false,
  }) async {
    try {
      final record = <String, Object?>{
        'backendId': workspace.backendId,
        'workspacePath': workspace.hostPath,
        'status': status,
        'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
        if (sessionId != null && sessionId.trim().isNotEmpty)
          'sessionId': sessionId.trim(),
        if (customProviderId != null && customProviderId.trim().isNotEmpty)
          'customProviderId': customProviderId.trim(),
        'draft': draft,
        'queuedPrompts': queuedPrompts,
        'codexModel': codexModel,
        'codexEffort': codexEffort,
        'executionIdentity': executionIdentity.name,
        // A Root grant is meaningful only for a durable, named session; it
        // must never leak from legacy one-workspace history into new work.
        'rootApprovalGranted':
            rootApprovalGranted && sessionId?.trim().isNotEmpty == true,
        'codexSandbox': codexSandbox,
        if (codexPermissions != null && codexPermissions.trim().isNotEmpty)
          'codexPermissions': codexPermissions.trim(),
        'codexApprovalPolicy': codexApprovalPolicy,
        'codexPlanMode': codexPlanMode,
        'pinned': pinned,
        'titleIsManual': titleIsManual,
        'promptHistory': promptHistory,
        'entries': entries,
      };
      final normalizedTitle = title?.trim();
      if (normalizedTitle != null && normalizedTitle.isNotEmpty) {
        record['title'] = normalizedTitle;
      }
      final normalizedThreadName = threadName?.trim();
      if (normalizedThreadName != null && normalizedThreadName.isNotEmpty) {
        record['threadName'] = normalizedThreadName;
      }
      if (threadId != null) record['threadId'] = threadId;
      if (threadPath != null && threadPath.trim().isNotEmpty) {
        record['threadPath'] = threadPath.trim();
      }
      if (authGeneration != null && authGeneration > 0) {
        record['authGeneration'] = authGeneration;
      }
      await _channel.invokeMethod<void>('saveSessionHistory', <String, Object?>{
        'key': _key(workspace, sessionId),
        'record': record,
      });
    } on MissingPluginException {
      // Non-Android widget tests and other platforms have no native store.
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> updateFlags(SessionHistoryRecord history, {bool? pinned}) async {
    if (pinned == null) return;
    try {
      final arguments = <String, Object?>{
        'key': _keyFromValues(
          history.backendId,
          history.workspacePath,
          history.sessionId,
        ),
      };
      arguments['pinned'] = pinned;
      await _channel.invokeMethod<void>('updateSessionHistoryFlags', arguments);
    } on MissingPluginException {
      // Non-Android widget tests and other platforms have no native store.
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> delete(SessionHistoryRecord history) async {
    try {
      await _channel.invokeMethod<void>('clearSessionHistory', {
        'key': _keyFromValues(
          history.backendId,
          history.workspacePath,
          history.sessionId,
        ),
      });
    } on MissingPluginException {
      // Non-Android widget tests and other platforms have no native store.
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> clearAll() async {
    try {
      await _channel.invokeMethod<void>('clearAllSessionHistories');
    } on MissingPluginException {
      // Non-Android widget tests and other platforms have no native store.
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<void> updateTitle(SessionHistoryRecord history, String? title) async {
    try {
      await _channel.invokeMethod<void>('updateSessionHistoryTitle', {
        'key': _keyFromValues(
          history.backendId,
          history.workspacePath,
          history.sessionId,
        ),
        'title': title?.trim() ?? '',
      });
    } on MissingPluginException {
      // Non-Android widget tests and other platforms have no native store.
    } on PlatformException catch (error) {
      throw StateError(error.message ?? error.code);
    }
  }

  Future<SessionHistoryRecord?> loadLatest(WorkspaceRef workspace) async {
    final matches = (await list())
        .where(
          (record) =>
              record.backendId == workspace.backendId &&
              record.workspacePath == workspace.hostPath,
        )
        .toList(growable: false);
    if (matches.isNotEmpty) return matches.first;
    // Keep old one-record-per-workspace data readable after the session index
    // becomes multi-session aware.
    return load(workspace);
  }

  String _key(WorkspaceRef workspace, [String? sessionId]) {
    return _keyFromValues(workspace.backendId, workspace.hostPath, sessionId);
  }

  String _keyFromValues(
    String backendId,
    String workspacePath,
    String? sessionId,
  ) {
    final base = '$backendId|$workspacePath';
    final normalized = sessionId?.trim();
    return normalized == null || normalized.isEmpty
        ? base
        : '$base|session:$normalized';
  }
}
