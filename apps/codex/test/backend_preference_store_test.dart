import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/services/backend_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.henry.codex/app_preferences');

  test('loads and saves the preferred backend id', () async {
    String? saved;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadPreferredBackendId') return saved;
      if (call.method == 'savePreferredBackendId') {
        saved =
            (call.arguments as Map<Object?, Object?>)['backendId'] as String;
        return null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final store = BackendPreferenceStore();
    expect(await store.loadPreferredBackendId(), isNull);
    await store.savePreferredBackendId('linux-compatibility');
    expect(await store.loadPreferredBackendId(), 'linux-compatibility');
  });

  test('treats a missing native store as a non-fatal no-op', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) {
      throw MissingPluginException();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final store = BackendPreferenceStore();
    expect(await store.loadPreferredBackendId(), isNull);
    await expectLater(store.savePreferredBackendId('local-android'), completes);
  });
}
