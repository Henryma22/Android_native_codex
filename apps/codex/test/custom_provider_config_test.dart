import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/custom_provider.dart';

void main() {
  const provider = CustomProviderConfig(
    id: 'local-model',
    name: 'Local model',
    baseUrl: 'https://models.example/v1',
    model: 'model-a',
    apiKey: 'test-key',
    reasoningEfforts: <String>['low', 'high'],
  );

  test(
    'configuration equality notices edits even when provider id is stable',
    () {
      expect(provider.hasSameConfigurationAs(provider.copyWith()), isTrue);
      expect(
        provider.hasSameConfigurationAs(provider.copyWith(name: 'Renamed')),
        isFalse,
      );
      expect(
        provider.hasSameConfigurationAs(
          provider.copyWith(baseUrl: 'https://other.example/v1'),
        ),
        isFalse,
      );
      expect(
        provider.hasSameConfigurationAs(provider.copyWith(model: 'model-b')),
        isFalse,
      );
      expect(
        provider.hasSameConfigurationAs(provider.copyWith(apiKey: 'new-key')),
        isFalse,
      );
      expect(
        provider.hasSameConfigurationAs(
          provider.copyWith(reasoningEfforts: <String>['low']),
        ),
        isFalse,
      );
      expect(provider.hasSameConfigurationAs(null), isFalse);
    },
  );

  test('keeps explicit provider effort capabilities and migrates old maps', () {
    expect(
      CustomProviderConfig.fromMap(<Object?, Object?>{
        'id': 'deepseek',
        'name': 'DeepSeek',
        'baseUrl': 'https://api.deepseek.com/v1',
        'model': 'deepseek-flash',
        'apiKey': 'secret',
      }).reasoningEfforts,
      <String>['none', 'low', 'high', 'max'],
    );
    expect(
      CustomProviderConfig.fromMap(<Object?, Object?>{
        'id': 'generic',
        'name': 'Generic',
        'baseUrl': 'https://example.test/v1',
        'model': 'model-a',
        'apiKey': '',
        'reasoningEfforts': <Object?>['low', 'HIGH', 'low'],
      }).reasoningEfforts,
      <String>['low', 'high'],
    );
    expect(
      () => CustomProviderConfig.parseReasoningEfforts(
        'low, invalid value',
        model: 'model-a',
      ),
      throwsFormatException,
    );
  });

  test('uses the documented DeepSeek Responses API root', () {
    for (final baseUrl in <String>[
      'https://api.deepseek.com/v1',
      'https://api.deepseek.com/v1/responses',
      'https://api.deepseek.com/v1/chat/completions',
    ]) {
      expect(
        provider.copyWith(baseUrl: baseUrl).responsesBaseUri.toString(),
        'https://api.deepseek.com',
        reason: 'DeepSeek Codex requests use /responses at the API root.',
      );
    }

    expect(
      provider
          .copyWith(baseUrl: 'https://api.example.com/v1')
          .responsesBaseUri
          .toString(),
      'https://api.example.com/v1',
      reason: 'Other OpenAI-compatible providers keep their configured path.',
    );
  });
}
