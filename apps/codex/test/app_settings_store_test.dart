import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/services/app_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.henry.codex/app_preferences');

  test(
    'loads and saves app and Codex defaults through the Android channel',
    () async {
      Map<Object?, Object?>? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'loadAppSettings':
                return <String, String>{
                  'themeMode': 'dark',
                  'locale': 'en',
                  'codexModel': 'gpt-6-sol',
                  'codexEffort': 'high',
                  'codexApprovalPolicy': 'on-failure',
                  'codexSandbox': 'read-only',
                };
              case 'saveAppSettings':
                saved = Map<Object?, Object?>.from(call.arguments as Map);
                return null;
              default:
                throw MissingPluginException();
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final store = AppSettingsStore();
      final loaded = await store.load();
      expect(loaded.themeMode, 'dark');
      expect(loaded.locale, 'en');
      expect(loaded.codexModel, 'gpt-6-sol');
      expect(loaded.codexEffort, 'high');
      expect(loaded.codexApprovalPolicy, 'on-failure');
      expect(loaded.codexSandbox, 'read-only');

      await store.save(
        const AppSettingsSnapshot(
          themeMode: 'light',
          locale: 'zh',
          codexModel: 'gpt-6-luna',
          codexEffort: 'low',
          codexApprovalPolicy: 'never',
          codexSandbox: 'danger-full-access',
        ),
      );
      expect(saved, <String, String?>{
        'themeMode': 'light',
        'locale': 'zh',
        'compatibilityCliVersion': null,
        'codexModel': 'gpt-6-luna',
        'codexEffort': 'low',
        'codexApprovalPolicy': 'never',
        'codexSandbox': 'danger-full-access',
      });
    },
  );

  test('normalizes unknown persisted presentation values', () {
    final settings = AppSettingsSnapshot.fromMap(<String, Object?>{
      'themeMode': 'neon',
      'locale': 'fr',
    });

    expect(settings.themeMode, 'system');
    expect(settings.locale, 'system');
  });

  test('normalizes unknown Codex defaults without discarding valid values', () {
    final settings = AppSettingsSnapshot.fromMap(<String, Object?>{
      'themeMode': 'dark',
      'locale': 'zh',
      'codexModel': ' ',
      'codexEffort': 'ridiculous',
      'codexApprovalPolicy': 'always',
      'codexSandbox': 'root-all',
    });

    expect(settings.codexModel, 'gpt-6-luna');
    expect(settings.codexEffort, 'low');
    expect(settings.codexApprovalPolicy, 'never');
    expect(settings.codexSandbox, 'danger-full-access');
    expect(settings.themeMode, 'dark');
  });

  test('persists and validates the active compatibility CLI version', () {
    const settings = AppSettingsSnapshot(
      themeMode: 'system',
      locale: 'zh',
      compatibilityCliVersion: '0.157.1',
    );

    expect(settings.toMap(), <String, String>{
      'themeMode': 'system',
      'locale': 'zh',
      'compatibilityCliVersion': '0.157.1',
      'codexModel': 'gpt-6-luna',
      'codexEffort': 'low',
      'codexApprovalPolicy': 'never',
      'codexSandbox': 'danger-full-access',
    });
    expect(
      AppSettingsSnapshot.fromMap(settings.toMap()).compatibilityCliVersion,
      '0.157.1',
    );
    expect(
      AppSettingsSnapshot.fromMap(<String, Object?>{
        'themeMode': 'system',
        'locale': 'zh',
        'compatibilityCliVersion': 'latest',
      }).compatibilityCliVersion,
      isNull,
    );
  });
}
