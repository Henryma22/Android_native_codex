import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../models/offline_pending_action.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/provider_style.dart';
import '../../../widgets/pin_toggle_button.dart';
import '../../../widgets/session_card.dart';
import '../state/session_list_presentation.dart';
import 'section_header.dart';
import 'session_filter_bar.dart';
import 'session_list_empty_state.dart';
import 'session_list_loading_view.dart';
import 'session_reconnect_banner.dart';

class _ProjectSessionGroup {
  final String projectPath;
  final String projectName;
  final List<RecentSession> sessions;

  const _ProjectSessionGroup({
    required this.projectPath,
    required this.projectName,
    required this.sessions,
  });
}

List<_ProjectSessionGroup> _groupSessionsByProject({
  required Iterable<String> projectPaths,
  required List<RecentSession> sessions,
}) {
  final grouped = <String, List<RecentSession>>{
    for (final path in projectPaths)
      if (path.isNotEmpty) path: <RecentSession>[],
  };
  for (final session in sessions) {
    grouped.putIfAbsent(session.projectPath, () => <RecentSession>[]);
    grouped[session.projectPath]!.add(session);
  }
  return [
    for (final entry in grouped.entries)
      _ProjectSessionGroup(
        projectPath: entry.key,
        projectName: pathBasename(entry.key),
        sessions: entry.value,
      ),
  ];
}

class _LazyListItem {
  final Key? key;
  final WidgetBuilder builder;

  const _LazyListItem({this.key, required this.builder});
}

class HomeContent extends StatefulWidget {
  final LocalRuntimeConnectionState connectionState;
  final String? runtimeVersion;
  final List<SessionInfo> sessions;
  final List<OfflinePendingAction> offlinePendingActions;
  final List<RecentSession> recentSessions;
  final Set<String> accumulatedProjectPaths;
  final Set<String> collapsedProjectPaths;
  final Set<String> pinnedSessionKeys;
  final Set<String> pinnedProjectPaths;
  final String searchQuery;
  final bool isLoadingMore;
  final bool isInitialLoading;
  final bool hasMoreSessions;
  final Set<String> deletingSessionIds;
  final Set<String> unseenSessionIds;
  final String? currentProjectFilter;
  final VoidCallback onNewSession;
  final void Function(
    String sessionId, {
    String? projectPath,
    String? gitBranch,
    String? worktreePath,
    String? provider,
    String? permissionMode,
    String? sandboxMode,
    String? approvalPolicy,
    String? approvalsReviewer,
  })
  onTapRunning;
  final ValueChanged<String> onStopSession;
  final ValueChanged<String>? onCancelOfflinePendingAction;
  final void Function(String sessionId, String toolUseId, {bool clearContext})?
  onApprovePermission;
  final void Function(String sessionId, String toolUseId)? onApproveAlways;
  final void Function(String sessionId, String toolUseId, {String? message})?
  onRejectPermission;
  final void Function(String sessionId, String toolUseId, String result)?
  onAnswerQuestion;
  final ValueChanged<RecentSession> onResumeSession;
  final ValueChanged<RecentSession>? onToggleRecentSessionPinned;
  final void Function(RecentSession session, Offset? position)
  onLongPressRecentSession;
  final ValueChanged<RecentSession> onDeleteSession;
  final void Function(SessionInfo session, Offset? position)
  onLongPressRunningSession;
  final ValueChanged<SessionInfo>? onToggleRunningSessionPinned;
  final ValueChanged<String?> onSelectProject;
  final ValueChanged<String>? onSearchQueryChanged;
  final VoidCallback onLoadMore;
  final ValueChanged<String>? onToggleProjectCollapsed;
  final ValueChanged<String>? onToggleProjectPinned;
  final bool namedOnly;
  final VoidCallback onToggleNamed;
  final bool? showInlineStopButtonOverride;

  /// Optional CC Pocket-style content shown above Running/Recent sessions.
  ///
  /// The independent local app uses this slot for its workspace cards while
  /// keeping the original lazy list, filtering, grouping and session actions.
  final Widget? leadingContent;

