import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/custom_provider.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/main.dart';
import 'package:codex/services/auth_binding_store.dart';
import 'package:codex/services/codex_model_catalog_cache.dart';
import 'package:codex/services/session_history.dart';
import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';
import 'package:ccpocket_ui/widgets/message_bubble.dart';

void main() {
  const probeChannel = MethodChannel('io.henry.codex/native_probe');
  const localChannel = MethodChannel('io.henry.codex/local_backend');
  const browserChannel = MethodChannel('io.henry.codex/browser');
  const appPreferencesChannel = MethodChannel('io.henry.codex/app_preferences');
  const sessionHistoryChannel = MethodChannel('io.henry.codex/session_history');
  const preferencesChannel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
  );

  test(
    'localizes local file-change transcript projection without rewriting it',
    () {
      expect(
        localizeCodexTranscriptEntry(
          'Agent file change verified: 2 file(s) match the approved content.',
          languageCode: 'zh',
        ),
        'System: 文件变更已验证：2 个文件与批准内容一致。',
      );
      expect(
        localizeCodexTranscriptEntry(
          'Agent file change verified: 2 file(s) match the approved content.',
          languageCode: 'en',
        ),
        'Agent file change verified: 2 file(s) match the approved content.',
      );
    },
  );

  testWidgets(
    'refreshes an existing home session model catalog after a CLI update',
    (tester) async {
      final backend = FakeBackend();
      final generation = AuthBindingStore.currentGeneration.value;
      var encodedCatalog = jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'runtime': 'linux-proot',
        'cliVersion': '0.154.0',
        'authGeneration': generation,
        'models': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'old-model',
            'displayName': 'Old model',
            'reasoningEfforts': <String>['low'],
            'hidden': false,
          },
        ],
      });
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        appPreferencesChannel,
        (call) async => switch (call.method) {
          'loadAuthGeneration' => generation,
          'loadCustomProviders' => <Object?>[],
          'loadActiveProviderId' => null,
          'loadModelProviderMode' => null,
          'loadCodexModelCatalogCache' => encodedCatalog,
          _ => null,
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (call) async =>
            call.method == 'listSessionHistories' ? <Object?>[] : null,
      );
      addTearDown(() async {
        CodexModelCatalogCache.clearMemoryForTesting();
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(appPreferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      Widget shell(String cliVersion) => MaterialApp(
        key: const ValueKey('cli-version-shell'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CodexHomePage(
          key: const ValueKey('codex-home'),
          selector: BackendSelector(<Backend>[backend]),
          compatibilityCliVersion: cliVersion,
        ),
      );

      await tester.pumpWidget(shell('0.154.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final initialState = tester.state(find.byType(LocalSessionPage));
      final initialCatalog =
          await (initialState as dynamic).cachedModelCatalog
              as CodexModelCatalog;
      expect(initialCatalog.modelIds, <String>['old-model']);

      encodedCatalog = jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'runtime': 'linux-proot',
        'cliVersion': '0.155.0',
        'authGeneration': generation,
        'models': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'new-model',
            'displayName': 'New model',
            'reasoningEfforts': <String>['low'],
            'hidden': false,
          },
        ],
      });
      await tester.pumpWidget(shell('0.155.0'));
      await tester.pump();

      final updatedState = tester.state(find.byType(LocalSessionPage));
      final updatedCatalog =
          await (updatedState as dynamic).cachedModelCatalog
              as CodexModelCatalog;
      expect(updatedCatalog.modelIds, <String>['new-model']);
    },
  );

  testWidgets('localizes session details and rename controls in all locales', (
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    final savedTitles = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sessionHistoryChannel,
      (call) async {
        if (call.method == 'saveSessionHistory') {
          final arguments = call.arguments as Map<Object?, Object?>;
          final record = arguments['record'] as Map<Object?, Object?>;
          savedTitles.add(record['title'] as String);
        }
        return null;
      },
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null)
        ..setMockMethodCallHandler(sessionHistoryChannel, null);
    });

    const cases =
        <
          ({
            Locale locale,
            String sessionTitle,
            String sessionDescription,
            String workspace,
            String identity,
            String identityValue,
            String runtime,
            String runtimeValue,
          })
        >[
          (
            locale: Locale('en'),
            sessionTitle: 'Local Android session',
            sessionDescription:
                'The app-server process and transcript stay on this device.',
            workspace: 'Workspace',
            identity: 'Execution identity',
            identityValue: 'App UID',
            runtime: 'Runtime path',
            runtimeValue: 'Local Android',
          ),
          (
            locale: Locale('zh'),
            sessionTitle: 'Android 本地会话',
            sessionDescription: 'app-server 进程和会话记录均保存在此设备上。',
            workspace: '工作区',
            identity: '执行身份',
            identityValue: '应用 UID',
            runtime: '运行环境',
            runtimeValue: '本地 Android',
          ),
          (
            locale: Locale('ja'),
            sessionTitle: 'Android ローカルセッション',
            sessionDescription: 'app-server のプロセスと会話履歴はこの端末に保存されます。',
            workspace: 'ワークスペース',
            identity: '実行 ID',
            identityValue: 'アプリ UID',
            runtime: '実行環境',
            runtimeValue: 'ローカル Android',
          ),
          (
            locale: Locale('ko'),
            sessionTitle: 'Android 로컬 세션',
            sessionDescription: 'app-server 프로세스와 대화 기록은 이 기기에 저장됩니다.',
            workspace: '작업 공간',
            identity: '실행 ID',
            identityValue: '앱 UID',
            runtime: '런타임 경로',
            runtimeValue: '로컬 Android',
          ),
        ];

    for (final testCase in cases) {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(testCase.locale.languageCode),
          locale: testCase.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            restoreHistory: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('local_codex_inactive_session_menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem && widget.value == 'details',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(testCase.sessionTitle), findsOneWidget);
      expect(find.text(testCase.sessionDescription), findsOneWidget);
      expect(find.text(testCase.workspace), findsOneWidget);
      expect(find.text(testCase.identity), findsOneWidget);
      expect(find.text(testCase.identityValue), findsOneWidget);
      expect(find.text(testCase.runtime), findsOneWidget);
      expect(find.text(testCase.runtimeValue), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      Future<void> openRename() async {
        await tester.tap(
          find.byKey(const ValueKey('local_codex_inactive_session_menu')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem && widget.value == 'rename',
          ),
        );
        await tester.pumpAndSettle();
      }

      await openRename();
      var localization = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      expect(find.text(localization.renameSession), findsOneWidget);
      expect(find.text(localization.cancel), findsOneWidget);
      expect(find.text(localization.save), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .decoration!
            .hintText,
        localization.sessionNameHint,
      );
      await tester.tap(find.text(localization.cancel));
      await tester.pumpAndSettle();
      expect(find.text('Saved from session menu'), findsNothing);

      await openRename();
      localization = AppLocalizations.of(
        tester.element(find.byType(AlertDialog)),
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Saved from session menu',
      );
      await tester.tap(find.text(localization.save));
      await tester.pumpAndSettle();
      expect(find.text('Saved from session menu'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      expect(savedTitles, contains('Saved from session menu'));
    }
  });

  testWidgets('read-only Root sessions block command write approvals', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <Object?, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'root',
            }
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sessionHistoryChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null)
        ..setMockMethodCallHandler(sessionHistoryChannel, null);
    });

    final backend = _AutomaticTitleConversationBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'root-read-only-session',
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

    final permissionChip = find.byKey(
      const ValueKey('local_codex_execution_mode_chip'),
    );
    await tester.ensureVisible(permissionChip);
    await tester.tap(permissionChip);
    await tester.pumpAndSettle();
    expect(find.text('Root write policy'), findsOneWidget);
    expect(
      find.textContaining(
        'RootAccessPolicy is app-side guidance and soft routing',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not kernel write isolation'), findsOneWidget);
    const readOnlyLabel = 'Read-only (app-enforced): deny Codex write requests';
    final permissionsScrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 4 && find.text(readOnlyLabel).evaluate().isEmpty; i++) {
      await tester.drag(permissionsScrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text(readOnlyLabel), findsOneWidget);
    final readOnlyOption = find.text(readOnlyLabel);
    await tester.ensureVisible(readOnlyOption);
    await tester.tap(readOnlyOption);
    await tester.pumpAndSettle();

    final composer = find.byKey(const ValueKey('local_codex_composer'));
    await tester.enterText(composer, 'inspect without writing');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await _pumpSession(tester);

    expect(
      find.text(
        'This Root session is read-only; Codex write requests are denied.',
      ),
      findsOneWidget,
    );
    final approve = tester.widget<FilledButton>(
      find.byKey(const ValueKey('local_codex_approve_button')),
    );
    expect(approve.onPressed, isNull);
    expect(
      backend.process.writes.any((value) {
        final message = jsonDecode(value) as Map<Object?, Object?>;
        return message['id'] == 'approval-1';
      }),
      isFalse,
    );
  });

  testWidgets(
    'ordinary Root file changes auto-approve without workspace backup',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <Object?, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'root',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final backend = _ConversationBackend(fileChangeApproval: true);
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'root-direct-file-change-session',
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

      final composer = find.byKey(const ValueKey('local_codex_composer'));
      await tester.enterText(composer, 'update my Android app config');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      expect(
        backend.process.writes.any((value) {
          final message = jsonDecode(value) as Map<Object?, Object?>;
          return message['id'] == 'approval-1' &&
              message['result'] is Map<Object?, Object?> &&
              (message['result'] as Map<Object?, Object?>)['decision'] ==
                  'accept';
        }),
        isTrue,
      );
      expect(find.text('Codex finished the fixture turn.'), findsOneWidget);
      expect(
        find.text('Wait for the file-change preview before approving it.'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('local_codex_approve_button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'ordinary Root system-file commands auto-approve without a generic prompt',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <Object?, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'root',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final backend = _ConversationBackend(
        approvalCommand: 'sed -i s/a/b/ /system/fonts/Roboto-Regular.ttf',
      );
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'root-unclassified-command-session',
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

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'install the workspace package',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      expect(
        backend.process.writes.any((value) {
          final message = jsonDecode(value) as Map<Object?, Object?>;
          return message['id'] == 'approval-1' &&
              message['result'] is Map<Object?, Object?> &&
              (message['result'] as Map<Object?, Object?>)['decision'] ==
                  'accept';
        }),
        isTrue,
      );
      expect(find.text('Codex finished the fixture turn.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local_codex_approve_button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'composer starts a local thread, renders tool approval, and resumes the turn',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async {
          if (call.method == 'probeCodexRuntime') {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _AutomaticTitleConversationBackend();
      backend.process.supportsAutomaticTitle = true;
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      final modelChip = find.byKey(const ValueKey('local_codex_model_chip'));
      final modelChipTopBeforeUsage = tester.getTopLeft(modelChip).dy;
      final composer = find.byKey(const ValueKey('local_codex_composer'));
      await tester.enterText(composer, 'run the fixture command');
      await tester.pump();
      final sendButton = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      // The same text appears once as the user's message and once as the
      // command being proposed in the approval card.
      expect(find.text('run the fixture command'), findsNWidgets(2));
      expect(find.text('echo fixture', skipOffstage: false), findsOneWidget);
      expect(find.text('Command Approval'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local_codex_approve_button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('local_codex_approve_button')),
      );
      await _pumpSession(tester);

      expect(find.text('Command approval'), findsNothing);
      expect(
        backend.process.writes.any((value) {
          final message = jsonDecode(value) as Map<Object?, Object?>;
          return message['id'] == 'approval-1' &&
              message['result'] is Map<Object?, Object?> &&
              (message['result'] as Map<Object?, Object?>)['decision'] ==
                  'accept';
        }),
        isTrue,
      );
      expect(find.text('Codex finished the fixture turn.'), findsOneWidget);
      expect(find.text('Starting local Codex session'), findsNothing);
      final titleRequests = backend.process.writes
          .map((value) => jsonDecode(value) as Map<Object?, Object?>)
          .toList(growable: false);
      expect(
        titleRequests.any(
          (message) =>
              message['method'] == 'thread/start' &&
              (message['params'] as Map<Object?, Object?>)['ephemeral'] == true,
        ),
        isTrue,
      );
      expect(
        titleRequests.any(
          (message) =>
              message['method'] == 'thread/name/set' &&
              (message['params'] as Map<Object?, Object?>)['threadId'] ==
                  'thread-ui-1' &&
              (message['params'] as Map<Object?, Object?>)['name'] ==
                  'Run fixture command',
        ),
        isTrue,
      );

      backend.process._emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/name/updated',
        'params': <String, dynamic>{
          'threadId': 'thread-ui-1',
          'threadName': 'Generated Codex session name',
        },
      });
      await _pumpSession(tester);
      expect(find.text('Generated Codex session name'), findsOneWidget);

      backend.process._emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/tokenUsage/updated',
        'params': <String, dynamic>{
          'threadId': 'thread-ui-1',
          'tokenUsage': <String, dynamic>{
            'total': <String, int>{'inputTokens': 1500, 'outputTokens': 200},
            'last': <String, int>{
              'inputTokens': 750,
              'cachedInputTokens': 50,
              'outputTokens': 200,
            },
            'modelContextWindow': 1000,
          },
        },
      });
      await _pumpSession(tester);
      expect(find.bySemanticsLabel('Context usage 80%'), findsOneWidget);
      expect(
        tester.getTopLeft(modelChip).dy,
        modelChipTopBeforeUsage,
        reason: 'Async quota and token usage updates must not move the model controls.',
      );
    },
  );

  testWidgets(
    'OpenAI app-server sessions use HTTP Responses with the first-party login',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final backend = _ConversationBackend(requestApproval: false);
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            restoreHistory: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'verify first-party HTTP transport',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      final request = backend.requests.singleWhere(
        (request) => request.argv.contains('app-server'),
      );
      const providerId = 'android_openai_http';
      expect(request.argv, contains('model_provider="$providerId"'));
      expect(
        request.argv,
        contains('model_providers.$providerId.name="OpenAI"'),
      );
      expect(
        request.argv,
        contains('model_providers.$providerId.requires_openai_auth=true'),
      );
      expect(
        request.argv,
        contains('model_providers.$providerId.supports_websockets=false'),
      );
      expect(
        request.environment,
        isNot(contains('ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY')),
      );
      expect(backend.process.turnPrompts, <String>[
        'verify first-party HTTP transport',
      ]);
    },
  );

  testWidgets(
    'explicit OpenAI source overrides a third-party provider saved in history',
    (tester) async {
      final savedHistoryRecords = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (call) async {
          if (call.method == 'saveSessionHistory') {
            final arguments = call.arguments as Map<Object?, Object?>;
            savedHistoryRecords.add(
              Map<Object?, Object?>.from(
                arguments['record'] as Map<Object?, Object?>,
              ),
            );
          }
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final backend = _ConversationBackend(requestApproval: false);
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'saved-provider-session',
              threadId: 'saved-third-party-thread',
              customProviderId: 'fixture-provider',
              codexModel: 'deepseek-chat',
              codexEffort: 'high',
              status: 'stopped',
              updatedAtEpochMs: 1,
              entries: const <String>['You: previous third-party turn'],
            ),
            providerModeExplicit: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        backend.requests.where(
          (request) => request.argv.contains('app-server'),
        ),
        isEmpty,
        reason: 'A provider-specific saved thread must not auto-resume under OpenAI.',
      );

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'use OpenAI after switching the provider source',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      final request = backend.requests.singleWhere(
        (request) => request.argv.contains('app-server'),
      );
      expect(request.argv, contains('model_provider="android_openai_http"'));
      expect(request.argv, isNot(contains('model_provider="android_custom"')));
      expect(
        request.environment,
        isNot(contains('ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY')),
      );
      final turnStart = backend.process.writes
          .map((write) => jsonDecode(write) as Map<String, dynamic>)
          .singleWhere((message) => message['method'] == 'turn/start');
      final turnSettings = turnStart['params'] as Map<String, dynamic>;
      expect(turnSettings['model'], 'gpt-6-luna');
      expect(turnSettings['effort'], 'low');
      expect(savedHistoryRecords, isNotEmpty);
      expect(savedHistoryRecords.last['customProviderId'], isNull);
      expect(savedHistoryRecords.last['codexModel'], 'gpt-6-luna');
      final threadMethods = backend.process.writes
          .map((write) => jsonDecode(write) as Map<String, dynamic>)
          .where(
            (message) =>
                message['method'] == 'thread/start' ||
                message['method'] == 'thread/resume',
          );
      expect(threadMethods.single['method'], 'thread/start');
      expect(find.textContaining('prior provider context'), findsOneWidget);
    },
  );

  testWidgets(
    'does not auto-resume a saved thread after the auth generation changes',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final backend = _ConversationBackend(requestApproval: false);
      final workspace = (await backend.listWorkspaces()).single;
      final previousGeneration = AuthBindingStore.currentGeneration.value;
      final currentGeneration = previousGeneration + 1;
      AuthBindingStore.currentGeneration.value = currentGeneration;
      addTearDown(() {
        AuthBindingStore.currentGeneration.value = previousGeneration;
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'old-account-session',
              threadId: 'old-account-thread',
              authGeneration: previousGeneration,
              status: 'ready',
              updatedAtEpochMs: 1,
              entries: const <String>[
                'You: message from the previous account',
                'Codex: previous account response',
              ],
            ),
            // Simulate opening the row after Settings has completed an
            // account switch. The old transcript remains visible, but the
            // provider thread must not be resumed against the new account.
            initialAuthGeneration: currentGeneration + 1,
          ),
        ),
      );
      await _pumpSession(tester);

      expect(
        backend.requests.where(
          (request) => request.argv.contains('app-server'),
        ),
        isEmpty,
        reason:
            'A stale-account history row must not start an app-server: '
            '${backend.requests.map((request) => request.argv).toList()}',
      );
      expect(
        backend.process.writes
            .map((write) => jsonDecode(write) as Map<String, dynamic>)
            .where((message) => message['method'] == 'thread/resume'),
        isEmpty,
        reason: 'A stale-account history row must not resume its old thread.',
      );
      expect(find.textContaining('登录账号已切换'), findsAtLeastNWidgets(1));
      expect(find.text('previous account response'), findsOneWidget);
    },
  );

  testWidgets(
    'custom provider launches the native Codex app-server with an isolated key',
    (tester) async {
      final savedHistoryRecords = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (call) async {
          if (call.method == 'saveSessionHistory') {
            final arguments = call.arguments as Map<Object?, Object?>;
            savedHistoryRecords.add(
              Map<Object?, Object?>.from(
                arguments['record'] as Map<Object?, Object?>,
              ),
            );
          }
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      const provider = CustomProviderConfig(
        id: 'fixture-provider',
        name: 'Fixture Responses',
        baseUrl: 'https://provider.example/v1',
        model: 'fixture-model',
        apiKey: 'fixture-provider-secret',
      );
      final backend = _ConversationBackend(requestApproval: false);
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            customProvider: provider,
            restoreHistory: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'use the Responses provider',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      expect(
        backend.requests.where(
          (request) => request.argv.contains('app-server'),
        ),
        isNotEmpty,
        reason:
            'Captured requests: ${backend.requests.map((request) => request.argv).toList()}',
      );
      final request = backend.requests.singleWhere(
        (request) => request.argv.contains('app-server'),
      );
      expect(request.argv, contains('model_provider="android_custom"'));
      expect(
        request.argv,
        isNot(contains('model_provider="android_openai_http"')),
      );
      expect(request.argv, contains('model="fixture-model"'));
      expect(
        request.argv,
        contains('model_providers.android_custom.wire_api="responses"'),
      );
      expect(request.argv.join(' '), isNot(contains(provider.apiKey)));
      expect(
        request.environment['ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY'],
        provider.apiKey,
      );
      expect(backend.process.turnPrompts, <String>[
        'use the Responses provider',
      ]);
      expect(savedHistoryRecords, isNotEmpty);
      expect(savedHistoryRecords.last['customProviderId'], 'fixture-provider');
      expect(
        jsonEncode(savedHistoryRecords.last),
        isNot(contains(provider.apiKey)),
      );
    },
  );

  testWidgets(
    'a custom-provider history resumes across an OpenAI auth generation change',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      const provider = CustomProviderConfig(
        id: 'fixture-provider',
        name: 'Fixture Responses',
        baseUrl: 'https://provider.example/v1',
        model: 'fixture-model',
        apiKey: 'fixture-provider-secret',
      );
      final backend = _ConversationBackend(requestApproval: false);
      final workspace = (await backend.listWorkspaces()).single;
      final previousGeneration = AuthBindingStore.currentGeneration.value;
      final currentGeneration = previousGeneration + 1;
      AuthBindingStore.currentGeneration.value = currentGeneration;
      addTearDown(() {
        AuthBindingStore.currentGeneration.value = previousGeneration;
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            customProvider: provider,
            providerModeExplicit: true,
            initialAuthGeneration: currentGeneration,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'custom-provider-history',
              threadId: 'custom-provider-thread',
              customProviderId: provider.id,
              authGeneration: previousGeneration,
              status: 'ready',
              updatedAtEpochMs: 1,
              entries: const <String>['You: previous provider prompt'],
            ),
          ),
        ),
      );
      await _pumpSession(tester);
      await _pumpUntil(
        tester,
        () => backend.requests.any(
          (request) => request.argv.contains('app-server'),
        ),
      );

      final appServerRequests = backend.requests
          .where((request) => request.argv.contains('app-server'))
          .toList(growable: false);
      expect(
        appServerRequests,
        isNotEmpty,
        reason:
            'Custom provider did not resume. Requests: '
            '${backend.requests.map((request) => request.argv).toList()}',
      );
      final appServerRequest = appServerRequests.single;
      expect(
        appServerRequest.argv,
        contains('model_provider="android_custom"'),
      );
      expect(
        backend.process.writes
            .map((write) => jsonDecode(write) as Map<String, dynamic>)
            .any((message) => message['method'] == 'thread/resume'),
        isTrue,
      );
      expect(find.textContaining('登录账号已切换'), findsNothing);
    },
  );

  testWidgets(
    'switching provider stops the current turn and routes the next prompt to OpenAI',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      const provider = CustomProviderConfig(
        id: 'fixture-provider',
        name: 'Fixture Responses',
        baseUrl: 'https://provider.example/v1',
        model: 'fixture-model',
        apiKey: 'fixture-provider-secret',
      );
      final backend = _ProviderSwitchConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      const sessionKey = ValueKey<String>('provider-switch-session');

      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            key: sessionKey,
            backend: backend,
            workspace: workspace,
            customProvider: provider,
            restoreHistory: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'start third-party turn before switching',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      expect(backend.processes, hasLength(1));
      expect(backend.processes.single.turnPrompts, <String>[
        'start third-party turn before switching',
      ]);
      expect(backend.processes.single.stopped, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            key: sessionKey,
            backend: backend,
            workspace: workspace,
            providerModeExplicit: true,
            restoreHistory: false,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(backend.processes.single.stopped, isTrue);
      expect(find.textContaining('6 Luna'), findsOneWidget);
      expect(find.textContaining('prior provider context'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'use OpenAI after switching',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      final openAiRequest = backend.requests.singleWhere(
        (request) =>
            request.argv.contains('app-server') &&
            request.argv.contains('model_provider="android_openai_http"'),
      );
      expect(
        openAiRequest.environment,
        isNot(contains('ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY')),
      );
      expect(backend.processes, hasLength(2));
      expect(backend.processes[1].turnPrompts, <String>[
        'use OpenAI after switching',
      ]);
    },
  );

  testWidgets(
    'the latest OpenAI choice wins while a provider switch is stopping the server',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
                'home': '/data/user/0/io.henry.codex/files/codex',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      const provider = CustomProviderConfig(
        id: 'fixture-provider',
        name: 'Fixture Responses',
        baseUrl: 'https://provider.example/v1',
        model: 'fixture-model',
        apiKey: 'fixture-provider-secret',
      );
      final stopGate = Completer<void>();
      final backend = _ProviderSwitchConversationBackend(stopGate: stopGate);
      final workspace = (await backend.listWorkspaces()).single;
      const sessionKey = ValueKey<String>('latest-provider-choice-session');

      Widget session({CustomProviderConfig? customProvider}) => MaterialApp(
        home: LocalSessionPage(
          key: sessionKey,
          backend: backend,
          workspace: workspace,
          customProvider: customProvider,
          providerModeExplicit: true,
          restoreHistory: false,
        ),
      );

      await tester.pumpWidget(session());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'start OpenAI before a rapid source change',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);
      expect(backend.processes, hasLength(1));

      // Begin switching to the provider, then select OpenAI again before the
      // app-server stop finishes. The last selection must be authoritative.
      await tester.pumpWidget(session(customProvider: provider));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpWidget(session());
      await tester.pump();
      stopGate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      expect(backend.processes.single.stopped, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'verify the final source is OpenAI',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);

      final openAiRequest = backend.requests.singleWhere(
        (request) =>
            request.argv.contains('app-server') &&
            request.argv.contains('model_provider="android_openai_http"'),
      );
      expect(
        openAiRequest.environment,
        isNot(contains('ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY')),
      );
      expect(backend.processes, hasLength(2));
      expect(backend.processes[1].turnPrompts, <String>[
        'verify the final source is OpenAI',
      ]);
    },
  );

  testWidgets('a saved session never falls back when its provider is missing', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <String, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'app',
            }
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final backend = _ConversationBackend(requestApproval: false);
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'saved-custom-session',
            threadId: 'saved-custom-thread',
            customProviderId: 'deleted-provider',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>['You: old provider conversation'],
          ),
          missingCustomProviderId: 'deleted-provider',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'custom provider required by this session is unavailable',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('local_codex_composer')),
      'do not send through OpenAI',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await _pumpSession(tester);

    expect(
      backend.requests.where((request) => request.argv.contains('app-server')),
      isEmpty,
    );
  });

  testWidgets('explicitly restoring a provider clears its stale warning', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <String, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'app',
              'home': '/data/user/0/io.henry.codex/files/codex',
            }
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sessionHistoryChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null)
        ..setMockMethodCallHandler(sessionHistoryChannel, null);
    });

    const provider = CustomProviderConfig(
      id: 'restored-provider',
      name: 'Restored provider',
      baseUrl: 'https://provider.example/v1',
      model: 'restored-model',
      apiKey: 'fixture-provider-secret',
    );
    final backend = _ConversationBackend(requestApproval: false);
    final workspace = (await backend.listWorkspaces()).single;
    const key = ValueKey<String>('restored-provider-session');

    Widget session({CustomProviderConfig? customProvider}) => MaterialApp(
      home: LocalSessionPage(
        key: key,
        backend: backend,
        workspace: workspace,
        customProvider: customProvider,
        missingCustomProviderId: customProvider == null
            ? 'restored-provider'
            : null,
        providerModeExplicit: true,
        restoreHistory: false,
      ),
    );

    await tester.pumpWidget(session());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('custom provider required by this session'),
      findsOneWidget,
    );

    await tester.pumpWidget(session(customProvider: provider));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('custom provider required by this session'),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('local_codex_composer')),
      'send after restoring the provider',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await _pumpSession(tester);

    final request = backend.requests.singleWhere(
      (request) => request.argv.contains('app-server'),
    );
    expect(request.argv, contains('model_provider="android_custom"'));
    expect(request.argv, contains('model="restored-model"'));
    expect(
      request.environment['ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY'],
      provider.apiKey,
    );
  });

  testWidgets('legacy chat-only history is preserved but never auto-resumed', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <String, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'app',
            }
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final backend = _ConversationBackend(requestApproval: false);
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'legacy-custom-session',
            threadId: 'custom:legacy-chat-thread',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>[
              'You: keep this old request',
              'Codex: keep this old answer',
            ],
          ),
        ),
      ),
    );
    await _pumpSession(tester);

    expect(find.textContaining('retired chat-only transport'), findsOneWidget);
    expect(find.text('keep this old answer'), findsOneWidget);
    expect(backend.requests, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('local_codex_composer')),
      'do not route the old transcript to another provider',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await _pumpSession(tester);

    expect(backend.requests, isEmpty);
    expect(backend.process.writes, isEmpty);
    expect(find.text('keep this old answer'), findsOneWidget);
  });

  testWidgets('new App UID turns prefer Linux Compatibility with image input', (
    tester,
  ) async {
    final imageBytes = File('assets/branding/codex-icon.png').readAsBytesSync();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
          return <Object?, Object?>{
            'state': 'verified',
            'command': 'codex',
            'version': 'codex fixture',
            'identity': 'app',
          };
        }
        if (call.method == 'pickImages') {
          return <Object?>[
            <String, Object?>{'bytes': imageBytes, 'mimeType': 'image/png'},
          ];
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final nativeBackend = _ConversationBackend(requestApproval: false);
    final compatibilityBackend = _CliConversationBackend(
      requestApproval: false,
    );
    final workspace = (await nativeBackend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: nativeBackend,
          fallbackBackend: compatibilityBackend,
          workspace: workspace,
          restoreHistory: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final attachButton = find.byKey(const ValueKey('attach_image_button'));
    await tester.ensureVisible(attachButton);
    await tester.tap(attachButton);
    await tester.pumpAndSettle();
    final composer = find.byKey(const ValueKey('local_codex_composer'));
    await tester.enterText(composer, 'retry this first turn');
    await tester.pump();
    final sendButton = find.byKey(const ValueKey('send_button'));
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await _pumpSession(tester);

    expect(nativeBackend.process.turnPrompts, isEmpty);
    expect(compatibilityBackend.process.turnPrompts, <String>[
      'retry this first turn',
    ]);
    expect(compatibilityBackend.process.stopped, isFalse);
    expect(
      find.descendant(
        of: find.byType(ChatEntryWidget),
        matching: find.text('retry this first turn'),
      ),
      findsOneWidget,
    );

    List<Map<Object?, Object?>> turnRequests(_ConversationProcess process) =>
        process.writes
            .map((value) => jsonDecode(value) as Map<Object?, Object?>)
            .where((message) => message['method'] == 'turn/start')
            .toList();
    for (final request in turnRequests(compatibilityBackend.process)) {
      final params = request['params'] as Map<Object?, Object?>;
      final input = params['input'] as List<Object?>;
      expect(input, hasLength(2));
      expect(input.last, <String, String>{
        'type': 'image',
        'url': 'data:image/png;base64,${base64Encode(imageBytes)}',
      });
    }
  });

  testWidgets('a new Root turn prefers the Linux Compatibility backend', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async => call.method == 'probeCodexRuntime'
          ? <String, Object?>{
              'state': 'verified',
              'command': 'codex',
              'version': 'codex fixture',
              'identity': 'app',
            }
          : null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sessionHistoryChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null)
        ..setMockMethodCallHandler(sessionHistoryChannel, null);
    });

    final nativeBackend = _ConversationBackend(requestApproval: false);
    final compatibilityBackend = _CliConversationBackend(
      requestApproval: false,
    );
    final workspace = (await nativeBackend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: nativeBackend,
          fallbackBackend: compatibilityBackend,
          workspace: workspace,
          initialIdentity: ExecutionIdentity.root,
          restoreHistory: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local_codex_composer')),
      'run this new Root session through PRoot',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send_button')));
    await _approveRootSessionIfNeeded(tester);
    await _pumpSession(tester);

    expect(nativeBackend.process.turnPrompts, isEmpty);
    expect(
      compatibilityBackend.process.turnPrompts,
      <String>['run this new Root session through PRoot'],
      reason:
          'Compatibility requests: ${compatibilityBackend.requests.map((request) => request.argv).toList()}; native requests: ${nativeBackend.requests.map((request) => request.argv).toList()}; transcript: ${find.byType(ChatEntryWidget)}',
    );
    expect(
      compatibilityBackend.requests.any(
        (request) => request.identity == ExecutionIdentity.root,
      ),
      isTrue,
    );
    final threadStart = compatibilityBackend.process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .singleWhere((message) => message['method'] == 'thread/start');
    final threadStartParams = threadStart['params'] as Map<Object?, Object?>;
    expect(threadStartParams['sandbox'], 'danger-full-access');
    expect(threadStartParams['approvalPolicy'], 'never');
    expect(
      find.textContaining('Root session selected Linux Compatibility / PRoot'),
      findsNothing,
      reason: 'The configured PRoot runtime is the normal route, not a fallback notice.',
    );
  });

  testWidgets('restores a saved thread through Linux/PRoot', (tester) async {
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final nativeBackend = _ConversationBackend(requestApproval: false);
    final compatibilityBackend = _CliConversationBackend();
    final workspace = (await nativeBackend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: nativeBackend,
          fallbackBackend: compatibilityBackend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'saved-session',
            threadId: 'saved-thread',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>[
              'You: previous prompt',
              'Codex: previous response',
            ],
          ),
        ),
      ),
    );
    await _pumpSession(tester);
    expect(find.text('previous response'), findsOneWidget);

    final composer = find.byKey(const ValueKey('local_codex_composer'));
    await tester.enterText(composer, 'continue the saved thread');
    await tester.pump();
    final sendButton = find.byKey(const ValueKey('send_button'));
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await _pumpSession(tester);

    expect(nativeBackend.process.turnPrompts, isEmpty);
    expect(compatibilityBackend.process.turnPrompts, <String>[
      'continue the saved thread',
    ]);
    final resumedThread = compatibilityBackend.process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .singleWhere((message) => message['method'] == 'thread/resume');
    expect(
      (resumedThread['params'] as Map<Object?, Object?>)['threadId'],
      'saved-thread',
    );
  });

  testWidgets(
    'interrupting a running turn drains the next queued prompt in order',
    (tester) async {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _QueuedConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      final composer = find.byKey(const ValueKey('local_codex_composer'));
      await tester.enterText(composer, 'first prompt');
      await tester.pump();
      final initialSendButton = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(initialSendButton);
      await tester.tap(initialSendButton);
      await _pumpSession(tester);
      expect(backend.process.turnPrompts, <String>['first prompt']);
      expect(find.byKey(const ValueKey('stop_button')), findsOneWidget);

      await tester.enterText(composer, 'second prompt');
      await tester.pump();
      final sendButton = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.process.turnPrompts, <String>['first prompt']);
      expect(find.text('second prompt'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stop_button')));
      await tester.pump();
      expect(
        backend.process.writes.any((value) {
          final message = jsonDecode(value) as Map<Object?, Object?>;
          return message['method'] == 'turn/interrupt';
        }),
        isTrue,
      );

      backend.process.completeTurn(interrupted: true);
      await _pumpSession(tester);
      await _pumpSession(tester);

      expect(backend.process.turnPrompts, <String>[
        'first prompt',
        'second prompt',
      ]);
      expect(find.byType(InputChip), findsNothing);
      expect(find.byKey(const ValueKey('stop_button')), findsOneWidget);
    },
  );

  testWidgets('provider network retry resends the prompt on the same thread', (
    tester,
  ) async {
    final imageBytes = File('assets/branding/codex-icon.png').readAsBytesSync();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
          return <Object?, Object?>{
            'state': 'verified',
            'command': 'codex',
            'version': 'codex fixture',
            'identity': 'app',
          };
        }
        if (call.method == 'pickImages') {
          return <Object?>[
            <String, Object?>{'bytes': imageBytes, 'mimeType': 'image/png'},
          ];
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final backend = _QueuedConversationBackend();
    backend.process.failNextTurnWithNetworkError = true;
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalSessionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    final attachButton = find.byKey(const ValueKey('attach_image_button'));
    await tester.ensureVisible(attachButton);
    await tester.tap(attachButton);
    await tester.pumpAndSettle();
    final composer = find.byKey(const ValueKey('local_codex_composer'));
    await tester.enterText(composer, 'retry this prompt');
    await tester.pump();
    final sendButton = find.byKey(const ValueKey('send_button'));
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await _pumpSession(tester);

    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('网络连接失败'), findsWidgets);
    expect(backend.process.turnPrompts, <String>['retry this prompt']);

    await tester.tap(find.text('重试'));
    await _pumpSession(tester);

    expect(backend.process.turnPrompts, <String>[
      'retry this prompt',
      'retry this prompt',
    ]);
    expect(
      backend.process.writes
          .map((value) => jsonDecode(value) as Map<Object?, Object?>)
          .where((message) => message['method'] == 'thread/start'),
      hasLength(1),
    );
    expect(find.text('重试'), findsNothing);
    expect(find.byKey(const ValueKey('stop_button')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatEntryWidget),
        matching: find.text('retry this prompt'),
      ),
      findsOneWidget,
    );

    List<Map<Object?, Object?>> turnRequests() => backend.process.writes
        .map((value) => jsonDecode(value) as Map<Object?, Object?>)
        .where((message) => message['method'] == 'turn/start')
        .toList();
    void expectImageOnEveryRequest(List<Map<Object?, Object?>> requests) {
      expect(requests, hasLength(2));
      for (final request in requests) {
        final params = request['params'] as Map<Object?, Object?>;
        final inputs = params['input'] as List<Object?>;
        final imageInputs = inputs
            .whereType<Map<Object?, Object?>>()
            .where((input) => input['type'] == 'image')
            .toList();
        expect(imageInputs, hasLength(1));
        expect(
          imageInputs.single['url'],
          'data:image/png;base64,${base64Encode(imageBytes)}',
        );
      }
    }

    expectImageOnEveryRequest(turnRequests());
  });

  testWidgets(
    'does not surface an idle provider diagnostic as a turn failure',
    (tester) async {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _QueuedConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      backend.process.emitStderr(
        'ERROR codex_api::endpoint: failed to connect to websocket: '
        'IO error: tls handshake eof',
      );
      await _pumpSession(tester);

      expect(find.textContaining('网络连接失败'), findsNothing);
    },
  );

  testWidgets(
    'keeps a retryable websocket failure running and surfaces terminal network errors',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async => call.method == 'probeCodexRuntime'
            ? <String, Object?>{
                'state': 'verified',
                'command': 'codex',
                'version': 'codex fixture',
                'identity': 'app',
              }
            : null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _QueuedConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'continue after websocket retry',
      );
      await tester.pump();
      final firstSend = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(firstSend);
      await tester.tap(firstSend);
      await _pumpSession(tester);
      expect(backend.process.turnPrompts, <String>[
        'continue after websocket retry',
      ]);

      backend.process.emitStderr(
        'ERROR codex_api::endpoint: failed to connect to websocket: '
        'IO error: tls handshake eof',
      );
      backend.process.emitNetworkError(willRetry: true);
      await _pumpSession(tester);

      expect(find.textContaining('网络连接失败'), findsNothing);
      expect(find.byKey(const ValueKey('stop_button')), findsOneWidget);

      backend.process.emitAssistantDelta('Recovered over HTTPS.');
      backend.process.completeTurn();
      await _pumpSession(tester);
      expect(find.textContaining('Recovered over HTTPS.'), findsOneWidget);
      expect(find.textContaining('网络连接失败'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('local_codex_composer')),
        'report a terminal network error',
      );
      await tester.pump();
      final secondSend = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(secondSend);
      await tester.tap(secondSend);
      await _pumpSession(tester);
      backend.process.emitNetworkError(willRetry: false);
      await _pumpSession(tester);

      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('网络连接失败'), findsWidgets);
      expect(find.textContaining('TLS/证书握手失败'), findsWidgets);
    },
  );

  testWidgets('provider retry accepts an image-only prompt', (tester) async {
    final imageBytes = File('assets/branding/codex-icon.png').readAsBytesSync();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
          return <Object?, Object?>{
            'state': 'verified',
            'command': 'codex',
            'version': 'codex fixture',
            'identity': 'app',
          };
        }
        if (call.method == 'pickImages') {
          return <Object?>[
            <String, Object?>{'bytes': imageBytes, 'mimeType': 'image/png'},
          ];
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final backend = _QueuedConversationBackend();
    backend.process.failNextTurnWithNetworkError = true;
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalSessionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    final attachButton = find.byKey(const ValueKey('attach_image_button'));
    await tester.ensureVisible(attachButton);
    await tester.tap(attachButton);
    await tester.pumpAndSettle();
    final sendButton = find.byKey(const ValueKey('send_button'));
    expect(find.byType(Image), findsWidgets, reason: 'picked image preview');
    expect(
      tester.widget<IconButton>(sendButton).onPressed,
      isNotNull,
      reason: 'an image attachment should enable sending without text',
    );
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await _pumpSession(tester);
    expect(
      backend.process.writes
          .map((value) => jsonDecode(value) as Map<Object?, Object?>)
          .where((message) => message['method'] == 'turn/start'),
      hasLength(1),
      reason: 'an image-only composer submission must start a turn',
    );
    expect(find.textContaining('网络连接失败'), findsWidgets);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await _pumpSession(tester);

    final requests = backend.process.writes
        .map((value) => jsonDecode(value) as Map<Object?, Object?>)
        .where((message) => message['method'] == 'turn/start')
        .toList();
    expect(requests, hasLength(2));
    for (final request in requests) {
      final params = request['params'] as Map<Object?, Object?>;
      final inputs = params['input'] as List<Object?>;
      final imageInputs = inputs
          .whereType<Map<Object?, Object?>>()
          .where((input) => input['type'] == 'image')
          .toList();
      expect(imageInputs, hasLength(1));
      expect(
        imageInputs.single['url'],
        'data:image/png;base64,${base64Encode(imageBytes)}',
      );
      expect(inputs.whereType<Map<Object?, Object?>>(), hasLength(1));
    }
    expect(
      find.descendant(
        of: find.byType(ChatEntryWidget),
        matching: find.text('[图片 1 张]'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'CLI version command shows progress and its result in the thread',
    (tester) async {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      final openedMcpAuthUrls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        browserChannel,
        (call) async {
          if (call.method == 'openExternalUrl') {
            final arguments = call.arguments as Map<Object?, Object?>;
            openedMcpAuthUrls.add(arguments['url'] as String);
            return true;
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(browserChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _CliConversationBackend(
        mcpServers: <String, dynamic>{
          'fixture-mcp': <String, dynamic>{
            'url': 'https://mcp.example.test/mcp',
          },
        },
      );
      backend.process.supportsAutomaticTitle = true;
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      final composer = find.byKey(const ValueKey('local_codex_composer'));
      await tester.enterText(composer, 'start CLI command test');
      await tester.pump();
      final sendButton = find.byKey(const ValueKey('send_button'));
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);
      await tester.tap(
        find.byKey(const ValueKey('local_codex_approve_button')),
      );
      await _pumpSession(tester);
      expect(find.text('Codex finished the fixture turn.'), findsOneWidget);
      expect(find.byKey(const ValueKey('stop_button')), findsNothing);

      await tester.enterText(composer, '/version');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(find.textContaining('codex --version'), findsWidgets);
      expect(backend.oneShotCommands.single, <String>['codex', '--version']);
      expect(find.textContaining('codex-cli 0.156.1'), findsOneWidget);

      await tester.enterText(composer, '/cli --version');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.oneShotCommands.last, <String>['codex', '--version']);
      expect(backend.oneShotCommands, hasLength(2));
      expect(find.textContaining('codex-cli 0.156.1'), findsNWidgets(2));

      await tester.enterText(composer, '/cli login status');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.oneShotCommands.last, <String>[
        'codex',
        'login',
        'status',
      ]);
      expect(
        find.textContaining('Codex login status: Logged in'),
        findsOneWidget,
      );

      await tester.enterText(
        composer,
        '/cli debug prompt-input "a prompt with spaces"',
      );
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.oneShotCommands.last, <String>[
        'codex',
        'debug',
        'prompt-input',
        'a prompt with spaces',
      ]);
      expect(backend.oneShotCommands, hasLength(4));

      await tester.enterText(composer, '/cli mcp status --json');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      final statusRequest = backend.process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'mcpServerStatus/list');
      final statusParams = statusRequest['params'] as Map<Object?, Object?>;
      expect(statusParams['threadId'], 'thread-ui-1');
      expect(statusParams['detail'], 'toolsAndAuthOnly');
      expect(find.textContaining('connected'), findsOneWidget);
      expect(find.textContaining('PRIVATE_MCP_STATUS_ERROR'), findsNothing);
      expect(backend.oneShotCommands, hasLength(4));

      await tester.enterText(composer, '/cli thread list --json');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      final threadListRequest = backend.process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'thread/list');
      final threadListParams =
          threadListRequest['params'] as Map<Object?, Object?>;
      expect(threadListParams['archived'], isFalse);
      expect(threadListParams['sortKey'], 'updated_at');
      expect(threadListParams['useStateDbOnly'], isTrue);
      expect(find.textContaining('"id": "thread-ui-1"'), findsOneWidget);

      await tester.enterText(composer, '/cli mcp login fixture-mcp');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(openedMcpAuthUrls, <String>[
        'https://mcp.example.test/authorize?state=fixture',
      ]);
      expect(
        find.textContaining(
          'OAuth login completed for MCP server "fixture-mcp"',
        ),
        findsOneWidget,
      );
      expect(backend.oneShotCommands, hasLength(4));

      await tester.enterText(composer, '/cli mcp logout fixture-mcp');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.oneShotCommands.last, <String>[
        'codex',
        'mcp',
        'logout',
        'fixture-mcp',
      ]);
      expect(
        find.textContaining('Removed MCP login credentials for "fixture-mcp"'),
        findsOneWidget,
      );
      expect(backend.oneShotCommands, hasLength(5));

      await tester.enterText(composer, '/cli mcp remove fixture-mcp');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      final removeRequest = backend.process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'config/batchWrite');
      final removeParams = removeRequest['params'] as Map<Object?, Object?>;
      final removeEdit =
          (removeParams['edits'] as List).single as Map<Object?, Object?>;
      expect(removeEdit['keyPath'], 'mcp_servers."fixture-mcp"');
      expect(removeParams['expectedVersion'], 'user-config-ui-v1');
      expect(backend.process.mcpServers, isNot(contains('fixture-mcp')));
      expect(find.textContaining('Removed MCP server'), findsOneWidget);
      expect(backend.oneShotCommands, hasLength(5));

      await tester.enterText(composer, '/exec printf hello-from-app-server');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      final commandExecRequest = backend.process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'command/exec');
      final commandExecParams =
          commandExecRequest['params'] as Map<Object?, Object?>;
      expect(commandExecParams['command'], <String>[
        'printf',
        'hello-from-app-server',
      ]);
      expect(commandExecParams['cwd'], '/workspace');
      expect(commandExecParams['processId'], startsWith('session-command-'));
      expect(commandExecParams['streamStdoutStderr'], isTrue);
      expect(find.textContaining('hello-from-app-server'), findsOneWidget);

      await tester.enterText(
        composer,
        '/cli mcp add fixture-new -- node server.js',
      );
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      final addRequest = backend.process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .lastWhere((message) => message['method'] == 'config/batchWrite');
      final addParams = addRequest['params'] as Map<Object?, Object?>;
      final addEdit =
          (addParams['edits'] as List).single as Map<Object?, Object?>;
      expect(addEdit['keyPath'], 'mcp_servers."fixture-new"');
      expect(addEdit['value'], <String, Object?>{
        'command': 'node',
        'args': <String>['server.js'],
      });
      expect(backend.process.mcpServers['fixture-new'], addEdit['value']);
      expect(find.textContaining('Added MCP server'), findsOneWidget);

      await tester.enterText(composer, '/network-test');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);

      expect(backend.oneShotCommands.last[0], 'python');
      expect(backend.oneShotCommands.last[1], '-c');
      expect(
        backend.oneShotCommands.last,
        contains('https://api.openai.com/v1/models'),
      );
      expect(
        backend.requests.last.environment.values,
        isNot(contains('never-include-this-key')),
      );
      expect(find.textContaining('api.openai.com：HTTP 401'), findsOneWidget);
      expect(
        backend.process.writes
            .map(jsonDecode)
            .whereType<Map<Object?, Object?>>()
            .any((message) => message['method'] == 'account/rateLimits/read'),
        isTrue,
      );
      expect(find.textContaining('Codex RPC: reachable'), findsOneWidget);

      backend.process.failRateLimitRead = true;
      await tester.enterText(composer, '/network-test');
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.tap(sendButton);
      await _pumpSession(tester);
      expect(
        find.textContaining('Codex RPC: TLS/certificate handshake failed'),
        findsOneWidget,
      );
    },
  );

  testWidgets('network-test checks Codex RPC before the first thread', (
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferencesChannel,
      (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(preferencesChannel, null);
    });

    final backend = _CliConversationBackend(requestApproval: false);
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    final composer = find.byKey(const ValueKey('local_codex_composer'));
    final sendButton = find.byKey(const ValueKey('send_button'));
    await tester.enterText(composer, '/network-test');
    await tester.pump();
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    await _pumpSession(tester);

    expect(backend.oneShotCommands.single[0], 'python');
    final rpcMethods = backend.process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .map((message) => message['method'])
        .toList();
    expect(rpcMethods, contains('account/rateLimits/read'));
    expect(rpcMethods, isNot(contains('thread/start')));
    expect(find.textContaining('Codex RPC: reachable'), findsOneWidget);
  });

  testWidgets(
    'slash menu fills commands without prematurely clearing history',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            restoreHistory: false,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'slash-menu-history-test',
              status: 'stopped',
              updatedAtEpochMs: 1,
              entries: const <String>[
                'user: Retain this prompt',
                'assistant: Retain this transcript',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final slashButton = find.byKey(const ValueKey('slash_command_button'));
      final composer = find.byKey(const ValueKey('local_codex_composer'));
      final composerField = find
          .descendant(of: composer, matching: find.byType(TextField))
          .first;
      await tester.tap(slashButton);
      await tester.pumpAndSettle();
      final commandList = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('/network-test'),
        280,
        scrollable: commandList,
      );
      await tester.tap(find.text('/network-test'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composerField).controller!.text,
        '/network-test',
      );
      expect(find.text('Retain this transcript'), findsOneWidget);

      await tester.enterText(composerField, '');
      await tester.pump();
      await tester.tap(slashButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('/clear'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composerField).controller!.text,
        '/clear',
      );
      expect(find.text('Retain this transcript'), findsOneWidget);
    },
  );

  testWidgets('opens a saved session by automatically resuming its thread', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null);
    });

    final backend = _ConversationBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'saved-session',
            threadId: 'saved-thread',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>[
              'You: previous prompt',
              'Codex: previous response',
              'System: 当前网络无法连接可选的 MCP 工作器。本地 Codex 会话仍可在不使用该工作器的情况下继续。',
              'System: 当前网络无法连接可选的 MCP 工作器。本地 Codex 会话仍可在不使用该工作器的情况下继续。',
            ],
          ),
        ),
      ),
    );
    await _pumpSession(tester);
    backend.process.emitStderr(
      'rmcp::transport::worker: transport channel closed',
    );
    await _pumpSession(tester);

    expect(
      backend.process.writes.any((value) {
        final message = jsonDecode(value) as Map<Object?, Object?>;
        return message['method'] == 'thread/resume';
      }),
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('local_codex_resume_button')),
      findsNothing,
    );
    expect(find.text('previous response'), findsOneWidget);
    expect(find.textContaining('当前网络无法连接可选的 MCP 工作器'), findsOneWidget);
  });

  testWidgets('localizes an expired saved thread in Chinese', (tester) async {
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null);
    });

    final backend = _ConversationBackend(expiredResume: true);
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'expired-session',
            threadId: 'expired-thread',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>['You: cached message'],
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 4; attempt++) {
      await _pumpSession(tester);
    }

    expect(find.textContaining('已保存的 Codex 会话已过期；本地消息已保留。'), findsOneWidget);
    expect(find.textContaining('已保存的 Codex 会话在此本地运行环境中已不可用'), findsOneWidget);
    expect(find.textContaining('Saved thread expired'), findsNothing);
    expect(find.textContaining('The saved Codex thread'), findsNothing);
    expect(backend.process.stopped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cold-restores session identity, transcript, composer state, and settings',
    (tester) async {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );

      final backend = _QueuedConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      var storedRecord = <Object?, Object?>{
        'backendId': workspace.backendId,
        'workspacePath': workspace.hostPath,
        'sessionId': 'cold-session',
        'threadId': 'cold-thread',
        'title': 'Saved session title',
        'status': 'stopped',
        'updatedAtEpochMs': 123,
        'entries': <String>[
          'You: earlier request',
          'System: MCP request accepted.',
          'Codex: earlier response',
        ],
        'draft': 'draft restored after restart',
        'queuedPrompts': <String>['queued after restart'],
        'promptHistory': <String>[
          'queued after restart',
          'previously sent prompt',
        ],
        'codexModel': 'gpt-5.6-sol',
        'codexEffort': 'high',
        'codexSandbox': 'read-only',
        'codexApprovalPolicy': 'on-request',
        'codexPlanMode': true,
      };
      final historyCalls = <String>[];
      final savedRecords = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sessionHistoryChannel,
        (call) async {
          historyCalls.add(call.method);
          if (call.method == 'loadSessionHistory') return storedRecord;
          if (call.method == 'saveSessionHistory') {
            final arguments = call.arguments as Map<Object?, Object?>;
            final next = Map<Object?, Object?>.from(
              arguments['record'] as Map<Object?, Object?>,
            );
            storedRecord = next;
            savedRecords.add(next);
          }
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null)
          ..setMockMethodCallHandler(sessionHistoryChannel, null);
      });

      final snapshots = <LocalSessionSnapshot?>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            onSnapshotChanged: snapshots.add,
          ),
        ),
      );
      await _pumpSession(tester);

      expect(historyCalls, contains('loadSessionHistory'));
      expect(snapshots.last?.sessionId, 'cold-session');
      expect(snapshots.last?.planMode, isTrue);
      expect(snapshots.last?.model, 'gpt-5.6-sol');
      expect(snapshots.last?.effort, 'high');
      expect(snapshots.last?.sandbox, 'read-only');
      expect(snapshots.last?.transcriptCount, greaterThanOrEqualTo(2));
      expect(
        snapshots.any(
          (snapshot) =>
              snapshot?.sessionId == 'cold-session' &&
              snapshot?.lastMessage == 'earlier response',
        ),
        isTrue,
      );
      expect(
        snapshots.any(
          (snapshot) =>
              snapshot?.queuedPrompts.contains('queued after restart') == true,
        ),
        isTrue,
      );
      final composer = find.byKey(const ValueKey('local_codex_composer'));
      final composerField = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      final controller = tester.widget<TextField>(composerField).controller!;
      expect(controller.text, 'draft restored after restart');

      final resumed = backend.process.writes
          .map((write) => jsonDecode(write) as Map<String, dynamic>)
          .firstWhere((message) => message['method'] == 'thread/resume');
      expect(
        (resumed['params'] as Map<String, dynamic>)['threadId'],
        'cold-thread',
      );
      expect(backend.process.turnPrompts, <String>['queued after restart']);

      controller.text = 'updated after cold restore';
      await tester.pump(const Duration(milliseconds: 500));
      await _pumpSession(tester);
      expect(savedRecords, isNotEmpty);
      expect(savedRecords.last['sessionId'], 'cold-session');
      expect(savedRecords.last['draft'], 'updated after cold restore');
      expect(savedRecords.last['queuedPrompts'], isEmpty);
      expect(
        savedRecords.last['promptHistory'],
        containsAll(<String>['queued after restart', 'previously sent prompt']),
      );
      expect(savedRecords.last['codexModel'], 'gpt-5.6-sol');
      expect(savedRecords.last['codexEffort'], 'high');
      expect(savedRecords.last['codexPlanMode'], isTrue);
      expect(
        savedRecords.last['entries'],
        contains('System: MCP request accepted.'),
        reason: 'history persistence must retain source transcript rows',
      );
      expect(
        savedRecords.last['entries'],
        isNot(contains('System: MCP 请求已接受。')),
        reason: 'localized display text must not be persisted as history',
      );
    },
  );

  testWidgets(
    'reconnects an unexpectedly exited thread once and keeps the session open',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async {
          if (call.method == 'probeCodexRuntime') {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null);
      });

      final backend = _ReconnectBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(
            backend: backend,
            workspace: workspace,
            initialHistory: SessionHistoryRecord(
              backendId: workspace.backendId,
              workspacePath: workspace.hostPath,
              sessionId: 'reconnect-session',
              threadId: 'reconnect-thread',
              status: 'stopped',
              updatedAtEpochMs: 1,
              entries: const <String>['You: keep this history'],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.processes, hasLength(1));
      backend.processes.single.emitExit();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(backend.processes, hasLength(greaterThanOrEqualTo(2)));
      final reconnectWrites = backend.processes[1].writes;
      expect(
        reconnectWrites.any((value) {
          final message = jsonDecode(value) as Map<Object?, Object?>;
          return message['method'] == 'thread/resume';
        }),
        isTrue,
      );
      // The persisted legacy transcript entry and the current turn are both
      // retained while the session reconnects independently.
      expect(find.text('keep this history'), findsNWidgets(2));
      expect(
        find.text('The local Codex app-server disconnected.'),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('local_codex_resume_button')),
        findsNothing,
      );
    },
  );

  testWidgets('manual stop wins over a delayed unexpected-exit cleanup', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null);
    });

    final cleanupGate = Completer<void>();
    final backend = _ReconnectBackend(stopGate: cleanupGate);
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(
          backend: backend,
          workspace: workspace,
          initialHistory: SessionHistoryRecord(
            backendId: workspace.backendId,
            workspacePath: workspace.hostPath,
            sessionId: 'manual-stop-session',
            threadId: 'manual-stop-thread',
            status: 'stopped',
            updatedAtEpochMs: 1,
            entries: const <String>['You: preserve this transcript'],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.processes, hasLength(1));

    backend.processes.single.emitExit();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('local_codex_stop_session_button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('local_codex_stop_session_button')),
    );
    await tester.pump();

    cleanupGate.complete();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(backend.processes, hasLength(1));
    expect(
      find.byKey(const ValueKey('local_codex_resume_button')),
      findsNothing,
    );
    expect(find.text('preserve this transcript'), findsWidgets);
  });

  testWidgets(
    'CC Pocket composer commands and prompt history are interactive',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async {
          if (call.method == 'probeCodexRuntime') {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _ConversationBackend();
      final workspace = (await backend.listWorkspaces()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSessionPage(backend: backend, workspace: workspace),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Insert command or skill'));
      await tester.pumpAndSettle();
      expect(find.text('/status'), findsOneWidget);
      await tester.tap(find.text('/status'));
      await tester.pumpAndSettle();

      final composer = find.byKey(const ValueKey('local_codex_composer'));
      final composerField = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      final controller = tester.widget<TextField>(composerField).controller!;
      expect(controller.text, '/status');
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);
      expect(controller.text, isEmpty);
      expect(find.textContaining('Codex app-server'), findsOneWidget);

      controller.value = const TextEditingValue(
        text: '/status',
        selection: TextSelection.collapsed(offset: 7),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('mention_button')));
      await tester.pump();
      expect(controller.text, '/status@');

      controller.value = const TextEditingValue(
        text: 'alpha\nbeta',
        selection: TextSelection.collapsed(offset: 10),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('indent_button')));
      await tester.pump();
      expect(controller.text, 'alpha\n    beta');

      controller.value = const TextEditingValue(
        text: 'history probe',
        selection: TextSelection.collapsed(offset: 13),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send_button')));
      await _pumpSession(tester);
      await tester.tap(find.byKey(const ValueKey('prompt_history_button')));
      await tester.pumpAndSettle();
      final historyEntry = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('history probe'),
      );
      expect(historyEntry, findsOneWidget);
      await tester.tap(historyEntry);
      await tester.pumpAndSettle();
      expect(controller.text, 'history probe');
    },
  );

  testWidgets(
    'switching sessions preserves and continues the hidden streaming turn',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        (call) async {
          if (call.method == 'probeCodexRuntime') {
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        localChannel,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        preferencesChannel,
        (call) async => call.method == 'getAll' ? <String, Object?>{} : true,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        appPreferencesChannel,
        (call) async => switch (call.method) {
          'loadCustomProviders' => <Object?>[],
          'loadActiveProviderId' => null,
          _ => null,
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
          ..setMockMethodCallHandler(probeChannel, null)
          ..setMockMethodCallHandler(localChannel, null)
          ..setMockMethodCallHandler(appPreferencesChannel, null)
          ..setMockMethodCallHandler(preferencesChannel, null);
      });

      final backend = _ConcurrentConversationBackend();
      await tester.pumpWidget(
        CodexApp(selector: BackendSelector(<Backend>[backend])),
      );
      await tester.pumpAndSettle();

      await _openHomeSession(tester, 'first session');
      expect(backend.processes, hasLength(1));
      backend.processes[0].emitAssistantDelta('first chunk');
      await _pumpSession(tester);
      expect(find.text('first chunk'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('local_codex_session_back_button')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('ccpocket_home_content')),
        findsOneWidget,
      );

      await _openHomeSession(tester, 'second session');

      expect(backend.processes, hasLength(2));
      expect(backend.processes[0].stopped, isFalse);
      expect(backend.processes[1].stopped, isFalse);

      // The first turn must continue delivering events while its page is
      // offstage, not merely leave its OS process alive.
      backend.processes[0].emitAssistantDelta(' while the second is open');
      await _pumpSession(tester);
      expect(
        find.text('first chunk while the second is open', skipOffstage: false),
        findsOneWidget,
      );
      expect(backend.processes[0].stopped, isFalse);
      expect(backend.processes[1].stopped, isFalse);
    },
  );
}

