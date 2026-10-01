import 'dart:convert';

import '../domain/custom_provider.dart';

/// Applies one session's custom Responses provider to its Codex app-server.
///
/// The API key is passed only through the app-server process environment. The
/// Codex configuration override contains the environment-variable name, never
/// the secret itself. For keyed providers, Codex's default KEY/SECRET/TOKEN
/// shell-environment exclusions are enabled so model-run child commands do not
/// inherit this variable. This is not an OS boundary: the key remains in the
/// app-server environment and can be inspected by same-UID/root processes.
/// Each local session owns an app-server process and CODEX_HOME, so this
/// selection does not mutate OpenAI OAuth state or another session.
class CodexProviderLaunchConfiguration {
  CodexProviderLaunchConfiguration._({
    required List<String> configArguments,
    required Map<String, String> environment,
  }) : configArguments = List<String>.unmodifiable(configArguments),
       environment = Map<String, String>.unmodifiable(environment);

  static const providerId = 'android_custom';
  static const androidOpenAiHttpProviderId = 'android_openai_http';
  static const apiKeyEnvironmentVariable =
      'ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY';
  static const modelCatalogEnvironmentVariable =
      'ANDROID_CODEX_CUSTOM_MODEL_CATALOG_JSON';
  static const modelCatalogFileName = 'models.json';

  final List<String> configArguments;
  final Map<String, String> environment;

  /// Uses Codex's standard OpenAI auth/API routing with HTTP/SSE instead of
  /// Responses WebSockets, which are unreliable in some Android PRoot network
  /// configurations. The provider's canonical name preserves the CLI's
  /// first-party ChatGPT backend routing; an unset base URL lets Codex select
  /// the ChatGPT or api.openai.com endpoint from the active login type.
  factory CodexProviderLaunchConfiguration.forAndroidOpenAiHttp() {
    const id = androidOpenAiHttpProviderId;
    final settings = <String, Object?>{
      'model_provider': id,
      'model_providers.$id.name': 'OpenAI',
      'model_providers.$id.wire_api': 'responses',
      'model_providers.$id.requires_openai_auth': true,
      'model_providers.$id.supports_websockets': false,
      'model_providers.$id.supports_standalone_web_search': true,
      'model_providers.$id.env_http_headers.OpenAI-Organization':
          'OPENAI_ORGANIZATION',
      'model_providers.$id.env_http_headers.OpenAI-Project': 'OPENAI_PROJECT',
      // Android host commands such as /system/bin/pm are shell wrappers. Keep
      // the worker's full PATH/environment visible to Codex command
      // execution; the local runtime still controls which variables are
      // injected and keyed provider secrets remain filtered below.
      'shell_environment_policy.inherit': 'all',
    };
    return CodexProviderLaunchConfiguration._(
      configArguments: <String>[
        for (final entry in settings.entries) ...[
          '-c',
          '${entry.key}=${_tomlValue(entry.value)}',
        ],
      ],
      environment: const <String, String>{},
    );
  }

  factory CodexProviderLaunchConfiguration.forProvider(
    CustomProviderConfig provider, {
    required String codexHome,
    required String baseInstructions,
  }) {
    final name = provider.name.trim();
    final model = provider.model.trim();
    final sessionHome = codexHome.trim().replaceFirst(RegExp(r'/+$'), '');
    if (name.isEmpty || model.isEmpty) {
      throw const FormatException('Provider name and model are required.');
    }
    if (baseInstructions.trim().isEmpty) {
      throw const FormatException(
        'The installed Codex CLI did not provide base model instructions.',
      );
    }
    if (!sessionHome.startsWith('/') ||
        sessionHome.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        sessionHome.split('/').any((part) => part == '.' || part == '..')) {
      throw const FormatException(
        'An isolated absolute Codex session home is required for a custom provider.',
      );
    }
    if (name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        model.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException(
        'Provider name and model must not contain control characters.',
      );
    }
    if (provider.apiKey.contains('\u0000')) {
      throw const FormatException('Provider API key contains an invalid byte.');
    }
    final baseUri = provider.responsesBaseUri;
    final modelCatalog = _modelCatalog(
      provider,
      name,
      model,
      baseUri.host,
      baseInstructions,
    );
    final modelCatalogJson = jsonEncode(<String, Object?>{
      'models': <Map<String, Object?>>[modelCatalog],
    });
    if (utf8.encode(modelCatalogJson).length > 64 * 1024) {
      throw const FormatException(
        'The installed Codex model instructions exceed the session catalog size limit.',
      );
    }
    final modelCatalogPath = '$sessionHome/$modelCatalogFileName';

    final settings = <String, Object?>{
      'model_provider': providerId,
      'model': model,
      'model_catalog_json': modelCatalogPath,
      'model_providers.$providerId.name': name,
      'model_providers.$providerId.base_url': baseUri.toString(),
      'model_providers.$providerId.wire_api': 'responses',
      'model_providers.$providerId.requires_openai_auth': false,
      'shell_environment_policy.inherit': 'all',
      if (provider.apiKey.trim().isNotEmpty)
        'model_providers.$providerId.env_key': apiKeyEnvironmentVariable,
      if (provider.apiKey.trim().isNotEmpty)
        'shell_environment_policy.ignore_default_excludes': false,
    };
    final configArguments = <String>[
      for (final entry in settings.entries) ...[
        '-c',
        '${entry.key}=${_tomlValue(entry.value)}',
      ],
    ];
    return CodexProviderLaunchConfiguration._(
      configArguments: configArguments,
      environment: <String, String>{
        if (provider.apiKey.trim().isNotEmpty)
          apiKeyEnvironmentVariable: provider.apiKey,
        modelCatalogEnvironmentVariable: modelCatalogJson,
      },
    );
  }