  /// Compact content aligned to the right of CC Pocket's Running header.
  ///
  /// The upstream app uses this slot for its small Codex usage summary. It is
  /// optional so the presentation package stays independent of any provider
  /// or transport implementation.
  final Widget? runningHeaderTrailing;
  final Widget? recentHeaderTrailing;
  final bool showRunningSection;
  final bool compactRecentCards;
  final double bottomContentInset;

  const HomeContent({
    super.key,
    required this.connectionState,
    this.runtimeVersion,
    required this.sessions,
    this.offlinePendingActions = const [],
    required this.recentSessions,
    required this.accumulatedProjectPaths,
    this.collapsedProjectPaths = const {},
    this.pinnedSessionKeys = const {},
    this.pinnedProjectPaths = const {},
    required this.searchQuery,
    required this.isLoadingMore,
    required this.isInitialLoading,
    required this.hasMoreSessions,
    this.deletingSessionIds = const {},
    this.unseenSessionIds = const {},
    required this.currentProjectFilter,
    required this.onNewSession,
    required this.onTapRunning,
    required this.onStopSession,
    this.onCancelOfflinePendingAction,
    this.onApprovePermission,
    this.onApproveAlways,
    this.onRejectPermission,
    this.onAnswerQuestion,
    required this.onResumeSession,
    this.onToggleRecentSessionPinned,
    required this.onLongPressRecentSession,
    required this.onDeleteSession,
    required this.onLongPressRunningSession,
    this.onToggleRunningSessionPinned,
    required this.onSelectProject,
    this.onSearchQueryChanged,
    required this.onLoadMore,
    this.onToggleProjectCollapsed,
    this.onToggleProjectPinned,
    required this.namedOnly,
    required this.onToggleNamed,
    this.showInlineStopButtonOverride,
    this.leadingContent,
    this.runningHeaderTrailing,
    this.recentHeaderTrailing,
    this.showRunningSection = true,
    this.compactRecentCards = false,
    this.bottomContentInset = 0,
  });

  @override
  State<HomeContent> createState() => HomeContentState();
}

class HomeContentState extends State<HomeContent> {
  static const _displayModePreferenceKey = 'session_list_display_mode';
  static const _groupRecentSessionsPreferenceKey =
      'session_list_group_recent_sessions';

