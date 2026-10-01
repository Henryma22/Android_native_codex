import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/core/application/codex_provider_launch_configuration.dart';
import 'package:codex/core/domain/custom_provider.dart';

void main() {
  const codexHome = '/data/local/codex/sessions/test-session';
  const baseInstructions = 'You are the current Codex agent.';
  const provider = CustomProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-flash',
    apiKey: 'secret-test-key',
  );

  test('keeps OpenAI auth and model routing while disabling WebSockets', () {
    final launch = CodexProviderLaunchConfiguration.forAndroidOpenAiHttp();
    final argv = launch.applyTo(<String>[
      'codex',
      'features.respect_system_proxy=true',
      'app-server',
      '--listen',
      'stdio',
    ]);
    final providerId =
        CodexProviderLaunchConfiguration.androidOpenAiHttpProviderId;

    expect(argv, contains('model_provider="$providerId"'));
    expect(argv, contains('model_providers.$providerId.name="OpenAI"'));
    expect(argv, contains('model_providers.$providerId.wire_api="responses"'));
    expect(
      argv,
      contains('model_providers.$providerId.requires_openai_auth=true'),
    );
    expect(
      argv,
      contains('model_providers.$providerId.supports_websockets=false'),
    );
    expect(
      argv,
      contains(
        'model_providers.$providerId.supports_standalone_web_search=true',
      ),
    );
    expect(
      argv,
      contains(
        'model_providers.$providerId.env_http_headers.OpenAI-Organization="OPENAI_ORGANIZATION"',
      ),
    );
    expect(
      argv,
      contains(
        'model_providers.$providerId.env_http_headers.OpenAI-Project="OPENAI_PROJECT"',
      ),
    );
    expect(argv, contains('shell_environment_policy.inherit="all"'));
    expect(
      argv.indexOf('model_provider="$providerId"'),
      lessThan(argv.indexOf('app-server')),
    );
    expect(launch.environment, isEmpty);
    expect(
      argv.join(' '),
      isNot(contains('base_url=')),
      reason: 'Codex selects the first-party endpoint from the login type.',
    );
  });

  test('configures a native Responses provider without exposing its API key', () {
    final launch = CodexProviderLaunchConfiguration.forProvider(
      provider,
      codexHome: codexHome,
      baseInstructions: baseInstructions,
    );
    final argv = launch.applyTo(<String>[
      'codex',
      'app-server',
      '--listen',
      'stdio',
    ]);

    expect(
      argv.indexOf('model_provider="android_custom"'),
      lessThan(argv.indexOf('app-server')),
    );
    expect(argv, contains('model="deepseek-flash"'));
    expect(argv, contains('model_catalog_json="$codexHome/models.json"'));
    expect(
      argv,
      contains(
        'model_providers.android_custom.base_url="https://api.deepseek.com"',
      ),
    );
    expect(
      argv,
      contains('model_providers.android_custom.wire_api="responses"'),
    );
    expect(
      argv,
      contains('model_providers.android_custom.requires_openai_auth=false'),
    );
    expect(
      argv,
      contains(
        'model_providers.android_custom.env_key="${CodexProviderLaunchConfiguration.apiKeyEnvironmentVariable}"',
      ),
    );
    expect(
      argv,
      contains('shell_environment_policy.ignore_default_excludes=false'),
    );
    expect(argv, contains('shell_environment_policy.inherit="all"'));
    expect(argv.join(' '), isNot(contains(provider.apiKey)));
    expect(
      launch.environment[CodexProviderLaunchConfiguration
          .apiKeyEnvironmentVariable],
      provider.apiKey,
    );
    final catalog = jsonDecode(
      launch.environment[CodexProviderLaunchConfiguration
          .modelCatalogEnvironmentVariable]!,
    ) as Map<String, dynamic>;
    final model =
        (catalog['models'] as List<dynamic>).single as Map<String, dynamic>;
    expect(model['slug'], provider.model);
    expect(model['base_instructions'], baseInstructions);
    expect(model['model_messages'], <String, Object?>{
      'instructions_template': baseInstructions,
    });
    expect(model['display_name'], provider.name);
    expect(model['context_window'], 1048576);
    expect(model['input_modalities'], <String>['text', 'image']);
    expect(model['priority'], 1);
    expect(model['experimental_supported_tools'], isEmpty);
    expect(model['supports_search_tool'], isTrue);
    expect(model['support_verbosity'], isTrue);
    expect(model['comp_hash'], '3000');
    expect(model['truncation_policy'], <String, Object>{
      'mode': 'tokens',
      'limit': 10000,
    });
    expect(
      (model['supported_reasoning_levels'] as List<dynamic>)
          .map((level) => (level as Map<String, dynamic>)['effort'])
          .toList(),
      <String>['low'],
    );
    expect(
      launch.environment[CodexProviderLaunchConfiguration
          .modelCatalogEnvironmentVariable],
      isNot(contains(provider.apiKey)),
    );
  });

  test('omits auth environment wiring when the provider has no API key', () {
    final launch = CodexProviderLaunchConfiguration.forProvider(
      provider.copyWith(apiKey: '  '),
      codexHome: codexHome,
      baseInstructions: baseInstructions,
    );

    expect(launch.environment.keys, <String>[
      CodexProviderLaunchConfiguration.modelCatalogEnvironmentVariable,
    ]);
    expect(
      launch.configArguments.join(' '),
      isNot(contains('model_providers.android_custom.env_key')),
    );
    expect(
      launch.configArguments.join(' '),
      isNot(contains('shell_environment_policy.ignore_default_excludes')),
    );
    expect(
      launch.configArguments,
      contains('shell_environment_policy.inherit="all"'),
    );
    expect(
      launch.configArguments,
      contains('model_providers.android_custom.requires_openai_auth=false'),
    );
  });

  test('normalizes previously stored full API endpoint URLs', () {
    final launch = CodexProviderLaunchConfiguration.forProvider(
      provider.copyWith(baseUrl: 'https://api.example/v1/chat/completions'),
      codexHome: codexHome,
      baseInstructions: baseInstructions,
    );

    expect(
      launch.configArguments,
      contains(
        'model_providers.android_custom.base_url="https://api.example/v1"',
      ),
    );
  });

  test('rejects provider URLs with embedded secrets or request parameters', () {
    for (final baseUrl in <String>[
      'https://user:password@example.test/v1',
      'https://api.example/v1?api_key=secret',
      'https://api.example/v1#token',
      'file:///tmp/provider',
    ]) {
      expect(
        () => CodexProviderLaunchConfiguration.forProvider(
          provider.copyWith(baseUrl: baseUrl),
          codexHome: codexHome,
          baseInstructions: baseInstructions,
        ),
        throwsFormatException,
        reason: 'must reject $baseUrl',
      );
    }
  });

  test('rejects invalid provider values and non-app-server commands', () {
    expect(
      () => CodexProviderLaunchConfiguration.forProvider(
        provider.copyWith(baseUrl: 'https://user:password@example.test/v1'),
        codexHome: codexHome,
        baseInstructions: baseInstructions,
      ),
      throwsFormatException,
    );
    expect(
      () => CodexProviderLaunchConfiguration.forProvider(
        provider.copyWith(model: '  '),
        codexHome: codexHome,
        baseInstructions: baseInstructions,
      ),
      throwsFormatException,
    );
    expect(
      () => CodexProviderLaunchConfiguration.forProvider(
        provider,
        codexHome: codexHome,
        baseInstructions: baseInstructions,
      ).applyTo(<String>['codex', 'exec']),
      throwsFormatException,
    );
  });

  test('requires a canonical isolated absolute session home', () {
    for (final home in <String>[
      '',
      'relative/path',
      '/tmp/../shared-codex',
      '/tmp/session\n-injected',
    ]) {
      expect(
        () => CodexProviderLaunchConfiguration.forProvider(
          provider,
          codexHome: home,
          baseInstructions: baseInstructions,
        ),
        throwsFormatException,
        reason: 'must reject $home',
      );
    }
  });

  test(
    'limits DeepSeek metadata to explicitly configured reasoning efforts',
    () {
      final launch = CodexProviderLaunchConfiguration.forProvider(
        provider.copyWith(
          reasoningEfforts: const <String>['low', 'high', 'max'],
        ),
        codexHome: codexHome,
        baseInstructions: baseInstructions,
      );
      final catalog = jsonDecode(
        launch.environment[CodexProviderLaunchConfiguration
            .modelCatalogEnvironmentVariable]!,
      ) as Map<String, dynamic>;
      final model =
          (catalog['models'] as List<dynamic>).single as Map<String, dynamic>;

      expect(
        (model['supported_reasoning_levels'] as List<dynamic>)
            .map((level) => (level as Map<String, dynamic>)['effort'])
            .toList(),
        <String>['low', 'high', 'max'],
      );
    },
  );

  test('gives generic Responses models required Codex metadata defaults', () {
    final launch = CodexProviderLaunchConfiguration.forProvider(
      provider.copyWith(
        baseUrl: 'https://api.example.test/v1',
        model: 'qwen-coder',
        reasoningEfforts: const <String>['low', 'high'],
      ),
      codexHome: codexHome,
      baseInstructions: baseInstructions,
    );
    final catalog = jsonDecode(
      launch.environment[CodexProviderLaunchConfiguration
          .modelCatalogEnvironmentVariable]!,
    ) as Map<String, dynamic>;
    final model =
        (catalog['models'] as List<dynamic>).single as Map<String, dynamic>;

    expect(model['priority'], 1);
    expect(model['experimental_supported_tools'], isEmpty);
    expect(model['support_verbosity'], isFalse);
    expect(model['truncation_policy'], <String, Object>{
      'mode': 'tokens',
      'limit': 10000,
    });
    expect(model['context_window'], isNull);
    expect(model['input_modalities'], <String>['text']);
    expect(
      (model['model_messages']
          as Map<String, Object?>)['instructions_template'],
      baseInstructions,
    );
  });

  test('reads model instructions from the current CLI model catalog', () {
    final instructions = CodexModelCatalogClient.parseBaseInstructions(
      <Object?, Object?>{
        'models': <Object?>[
          <String, Object?>{
            'slug': 'first',
            'base_instructions': 'First template',
          },
          <String, Object?>{
            'slug': 'preferred',
            'model_messages': <String, Object?>{
              'instructions_template': 'Preferred current template',
            },
          },
        ],
      },
      preferredModel: 'preferred',
    );

    expect(instructions, 'Preferred current template');
  });

  test(
    'rejects empty model instructions instead of creating invalid metadata',
    () {
      expect(
        () => CodexProviderLaunchConfiguration.forProvider(
          provider,
          codexHome: codexHome,
          baseInstructions: '  ',
        ),
        throwsFormatException,
      );
    },
  );
}
