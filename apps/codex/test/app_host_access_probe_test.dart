import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:codex/services/app_host_access_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps App UID denial distinct from available access', () {
    const denied = AppHostAccessResult(
      state: 'denied',
      identity: 'app',
      path: '/storage/emulated/0/Codex/Workspaces',
      reason: 'permission denied',
    );
    const available = AppHostAccessResult(
      state: 'available',
      identity: 'app',
      path: '/storage/emulated/0/Codex/Workspaces',
      readable: true,
      writable: false,
      entryCount: 1,
    );

    expect(denied.isAvailable, isFalse);
    expect(denied.label, 'Denied');
    expect(available.isAvailable, isTrue);
    expect(available.label, 'Available');
    expect(available.writable, isFalse);
  });

  test(
    'opens Android storage access settings through the native channel',
    () async {
      const channel = MethodChannel('io.henry.codex/native_probe');
      String? method;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        method = call.method;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await AppHostAccessProbe.openSettings();

      expect(method, 'openHostAccessSettings');
    },
  );
}
