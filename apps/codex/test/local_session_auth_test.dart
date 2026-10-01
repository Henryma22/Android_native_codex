import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/ccpocket_local_settings.dart';
import 'package:codex/ccpocket_native_session.dart';
import 'package:codex/core/application/codex_auth_client.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/core/domain/runtime.dart';
import 'package:codex/main.dart';
import 'package:codex/services/session_history.dart';
import 'package:ccpocket_ui/l10n/app_localizations.dart';

class _RecordingBackend extends FakeBackend {
  List<String>? lastArgv;
  final identities = <ExecutionIdentity>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    lastArgv = request.argv;
    identities.add(request.identity);
    return _AuthProcess(request);
  }
}

class _AuthProcess implements InteractiveExecution {
  _AuthProcess(this.request) {
    _events.onListen = () => unawaited(_emitResult());
  }

  final ExecutionRequest request;
  final _events = StreamController<ExecutionEvent>();

  Future<void> _emitResult() async {
    await Future<void>.delayed(Duration.zero);
    if (_events.isClosed) return;
    final output = request.argv.contains('status')
        ? 'Logged in\n'
        : 'Logged out\n';
    _events
      ..add(ExecutionEvent.stdout(output))
      ..add(const ExecutionEvent.exit(0));
    await _events.close();
  }

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }
}

void main() {
  const probeChannel = MethodChannel('io.henry.codex/native_probe');

  testWidgets('refreshes the runtime probe after session resume', (
    tester,
  ) async {
    var probeCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
          probeCount++;
          return <Object?, Object?>{
            'state': 'verified',
            'command': 'codex',
            'version': 'codex fixture',
            'identity': 'app',
          };
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      ),
    );

    final backend = _RecordingBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();
    final initialCount = probeCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(probeCount, greaterThan(initialCount));
  });

  testWidgets('root approval is reused within one session, but not the next', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <Object?, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'app',
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      ),
    );

    final backend = _RecordingBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'root-session-1',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>[],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(LocalSessionPage));
    expect(state.updateExecutionIdentity(ExecutionIdentity.root), isTrue);
    await tester.pump();

    unawaited(state.refreshAuthStatus());
    await tester.pumpAndSettle();
    expect(find.text('Allow Root for this session?'), findsOneWidget);
    await tester.tap(find.text('Allow for session'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(backend.identities.last, ExecutionIdentity.root);

    // Settings refreshes auth status on every entry. The same session grant
    // must suppress another Root prompt while still running the probe as Root.
    unawaited(state.refreshAuthStatus());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Allow Root for this session?'), findsNothing);
    expect(backend.identities.last, ExecutionIdentity.root);

    final composer = find.byKey(const ValueKey('local_codex_composer'));
    await tester.enterText(composer, '/new');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await tester.pump(const Duration(milliseconds: 350));

    unawaited(state.refreshAuthStatus());
    await tester.pumpAndSettle();
    expect(find.text('Allow Root for this session?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // A restored history row carries its Root identity and prior session
    // approval so Settings can refresh status without asking again.
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'root-session-1',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>[],
            executionIdentity: ExecutionIdentity.root,
            rootApprovalGranted: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final restoredState =
        tester.state(find.byType(LocalSessionPage)) as dynamic;
    unawaited(restoredState.refreshAuthStatus());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Allow Root for this session?'), findsNothing);
    expect(backend.identities.last, ExecutionIdentity.root);
  });

  testWidgets('settings owns the interactive login panel', (tester) async {
    var starts = 0;
    var refreshes = 0;
    var logouts = 0;
    final apiKeyController = TextEditingController();
    addTearDown(apiKeyController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: 'codex fixture',
            ),
          ),
          onRefresh: () => Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: 'codex fixture',
            ),
          ),
          loginBuilder: (_) => CcpocketNativeAuthCard(
            status: 'Not checked',
            loginStatus: null,
            busy: false,
            pending: false,
            authenticated: false,
            selectedMode: CodexAuthMode.deviceAuth,
            apiKeyController: apiKeyController,
            challenge: null,
            onModeChanged: (_) {},
            onStart: () => starts++,
            onRefresh: () => refreshes++,
            onCancel: () {},
            onLogout: () => logouts++,
            onCopyCode: () {},
            onOpenUrl: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('local_codex_login_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('local_codex_login_button')),
        )
        .onPressed!
        .call();
    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('local_codex_check_login_button')),
        )
        .onPressed!
        .call();
    expect(starts, 1);
    expect(refreshes, 1);
    expect(logouts, 0);
  });

  testWidgets('localizes a missing-runtime auth error in Chinese', (
    tester,
  ) async {
    final apiKeyController = TextEditingController();
    addTearDown(apiKeyController.dispose);
    const missingRuntime = CodexRuntimeDescriptor(
      state: CodexRuntimeState.missing,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CodexPocketSettingsPage(
          runtime: Future.value(missingRuntime),
          onRefresh: () async => missingRuntime,
          locale: const Locale('zh'),
          loginBuilder: (_) => CcpocketNativeAuthCard(
            status: 'Not checked',
            loginStatus: null,
            error: 'No Codex runtime is installed in the app or root runtime slots.',
            busy: true,
            pending: false,
            authenticated: false,
            selectedMode: CodexAuthMode.deviceAuth,
            apiKeyController: apiKeyController,
            challenge: null,
            onModeChanged: (_) {},
            onStart: () {},
            onRefresh: () {},
            onCancel: () {},
            onLogout: () {},
            onCopyCode: () {},
            onOpenUrl: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final error = find.byKey(const ValueKey('local_codex_auth_error'));
    await tester.ensureVisible(error);
    expect(find.text('应用或 Root 运行时目录中均未安装 Codex 运行环境。'), findsOneWidget);
    expect(find.textContaining('No Codex runtime is installed'), findsNothing);
  });
}
