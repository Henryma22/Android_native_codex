import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/main.dart';

void main() {
  const appPreferencesChannel = MethodChannel('io.henry.codex/app_preferences');

  void mockAppPreferences({
    List<Object?> providers = const <Object?>[],
    String? activeProviderId,
    String? providerMode,
  }) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(appPreferencesChannel, (call) async {
      return switch (call.method) {
        'loadAppSettings' => <String, Object?>{
          'themeMode': 'system',
          'locale': 'zh',
          'codexModel': 'gpt-6-luna',
          'codexEffort': 'low',
          'codexApprovalPolicy': 'never',
          'codexSandbox': 'danger-full-access',
        },
        'loadCustomProviders' => providers,
        'loadActiveProviderId' => activeProviderId,
        'loadModelProviderMode' => providerMode,
        _ => null,
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(appPreferencesChannel, null),
    );
  }

  testWidgets('home new-session action yields its space to the keyboard', (
    tester,
  ) async {
    mockAppPreferences();
    const probeChannel = MethodChannel('io.henry.codex/native_probe');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      );
    });

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('a session created from the home page defaults to Root', (
    tester,
  ) async {
    mockAppPreferences();
    const probeChannel = MethodChannel('io.henry.codex/native_probe');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      );
    });

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_codex_execution_mode_chip')),
      findsOneWidget,
    );
    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new session accepts the active third-party provider', (
    tester,
  ) async {
    mockAppPreferences(
      providers: const <Object?>[
        <String, Object?>{
          'id': 'fixture-provider',
          'name': 'Fixture DeepSeek',
          'baseUrl': 'https://provider.example/v1',
          'model': 'deepseek-flash',
          'apiKey': 'fixture-only-secret',
          'reasoningEfforts': <String>['low'],
        },
      ],
      activeProviderId: 'fixture-provider',
      providerMode: 'third_party',
    );
    const probeChannel = MethodChannel('io.henry.codex/native_probe');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      );
    });

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新会话').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('此会话需要的第三方模型配置已不存在'), findsNothing);
    expect(
      find.byKey(const ValueKey('local_codex_model_chip')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local shell exposes CC Pocket home and settings sections', (
    tester,
  ) async {
    mockAppPreferences();
    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();

    expect(find.text('工作区'), findsOneWidget);
    expect(
      find.text('/storage/emulated/0/Codex/Workspaces/demo'),
      findsOneWidget,
    );
    final workspaceCard = find
        .ancestor(
          of: find.text('/storage/emulated/0/Codex/Workspaces/demo'),
          matching: find.byType(Card),
        )
        .first;
    final workspaceCardBounds = tester.getRect(workspaceCard);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(workspaceCardBounds.left, greaterThan(0));
    expect(workspaceCardBounds.right, lessThan(screenWidth));
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byKey(const ValueKey('settings_button')),
              matching: find.byType(IconButton),
            ),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('refresh_workspace_button')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('add_workspace_button'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Bridge'), findsNothing);
    expect(find.text('Claude'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings_button')));
    await tester.pumpAndSettle();
    expect(find.text('设备与运行时'), findsOneWidget);
    expect(find.text('Codex 运行环境'), findsOneWidget);
    expect(find.text('Codex runtime'), findsNothing);
    final settingsScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('codex_settings_scroll')).first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (var i = 0; i < 8 && find.text('Codex 登录').evaluate().isEmpty; i++) {
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.text('Codex 登录'), findsNWidgets(2));
    for (var i = 0; i < 8 && find.text('CODEX').evaluate().isEmpty; i++) {
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.text('CODEX'), findsOneWidget);
    for (
      var i = 0;
      i < 8 &&
          find.byKey(const ValueKey('settings_model_tile')).evaluate().isEmpty;
      i++
    ) {
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('settings_model_tile')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings_execution_identity_tile')),
      findsNothing,
    );
    expect(find.text('新会话默认推理档位'), findsOneWidget);
    expect(find.text('新会话默认审批策略'), findsOneWidget);
    expect(find.text('新会话默认沙盒'), findsOneWidget);

    for (
      var i = 0;
      i < 8 &&
          (tester
                  .getRect(
                    find.byKey(const ValueKey('settings_model_provider_tile')),
                  )
                  .bottom >
              tester.view.physicalSize.height / tester.view.devicePixelRatio);
      i++
    ) {
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.byKey(const ValueKey('settings_model_provider_tile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('模型来源'), findsOneWidget);
    expect(find.text('OpenAI 订阅'), findsOneWidget);
    expect(find.text('第三方服务商'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('model_provider_manage_third_party')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第三方服务商配置'), findsOneWidget);
    expect(find.text('OpenAI 订阅'), findsNothing);
  });

  testWidgets('changing provider source updates every open session', (
    tester,
  ) async {
    mockAppPreferences(
      providers: const <Object?>[
        <String, Object?>{
          'id': 'fixture-provider',
          'name': 'Fixture DeepSeek',
          'baseUrl': 'https://provider.example/v1',
          'model': 'fixture-model',
          'apiKey': 'fixture-only-secret',
          'reasoningEfforts': <String>['low'],
        },
      ],
      activeProviderId: 'fixture-provider',
      providerMode: 'third_party',
    );
    const probeChannel = MethodChannel('io.henry.codex/native_probe');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      );
    });

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();

    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Fixture Model'), findsOneWidget);
      await tester.tap(find.byTooltip('返回会话列表'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const ValueKey('settings_button')));
    await tester.pumpAndSettle();
    final providerTile = find.byKey(
      const ValueKey('settings_model_provider_tile'),
    );
    final settingsScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('codex_settings_scroll')).first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (
      var index = 0;
      index < 8 && find.text('CODEX').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    for (var index = 0; index < 8; index++) {
      if (providerTile.evaluate().isNotEmpty) {
        await tester.ensureVisible(providerTile);
        await tester.pumpAndSettle();
        break;
      }
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    for (var index = 0; index < 8; index++) {
      final bounds = tester.getRect(providerTile);
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      if (bounds.top >= 0 && bounds.bottom <= viewportHeight) break;
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(providerTile);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('model_provider_openai_option')),
    );
    await tester.pumpAndSettle();

    final modelChips = find.byKey(
      const ValueKey('local_codex_model_chip'),
      skipOffstage: false,
    );
    // Two open conversation entries plus the settings-only Codex surface.
    expect(modelChips, findsNWidgets(3));
    final chipLabels = <String>[];
    void collectChipLabels(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) chipLabels.add(widget.data!);
      element.visitChildren(collectChipLabels);
    }

    for (final chip in modelChips.evaluate()) {
      collectChipLabels(chip);
    }
    expect(chipLabels, hasLength(3));
    expect(
      chipLabels.every((label) => label.contains('6 Luna')),
      isTrue,
      reason: 'model chip labels: $chipLabels',
    );
  });

  testWidgets('provider source selection survives a delayed startup restore', (
    tester,
  ) async {
    const provider = <String, Object?>{
      'id': 'fixture-provider',
      'name': 'Fixture DeepSeek',
      'baseUrl': 'https://provider.example/v1',
      'model': 'fixture-model',
      'apiKey': 'fixture-only-secret',
      'reasoningEfforts': <String>['low'],
    };
    final initialMode = Completer<String?>();
    final channel = const MethodChannel('io.henry.codex/app_preferences');
    var loadModeCount = 0;
    var savedMode = 'third_party';
    final savedActiveIds = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      return switch (call.method) {
        'loadAppSettings' => <String, Object?>{
          'themeMode': 'system',
          'locale': 'zh',
          'codexModel': 'gpt-6-luna',
          'codexEffort': 'low',
          'codexApprovalPolicy': 'never',
          'codexSandbox': 'danger-full-access',
        },
        'loadCustomProviders' => <Object?>[provider],
        'loadActiveProviderId' => 'fixture-provider',
        'loadModelProviderMode' =>
          loadModeCount++ == 0 ? initialMode.future : savedMode,
        'saveActiveProviderId' => savedActiveIds.add(
          (call.arguments as Map<Object?, Object?>)['id'],
        ),
        'saveModelProviderMode' =>
          savedMode =
              (call.arguments as Map<Object?, Object?>)['mode'] as String,
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    const probeChannel = MethodChannel('io.henry.codex/native_probe');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        probeChannel,
        null,
      ),
    );

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings_button')));
    await tester.pumpAndSettle();
    expect(find.text('设备与运行时'), findsNothing);
    initialMode.complete('third_party');
    await tester.pumpAndSettle();
    expect(find.text('设备与运行时'), findsOneWidget);
    final providerTile = find.byKey(
      const ValueKey('settings_model_provider_tile'),
    );
    final settingsScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('codex_settings_scroll')).first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (var index = 0; index < 8; index++) {
      if (providerTile.evaluate().isNotEmpty) {
        final bounds = tester.getRect(providerTile);
        final viewportHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        if (bounds.top >= 0 && bounds.bottom <= viewportHeight) break;
      }
      await tester.drag(settingsScrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(providerTile);
    await tester.pumpAndSettle();

    await tester.tap(providerTile);
    await tester.pumpAndSettle();
    expect(find.text('模型来源'), findsOneWidget);
    expect(find.textContaining('当前启用: Fixture DeepSeek'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('model_provider_openai_option')),
    );
    await tester.pumpAndSettle();
    expect(savedMode, 'openai');
    expect(savedActiveIds, isEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // The third-party configuration remains saved, but OpenAI is the active
    // source after the settings route performs its final preference refresh.
    await tester.ensureVisible(providerTile);
    await tester.pumpAndSettle();
    await tester.tap(providerTile);
    await tester.pumpAndSettle();
    expect(find.textContaining('已配置: Fixture DeepSeek'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('6 Luna'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