Future<void> _pumpSession(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pump();
}

Future<void> _openHomeSession(WidgetTester tester, String prompt) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pump();
  // Opening a Home session may now await secure provider-store restoration so
  // a new session cannot race into the wrong auth/provider mode.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  final composer = find.byKey(const ValueKey('local_codex_composer'));
  await tester.enterText(composer, prompt);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('send_button')));
  await _approveRootSessionIfNeeded(tester);
  await _pumpSession(tester);
}

Future<void> _approveRootSessionIfNeeded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final allowForSession = find.text('Allow for session');
    final allowThisSession = find.text('允许此会话');
    final approvalButton = allowForSession.evaluate().isNotEmpty
        ? allowForSession
        : allowThisSession;
    if (approvalButton.evaluate().isEmpty) continue;
    await tester.tap(approvalButton);
    await tester.pump(const Duration(milliseconds: 100));
    return;
  }
}

class _ConversationBackend extends FakeBackend {
  _ConversationBackend({
    bool requestApproval = true,
    bool fileChangeApproval = false,
    bool expiredResume = false,
    String approvalCommand = 'echo fixture',
    Map<String, dynamic> mcpServers = const <String, dynamic>{},
  }) : process = _ConversationProcess(
         requestApproval: requestApproval,
         fileChangeApproval: fileChangeApproval,
         expiredResume: expiredResume,
         approvalCommand: approvalCommand,
         mcpServers: mcpServers,
       );

