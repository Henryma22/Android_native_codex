import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/backend_selector.dart';
import 'package:codex/core/domain/backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeBackend', () {
    test(
      'exposes a deterministic workspace without claiming verification',
      () async {
        final backend = FakeBackend();

        expect(backend.descriptor.id, 'fake-backend');
        expect(backend.descriptor.capabilities.available, isTrue);
        expect(backend.descriptor.capabilities.verified, isFalse);

        final workspaces = await backend.listWorkspaces();
        expect(workspaces, hasLength(1));
        expect(
          workspaces.single.displayPath,
          '/storage/emulated/0/Codex/Workspaces/demo',
        );
      },
    );

    test('reads fixture content through the backend boundary', () async {
      final backend = FakeBackend();
      final workspace = await backend.openWorkspace(
        (await backend.listWorkspaces()).single,
      );

      final content = await backend.readText(workspace, 'README.md');

      expect(content, contains('Stage 0 UI development'));
    });
  });

  test('selector resolves by stable backend id', () {
    final selector = BackendSelector.development();

    expect(selector.select('fake-backend'), same(selector.backends.single));
    expect(() => selector.select('missing'), throwsA(isA<BackendException>()));
  });

  test(
    'device selector exposes compatibility only as an unverified backend',
    () {
      final selector = BackendSelector.device();
      final compatibility = selector.select('linux-compatibility');

      expect(compatibility.descriptor.kind, BackendKind.linuxCompatibility);
      expect(compatibility.descriptor.capabilities.supported, isTrue);
      expect(compatibility.descriptor.capabilities.available, isFalse);
      expect(compatibility.descriptor.capabilities.verified, isFalse);
    },
  );
}
