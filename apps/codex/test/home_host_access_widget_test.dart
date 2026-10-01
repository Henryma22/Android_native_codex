import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/local/local_android_backend.dart';
import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home exposes the local workspace state when storage is denied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const nativeChannel = MethodChannel('io.henry.codex/native_probe');
    const backendChannel = MethodChannel('io.henry.codex/local_backend');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var settingsOpens = 0;

    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      switch (call.method) {
        case 'probeRoot':
          return <String, Object?>{
            'state': 'denied',
            'reason': 'fixture root unavailable',
          };
        case 'probeAppHostAccess':
          return <String, Object?>{
            'state': 'denied',
            'identity': 'app',
            'path': '/storage/emulated/0/Codex/Workspaces',
            'reason': 'MANAGE_EXTERNAL_STORAGE is not granted',
          };
        case 'probeCodexRuntime':
          return <String, Object?>{
            'state': 'missing',
            'reason': 'fixture has no runtime',
          };
        case 'openHostAccessSettings':
          settingsOpens += 1;
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(backendChannel, (call) async {
      switch (call.method) {
        case 'listHostDirectory':
        case 'listSafWorkspaces':
          return <Object?>[];
      }
      return null;
    });

    final backend = LocalAndroidBackend(subscribeToHostEvents: false);
    addTearDown(() async {
      await backend.dispose();
      messenger.setMockMethodCallHandler(nativeChannel, null);
      messenger.setMockMethodCallHandler(backendChannel, null);
    });

    await tester.pumpWidget(
      CodexApp(selector: BackendSelector(<LocalAndroidBackend>[backend])),
    );
    await tester.pumpAndSettle();

    expect(find.text('此设备 · 已拒绝'), findsOneWidget);
    expect(find.text('还没有工作区'), findsOneWidget);
    expect(find.text('添加文件夹'), findsOneWidget);
    expect(find.text('创建本地工作区'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_host_access_tile')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('codex_settings_scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    // The default test viewport is only 600 px high and the tile can still
    // sit below the hit-testable portion after one scroll step.
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings_host_access_tile')),
    );
    await tester.tap(find.byKey(const ValueKey('settings_host_access_tile')));
    expect(settingsOpens, 1);
  });
}
