import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ccpocket_ui/features/session_list/widgets/home_content.dart';
import 'package:ccpocket_ui/features/session_list/state/session_list_presentation.dart'
    as pocket_list;
import 'package:ccpocket_ui/models/messages.dart' as pocket;

import 'core/domain/backend.dart';
import 'core/application/codex_usage.dart';
import 'core/domain/workspace.dart';
import 'services/app_host_access_probe.dart';
import 'services/session_history.dart';
import 'ccpocket_usage.dart';

/// The local app's data adapter for the original CC Pocket HomeContent.
///
/// This file deliberately contains no home-page layout. The list, grouping,
/// search, filters, cards, slidable actions and empty/loading states all come
/// from the copied CC Pocket presentation source. Only local history and
/// session callbacks are projected into the widget's original input contract.
class CcpocketNativeHome extends StatefulWidget {
  const CcpocketNativeHome({
    required this.backend,
    this.fallbackBackend,
    required this.descriptor,
    required this.workspaces,
    required this.sessionHistories,
    required this.hostAccess,
    this.usage,
    this.onOpenUsageSettings,
    required this.onCreateHostWorkspace,
    required this.onAddSafWorkspace,
    required this.onRefresh,
    required this.onWorkspaceChanged,
    required this.onHistoryFlagsChanged,
    required this.onDeleteSession,
    required this.onHistoryTitleChanged,
    required this.activeSession,
    this.activeSessions = const <CcpocketHomeSessionSnapshot>[],
    required this.onOpenSession,
    this.onOpenFiles,
    required this.onOpenHistory,
    required this.onOpenActiveSession,
    required this.onStopActiveSession,
    required this.onToggleActiveSessionPinned,
    this.onOpenActiveSessionById,
    this.onStopActiveSessionById,
    this.onToggleActiveSessionPinnedById,
    super.key,
  });

  final Backend backend;
  final Backend? fallbackBackend;
  final BackendDescriptor descriptor;
  final Future<List<WorkspaceRef>> workspaces;
  final Future<List<SessionHistoryRecord>> sessionHistories;
  final Future<AppHostAccessResult> hostAccess;
  final CodexUsageSnapshot? usage;
  final VoidCallback? onOpenUsageSettings;
  final Future<void> Function() onCreateHostWorkspace;
  final Future<void> Function() onAddSafWorkspace;
  final Future<void> Function() onRefresh;
  final Future<void> Function(WorkspaceRef workspace) onWorkspaceChanged;
  final Future<void> Function(SessionHistoryRecord history, {bool? pinned})
  onHistoryFlagsChanged;
  final Future<void> Function(SessionHistoryRecord history) onDeleteSession;
  final Future<void> Function(SessionHistoryRecord history, String? title)
  onHistoryTitleChanged;
  final CcpocketHomeSessionSnapshot? activeSession;
  final List<CcpocketHomeSessionSnapshot> activeSessions;
  final Future<void> Function(WorkspaceRef workspace) onOpenSession;
  final Future<void> Function(WorkspaceRef workspace)? onOpenFiles;
  final Future<void> Function(
    WorkspaceRef workspace,
    SessionHistoryRecord history,
  )
  onOpenHistory;
  final VoidCallback onOpenActiveSession;
  final Future<void> Function() onStopActiveSession;
  final Future<void> Function() onToggleActiveSessionPinned;
  final ValueChanged<String>? onOpenActiveSessionById;
  final Future<void> Function(String)? onStopActiveSessionById;
  final Future<void> Function(String)? onToggleActiveSessionPinnedById;

  @override
  State<CcpocketNativeHome> createState() => _CcpocketNativeHomeState();
}

class CcpocketHomeSessionSnapshot {
  const CcpocketHomeSessionSnapshot({
    required this.workspace,
    required this.status,
    required this.active,
    this.busy = false,
    this.turnActive = false,
    required this.queuedPrompts,
    required this.sessionId,
    required this.title,
    required this.pinned,
    required this.model,
    required this.effort,
    required this.sandbox,
    required this.approvalPolicy,
    required this.planMode,
    required this.createdAtEpochMs,
    required this.lastActivityAtEpochMs,
    required this.lastMessage,
  });

