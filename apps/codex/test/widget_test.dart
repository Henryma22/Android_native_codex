import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the backend-first shell', (WidgetTester tester) async {
    const nativeChannel = MethodChannel('io.henry.codex/native_probe');
    const preferencesChannel = MethodChannel('io.henry.codex/app_preferences');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nativeChannel, (call) async => null);
    messenger.setMockMethodCallHandler(preferencesChannel, (call) async {
      return switch (call.method) {
        'loadAppSettings' => <String, Object?>{
          'themeMode': 'system',
          'locale': 'zh',
          'codexModel': 'gpt-6-luna',
          'codexEffort': 'low',
          'codexApprovalPolicy': 'never',
          'codexSandbox': 'danger-full-access',
        },
        'loadCustomProviders' => <Object?>[],
        'loadActiveProviderId' || 'loadModelProviderMode' => null,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));
    addTearDown(
      () => messenger.setMockMethodCallHandler(preferencesChannel, null),
    );

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('session_list_pane_title')),
      findsOneWidget,
    );
    expect(find.text('Codex'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings_button')));
    await tester.pumpAndSettle();
    expect(find.text('设备与运行时'), findsOneWidget);
    expect(find.text('Codex 运行环境'), findsOneWidget);
    expect(find.text('Codex runtime'), findsNothing);
    final settingsScrollable = find.descendant(
      of: find.byKey(const ValueKey('codex_settings_scroll')),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 8 && find.text('Codex 登录').evaluate().isEmpty; i++) {
      await tester.drag(settingsScrollable.first, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.text('Codex 登录'), findsNWidgets(2));
    for (
      var i = 0;
      i < 8 &&
          find.byKey(const ValueKey('settings_model_tile')).evaluate().isEmpty;
      i++
    ) {
      await tester.drag(settingsScrollable.first, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('gpt-6-luna'), findsOneWidget);
    expect(find.text('低'), findsOneWidget);
  });
}