  final _ConversationProcess process;
  final oneShotCommands = <List<String>>[];
  final requests = <ExecutionRequest>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    requests.add(request);
    final loadsModelInstructions =
        request.argv.contains('debug') && request.argv.contains('models');
    final checksLoginStatus =
        request.argv.contains('login') && request.argv.contains('status');
    final logsOutMcp =
        request.argv.contains('mcp') && request.argv.contains('logout');
    final probesNetwork =
        request.argv.firstOrNull == 'python' &&
        request.argv.length > 1 &&
        request.argv[1] == '-c';
    if (request.argv.contains('--version') ||
        checksLoginStatus ||
        logsOutMcp ||
        request.argv.contains('prompt-input') ||
        loadsModelInstructions ||
        probesNetwork) {
      oneShotCommands.add(request.argv);
      final command = _OneShotConversationProcess(
        request.argv.contains('--version')
            ? 'codex-cli 0.156.1\n'
            : checksLoginStatus
            ? 'Logged in\n'
            : logsOutMcp
            ? 'Logged out\n'
            : probesNetwork
            ? '{"host":"api.openai.com","scheme":"https","status":401}\n'
                  '{"host":"auth.openai.com","scheme":"https","status":200}\n'
            : loadsModelInstructions
            ? '{"models":[{"slug":"gpt-5.6-luna","base_instructions":"fixture model instructions"}]}\n'
            : '{"prompt":"a prompt with spaces"}\n',
      );
      return command;
    }
    return process;
  }
}

