import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/compatibility/linux_compatibility_backend.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/services/linux_compatibility_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'parses an available native PRoot probe without enabling execution',
    () async {
      const channel = MethodChannel('test/linux-compatibility-runtime');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probe');
            return <String, Object?>{
              'state': 'available',
              'version': 'PRoot 5.1.107.94',
              'maintenanceCwd': '/data/user/0/io.henry.codex/no_backup',
              'reason': 'rootfs missing',
            };
          });

      final runtime = AndroidCompatibilityRuntimeClient(channel: channel);
      final descriptor = await runtime.probe();

      expect(descriptor.state, CompatibilityRuntimeState.available);
      expect(descriptor.version, 'PRoot 5.1.107.94');
      expect(
        descriptor.maintenanceCwd,
        '/data/user/0/io.henry.codex/no_backup',
      );
      expect(descriptor.usable, isFalse);
      expect(
        () => runtime.execute(
          ExecutionRequest(argv: const <String>['sh'], cwd: '/host'),
        ),
        throwsA(isA<BackendException>()),
      );
    },
  );

  test(
    'keeps a missing probe fail-closed when the native channel is absent',
    () async {
      const channel = MethodChannel('test/linux-compatibility-runtime-missing');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final runtime = AndroidCompatibilityRuntimeClient(channel: channel);
      final descriptor = await runtime.probe();

      expect(descriptor.state, CompatibilityRuntimeState.missing);
      expect(descriptor.usable, isFalse);
      expect(descriptor.reason, contains('not available'));
    },
  );
}
