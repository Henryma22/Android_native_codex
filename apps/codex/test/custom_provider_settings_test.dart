import 'package:codex/custom_provider_settings.dart';
import 'package:codex/core/domain/custom_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  testWidgets(
    'explains custom provider key visibility in Chinese and English',
    (tester) async {
      const storeChannel = MethodChannel('io.henry.codex/app_preferences');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storeChannel, (call) async {
            return switch (call.method) {
              'loadCustomProviders' => <Object?>[],
              'loadActiveProviderId' => null,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storeChannel, null),
      );

      for (final locale in const <Locale>[Locale('zh'), Locale('en')]) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const CustomProviderSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(
          find.textContaining(
            locale.languageCode == 'zh'
                ? 'Root/UID 0 下的工具可能读取它'
                : 'Root/UID 0 tools may be able to inspect it',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            locale.languageCode == 'zh'
                ? '尚未添加第三方模型'
                : 'No providers configured',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            locale.languageCode == 'zh' ? '添加后返回上一级“模型来源”菜单，再选择第三方服务商启用。' : 'After adding one, return to the parent Model Source menu and choose the third-party source to activate it.',
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.text(locale.languageCode == 'zh' ? '添加服务商' : 'Add provider'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            locale.languageCode == 'zh' ? '添加第三方模型' : 'Add third-party model',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale.languageCode == 'zh'
                ? '需支持 Responses API。'
                : 'requires Responses API.',
          ),
          findsOneWidget,
        );
        await tester.tap(
          find.text(locale.languageCode == 'zh' ? '取消' : 'Cancel'),
        );
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('persists explicitly configured provider effort capabilities', (
    tester,
  ) async {
    const storeChannel = MethodChannel('io.henry.codex/app_preferences');
    Map<Object?, Object?>? saved;
    final activeIds = <Object?>[];
    final modes = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storeChannel, (call) async {
          return switch (call.method) {
            'loadCustomProviders' => <Object?>[],
            'loadActiveProviderId' => null,
            'saveCustomProvider' =>
              saved = call.arguments is Map
                  ? Map<Object?, Object?>.from(call.arguments as Map)
                  : null,
            'saveActiveProviderId' => activeIds.add(
              (call.arguments as Map<Object?, Object?>)['id'],
            ),
            'saveModelProviderMode' => modes.add(
              (call.arguments as Map<Object?, Object?>)['mode'],
            ),
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storeChannel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: CustomProviderSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加服务商'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('provider_name_field')),
      'Fixture provider',
    );
    await tester.enterText(
      find.byKey(const ValueKey('provider_base_url_field')),
      'https://provider.example/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('provider_model_field')),
      'fixture-model',
    );
    await tester.enterText(
      find.byKey(const ValueKey('provider_efforts_field')),
      'low, high, high',
    );
    await tester.tap(find.byKey(const ValueKey('provider_save_button')));
    await tester.pumpAndSettle();

    expect(saved?['reasoningEfforts'], <String>['low', 'high']);
    expect(activeIds, isEmpty);
    expect(modes, isEmpty);
  });

  testWidgets(
    'shows validation instead of silently ignoring an empty provider',
    (tester) async {
      const storeChannel = MethodChannel('io.henry.codex/app_preferences');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storeChannel, (call) async {
            return switch (call.method) {
              'loadCustomProviders' => <Object?>[],
              'loadActiveProviderId' => null,
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storeChannel, null),
      );

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CustomProviderSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加服务商'));
      await tester.pumpAndSettle();

      final apiHelp = find.text(
        '示例：https://api.deepseek.com（不要追加 /v1）；需支持 Responses API。',
      );
      expect(apiHelp, findsOneWidget);
      expect(tester.widget<Text>(apiHelp).maxLines, 3);

      await tester.tap(find.byKey(const ValueKey('provider_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('名称、Responses API 地址和模型 ID 不能为空。'), findsOneWidget);
      expect(find.text('添加第三方模型'), findsOneWidget);
    },
  );

  testWidgets('provider source is selected above third-party configuration', (
    tester,
  ) async {
    const storeChannel = MethodChannel('io.henry.codex/app_preferences');
    final savedActiveIds = <Object?>[];
    final savedModes = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storeChannel, (call) async {
          return switch (call.method) {
            'loadCustomProviders' => <Object?>[
              <String, Object?>{
                'id': 'fixture-provider',
                'name': 'Fixture provider',
                'baseUrl': 'https://provider.example',
                'model': 'fixture-model',
                'apiKey': 'not-a-real-key',
                'reasoningEfforts': <String>['low'],
              },
            ],
            'loadActiveProviderId' => 'fixture-provider',
            'loadModelProviderMode' => 'third_party',
            'saveActiveProviderId' => savedActiveIds.add(
              (call.arguments as Map<Object?, Object?>)['id'],
            ),
            'saveModelProviderMode' => savedModes.add(
              (call.arguments as Map<Object?, Object?>)['mode'],
            ),
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storeChannel, null),
    );

    const activeProvider = CustomProviderConfig(
      id: 'fixture-provider',
      name: 'Fixture provider',
      baseUrl: 'https://provider.example',
      model: 'fixture-model',
      apiKey: 'not-a-real-key',
      reasoningEfforts: <String>['low'],
    );
    CustomProviderConfig? selectedProvider = activeProvider;
    var selectedMode = 'third_party';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ModelProviderSettingsPage(
          selectedProvider: activeProvider,
          thirdPartyEnabled: true,
          onSelectionChanged: (mode, provider) {
            selectedMode = mode;
            selectedProvider = provider;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenAI 订阅'), findsOneWidget);
    expect(find.text('第三方服务商'), findsOneWidget);
    expect(find.text('模型来源'), findsOneWidget);
    expect(find.text('服务商配置'), findsNothing);
    final thirdPartyCard = find.byKey(
      const ValueKey('model_provider_third_party_card'),
    );
    expect(
      find.descendant(
        of: thirdPartyCard,
        matching: find.byKey(
          const ValueKey('model_provider_third_party_option'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: thirdPartyCard,
        matching: find.byKey(
          const ValueKey('model_provider_manage_third_party'),
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('model_provider_manage_third_party')),
    );
    await tester.pumpAndSettle();
    expect(find.text('第三方服务商配置'), findsOneWidget);
    expect(find.text('Fixture provider'), findsOneWidget);
    expect(find.text('OpenAI 登录'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('model_provider_openai_option')),
    );
    await tester.pumpAndSettle();

    expect(savedActiveIds, isEmpty);
    expect(savedModes, <Object?>['openai']);
    expect(selectedProvider, activeProvider);
    expect(selectedMode, 'openai');
    expect(
      tester
          .widget<Radio<String>>(
            find.descendant(
              of: find.byKey(const ValueKey('model_provider_openai_option')),
              matching: find.byType(Radio<String>),
            ),
          )
          .groupValue,
      'openai',
    );

    await tester.tap(
      find.byKey(const ValueKey('model_provider_third_party_option')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('model_provider_manage_third_party')),
      findsOneWidget,
    );
    expect(savedActiveIds, <Object?>['fixture-provider']);
    expect(savedModes, <Object?>['openai', 'third_party']);
    expect(selectedProvider, activeProvider);
    expect(selectedMode, 'third_party');
  });

  testWidgets('choosing a saved provider does not activate third-party mode', (
    tester,
  ) async {
    const storeChannel = MethodChannel('io.henry.codex/app_preferences');
    final savedActiveIds = <Object?>[];
    final savedModes = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storeChannel, (call) async {
          return switch (call.method) {
            'loadCustomProviders' => <Object?>[
              <String, Object?>{
                'id': 'fixture-provider',
                'name': 'Fixture provider',
                'baseUrl': 'https://provider.example',
                'model': 'fixture-model',
                'apiKey': 'not-a-real-key',
                'reasoningEfforts': <String>['low'],
              },
            ],
            'loadActiveProviderId' => null,
            'loadModelProviderMode' => 'openai',
            'saveActiveProviderId' => savedActiveIds.add(
              (call.arguments as Map<Object?, Object?>)['id'],
            ),
            'saveModelProviderMode' => savedModes.add(
              (call.arguments as Map<Object?, Object?>)['mode'],
            ),
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storeChannel, null),
    );

    const provider = CustomProviderConfig(
      id: 'fixture-provider',
      name: 'Fixture provider',
      baseUrl: 'https://provider.example',
      model: 'fixture-model',
      apiKey: 'not-a-real-key',
      reasoningEfforts: <String>['low'],
    );
    var selectedMode = 'openai';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ModelProviderSettingsPage(
          selectedProvider: provider,
          thirdPartyEnabled: false,
          onSelectionChanged: (mode, _) => selectedMode = mode,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('model_provider_manage_third_party')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixture provider'));
    await tester.pumpAndSettle();

    expect(savedActiveIds, <Object?>['fixture-provider']);
    expect(savedModes, isEmpty);
    expect(selectedMode, 'openai');
    expect(find.textContaining('已选配置，当前使用 OpenAI'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_added_outlined), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Radio<String>>(
            find.descendant(
              of: find.byKey(const ValueKey('model_provider_openai_option')),
              matching: find.byType(Radio<String>),
            ),
          )
          .groupValue,
      'openai',
    );
  });
}