class _ProviderSwitchConversationBackend extends FakeBackend {
  _ProviderSwitchConversationBackend({this.stopGate});

  final Completer<void>? stopGate;
  final requests = <ExecutionRequest>[];
  final processes = <_ConversationProcess>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    requests.add(request);
    if (request.argv.contains('debug') && request.argv.contains('models')) {
      return _OneShotConversationProcess(
        '{"models":[{"slug":"fixture-model","base_instructions":"fixture instructions"}]}\n',
      );
    }
    final process = _ConversationProcess(
      requestApproval: false,
      stopGate: stopGate,
    );
    processes.add(process);
    return process;
  }
}

class _QueuedConversationBackend extends FakeBackend {
  final process = _ConversationProcess(requestApproval: false);

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) => process;
}

class _CliConversationBackend extends _ConversationBackend {
  _CliConversationBackend({super.requestApproval = true, super.mcpServers});

  @override
  BackendDescriptor get descriptor => const BackendDescriptor(
    id: 'fake-backend',
    kind: BackendKind.linuxCompatibility,
    displayName: 'Fake PRoot Backend',
    version: 'fixture',
    health: BackendHealth.verified,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: true,
    ),
  );
}

class _AutomaticTitleConversationBackend extends _CliConversationBackend {}

class _ConcurrentConversationBackend extends FakeBackend {
  final processes = <_ConversationProcess>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    final process = _ConversationProcess(requestApproval: false);
    processes.add(process);
    return process;
  }
}

