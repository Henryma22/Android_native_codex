import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/features/session_list/widgets/session_filter_bar.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';
import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/backends/compatibility/linux_compatibility_backend.dart';
import 'package:codex/ccpocket_native_home.dart';
import 'package:codex/core/domain/workspace.dart';
import 'package:codex/services/app_host_access_probe.dart';
import 'package:codex/services/session_history.dart';

void main() {
  testWidgets('decodes SAF paths in the project/session list', (tester) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    const encodedPath = 'primary%3ACodex%2FWorkspaces%2Fvm-demo';
    const history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: encodedPath,
      sessionId: 'saf-session',
      status: 'stopped',
      updatedAtEpochMs: 123,
      entries: <String>['You: inspect the SAF workspace'],
    );
    WorkspaceRef? filesWorkspace;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              const <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenFiles: (value) async => filesWorkspace = value,
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('primary%3ACodex%2FWorkspaces%2Fvm-demo'), findsNothing);
    expect(find.text('vm-demo'), findsWidgets);
    final sessionList = tester.widget<ListView>(
      find.byKey(const ValueKey('session_list')),
    );
    expect(sessionList.padding, const EdgeInsets.fromLTRB(12, 12, 12, 100));

    await tester.tap(
      find.byKey(ValueKey('workspace_menu_${workspace.backendLocator}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse files'));
    await tester.pump();
    expect(identical(filesWorkspace, workspace), isTrue);
  });

  testWidgets('opens a legacy history row without a session id', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    const history = SessionHistoryRecord(
      backendId: 'fake-backend',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 123,
      entries: <String>['You: legacy prompt'],
    );
    SessionHistoryRecord? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              const <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, value) async => opened = value,
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('legacy prompt'),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.text('legacy prompt'));
    await tester.pump();

    expect(identical(opened, history), isTrue);
  });

  testWidgets('keeps a persisted disconnected row openable as history', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    const history = SessionHistoryRecord(
      backendId: 'fake-backend',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      sessionId: 'disconnected-session',
      threadId: 'provider-thread',
      status: 'disconnected',
      updatedAtEpochMs: 123,
      entries: <String>['You: reconnect me later'],
    );
    SessionHistoryRecord? opened;
    var openedAsActive = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              const <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, value) async => opened = value,
            onOpenActiveSession: () => openedAsActive = true,
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('reconnect me later'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('Disconnected'), findsOneWidget);
    await tester.tap(find.text('reconnect me later'));
    await tester.pump();

    expect(identical(opened, history), isTrue);
    expect(openedAsActive, isFalse);
  });

  testWidgets('reopens a compatibility-backend history in its own backend', (
    tester,
  ) async {
    final hostBackend = FakeBackend();
    final hostWorkspace = (await hostBackend.listWorkspaces()).single;
    final compatibilityBackend = LinuxCompatibilityBackend(hostBackend);
    final compatibilityWorkspace =
        (await compatibilityBackend.listWorkspaces()).single;
    final history = SessionHistoryRecord(
      backendId: compatibilityWorkspace.backendId,
      workspacePath: compatibilityWorkspace.hostPath,
      sessionId: 'compatibility-session',
      status: 'stopped',
      updatedAtEpochMs: 456,
      entries: const <String>['You: compatibility session prompt'],
    );
    WorkspaceRef? openedWorkspace;
    SessionHistoryRecord? openedHistory;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: hostBackend,
            fallbackBackend: compatibilityBackend,
            descriptor: hostBackend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              hostWorkspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (workspace, value) async {
              openedWorkspace = workspace;
              openedHistory = value;
            },
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('compatibility session prompt'),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.text('compatibility session prompt'));
    await tester.pump();

    expect(openedHistory, same(history));
    expect(openedWorkspace?.backendId, LinuxCompatibilityBackend.id);
    expect(openedWorkspace?.hostPath, hostWorkspace.hostPath);
  });

  testWidgets('CC Pocket search filters grouped sessions by prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final alphaPath = '${workspace.hostPath}/alpha-project';
    final betaPath = '${workspace.hostPath}/beta-project';
    final histories = <SessionHistoryRecord>[
      SessionHistoryRecord(
        backendId: workspace.backendId,
        workspacePath: alphaPath,
        sessionId: 'search-alpha',
        status: 'stopped',
        updatedAtEpochMs: 200,
        title: 'Alpha title',
        titleIsManual: true,
        entries: const <String>['You: alpha needle'],
      ),
      SessionHistoryRecord(
        backendId: workspace.backendId,
        workspacePath: betaPath,
        sessionId: 'search-beta',
        status: 'stopped',
        updatedAtEpochMs: 100,
        entries: const <String>['You: beta needle'],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              histories,
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNWidgets(2),
    );
    for (final key in <ValueKey<String>>[
      const ValueKey('recent_session_pin_search-alpha_button'),
      ValueKey('pin_project_$alphaPath'),
    ]) {
      expect(tester.getSize(find.byKey(key).first), const Size(48, 48));
    }

    final groupingToggle = find.byKey(const ValueKey('recent_grouping_toggle'));
    await tester.ensureVisible(groupingToggle);
    expect(find.text('已分组'), findsOneWidget);

    for (final target in <Finder>[
      find.byKey(const ValueKey('recent_display_mode_toggle')),
      groupingToggle,
      find.byKey(const ValueKey('recent_project_filter')),
      find.byKey(const ValueKey('recent_named_only_toggle')),
    ]) {
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }

    final searchButton = find.byKey(const ValueKey('search_button'));
    await tester.ensureVisible(searchButton);
    expect(tester.getSize(searchButton).height, greaterThanOrEqualTo(48));
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('search_field')),
      'beta needle',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNWidgets(2),
    );

    await tester.ensureVisible(groupingToggle);
    await tester.tap(groupingToggle);
    await tester.pumpAndSettle();
    expect(find.text('列表'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNWidgets(2),
    );

    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNWidgets(2),
    );
    final projectBar = find.byType(SessionFilterBar);
    final projectFilter = find.descendant(
      of: projectBar,
      matching: find.text('全部项目'),
    );
    await tester.ensureVisible(projectFilter);
    await tester.tap(projectFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'alpha-project'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: projectBar, matching: find.text('alpha-project')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, '全部项目'));
    await tester.pumpAndSettle();
    final namedToggle = find.descendant(
      of: projectBar,
      matching: find.text('已命名'),
    );
    await tester.ensureVisible(namedToggle);
    await tester.tap(namedToggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('recent_session_search-alpha')),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey('recent_session_search-beta')),
      findsNothing,
    );
  });

  testWidgets('recent-session swipe is an accessible delete action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final history = SessionHistoryRecord(
      backendId: workspace.backendId,
      workspacePath: '${workspace.hostPath}/swipe-delete-project',
      sessionId: 'swipe-delete-session',
      status: 'disconnected',
      updatedAtEpochMs: 100,
      title: 'Delete through swipe',
      titleIsManual: true,
      entries: const <String>['You: delete through swipe'],
    );
    SessionHistoryRecord? deleted;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (value) async => deleted = value,
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sessionCard = find
        .byKey(const ValueKey('recent_session_swipe-delete-session'))
        .first;
    await tester.ensureVisible(sessionCard);
    await tester.drag(sessionCard, const Offset(-260, 0));
    await tester.pumpAndSettle();

    final deleteAction = find.bySemanticsLabel('删除会话');
    expect(deleteAction, findsOneWidget);
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    expect(identical(deleted, history), isTrue);
  });

  testWidgets('keeps two sessions under one workspace independently openable', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    const first = SessionHistoryRecord(
      backendId: 'fake-backend',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      sessionId: 'session-first',
      status: 'stopped',
      updatedAtEpochMs: 200,
      entries: <String>['You: first session prompt'],
    );
    const second = SessionHistoryRecord(
      backendId: 'fake-backend',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      sessionId: 'session-second',
      status: 'stopped',
      updatedAtEpochMs: 100,
      entries: <String>['You: second session prompt'],
    );
    SessionHistoryRecord? opened;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              const <SessionHistoryRecord>[first, second],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, value) async => opened = value,
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text('first session prompt'),
      300,
      scrollable: scrollable,
    );
    await tester.scrollUntilVisible(
      find.text('second session prompt'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('first session prompt'), findsOneWidget);
    expect(find.text('second session prompt'), findsOneWidget);

    await tester.ensureVisible(find.text('second session prompt'));
    await tester.pump();
    await tester.tap(find.text('second session prompt'));
    await tester.pump();
    expect(identical(opened, second), isTrue);
    expect(identical(opened, first), isFalse);
  });

  testWidgets('shows live sessions under their workspace and reopens by id', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    String? openedSessionId;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              const <SessionHistoryRecord>[],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            onOpenActiveSessionById: (id) => openedSessionId = id,
            onStopActiveSessionById: (_) async {},
            onToggleActiveSessionPinnedById: (_) async {},
            activeSession: null,
            activeSessions: <CcpocketHomeSessionSnapshot>[
              CcpocketHomeSessionSnapshot(
                workspace: workspace,
                status: 'running',
                active: true,
                turnActive: true,
                queuedPrompts: const <String>['Inspect this workspace'],
                sessionId: 'live-session-1',
                title: 'Live session title',
                pinned: false,
                model: 'gpt-6-luna',
                effort: 'low',
                sandbox: 'workspace-write',
                approvalPolicy: 'on-request',
                planMode: false,
                createdAtEpochMs: 100,
                lastActivityAtEpochMs: 200,
                lastMessage:
                    'This assistant response must not become the title',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('running_sessions_header')), findsNothing);
    expect(find.text('Live session title'), findsOneWidget);
    expect(
      find.text('This assistant response must not become the title'),
      findsNothing,
    );
    expect(find.text('Generating'), findsOneWidget);

    await tester.tap(find.text('Live session title'));
    await tester.pump();
    expect(openedSessionId, 'live-session-1');
  });

  testWidgets('localizes recent-session actions and rename dialog in English', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final history = SessionHistoryRecord(
      backendId: workspace.backendId,
      workspacePath: workspace.hostPath,
      sessionId: 'english-context-session',
      status: 'stopped',
      updatedAtEpochMs: 100,
      title: 'English session',
      entries: const <String>['You: English prompt'],
    );
    String? updatedTitle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.value(
              <SessionHistoryRecord>[history],
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, title) async => updatedTitle = title,
            onOpenSession: (_) async {},
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find
        .byKey(const ValueKey('recent_session_english-context-session'))
        .first;
    await tester.ensureVisible(row);
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Pin session'), findsOneWidget);
    expect(find.text('Rename session'), findsOneWidget);
    expect(find.text('Delete session'), findsOneWidget);
    expect(find.text('打开会话'), findsNothing);

    await tester.tap(find.text('Rename session'));
    await tester.pumpAndSettle();
    expect(find.text('Session name'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('保存'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Renamed session');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(updatedTitle, 'Renamed session');
  });

  testWidgets('localizes local-session read failure and retry in English', (
    tester,
  ) async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CcpocketNativeHome(
            backend: backend,
            descriptor: backend.descriptor,
            workspaces: Future<List<WorkspaceRef>>.value(<WorkspaceRef>[
              workspace,
            ]),
            sessionHistories: Future<List<SessionHistoryRecord>>.delayed(
              Duration.zero,
              () => throw StateError('fixture failure'),
            ),
            hostAccess: Future<AppHostAccessResult>.value(
              const AppHostAccessResult(
                state: 'available',
                identity: 'app',
                path: '/storage/emulated/0/Codex/Workspaces',
                readable: true,
                writable: true,
              ),
            ),
            onCreateHostWorkspace: () async {},
            onAddSafWorkspace: () async {},
            onRefresh: () async {},
            onWorkspaceChanged: (_) async {},
            onHistoryFlagsChanged: (_, {pinned}) async {},
            onDeleteSession: (_) async {},
            onHistoryTitleChanged: (_, _) async {},
            onOpenSession: (_) async {},
            onOpenHistory: (_, _) async {},
            onOpenActiveSession: () {},
            onStopActiveSession: () async {},
            onToggleActiveSessionPinned: () async {},
            activeSession: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not read local sessions:'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}