  bool _isSearching = false;
  bool _groupRecentSessions = true;
  final _searchController = TextEditingController();
  SessionDisplayMode _displayMode = SessionDisplayMode.first;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_displayModePreferenceKey);
    final groupRecentSessions =
        prefs.getBool(_groupRecentSessionsPreferenceKey) ?? true;
    if (!mounted) return;
    setState(() {
      if (modeStr != null) {
        _displayMode = SessionDisplayMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => SessionDisplayMode.first,
        );
      }
      _groupRecentSessions = groupRecentSessions;
    });
  }

  void _toggleDisplayMode() async {
    final next = switch (_displayMode) {
      SessionDisplayMode.first => SessionDisplayMode.last,
      SessionDisplayMode.last => SessionDisplayMode.summary,
      SessionDisplayMode.summary => SessionDisplayMode.first,
    };
    setState(() => _displayMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModePreferenceKey, next.name);
  }

  void _toggleRecentGrouping() async {
    final next = !_groupRecentSessions;
    setState(() => _groupRecentSessions = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_groupRecentSessionsPreferenceKey, next);
  }

  @override
  void didUpdateWidget(covariant HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部から searchQuery がクリアされたら検索UIも閉じる
    if (widget.searchQuery.isEmpty && oldWidget.searchQuery.isNotEmpty) {
      setState(() => _isSearching = false);
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        widget.onSearchQueryChanged?.call('');
      }
    });
  }

  /// Open search field programmatically (e.g. from keyboard shortcut).
  void openSearch() {
    if (!_isSearching) {
      _toggleSearch();
    }
  }

  Widget? _buildAppUpdateBanner() => null;

  Widget? _buildUpdateBanner() => null;

  Widget? _buildConnectedRuntimeBanner(BuildContext context) => null;

  Widget _buildLazyList({
    Key? key,
    EdgeInsetsGeometry? padding,
    required List<_LazyListItem> items,
  }) {
    // Do not provide a global key-to-index map here. The home adapter can
    // project local histories that change while the list is scrolled (for
    // example when a hidden session finishes a turn). A stale or duplicate
    // projected key makes Slidable reuse the previous card's gesture
    // callback even though its semantics/text have already been rebuilt for
    // the next session. Index-based lazy building keeps the visual card and
    // its tap closure in the same item; the inner session keys still preserve
    // the small amount of state needed by an already-visible card.
    final listPadding = widget.bottomContentInset > 0
        ? (padding ?? EdgeInsets.zero).add(
            EdgeInsets.only(bottom: widget.bottomContentInset),
          )
        : padding;
    return ListView.builder(
      key: key ?? const ValueKey('ccpocket_home_scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: listPadding,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final child = item.builder(context);
        return item.key == null
            ? child
            : KeyedSubtree(key: item.key, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) => _buildContent(context);

  Widget _buildContent(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appColors = Theme.of(context).extension<AppColors>()!;
    final hasPendingActions = widget.offlinePendingActions.isNotEmpty;
    final hasRunningSessions =
        widget.showRunningSection &&
        (widget.sessions.isNotEmpty || hasPendingActions);
    final hasRecentSessions = widget.recentSessions.isNotEmpty;
    final hasKnownProjects = widget.accumulatedProjectPaths.isNotEmpty;
    final isReconnecting =
        widget.connectionState == LocalRuntimeConnectionState.reconnecting;
    final updateBanner = _buildUpdateBanner();
    final appUpdateBanner = _buildAppUpdateBanner();
    final showInlineStopButton = widget.showInlineStopButtonOverride ?? true;
    final connectedRuntimeBanner = _buildConnectedRuntimeBanner(context);

    // Compute derived state
    // Exclude running sessions from recent list to avoid duplicates
    final visibleRunningSessions = widget.showRunningSection
        ? widget.sessions
        : <SessionInfo>[];
    final runningSessionIds = visibleRunningSessions
        .expand(
          (s) => [s.id, if (s.providerSessionId != null) s.providerSessionId!],
        )
        .toSet();
    final pendingResumeSessionIds = widget.offlinePendingActions
        .where((action) => action.kind == OfflinePendingActionKind.resume)
        .map((action) => action.sessionId)
        .whereType<String>()
        .toSet();
    final runningSessionFallbackKeys = visibleRunningSessions
        .map(
          (session) =>
              (session.provider, session.projectPath, session.createdAt),
        )
        .toSet();

    // Fallback for Codex sessions which use a short proxy ID instead of UUID
    bool isDuplicate(RecentSession rs) {
      if (pendingResumeSessionIds.contains(rs.sessionId)) return true;
      if (runningSessionIds.contains(rs.sessionId)) return true;
      return runningSessionFallbackKeys.contains((
        rs.provider,
        rs.projectPath,
        rs.created,
      ));
    }

    // All filtering (project, provider, namedOnly, searchQuery) is applied
    // server-side. Only deduplicate running sessions here.
    final filteredSessions = prioritizePinned(
      widget.recentSessions.where((session) => !isDuplicate(session)),
      isPinned: (session) =>
          widget.pinnedSessionKeys.contains(recentSessionPinKey(session)),
      isProjectPinned: (session) =>
          widget.pinnedProjectPaths.contains(session.projectPath),
    );
    final projectPathsWithPinnedSessions = filteredSessions
        .where(
          (session) =>
              widget.pinnedSessionKeys.contains(recentSessionPinKey(session)),
        )
        .map((session) => session.projectPath)
        .toSet();
    final allProjectPaths = prioritizePinned(
      <String>{
        if (widget.currentProjectFilter != null) widget.currentProjectFilter!,
        if (widget.currentProjectFilter == null)
          ...widget.accumulatedProjectPaths,
        if (widget.currentProjectFilter == null)
          ...filteredSessions.map((session) => session.projectPath),
      }.where((path) => path.isNotEmpty),
      isPinned: projectPathsWithPinnedSessions.contains,
      isProjectPinned: widget.pinnedProjectPaths.contains,
    );
    final groupedRecentSessions = _groupSessionsByProject(
      projectPaths: allProjectPaths,
      sessions: filteredSessions,
    );
    final runningSessions = prioritizePinned(
      widget.sessions,
      isPinned: (session) {
        final key = runningSessionPinKey(session);
        return key != null && widget.pinnedSessionKeys.contains(key);
      },
      isProjectPinned: (session) =>
          widget.pinnedProjectPaths.contains(session.projectPath),
    );

    final runningSessionsHeader = _RunningSessionsHeader(
      label: l.running,
      emptyLabel: l.noActiveSessions,
      color: appColors.statusOnline,
      usageSummary: widget.runningHeaderTrailing,
      showEmptyMessage: !hasRunningSessions,
    );

    final hasActiveFilter =
        widget.currentProjectFilter != null ||
        widget.namedOnly ||
        widget.searchQuery.isNotEmpty;

    final items = <_LazyListItem>[];
    void addItem(WidgetBuilder builder, {Key? itemKey}) {
      items.add(_LazyListItem(key: itemKey, builder: builder));
    }

    void addWidget(Widget? child) {
      if (child != null) addItem((_) => child);
    }

    // Keep app-specific content inside the same scroll surface as the
    // original CC Pocket home. This is intentionally a slot rather than a
    // second ListView so session list scrolling and empty/loading states stay
    // identical to the copied presentation flow.
    addWidget(widget.leadingContent);
    if (widget.leadingContent != null) {
      addItem((_) => const SizedBox(height: 12));
    }

    final hasLeadingContent = widget.leadingContent != null;

    if (!hasLeadingContent &&
        !hasRunningSessions &&
        !hasRecentSessions &&
        !hasKnownProjects &&
        !hasActiveFilter) {
      // Show skeleton while initial data is loading
      if (widget.isInitialLoading) {
        if (isReconnecting) addItem((_) => const SessionReconnectBanner());
        addWidget(connectedRuntimeBanner);
        addWidget(updateBanner);
        addWidget(appUpdateBanner);
        if (widget.showRunningSection) addItem((_) => runningSessionsHeader);
        addItem((_) => const SizedBox(height: 16));
        addItem(
          (_) => SectionHeader(
            icon: Icons.history,
            label: l.recentSessions,
            color: appColors.subtleText,
            trailing: widget.recentHeaderTrailing,
          ),
        );
        addItem((_) => const SizedBox(height: 8));
        addItem((_) => const SessionListLoadingStatus());
        addItem((_) => const SizedBox(height: 12));
        addItem((_) => const SessionListSkeleton());
        return _buildLazyList(padding: const EdgeInsets.all(12), items: items);
      }

      if (isReconnecting) addItem((_) => const SessionReconnectBanner());
      addWidget(connectedRuntimeBanner);
      addWidget(updateBanner);
      if (widget.showRunningSection) addItem((_) => runningSessionsHeader);
      addItem((_) => const SizedBox(height: 80));
      addItem((_) => SessionListEmptyState(onNewSession: widget.onNewSession));
      return _buildLazyList(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        items: items,
      );
    }

    if (isReconnecting) addItem((_) => const SessionReconnectBanner());
    addWidget(connectedRuntimeBanner);
    addWidget(updateBanner);
    if (widget.showRunningSection) addItem((_) => runningSessionsHeader);
    if (widget.showRunningSection && hasRunningSessions) {
      addItem((_) => const SizedBox(height: 4));
      for (final action in widget.offlinePendingActions) {
        addItem(
          (_) => OfflinePendingSessionCard(
            key: ValueKey('pending_session_${action.id}'),
            action: action,
            onCancel:
                widget.onCancelOfflinePendingAction == null || !action.canCancel
                ? null
                : () => widget.onCancelOfflinePendingAction!(action.id),
          ),
          itemKey: ValueKey('pending_session_${action.id}'),
        );
      }
      for (final session in runningSessions) {
        addItem(
          (itemContext) => Slidable(
            key: ValueKey('running_session_${session.id}'),
            endActionPane: ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.18,
              children: [
                CustomSlidableAction(
                  onPressed: (_) => widget.onStopSession(session.id),
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(itemContext).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            child: RunningSessionCard(
              session: session,
              isPinned: switch (runningSessionPinKey(session)) {
                final key? => widget.pinnedSessionKeys.contains(key),
                null => false,
              },
              onTogglePinned:
                  runningSessionPinKey(session) == null ||
                      widget.onToggleRunningSessionPinned == null
                  ? null
                  : () => widget.onToggleRunningSessionPinned!(session),
              isUnseen: widget.unseenSessionIds.contains(session.id),
              isSelected: false,
              onLongPress: () =>
                  widget.onLongPressRunningSession(session, null),
              onShowActions: (position) =>
                  widget.onLongPressRunningSession(session, position),
              onStop: showInlineStopButton
                  ? () => widget.onStopSession(session.id)
                  : null,
              onTap: () => widget.onTapRunning(
                session.id,
                projectPath: session.projectPath,
                gitBranch: session.worktreePath != null
                    ? session.worktreeBranch
                    : session.gitBranch,
                worktreePath: session.worktreePath,
                provider: session.provider,
                permissionMode: session.permissionMode,
                sandboxMode: session.codexSandboxMode,
                approvalPolicy: session.codexApprovalPolicy,
                approvalsReviewer: session.codexApprovalsReviewer,
              ),
              onApprove: (toolUseId, {bool clearContext = false}) => widget
                  .onApprovePermission
                  ?.call(session.id, toolUseId, clearContext: clearContext),
              onApproveAlways: (toolUseId) =>
                  widget.onApproveAlways?.call(session.id, toolUseId),
              onReject: (toolUseId, {String? message}) => widget
                  .onRejectPermission
                  ?.call(session.id, toolUseId, message: message),
              onAnswer: (toolUseId, result) =>
                  widget.onAnswerQuestion?.call(session.id, toolUseId, result),
            ),
          ),
          itemKey: ValueKey('running_session_${session.id}'),
        );
      }
      addItem((_) => const SizedBox(height: 16));
    }
    if (widget.isInitialLoading ||
        hasRecentSessions ||
        hasKnownProjects ||
        hasActiveFilter) {
      addItem(
        (_) => SectionHeader(
          icon: Icons.history,
          label: l.recentSessions,
          color: appColors.subtleText,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.recentHeaderTrailing != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: widget.recentHeaderTrailing!,
                ),
              IconButton(
                key: const ValueKey('search_button'),
                icon: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  size: 18,
                  color: appColors.subtleText,
                ),
                onPressed: _toggleSearch,
                tooltip: l.search,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                visualDensity: VisualDensity.standard,
              ),
            ],
          ),
        ),
      );
      if (_isSearching) {
        addItem((_) => const SizedBox(height: 4));
        addItem(
          (itemContext) => TextField(
            key: const ValueKey('search_field'),
            controller: _searchController,
            autofocus: true,
            onTapOutside: (_) => FocusScope.of(itemContext).unfocus(),
            decoration: InputDecoration(
              hintText: l.searchSessions,
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: appColors.subtleText,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: appColors.subtleText.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: appColors.subtleText.withValues(alpha: 0.3),
                ),
              ),
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) => widget.onSearchQueryChanged?.call(value),
          ),
        );
      }
      addItem((_) => const SizedBox(height: 8));
      addItem(
        (_) => SessionFilterBar(
          displayMode: _displayMode,
          onToggleDisplayMode: _toggleDisplayMode,
          groupRecentSessions: _groupRecentSessions,
          onToggleRecentGrouping: _toggleRecentGrouping,
          projects:
              prioritizePinned(
                widget.accumulatedProjectPaths,
                isPinned: widget.pinnedProjectPaths.contains,
              ).map((path) {
                return (path: path, name: pathBasename(path));
              }).toList(),
          currentProjectFilter: widget.currentProjectFilter,
          onProjectFilterChanged: widget.onSelectProject,
          namedOnly: widget.namedOnly,
          onToggleNamed: widget.onToggleNamed,
        ),
      );
      addItem((_) => const SizedBox(height: 8));
      if (widget.isInitialLoading) {
        addItem(
          (_) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SessionListLoadingStatus(),
              SizedBox(height: 12),
              SessionListSkeleton(),
            ],
          ),
        );
      } else {
        void addRecentSession(
          RecentSession session, {
          bool hideProjectBadge = false,
        }) {
          addItem(
            (_) => _RecentSessionSlidable(
              session: session,
              isPinned: widget.pinnedSessionKeys.contains(
                recentSessionPinKey(session),
              ),
              displayMode: _displayMode,
              deletingSessionIds: widget.deletingSessionIds,
              onDeleteSession: widget.onDeleteSession,
              onResumeSession: widget.onResumeSession,
              onTogglePinned: widget.onToggleRecentSessionPinned == null
                  ? null
                  : () => widget.onToggleRecentSessionPinned!(session),
              onLongPressRecentSession: widget.onLongPressRecentSession,
              compact: widget.compactRecentCards,
              hideProjectBadge: hideProjectBadge,
            ),
            itemKey: ValueKey('recent_session_${session.sessionId}'),
          );
        }

        if ((!_groupRecentSessions && filteredSessions.isEmpty) ||
            (_groupRecentSessions && groupedRecentSessions.isEmpty)) {
          addItem(
            (_) => _RecentSessionsEmptyResult(
              title: hasActiveFilter
                  ? l.noSessionsMatchFilters
                  : l.noRecentSessions,
              subtitle: hasActiveFilter ? l.adjustFiltersAndSearch : null,
            ),
          );
        } else if (!_groupRecentSessions) {
          for (final session in filteredSessions) {
            addRecentSession(session);
          }
          if (widget.hasMoreSessions) {
            addItem((_) => const SizedBox(height: 8));
            addItem(
              (_) => _LoadMoreRecentSessionsButton(
                isLoadingMore: widget.isLoadingMore,
                onLoadMore: widget.onLoadMore,
              ),
            );
            addItem((_) => const SizedBox(height: 8));
          }
        } else {
          for (final group in groupedRecentSessions) {
            final projectPath = group.projectPath;
            final isCollapsed = widget.collapsedProjectPaths.contains(
              projectPath,
            );
            final isPinned = widget.pinnedProjectPaths.contains(projectPath);

            // Keep each project header and session card as an outer lazy-list
            // item. Building a whole project's Column here made entering a
            // large project group cause a concentrated layout/raster spike.
            addItem(
              (_) => _ProjectRecentSessionHeader(
                projectPath: projectPath,
                projectName: group.projectName,
                isCollapsed: isCollapsed,
                isPinned: isPinned,
                onTap: () => widget.onToggleProjectCollapsed?.call(projectPath),
                onTogglePinned: widget.onToggleProjectPinned == null
                    ? null
                    : () => widget.onToggleProjectPinned!(projectPath),
              ),
              itemKey: ValueKey('project_header_item_$projectPath'),
            );

            if (!isCollapsed) {
              addItem((_) => const SizedBox(height: 4));
              for (final session in group.sessions) {
                addRecentSession(session, hideProjectBadge: true);
              }

              if (group.sessions.isEmpty) {
                addItem(
                  (itemContext) => Padding(
                    padding: const EdgeInsets.only(left: 40, top: 4, bottom: 8),
                    child: Text(
                      AppLocalizations.of(itemContext).noRecentSessions,
                      style: Theme.of(itemContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Theme.of(itemContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                );
              }
            }

            addItem((_) => const SizedBox(height: 8));
          }
        }

        if (widget.currentProjectFilter != null && widget.hasMoreSessions) {
          addItem((_) => const SizedBox(height: 8));
          addItem(
            (_) => _LoadMoreRecentSessionsButton(
              isLoadingMore: widget.isLoadingMore,
              onLoadMore: widget.onLoadMore,
            ),
          );
          addItem((_) => const SizedBox(height: 8));
        }
      }
    }

    return _buildLazyList(
      key: const ValueKey('session_list'),
      padding: const EdgeInsets.all(12),
      items: items,
    );
  }
}

class _RunningSessionsHeader extends StatelessWidget {
  const _RunningSessionsHeader({
    required this.label,
    required this.emptyLabel,
    required this.color,
    required this.usageSummary,
    required this.showEmptyMessage,
  });

  final String label;
  final String emptyLabel;
  final Color color;
  final Widget? usageSummary;
  final bool showEmptyMessage;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          key: const ValueKey('running_sessions_header'),
          icon: Icons.play_circle_filled,
          label: label,
          color: color,
        ),
        if (showEmptyMessage)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              emptyLabel,
              key: const ValueKey('running_sessions_empty_message'),
              style: TextStyle(fontSize: 12, color: appColors.subtleText),
            ),
          ),
      ],
    );
    if (usageSummary == null) return header;

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final tapTargetLeft = 4 + 16 + 6 + labelPainter.width + 8;

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          header,
          Positioned(
            top: 0,
            left: tapTargetLeft.clamp(0, constraints.maxWidth).toDouble(),
            right: 0,
            height: 44,
            child: usageSummary!,
          ),
        ],
      ),
    );
  }
}