class _ConversationProcess implements InteractiveExecution {
  _ConversationProcess({
    this.requestApproval = true,
    this.fileChangeApproval = false,
    this.expiredResume = false,
    this.approvalCommand = 'echo fixture',
    this.stopGate,
    Map<String, dynamic> mcpServers = const <String, dynamic>{},
  }) : mcpServers = Map<String, dynamic>.of(mcpServers);

  final bool requestApproval;
  final bool fileChangeApproval;
  final bool expiredResume;
  final String approvalCommand;
  final Completer<void>? stopGate;
  final Map<String, dynamic> mcpServers;
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  var supportsAutomaticTitle = false;
  var _stopped = false;
  var failNextTurnWithNetworkError = false;
  var failNextTurnWithCapabilityError = false;
  var failRateLimitRead = false;
  Object? _pendingInterruptRequestId;

  bool get stopped => _stopped;

  List<String> get turnPrompts {
    final prompts = <String>[];
    for (final write in writes) {
      final message = jsonDecode(write) as Map<String, dynamic>;
      if (message['method'] != 'turn/start') continue;
      final params = message['params'] as Map<String, dynamic>;
      for (final input in params['input'] as List<Object?>) {
        if (input is Map && input['type'] == 'text') {
          prompts.add(input['text'] as String);
          break;
        }
      }
    }
    return prompts;
  }

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    if (_stopped) return;
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    final params =
        message['params'] as Map<Object?, Object?>? ??
        const <Object?, Object?>{};
    if (id == null) return;

