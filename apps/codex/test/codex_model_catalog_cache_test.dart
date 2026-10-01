import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/services/codex_model_catalog_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.henry.codex/app_preferences');

  tearDown(() {
    CodexModelCatalogCache.clearMemoryForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('loads only the catalog cached for the installed CLI version', () async {
    CodexModelCatalogCache.clearMemoryForTesting();
    final encoded = jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'runtime': 'linux-proot',
      'cliVersion': '0.157.1',
      'authGeneration': 3,
      'models': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'gpt-6-luna',
          'displayName': 'GPT-6 Luna',
          'reasoningEfforts': <String>['low', 'high'],
          'hidden': false,
        },
        <String, Object?>{
          'id': 'internal-model',
          'displayName': 'Internal model',
          'reasoningEfforts': <String>['low'],
          'hidden': true,
        },
      ],
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'loadCodexModelCatalogCache');
          return encoded;
        });

    final catalog = await CodexModelCatalogCache().load(
      cliVersion: '0.157.1',
      authGeneration: 3,
    );

    expect(catalog?.modelIds, <String>['gpt-6-luna', 'internal-model']);
    expect(catalog?.models.first.reasoningEfforts, <String>['low', 'high']);
    expect(catalog?.models.last.hidden, isTrue);
  });

  test('rejects a cache from a different CLI version', () async {
    CodexModelCatalogCache.clearMemoryForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'runtime': 'linux-proot',
            'cliVersion': '0.156.0',
            'authGeneration': 3,
            'models': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'old-model',
                'displayName': 'Old model',
                'reasoningEfforts': <String>['low'],
                'hidden': false,
              },
            ],
          });
        });

    final catalog = await CodexModelCatalogCache().load(cliVersion: '0.157.1');

    expect(catalog, isNull);
  });

  test('persists model metadata without provider credentials', () async {
    CodexModelCatalogCache.clearMemoryForTesting();
    String? persisted;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'saveCodexModelCatalogCache');
          persisted =
              (call.arguments as Map<Object?, Object?>)['catalog'] as String;
          return null;
        });
    const catalog = CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: 'gpt-6-sol',
          displayName: 'GPT-6 Sol',
          reasoningEfforts: <String>['low', 'high'],
        ),
      ],
    );

    await CodexModelCatalogCache().save(
      cliVersion: '0.157.1',
      authGeneration: 3,
      catalog: catalog,
    );

    final saved = jsonDecode(persisted!) as Map<String, dynamic>;
    expect(saved['cliVersion'], '0.157.1');
    expect(saved['authGeneration'], 3);
    expect(saved['runtime'], 'linux-proot');
    expect(saved['models'], hasLength(1));
    expect(persisted, isNot(contains('apiKey')));
  });

  test(
    'rejects a catalog cached for a different OpenAI auth generation',
    () async {
      CodexModelCatalogCache.clearMemoryForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return jsonEncode(<String, Object?>{
              'schemaVersion': 2,
              'runtime': 'linux-proot',
              'cliVersion': '0.157.1',
              'authGeneration': 4,
              'models': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'old-account-model',
                  'displayName': 'Old account model',
                  'reasoningEfforts': <String>['low'],
                  'hidden': false,
                },
              ],
            });
          });

      final catalog = await CodexModelCatalogCache().load(
        cliVersion: '0.157.1',
        authGeneration: 5,
      );

      expect(catalog, isNull);
    },
  );

  test(
    'does not read an account-bound cache without an auth generation',
    () async {
      CodexModelCatalogCache.clearMemoryForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return jsonEncode(<String, Object?>{
              'schemaVersion': 2,
              'runtime': 'linux-proot',
              'cliVersion': '0.157.1',
              'authGeneration': 4,
              'models': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'account-bound-model',
                  'displayName': 'Account bound model',
                  'reasoningEfforts': <String>['low'],
                  'hidden': false,
                },
              ],
            });
          });

      final catalog = await CodexModelCatalogCache().load(
        cliVersion: '0.157.1',
      );

      expect(catalog, isNull);
    },
  );

  test('does not query the platform when the CLI version is unknown', () async {
    CodexModelCatalogCache.clearMemoryForTesting();
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return null;
        });

    final catalog = await CodexModelCatalogCache().load(cliVersion: null);

    expect(catalog, isNull);
    expect(called, isFalse);
  });
}
