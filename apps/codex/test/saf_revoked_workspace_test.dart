import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/local/local_android_backend.dart';
import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/main.dart';

void main() {
  const localChannel = MethodChannel('io.henry.codex/local_backend');
  const hostEventsChannel = MethodChannel('io.henry.codex/host_events');
  const probeChannel = MethodChannel('io.henry.codex/native_probe');

  testWidgets('revoked SAF workspace keeps only the Forget action', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (call) async {
        return switch (call.method) {
          'listHostDirectory' => <Object?>[],
          'listSafWorkspaces' => <Object?>[
            <Object?, Object?>{
              'uri': 'content://com.example.documents/tree/revoked',
              'name': 'revoked',
              'displayPath': 'SAF: revoked',
              'filesystemOwnerId': 'android-saf-revoked',
            },
          ],
          'forgetSafWorkspace' => null,
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
            'state': 'denied',
            'identity': 'app',
            'path': '/storage/emulated/0/Codex/Workspaces',
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
    final listed = await backend.listWorkspaces();
    expect(listed, hasLength(1));
    final selector = BackendSelector(<Backend>[backend]);
    await tester.pumpWidget(CodexApp(selector: selector));
    await tester.pumpAndSettle();
    expect(find.text('SAF: revoked'), findsOneWidget);
    expect(
      find.text('SAF 授权已失效，请移除后重新添加文件夹'),
      findsOneWidget,
    );
    expect(find.text('新会话'), findsNothing);
    expect(find.text('开始新会话'), findsNothing);
    expect(
      find.byKey(
        const ValueKey(
          'workspace_menu_saf://content://com.example.documents/tree/revoked',
        ),
      ),
      findsOneWidget,
    );
    final workspaceCard = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('SAF: revoked'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(workspaceCard.onTap, isNull);
  });
}