  final WorkspaceRef workspace;
  final String status;
  final bool active;
  final bool busy;
  final bool turnActive;
  final List<String> queuedPrompts;
  final String? sessionId;
  final String? title;
  final bool pinned;
  final String model;
  final String effort;
  final String sandbox;
  final String approvalPolicy;
  final bool planMode;
  final int createdAtEpochMs;
  final int lastActivityAtEpochMs;
  final String lastMessage;
}

class _CcpocketNativeHomeState extends State<CcpocketNativeHome> {
  final Set<String> _collapsedProjectPaths = <String>{};
  final Set<String> _pinnedProjectPaths = <String>{};
  String? _projectFilter;
  String _searchQuery = '';
  bool _namedOnly = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SessionHistoryRecord>>(
      future: widget.sessionHistories,
      builder: (context, snapshot) {
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        final histories = snapshot.data ?? const <SessionHistoryRecord>[];
        final isInitialLoading =
            snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasError;
        if (snapshot.hasError) {
          return _LocalHomeError(
            message: zh
                ? '无法读取本地会话：${snapshot.error}'
                : 'Could not read local sessions: ${snapshot.error}',
            onRetry: widget.onRefresh,
          );
        }

        final liveSnapshots = _liveSnapshots();
        final visibleHistories = histories;
        final recentSessionIdByHistory = <SessionHistoryRecord, String>{};
        final historyByRecentSessionId = <String, SessionHistoryRecord>{};
        final historyIdentifiers = <String>{};
        for (final history in visibleHistories) {
          final recentId = _recentSessionId(history);
          recentSessionIdByHistory[history] = recentId;
          historyByRecentSessionId.putIfAbsent(recentId, () => history);
          historyIdentifiers.add(recentId);
          final sessionId = history.sessionId;
          if (sessionId != null && sessionId.isNotEmpty) {
            historyIdentifiers.add(sessionId);
          }
          final threadId = history.threadId;
          if (threadId != null && threadId.isNotEmpty) {
            historyIdentifiers.add(threadId);
          }
        }
        final activeSnapshotIndexById = <String, int>{};
        for (var index = 0; index < liveSnapshots.length; index++) {
          final sessionId = liveSnapshots[index].sessionId;
          if (sessionId != null) {
            activeSnapshotIndexById.putIfAbsent(sessionId, () => index);
          }
        }
        CcpocketHomeSessionSnapshot? snapshotForHistory(
          SessionHistoryRecord history,
        ) {
          final identifiers = <String>[
            recentSessionIdByHistory[history]!,
            if (history.sessionId?.isNotEmpty == true) history.sessionId!,
            if (history.threadId?.isNotEmpty == true) history.threadId!,
          ];
          var firstIndex = liveSnapshots.length;
          CcpocketHomeSessionSnapshot? match;
          for (final id in identifiers) {
            final index = activeSnapshotIndexById[id];
            if (index != null && index < firstIndex) {
              firstIndex = index;
              match = liveSnapshots[index];
            }
          }
          return match;
        }

        final recent = <pocket.RecentSession>[
          for (final history in visibleHistories)
            _toPocketRecentSession(
              history,
              localStatus: _historyStatusFor(
                history,
                snapshotForHistory(history),
              ),
            ),
          for (final snapshot in liveSnapshots)
            if (snapshot.sessionId == null ||
                !historyIdentifiers.contains(snapshot.sessionId))
              _toLivePocketRecentSession(snapshot),
        ]..sort((left, right) => right.modified.compareTo(left.modified));
        final normalizedSearchQuery = _searchQuery.trim().toLowerCase();
        final filteredRecent = recent
            .where((session) {
              if (_projectFilter != null &&
                  session.projectPath != _projectFilter) {
                return false;
              }
              final history = historyByRecentSessionId[session.sessionId];
              if (_namedOnly) {
                final hasPersistedName =
                    history != null &&
                    <String?>[
                      history.title,
                      history.threadName,
                    ].any((name) => name?.trim().isNotEmpty == true);
                final hasLiveName =
                    history == null && session.name?.trim().isNotEmpty == true;
                if (!hasPersistedName && !hasLiveName) {
                  return false;
                }
              }
              if (normalizedSearchQuery.isEmpty) {
                return true;
              }
              if (history != null) {
                return history.matches(normalizedSearchQuery);
              }
              return <String?>[
                session.name,
                session.firstPrompt,
                session.lastPrompt,
                session.summary,
                session.projectPath,
              ].any(
                (value) =>
                    value?.toLowerCase().contains(normalizedSearchQuery) ==
                    true,
              );
            })
            .toList(growable: false);
        final projects = <String>{
          for (final history in visibleHistories)
            if (history.workspacePath.isNotEmpty)
              humanReadableWorkspacePath(history.workspacePath),
          for (final snapshot in liveSnapshots)
            if (snapshot.workspace.displayPath.isNotEmpty)
              humanReadableWorkspacePath(snapshot.workspace.displayPath),
        };
        final pinnedSessionKeys = <String>{
          for (final history in visibleHistories.where(
            (history) => history.pinned,
          ))
            pocket_list.sessionPinKey(
              provider: pocket.Provider.codex.value,
              projectPath: humanReadableWorkspacePath(history.workspacePath),
              sessionId: recentSessionIdByHistory[history]!,
            ),
          for (final snapshot in liveSnapshots.where(
            (snapshot) => snapshot.pinned,
          ))
            if (snapshot.sessionId case final id?)
              pocket_list.sessionPinKey(
                provider: pocket.Provider.codex.value,
                projectPath: humanReadableWorkspacePath(
                  snapshot.workspace.displayPath,
                ),
                sessionId: id,
              ),
        };
        return HomeContent(
          key: const ValueKey('ccpocket_home_content'),
          leadingContent: _LocalWorkspaceOverview(
            workspaces: widget.workspaces,
            hostAccess: widget.hostAccess,
            onCreateHostWorkspace: widget.onCreateHostWorkspace,
            onAddSafWorkspace: widget.onAddSafWorkspace,
            onRefresh: widget.onRefresh,
            onOpenSession: widget.onOpenSession,
            onOpenFiles: widget.onOpenFiles,
            onWorkspaceChanged: widget.onWorkspaceChanged,
          ),
          recentHeaderTrailing: widget.usage?.hasData == true
              ? CcpocketCodexUsageSummary(
                  usage: widget.usage!,
                  zh: Localizations.localeOf(context).languageCode == 'zh',
                  onTap: widget.onOpenUsageSettings,
                )
              : null,
          // The outer Codex shell overlays an extended FAB on this shared
          // CC Pocket list. Reserve its footprint so the final session card
          // can scroll clear of the button.
          bottomContentInset: 88,
          connectionState: pocket.LocalRuntimeConnectionState.connected,
          sessions: const <pocket.SessionInfo>[],
          recentSessions: filteredRecent,
          accumulatedProjectPaths: projects,
          collapsedProjectPaths: _collapsedProjectPaths,
          pinnedProjectPaths: _pinnedProjectPaths,
          pinnedSessionKeys: pinnedSessionKeys,
          searchQuery: _searchQuery,
          isLoadingMore: false,
          isInitialLoading: isInitialLoading,
          hasMoreSessions: false,
          currentProjectFilter: _projectFilter,
          namedOnly: _namedOnly,
          onNewSession: _openFirstWorkspace,
          showRunningSection: false,
          compactRecentCards: true,
          onTapRunning:
              (
                sessionId, {
                projectPath,
                gitBranch,
                worktreePath,
                provider,
                permissionMode,
                sandboxMode,
                approvalPolicy,
                approvalsReviewer,
              }) {
                _openRunningSession(sessionId);
              },
          onStopSession: (sessionId) =>
              unawaited(_stopRunningSession(sessionId)),
          onResumeSession: (session) =>
              unawaited(_openRecentSession(session, histories)),
          onToggleRecentSessionPinned: (session) {
            final live = _snapshotForRecentSession(session, liveSnapshots);
            if (live?.sessionId case final id?) {
              unawaited(_toggleRunningSessionPinned(id));
              return;
            }
            final history = _historyFor(session, histories);
            if (history == null) return;
            unawaited(
              widget.onHistoryFlagsChanged(history, pinned: !history.pinned),
            );
          },
          onLongPressRecentSession: (session, position) =>
              unawaited(_showRecentActions(session, histories)),
          onDeleteSession: (session) {
            final history = _historyFor(session, histories);
            if (history == null) return;
            unawaited(widget.onDeleteSession(history));
          },
          onLongPressRunningSession: (session, _) =>
              _openRunningSession(_sessionIdFor(session)),
          onToggleRunningSessionPinned: (session) =>
              unawaited(_toggleRunningSessionPinned(_sessionIdFor(session))),
          onSelectProject: (value) => setState(() => _projectFilter = value),
          onSearchQueryChanged: (value) => setState(() => _searchQuery = value),
          onLoadMore: () {},
          onToggleProjectCollapsed: (path) => setState(() {
            if (!_collapsedProjectPaths.add(path)) {
              _collapsedProjectPaths.remove(path);
            }
          }),
          onToggleProjectPinned: (path) => setState(() {
            if (!_pinnedProjectPaths.add(path)) {
              _pinnedProjectPaths.remove(path);
            }
          }),
          onToggleNamed: () => setState(() => _namedOnly = !_namedOnly),
          showInlineStopButtonOverride: true,
        );
      },
    );
  }

  List<CcpocketHomeSessionSnapshot> _liveSnapshots() {
    final snapshots = widget.activeSessions.isNotEmpty
        ? widget.activeSessions
        : <CcpocketHomeSessionSnapshot?>[widget.activeSession]
              .whereType<CcpocketHomeSessionSnapshot>()
              .toList(growable: false);
    return snapshots
        .where((snapshot) => snapshot.active && snapshot.sessionId != null)
        .toList(growable: false);
  }

  String? _liveStatusFor(CcpocketHomeSessionSnapshot? snapshot) {
    if (snapshot == null) return null;
    final normalized = snapshot.status.toLowerCase();
    if (normalized.contains('approval') || normalized.contains('wait')) {
      return 'waiting';
    }
    if (normalized.contains('fail') || normalized.contains('error')) {
      return 'failed';
    }
    if (normalized.contains('reconnect')) return 'reconnecting';
    if (normalized.contains('disconnect')) return 'disconnected';
    if (snapshot.turnActive) return 'generating';
    if (snapshot.busy || normalized.contains('start')) return 'starting';
    return 'ready';
  }

  /// Keep terminal provider state visible after an app restart, without
  /// pretending that the persisted row is still an active local process.
  ///
  /// A live snapshot always wins. Persisted disconnected/failed states are
  /// only presentation metadata; opening the card still follows the history
  /// path and can reconnect through the normal session lifecycle.
  String? _historyStatusFor(
    SessionHistoryRecord history,
    CcpocketHomeSessionSnapshot? snapshot,
  ) {
    final liveStatus = _liveStatusFor(snapshot);
    if (liveStatus != null) return liveStatus;
    final normalized = history.status.trim().toLowerCase();
    if (normalized.contains('disconnect')) return 'disconnected';
    if (normalized.contains('fail') ||
        normalized.contains('error') ||
        normalized.contains('exit')) {
      return 'failed';
    }
    return null;
  }

  CcpocketHomeSessionSnapshot? _snapshotForRecentSession(
    pocket.RecentSession session,
    List<CcpocketHomeSessionSnapshot> snapshots,
  ) => snapshots.cast<CcpocketHomeSessionSnapshot?>().firstWhere(
    (snapshot) => snapshot?.sessionId == session.sessionId,
    orElse: () => null,
  );

  String _sessionIdFor(pocket.SessionInfo session) => session.id;

  void _openRunningSession(String sessionId) {
    final callback = widget.onOpenActiveSessionById;
    if (callback != null) {
      callback(sessionId);
    } else {
      widget.onOpenActiveSession();
    }
  }

  Future<void> _stopRunningSession(String sessionId) {
    final callback = widget.onStopActiveSessionById;
    return callback == null
        ? widget.onStopActiveSession()
        : callback(sessionId);
  }

  Future<void> _toggleRunningSessionPinned(String sessionId) {
    final callback = widget.onToggleActiveSessionPinnedById;
    return callback == null
        ? widget.onToggleActiveSessionPinned()
        : callback(sessionId);
  }

  pocket.RecentSession _toPocketRecentSession(
    SessionHistoryRecord history, {
    String? localStatus,
  }) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      history.updatedAtEpochMs > 0
          ? history.updatedAtEpochMs
          : DateTime.now().millisecondsSinceEpoch,
    ).toIso8601String();
    return pocket.RecentSession(
      sessionId: _recentSessionId(history),
      provider: pocket.Provider.codex.value,
      name: history.displayTitle,
      summary: history.latestUserPrompt,
      localStatus: localStatus == null ? null : _statusFor(localStatus),
      firstPrompt: history.firstUserPrompt,
      lastPrompt: history.latestUserPrompt,
      created: timestamp,
      modified: timestamp,
      gitBranch: '',
      projectPath: humanReadableWorkspacePath(history.workspacePath),
      resumeCwd: history.workspacePath,
      isSidechain: false,
      codexApprovalPolicy: history.codexApprovalPolicy,
      codexSandboxMode: history.codexSandbox,
      codexModel: history.codexModel,
      codexModelReasoningEffort: history.codexEffort,
      planMode: history.codexPlanMode,
    );
  }

  pocket.RecentSession _toLivePocketRecentSession(
    CcpocketHomeSessionSnapshot snapshot,
  ) {
    final created = DateTime.fromMillisecondsSinceEpoch(
      snapshot.createdAtEpochMs,
    ).toIso8601String();
    final modified = DateTime.fromMillisecondsSinceEpoch(
      snapshot.lastActivityAtEpochMs,
    ).toIso8601String();
    final prompt = snapshot.queuedPrompts.isEmpty
        ? ''
        : snapshot.queuedPrompts.first.trim();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final name = snapshot.title?.trim().isNotEmpty == true
        ? snapshot.title!.trim()
        : prompt.isNotEmpty
        ? _compactTitle(prompt)
        : (zh ? '新会话' : 'New session');
    return pocket.RecentSession(
      sessionId: snapshot.sessionId!,
      provider: pocket.Provider.codex.value,
      name: name,
      summary: prompt,
      firstPrompt: prompt,
      lastPrompt: snapshot.queuedPrompts.isEmpty
          ? null
          : snapshot.queuedPrompts.last,
      localStatus: _liveStatusFor(snapshot),
      created: created,
      modified: modified,
      gitBranch: '',
      projectPath: humanReadableWorkspacePath(snapshot.workspace.displayPath),
      resumeCwd: snapshot.workspace.displayPath,
      isSidechain: false,
      codexApprovalPolicy: snapshot.approvalPolicy,
      codexSandboxMode: snapshot.sandbox,
      codexModel: snapshot.model,
      codexModelReasoningEffort: snapshot.effort,
      planMode: snapshot.planMode,
    );
  }

  String _compactTitle(String prompt) {
    final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    final runes = normalized.runes.toList(growable: false);
    return String.fromCharCodes(runes.take(36)) +
        (runes.length > 36 ? '…' : '');
  }

  SessionHistoryRecord? _historyFor(
    pocket.RecentSession session,
    List<SessionHistoryRecord> histories,
  ) {
    final id = session.sessionId;
    return histories.cast<SessionHistoryRecord?>().firstWhere(
      (history) => history != null && _recentSessionId(history) == id,
      orElse: () => null,
    );
  }

  /// Keep the RecentSession adapter reversible even for legacy one-record
  /// histories that predate the durable local session id. Those rows still
  /// need to open from the copied CC Pocket HomeContent instead of becoming
  /// display-only cards with an ephemeral DateTime.now id.
  String _recentSessionId(SessionHistoryRecord history) {
    final sessionId = history.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) return sessionId;
    final threadId = history.threadId?.trim();
    if (threadId != null && threadId.isNotEmpty) return threadId;
    return 'legacy:${history.backendId}|${history.workspacePath}|'
        '${history.updatedAtEpochMs}|${history.title ?? ''}|'
        '${history.threadName ?? ''}|'
        '${history.entries.length}|${history.latestEntry}';
  }

  Future<void> _openRecentSession(
    pocket.RecentSession session,
    List<SessionHistoryRecord> histories,
  ) async {
    final live = _snapshotForRecentSession(session, _liveSnapshots());
    if (live?.sessionId case final sessionId?) {
      _openRunningSession(sessionId);
      return;
    }
    final history = _historyFor(session, histories);
    if (history == null) return;
    Backend? historyBackend;
    if (widget.backend.descriptor.id == history.backendId) {
      historyBackend = widget.backend;
    } else if (widget.fallbackBackend?.descriptor.id == history.backendId) {
      historyBackend = widget.fallbackBackend;
    }
    if (historyBackend == null) {
      _showMissingHistoryWorkspace();
      return;
    }
    final workspaces = identical(historyBackend, widget.backend)
        ? await widget.workspaces
        : await historyBackend.listWorkspaces();
    if (!mounted) return;
    final workspace = workspaces.cast<WorkspaceRef?>().firstWhere(
      (candidate) =>
          candidate!.backendId == historyBackend!.descriptor.id &&
          candidate.hostPath == history.workspacePath,
      orElse: () => null,
    );
    if (workspace == null) {
      _showMissingHistoryWorkspace();
      return;
    }
    await widget.onOpenHistory(workspace, history);
  }

  void _showMissingHistoryWorkspace() {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          zh
              ? '找不到该会话对应的本地 workspace。'
              : 'The local workspace for this session could not be found.',
        ),
      ),
    );
  }

  Future<void> _openFirstWorkspace() async {
    final workspaces = await widget.workspaces;
    if (!mounted) return;
    if (workspaces.isNotEmpty) {
      await widget.onOpenSession(workspaces.first);
      return;
    }
    await widget.onAddSafWorkspace();
  }

  Future<void> _showRecentActions(
    pocket.RecentSession session,
    List<SessionHistoryRecord> histories,
  ) async {
    final history = _historyFor(session, histories);
    final live = _snapshotForRecentSession(session, _liveSnapshots());
    if ((history == null && live == null) || !mounted) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(zh ? '打开会话' : 'Open session'),
              onTap: () => Navigator.of(context).pop('open'),
            ),
            if (live != null)
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: Text(zh ? '停止生成' : 'Stop generation'),
                onTap: () => Navigator.of(context).pop('stop'),
              ),
            if (history != null || live != null)
              ListTile(
                leading: Icon(
                  (live?.pinned ?? history?.pinned ?? false)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(
                  (live?.pinned ?? history?.pinned ?? false)
                      ? (zh ? '取消置顶' : 'Unpin session')
                      : (zh ? '置顶会话' : 'Pin session'),
                ),
                onTap: () => Navigator.of(context).pop('pin'),
              ),
            if (history != null)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(zh ? '重命名会话' : 'Rename session'),
                onTap: () => Navigator.of(context).pop('rename'),
              ),
            if (history != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(zh ? '删除会话' : 'Delete session'),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await _openRecentSession(session, histories);
      case 'stop':
        if (live?.sessionId case final id?) {
          await _stopRunningSession(id);
        }
      case 'pin':
        if (live?.sessionId case final id?) {
          await _toggleRunningSessionPinned(id);
        } else if (history != null) {
          await widget.onHistoryFlagsChanged(history, pinned: !history.pinned);
        }
      case 'rename':
        if (history != null) await _renameRecentSession(history);
      case 'delete':
        if (history != null) await widget.onDeleteSession(history);
    }
  }

  Future<void> _renameRecentSession(SessionHistoryRecord history) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final title = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameSessionDialog(initialTitle: history.displayTitle, zh: zh),
    );
    if (!mounted || title == null) return;
    final normalized = title.trim();
    await widget.onHistoryTitleChanged(
      history,
      normalized.isEmpty ? null : normalized,
    );
  }

  String _statusFor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('approval')) return 'waiting_approval';
    if (normalized.contains('compact')) return 'compacting';
    if (normalized.contains('reconnect')) return 'reconnecting';
    if (normalized.contains('disconnect')) return 'disconnected';
    if (normalized.contains('fail') || normalized.contains('exit')) {
      return 'failed';
    }
    if (normalized.contains('stop')) return 'stopping';
    if (normalized.contains('wait')) return 'waiting';
    if (normalized.contains('run') || normalized.contains('start')) {
      return 'running';
    }
    return 'idle';
  }
}