    if (method == 'initialize') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      return;
    }
    if (method == 'thread/start' || method == 'thread/resume') {
      if (method == 'thread/resume' && expiredResume) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{
            'code': -32000,
            'message': 'thread not found',
          },
        });
        return;
      }
      final isTitleThread =
          supportsAutomaticTitle && params['ephemeral'] == true;
      final threadId = isTitleThread ? 'title-thread-ui-1' : 'thread-ui-1';
      if (isTitleThread) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'thread/started',
          'params': <String, dynamic>{
            'thread': <String, String>{'id': threadId},
          },
        });
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': threadId},
        },
      });
      return;
    }
    if (method == 'account/rateLimits/read') {
      if (failRateLimitRead) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, Object?>{
            'code': -32000,
            'message': 'TLS handshake EOF',
          },
        });
        return;
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'rateLimits': <String, dynamic>{
            'primary': <String, dynamic>{
              'usedPercent': 1,
              'windowDurationMins': 300,
            },
            'secondary': <String, dynamic>{
              'usedPercent': 2,
              'windowDurationMins': 10080,
            },
          },
        },
      });
      return;
    }
    if (method == 'config/read') {
      final includeLayers = params['includeLayers'] == true;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'config': <String, dynamic>{'mcp_servers': mcpServers},
          if (includeLayers)
            'layers': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': <String, dynamic>{
                  'type': 'user',
                  'file': '/codex/config.toml',
                  'profile': null,
                },
                'version': 'user-config-ui-v1',
                'config': <String, dynamic>{
                  'mcp_servers': Map<String, dynamic>.of(mcpServers),
                },
              },
            ],
        },
      });
      return;
    }
    if (method == 'config/batchWrite') {
      final edit = (params['edits'] as List).single as Map<Object?, Object?>;
      final keyPath = edit['keyPath'] as String;
      final name = jsonDecode(keyPath.substring('mcp_servers.'.length));
      if (name is String) {
        final value = edit['value'];
        if (value == null) {
          mcpServers.remove(name);
        } else {
          mcpServers[name] = value;
        }
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'status': 'ok'},
      });
      return;
    }
    if (method == 'mcpServerStatus/list') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'fixture-mcp',
              'runtimeStatus': 'connected',
              'authStatus': 'oauth',
              'tools': <String, dynamic>{'read_file': <String, dynamic>{}},
              'toolsError': 'PRIVATE_MCP_STATUS_ERROR',
            },
          ],
          'nextCursor': null,
        },
      });
      return;
    }
    if (method == 'command/exec') {
      final streamed = params['streamStdoutStderr'] == true;
      if (streamed) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'command/exec/outputDelta',
          'params': <String, dynamic>{
            'processId': params['processId'],
            'stream': 'stdout',
            'deltaBase64': base64Encode(utf8.encode('hello-from-app-server\n')),
            'capReached': false,
          },
        });
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'exitCode': 0,
          'stdout': streamed ? '' : 'hello-from-app-server\n',
          'stderr': '',
        },
      });
      return;
    }
    if (method == 'thread/list') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'thread-ui-1',
              'sessionId': 'session-ui-1',
              'name': 'Run fixture command',
              'preview': 'start CLI command test',
              'cwd': '/workspace/fixture',
              'model': 'gpt-5.6-luna',
              'modelProvider': 'openai',
              'reasoningEffort': 'low',
              'status': <String, dynamic>{'type': 'idle'},
              'createdAt': 100,
              'updatedAt': 200,
            },
          ],
          'nextCursor': null,
        },
      });
      return;
    }
    if (method == 'mcpServer/oauth/login') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'mcpServer/oauthLogin/completed',
        'params': <String, dynamic>{
          'name': params['name'],
          'threadId': params['threadId'],
          'success': true,
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, String>{
          'authorizationUrl':
              'https://mcp.example.test/authorize?state=fixture',
        },
      });
      return;
    }
    if (method == 'turn/interrupt') {
      // app-server resolves turn/interrupt only after TurnAborted has been
      // emitted. Keep the fixture's response deferred to match the protocol.
      _pendingInterruptRequestId = id;
      return;
    }
    if (method == 'turn/start') {
      if (supportsAutomaticTitle && params['threadId'] == 'title-thread-ui-1') {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'turn/started',
          'params': <String, dynamic>{
            'threadId': 'title-thread-ui-1',
            'turn': <String, String>{'id': 'title-turn-ui-1'},
          },
        });
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'item/completed',
          'params': <String, dynamic>{
            'threadId': 'title-thread-ui-1',
            'turnId': 'title-turn-ui-1',
            'item': <String, String>{
              'type': 'agentMessage',
              'text': '{"title":"Run fixture command"}',
            },
          },
        });
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'turn/completed',
          'params': <String, dynamic>{
            'threadId': 'title-thread-ui-1',
            'turn': <String, String>{
              'id': 'title-turn-ui-1',
              'status': 'completed',
            },
          },
        });
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, dynamic>{
            'turn': <String, String>{'id': 'title-turn-ui-1'},
          },
        });
        return;
      }
      if (failNextTurnWithCapabilityError) {
        failNextTurnWithCapabilityError = false;
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32000,
            'message': 'thread store error: try_lock() not supported',
          },
        });
        return;
      }
      if (failNextTurnWithNetworkError) {
        failNextTurnWithNetworkError = false;
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32000,
            'message': 'TLS handshake EOF',
          },
        });
        return;
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, String>{'id': 'turn-ui-1'},
        },
      });
      if (requestApproval) {
        final itemType = fileChangeApproval ? 'fileChange' : 'commandExecution';
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'item/started',
          'params': <String, dynamic>{
            'item': <String, dynamic>{
              'type': itemType,
              if (!fileChangeApproval) 'command': approvalCommand,
            },
          },
        });
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'approval-1',
          'method': fileChangeApproval
              ? 'item/fileChange/requestApproval'
              : 'item/commandExecution/requestApproval',
          'params': <String, dynamic>{
            if (fileChangeApproval)
              'changes': <Map<String, String>>[
                <String, String>{
                  'path': '/data/user/0/example/files/preferences.xml',
                },
              ]
            else
              'command': approvalCommand,
            'availableDecisions': <String>['accept', 'decline'],
          },
        });
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, String>{'turnId': 'turn-ui-1'},
      });
      return;
    }
    if (id == 'approval-1') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'item/agentMessage/delta',
        'params': <String, String>{'delta': 'Codex finished the fixture turn.'},
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/completed',
        'params': <String, dynamic>{
          'turn': <String, String>{'status': 'completed'},
        },
      });
    }
    if (method == 'thread/name/set') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/name/updated',
        'params': <String, dynamic>{
          'threadId': params['threadId'],
          'threadName': params['name'],
        },
      });
      return;
    }
    if (method == 'thread/unsubscribe') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      return;
    }
  }

  void emitAssistantDelta(String delta) {
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/agentMessage/delta',
      'params': <String, String>{'delta': delta},
    });
  }

  void emitStderr(String text) {
    if (!_stopped && !_events.isClosed) {
      _events.add(ExecutionEvent.stderr(text));
    }
  }

  void emitNetworkError({required bool willRetry}) {
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'error',
      'params': <String, dynamic>{
        'error': <String, String>{
          'message':
              'failed to connect to websocket: IO error: tls handshake eof',
        },
        'willRetry': willRetry,
        'threadId': 'thread-ui-1',
        'turnId': 'turn-ui-1',
      },
    });
  }

  void completeTurn({bool interrupted = false}) {
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': interrupted ? 'turn/interrupted' : 'turn/completed',
      'params': <String, dynamic>{
        'turn': <String, String>{
          'status': interrupted ? 'interrupted' : 'completed',
        },
      },
    });
    final interruptRequestId = _pendingInterruptRequestId;
    if (interruptRequestId != null) {
      _pendingInterruptRequestId = null;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': interruptRequestId,
        'result': <String, dynamic>{},
      });
    }
  }

  void _emitJson(Map<String, dynamic> value) {
    if (!_stopped && !_events.isClosed) {
      _events.add(ExecutionEvent.stdout('${jsonEncode(value)}\n'));
    }
  }

  void completeCommand(String output) {
    if (_stopped || _events.isClosed) return;
    _events
      ..add(ExecutionEvent.stdout(output))
      ..add(const ExecutionEvent.exit(0));
    unawaited(_events.close());
  }

  @override
  Future<void> stop() async {
    await stopGate?.future;
    _stopped = true;
    if (!_events.isClosed) await _events.close();
  }
}

