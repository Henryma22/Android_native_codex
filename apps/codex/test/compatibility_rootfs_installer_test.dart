import 'package:codex/services/compatibility_rootfs_installer.dart';
import 'package:codex/backends/compatibility/linux_compatibility_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/linux-compatibility-rootfs');
  const installer = CompatibilityRootfsInstaller(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns false when the user cancels the SAF folder picker', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await installer.pickAndInstall(), isNull);
  });

  test('accepts only a device-verified installation result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <String, Object?>{'state': 'verified'},
        );

    expect(
      (await installer.pickAndInstall())?.state,
      CompatibilityRuntimeState.verified,
    );
  });

  test(
    'surfaces a failed native install instead of reporting success',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{'state': 'failed'},
          );

      await expectLater(
        installer.pickAndInstall(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
