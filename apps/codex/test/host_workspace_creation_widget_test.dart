import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/local/local_android_backend.dart';
import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/main.dart';

void main() {
  const localChannel = MethodChannel('io.henry.codex/local_backend');
  const hostEventsChannel = MethodChannel('io.henry.codex/host_events');
  const probeChannel = MethodChannel('io.henry.codex/native_probe');

  testWidgets('creates a direct Host workspace from the home UI', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (call) async {
        return switch (call.method) {
          'listHostDirectory' => <Object?>[],
          'listSafWorkspaces' => <Object?>[],
          'createHostWorkspace' => <String, Object?>{
            'name': 'widget-created',
            'relativePath': 'widget-created',
            'path': '/storage/emulated/0/Codex/Workspaces/widget-created',
          },
          _ => throw MissingPluginException(),
        };
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hostEventsChannel,
      (_) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        return switch (call.method) {
          'probeRoot' => <String, Object?>{
            'state': 'denied',
            'reason': 'test probe',
          },
          'probeAppHostAccess' => <String, Object?>{
            'state': 'available',
            'identity': 'app',
            'path': '/storage/emulated/0/Codex/Workspaces',
            'readable': true,
            'writable': true,
            'entryCount': 0,
          },
          'probeCodexRuntime' => <String, Object?>{'state': 'missing'},
          _ => null,
        };
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(localChannel, null)
        ..setMockMethodCallHandler(hostEventsChannel, null)
        ..setMockMethodCallHandler(probeChannel, null);
    });

    final backend = LocalAndroidBackend();
    await tester.pumpWidget(
      CodexApp(selector: BackendSelector(<Backend>[backend])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workspace_overflow_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建本地工作区').last);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'widget-created');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '已创建本地工作区：'
        '/storage/emulated/0/Codex/Workspaces/widget-created',
      ),
      findsOneWidget,
    );
    final createdWorkspace = find.text(
      '/storage/emulated/0/Codex/Workspaces/widget-created',
    );
    expect(createdWorkspace, findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace_menu_host://widget-created')),
      findsOneWidget,
    );
  });
}
