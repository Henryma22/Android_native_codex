import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/main.dart';

void main() {
  const channel = MethodChannel('io.henry.codex/native_probe');

  testWidgets('refreshes local capability probes after resume', (tester) async {
    final calls = <String, int>{};
    const historyChannel = MethodChannel('io.henry.codex/session_history');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.update(call.method, (count) => count + 1, ifAbsent: () => 1);
      return switch (call.method) {
        'probeAppHostAccess' => <String, Object?>{
          'state': 'denied',
          'identity': 'app',
          'path': '/storage/emulated/0/Codex/Workspaces',
        },
        'probeCodexRuntime' => <String, Object?>{'state': 'missing'},
        _ => null,
      };
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      historyChannel,
      (_) async => <Object?>[],
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(channel, null)
        ..setMockMethodCallHandler(historyChannel, null);
    });

    await tester.pumpWidget(CodexApp(selector: BackendSelector.development()));
    await tester.pumpAndSettle();
    final initial = Map<String, int>.from(calls);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      calls['probeAppHostAccess'],
      greaterThan(initial['probeAppHostAccess'] ?? 0),
    );
    expect(
      calls['probeCodexRuntime'],
      greaterThan(initial['probeCodexRuntime'] ?? 0),
    );
  });
}