  static Map<String, Object?> _modelCatalog(
    CustomProviderConfig provider,
    String name,
    String model,
    String host,
    String baseInstructions,
  ) {
    final isDeepSeek = host.toLowerCase() == 'api.deepseek.com';
    final isDeepSeekFlash =
        isDeepSeek && model.toLowerCase() == 'deepseek-flash';
    final isDeepSeekPro =
        isDeepSeek && model.toLowerCase() == 'deepseek-v4-pro';
    final deepSeekEfforts = <String>['low', 'high', 'max'];
    final configuredEfforts = provider.reasoningEfforts
        .map((effort) => effort.trim().toLowerCase())
        .where((effort) => effort.isNotEmpty && effort != 'none')
        .toSet();
    final efforts =
        (isDeepSeek
                ? deepSeekEfforts.where(configuredEfforts.contains)
                : configuredEfforts)
            .toList(growable: false);
    final supportedEfforts = efforts.isEmpty ? const <String>['low'] : efforts;
    final descriptor = <String, Object?>{
      'slug': model,
      // Codex 0.157+ reads the instruction template from the structured
      // ModelInfo.model_messages field. Keep the legacy flat field as well so
      // older CLI overlays can consume the same per-session catalog.
      'model_messages': <String, Object?>{
        'instructions_template': baseInstructions,
      },
      'base_instructions': baseInstructions,
      'display_name': name,
      'description': 'User-configured Responses API model.',
      'prefer_websockets': false,
      'apply_patch_tool_type': 'freeform',
      'input_modalities': isDeepSeekFlash
          ? const <String>['text', 'image']
          : const <String>['text'],
      'supports_image_detail_original': isDeepSeekFlash,
      'supports_parallel_tool_calls': true,
      'default_reasoning_level': supportedEfforts.contains('low')
          ? 'low'
          : supportedEfforts.first,
      'supported_reasoning_levels': <Map<String, String>>[
        for (final effort in supportedEfforts)
          <String, String>{
            'effort': effort,
            'description': switch (effort) {
              'low' => 'Fast responses with lighter reasoning.',
              'high' => 'Deeper reasoning for complex tasks.',
              'max' => 'Maximum reasoning depth.',
              _ => 'Provider-supported reasoning level.',
            },
          },
      ],
      'shell_type': 'shell_command',
      'visibility': 'list',
      'supported_in_api': true,
      'priority': 1,
      'experimental_supported_tools': const <String>[],
      'support_verbosity': false,
      'truncation_policy': const <String, Object>{
        'mode': 'tokens',
        'limit': 10000,
      },
      'supports_search_tool': isDeepSeekFlash,
      'use_responses_lite': false,
      'include_skills_usage_instructions': false,
    };
    if (isDeepSeekFlash || isDeepSeekPro) {
      descriptor.addAll(<String, Object?>{
        'support_verbosity': true,
        'default_verbosity': 'low',
        'web_search_tool_type': 'text',
        'multi_agent_version': 'v2',
        'context_window': 1048576,
        'max_context_window': 1048576,
        'effective_context_window_percent': 95,
        'comp_hash': '3000',
        'reasoning_summary_format': 'experimental',
        'default_reasoning_summary': 'none',
        'minimal_client_version': '0.144.0',
      });
    }
    return descriptor;
  }

  /// Inserts provider overrides before the app-server subcommand.
  List<String> applyTo(List<String> argv) {
    final appServerIndex = argv.indexOf('app-server');
    if (appServerIndex < 1) {
      throw const FormatException(
        'A Codex app-server command is required for a custom provider.',
      );
    }
    return <String>[...argv]..insertAll(appServerIndex, configArguments);
  }

  static String _tomlValue(Object? value) => switch (value) {
    final String string => jsonEncode(string),
    final bool boolean => boolean.toString(),
    _ => throw ArgumentError.value(value, 'value', 'Unsupported TOML value.'),
  };
}