class _OneShotConversationProcess
    implements InteractiveExecution, StdinClosableExecution {
  _OneShotConversationProcess(this.output);

  final String output;
  final _events = StreamController<ExecutionEvent>();
  var _stopped = false;
  var stdinClosed = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> closeStdin() async {
    if (_stopped || stdinClosed) return;
    stdinClosed = true;
    _events
      ..add(ExecutionEvent.stdout(output))
      ..add(const ExecutionEvent.exit(0));
    await _events.close();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    if (!_events.isClosed) await _events.close();
  }
}

class _ReconnectBackend extends FakeBackend {
  _ReconnectBackend({this.stopGate});

  final Completer<void>? stopGate;
  final processes = <_ReconnectProcess>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    final process = _ReconnectProcess(
      stopGate: processes.isEmpty ? stopGate : null,
    );
    processes.add(process);
    return process;
  }
}

class _ReconnectProcess implements InteractiveExecution {
  _ReconnectProcess({this.stopGate});

  final Completer<void>? stopGate;
  final _events = StreamController<ExecutionEvent>.broadcast();
  final writes = <String>[];
  var _stopped = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    if (_stopped) return;
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    if (id == null) return;
    if (method == 'initialize') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      return;
    }
    if (method == 'thread/start' || method == 'thread/resume') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': 'reconnect-thread'},
        },
      });
      return;
    }
    if (method == 'account/rateLimits/read') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'rateLimits': <String, dynamic>{
            'primary': <String, dynamic>{
              'usedPercent': 1,
              'windowDurationMins': 300,
            },
            'secondary': <String, dynamic>{
              'usedPercent': 2,
              'windowDurationMins': 10080,
            },
          },
        },
      });
    }
  }

  void emitExit() {
    if (!_stopped && !_events.isClosed) {
      _events.add(const ExecutionEvent.exit(17));
    }
  }

  void _emitJson(Map<String, dynamic> value) {
    if (!_stopped && !_events.isClosed) {
      _events.add(ExecutionEvent.stdout('${jsonEncode(value)}\n'));
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await stopGate?.future;
  }
}
