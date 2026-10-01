import 'package:codex/services/session_lifecycle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.henry.codex/local_backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'requestSessionNotificationPermission' => true,
        _ => null,
      };
    });
  });

  tearDown(() async {
    // Return the static owner counter to zero for the next test. Each stop is
    // idempotent once all owners have released the shared service.
    await SessionLifecycle.stop();
    await SessionLifecycle.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('stopping one of two sessions keeps the shared service alive', () async {
    await Future.wait(<Future<void>>[
      SessionLifecycle.start(),
      SessionLifecycle.start(),
    ]);
    expect(calls, <String>[
      'requestSessionNotificationPermission',
      'startSessionForeground',
    ]);

    await SessionLifecycle.stop();
    expect(calls, isNot(contains('stopSessionForeground')));

    await SessionLifecycle.stop();
    expect(calls, contains('stopSessionForeground'));
    expect(
      calls.where((method) => method == 'stopSessionForeground'),
      hasLength(1),
    );
  });

  test('a failed foreground start releases its owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'requestSessionNotificationPermission') {
        throw PlatformException(code: 'permission_denied');
      }
      return null;
    });

    await expectLater(
      SessionLifecycle.start(),
      throwsA(isA<PlatformException>()),
    );
    await SessionLifecycle.stop();
    expect(calls, <String>['requestSessionNotificationPermission']);
  });
}