/// Local equivalent of CC Pocket's machine/workspace section.
///
/// The original CC Pocket section is intentionally adapted here because its
/// machine model belongs to the multi-device app. This adapter keeps the same
/// interaction shape (status, add, refresh, primary action and overflow
/// action) while operating only on the local Android workspace contract.
class _LocalWorkspaceOverview extends StatelessWidget {
  const _LocalWorkspaceOverview({
    required this.workspaces,
    required this.hostAccess,
    required this.onCreateHostWorkspace,
    required this.onAddSafWorkspace,
    required this.onRefresh,
    required this.onOpenSession,
    this.onOpenFiles,
    required this.onWorkspaceChanged,
  });

  final Future<List<WorkspaceRef>> workspaces;
  final Future<AppHostAccessResult> hostAccess;
  final Future<void> Function() onCreateHostWorkspace;
  final Future<void> Function() onAddSafWorkspace;
  final Future<void> Function() onRefresh;
  final Future<void> Function(WorkspaceRef workspace) onOpenSession;
  final Future<void> Function(WorkspaceRef workspace)? onOpenFiles;
  final Future<void> Function(WorkspaceRef workspace) onWorkspaceChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkspaceRef>>(
      future: workspaces,
      builder: (context, workspaceSnapshot) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        final items = workspaceSnapshot.data ?? const <WorkspaceRef>[];
        final loading =
            workspaceSnapshot.connectionState != ConnectionState.done &&
            !workspaceSnapshot.hasError;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_copy_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  zh ? '工作区' : 'Workspaces',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('refresh_workspace_button'),
                  onPressed: loading ? null : () => unawaited(onRefresh()),
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: zh ? '刷新工作区' : 'Refresh workspace',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  visualDensity: VisualDensity.standard,
                ),
                TextButton.icon(
                  key: const ValueKey('add_workspace_button'),
                  onPressed: () => unawaited(onAddSafWorkspace()),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(zh ? '添加' : 'Add'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('workspace_overflow_menu'),
                  icon: const Icon(Icons.more_horiz, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'create') {
                      unawaited(onCreateHostWorkspace());
                    }
                    if (value == 'refresh') {
                      unawaited(onRefresh());
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'create',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.create_new_folder_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              zh ? '创建本地工作区' : 'Create local workspace',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'refresh',
                      child: Row(
                        children: [
                          const Icon(Icons.refresh, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              zh ? '刷新列表' : 'Refresh list',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<AppHostAccessResult>(
              future: hostAccess,
              builder: (context, accessSnapshot) {
                final access = accessSnapshot.data;
                if (access == null) return const SizedBox.shrink();
                if (!access.isAvailable && items.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_shared_outlined,
                          size: 14,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            zh ? '已使用文件夹授权' : 'Using folder access',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.primary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final accessLabel = switch (access.state) {
                  'available' => zh ? '可用' : 'Available',
                  'missing' => zh ? '缺少' : 'Missing',
                  'denied' => zh ? '已拒绝' : 'Denied',
                  'failed' => zh ? '失败' : 'Failed',
                  _ => zh ? '不可用' : 'Unavailable',
                };
                final color = access.isAvailable
                    ? colors.primary
                    : colors.onSurfaceVariant;
                return Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        access.isAvailable
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 14,
                        color: color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${zh ? '此设备' : 'This device'} · $accessLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (workspaceSnapshot.hasError)
              _WorkspaceEmptyCard(
                title: zh ? '无法读取工作区' : 'Unable to read workspaces',
                subtitle: zh
                    ? '请检查本地存储访问后重试。'
                    : 'Check local storage access and try again.',
                actionLabel: zh ? '重试' : 'Retry',
                actionIcon: Icons.refresh,
                onAction: () => unawaited(onRefresh()),
              )
            else if (!loading && items.isEmpty)
              _WorkspaceEmptyCard(
                title: zh ? '还没有工作区' : 'No workspaces yet',
                subtitle: zh ? '添加一个文件夹，或创建本地工作区后开始 Codex 会话。' : 'Add a folder or create a local workspace to start Codex.',
                actionLabel: zh ? '添加文件夹' : 'Add folder',
                actionIcon: Icons.add,
                onAction: () => unawaited(onAddSafWorkspace()),
                secondaryAction: TextButton(
                  onPressed: () => unawaited(onCreateHostWorkspace()),
                  child: Text(zh ? '创建本地工作区' : 'Create local workspace'),
                ),
              )
            else
              ...items.map(
                (workspace) => _LocalWorkspaceCard(
                  workspace: workspace,
                  canRemove: true,
                  revoked: workspace.filesystemOwnerId == 'android-saf-revoked',
                  onOpen: () => unawaited(onOpenSession(workspace)),
                  onOpenFiles: onOpenFiles == null
                      ? null
                      : () => unawaited(onOpenFiles!(workspace)),
                  onRemove: () => unawaited(onWorkspaceChanged(workspace)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WorkspaceEmptyCard extends StatelessWidget {
  const _WorkspaceEmptyCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.secondaryAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  color: colors.outline,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 18),
                    label: Text(actionLabel),
                  ),
                ),
                if (secondaryAction != null) ...[
                  const SizedBox(width: 8),
                  secondaryAction!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalWorkspaceCard extends StatelessWidget {
  const _LocalWorkspaceCard({
    required this.workspace,
    required this.canRemove,
    required this.revoked,
    required this.onOpen,
    this.onOpenFiles,
    required this.onRemove,
  });

  final WorkspaceRef workspace;
  final bool canRemove;
  final bool revoked;
  final VoidCallback onOpen;
  final VoidCallback? onOpenFiles;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final safWorkspace = workspace.backendLocator.startsWith('saf://');
    final name = _workspaceName(workspace.displayPath);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: revoked ? null : onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.35),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!revoked)
                    FilledButton.tonal(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(zh ? '新会话' : 'New session'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspace.displayPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (revoked) ...[
                          const SizedBox(height: 3),
                          Text(
                            zh ? 'SAF 授权已失效，请移除后重新添加文件夹' : 'SAF permission revoked; forget and add the folder again',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('workspace_menu_${workspace.backendLocator}'),
                    icon: Icon(
                      Icons.more_horiz,
                      color: colors.outline,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'open' && !revoked) onOpen();
                      if (value == 'files' && !revoked) onOpenFiles?.call();
                      if (value == 'remove') onRemove();
                    },
                    itemBuilder: (context) => [
                      if (!revoked)
                        PopupMenuItem<String>(
                          value: 'open',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow_outlined, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  zh ? '开始新会话' : 'Start new session',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!revoked && onOpenFiles != null)
                        PopupMenuItem<String>(
                          value: 'files',
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open_outlined, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  zh ? '浏览文件' : 'Browse files',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (canRemove)
                        PopupMenuItem<String>(
                          value: 'remove',
                          child: Row(
                            children: [
                              Icon(
                                safWorkspace
                                    ? Icons.remove_circle_outline
                                    : Icons.delete_outline,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  safWorkspace
                                      ? (zh
                                            ? '移除文件夹授权'
                                            : 'Remove folder access')
                                      : (zh
                                            ? '删除本地工作区'
                                            : 'Delete local workspace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameSessionDialog extends StatefulWidget {
  const _RenameSessionDialog({required this.initialTitle, required this.zh});

  final String initialTitle;
  final bool zh;

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = widget.zh;
    return AlertDialog(
      title: Text(zh ? '重命名会话' : 'Rename session'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 128,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: zh ? '会话名称' : 'Session name'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}

String _workspaceName(String path) {
  return workspaceNameFromPath(path, fallback: 'Workspace');
}

class _LocalHomeError extends StatelessWidget {
  const _LocalHomeError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh),
              label: Text(zh ? '重试' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