class _LoadMoreRecentSessionsButton extends StatelessWidget {
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const _LoadMoreRecentSessionsButton({
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Center(
      child: isLoadingMore
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : TextButton.icon(
              key: const ValueKey('load_more_button'),
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 18),
               label: Text(zh ? '加载更多' : 'Load More'),
            ),
    );
  }
}

class _RecentSessionSlidable extends StatelessWidget {
  final RecentSession session;
  final bool isPinned;
  final SessionDisplayMode displayMode;
  final Set<String> deletingSessionIds;
  final ValueChanged<RecentSession> onDeleteSession;
  final ValueChanged<RecentSession> onResumeSession;
  final VoidCallback? onTogglePinned;
  final void Function(RecentSession session, Offset? position)
  onLongPressRecentSession;
  final bool compact;
  final bool hideProjectBadge;

  const _RecentSessionSlidable({
    required this.session,
    required this.isPinned,
    required this.displayMode,
    required this.deletingSessionIds,
    required this.onDeleteSession,
    required this.onResumeSession,
    required this.onTogglePinned,
    required this.onLongPressRecentSession,
    required this.compact,
    required this.hideProjectBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: ValueKey('recent_session_${session.sessionId}'),
      endActionPane: _canDeleteRecentSession(session)
          ? ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.18,
              children: [
                CustomSlidableAction(
                  onPressed: (_) => onDeleteSession(session),
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  child: Semantics(
                    button: true,
                    label: switch (Localizations.localeOf(context)
                        .languageCode) {
                      'zh' => '删除会话',
                      'ja' => 'セッションを削除',
                      'ko' => '세션 삭제',
                      _ => 'Delete session',
                    },
                    child: ExcludeSemantics(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: RecentSessionCard(
        session: session,
        isPinned: isPinned,
        displayMode: displayMode,
        compact: compact,
        hideProjectBadge: hideProjectBadge,
        isSelected: false,
        draftText: null,
        isProcessing: deletingSessionIds.contains(session.sessionId),
        onTogglePinned: onTogglePinned,
        onTap: () => onResumeSession(session),
        onLongPress: () => onLongPressRecentSession(session, null),
        onShowActions: (position) =>
            onLongPressRecentSession(session, position),
      ),
    );
  }

  /// A persisted disconnected/failed row still has a visual status, but it no
  /// longer owns a live worker. Keep the normal CC Pocket swipe-to-delete
  /// action available for those historical rows; active workers remain
  /// protected from accidental deletion and can be stopped explicitly.
  bool _canDeleteRecentSession(RecentSession value) {
    final status = value.localStatus?.trim().toLowerCase();
    return status == null ||
        status.contains('disconnect') ||
        status.contains('fail') ||
        status.contains('error');
  }
}

class _RecentSessionsEmptyResult extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _RecentSessionsEmptyResult({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Icon(Icons.filter_alt_off, color: appColors.subtleText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.subtleText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectRecentSessionHeader extends StatelessWidget {
  final String projectPath;
  final String projectName;
  final bool isCollapsed;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback? onTogglePinned;

  const _ProjectRecentSessionHeader({
    required this.projectPath,
    required this.projectName,
    required this.isCollapsed,
    required this.isPinned,
    required this.onTap,
    required this.onTogglePinned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('project_header_$projectPath'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              AnimatedRotation(
                turns: isCollapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PinToggleButton(
                key: ValueKey('pin_project_$projectPath'),
                isPinned: isPinned,
                onPressed: onTogglePinned,
                pinTooltip: AppLocalizations.of(context).pinProject,
                unpinTooltip: AppLocalizations.of(context).unpinProject,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflinePendingSessionCard extends StatelessWidget {
  const OfflinePendingSessionCard({
    super.key,
    required this.action,
    this.onCancel,
  });

  final OfflinePendingAction action;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    final provider = providerFromRaw(action.provider);
    final providerStyle = providerStyleFor(context, provider);
    final statusColor = colorScheme.tertiary;
    final isProcessing = action.state == OfflinePendingActionState.processing;
    final status = isProcessing
        ? switch (action.kind) {
            OfflinePendingActionKind.start =>
              l.pendingActionProcessingStartStatus,
            OfflinePendingActionKind.resume => l.pendingActionProcessingStatus,
          }
        : l.pendingActionStatus;
    final subtitle = switch ((action.state, action.kind)) {
      (
        OfflinePendingActionState.queuedForReconnect,
        OfflinePendingActionKind.start,
      ) =>
        l.pendingActionWillCreateOnReconnect,
      (
        OfflinePendingActionState.queuedForReconnect,
        OfflinePendingActionKind.resume,
      ) =>
        l.pendingActionWillResumeOnReconnect,
      (OfflinePendingActionState.processing, OfflinePendingActionKind.start) =>
        l.pendingActionProcessingStartDescription,
      (OfflinePendingActionState.processing, OfflinePendingActionKind.resume) =>
        l.pendingActionProcessingResumeDescription,
    };
    final title = switch ((action.state, action.kind)) {
      (
        OfflinePendingActionState.queuedForReconnect,
        OfflinePendingActionKind.start,
      ) =>
        l.offlinePendingNewSessionTitle,
      (
        OfflinePendingActionState.queuedForReconnect,
        OfflinePendingActionKind.resume,
      ) =>
        l.offlinePendingResumeTitle,
      (OfflinePendingActionState.processing, OfflinePendingActionKind.start) =>
        l.pendingActionProcessingStartTitle,
      (OfflinePendingActionState.processing, OfflinePendingActionKind.resume) =>
        l.pendingActionProcessingResumeTitle,
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 0),
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: statusColor.withValues(alpha: 0.08),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor.withValues(alpha: 0.82),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    key: const ValueKey('pending_session_cancel_button'),
                    onPressed: onCancel,
                    tooltip: l.tooltipCancelPendingAction,
                    icon: const Icon(Icons.close),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 28,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: providerStyle.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: providerStyle.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        action.projectName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: providerStyle.foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isProcessing ? Icons.cloud_sync : Icons.cloud_off,
                      size: 13,
                      color: appColors.subtleText,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isProcessing ? '正在本地执行' : l.queuedLocally,
                        style: TextStyle(
                          fontSize: 11,
                          color: appColors.subtleText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
