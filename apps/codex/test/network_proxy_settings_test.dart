import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/ccpocket_local_settings.dart';
import 'package:codex/core/domain/runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.henry.codex/app_preferences');

  testWidgets('settings saves a VPN local HTTP proxy for future sessions', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(
      state: CodexRuntimeState.verified,
      version: 'codex-cli 0.157.1',
    );
    final saved = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'loadHttpProxyEndpoint':
              return '127.0.0.1:7890';
            case 'saveHttpProxyEndpoint':
              saved.add((call.arguments as Map)['endpoint'] as String);
              return null;
            default:
              throw MissingPluginException();
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final endpointField = find.byKey(
      const ValueKey('network_http_proxy_endpoint'),
    );
    await tester.dragUntilVisible(
      endpointField,
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(endpointField).controller!.text,
      '127.0.0.1:7890',
    );
    expect(tester.widget<TextField>(endpointField).enabled, isTrue);

    await tester.enterText(endpointField, 'localhost:7891');
    expect(
      tester.widget<TextField>(endpointField).controller!.text,
      'localhost:7891',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('network_http_proxy_save'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, <String>['localhost:7891']);
    expect(find.text('已保存；仅对新启动的本地会话生效。'), findsOneWidget);

    final autoButton = find.byKey(const ValueKey('network_http_proxy_auto'));
    await tester.ensureVisible(autoButton);
    await tester.tap(autoButton);
    await tester.pumpAndSettle();
    expect(saved, <String>['localhost:7891', '']);
    expect(find.textContaining('已清除自定义代理'), findsOneWidget);
  });

  testWidgets('settings info dialog uses the selected English language', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(
      state: CodexRuntimeState.verified,
      version: 'codex-cli 0.157.1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final codeFont = find.text('Code font');
    await tester.dragUntilVisible(
      codeFont,
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester.tap(codeFont);
    await tester.pumpAndSettle();

    expect(
      find.text('Uses the Android-compatible monospace font.'),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('知道了'), findsNothing);
  });
}
