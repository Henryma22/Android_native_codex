import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_network_probe.dart';
import 'package:codex/core/domain/custom_provider.dart';

void main() {
  test('probes only the selected provider without passing credentials', () {
    const provider = CustomProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      apiKey: 'never-include-this-key',
    );

    final endpoints = CodexNetworkProbe.endpointsFor(provider);
    final arguments = CodexNetworkProbe.argumentsFor(endpoints);

    expect(endpoints, <Uri>[Uri.parse('https://api.deepseek.com')]);
    expect(arguments, contains('https://api.deepseek.com'));
    expect(arguments.join(' '), isNot(contains(provider.apiKey)));
    expect(arguments, contains('-c'));
  });

  test('OpenAI probe checks the ChatGPT Codex, API, and auth origins', () {
    expect(CodexNetworkProbe.endpointsFor(null), <Uri>[
      Uri.parse('https://chatgpt.com/backend-api/codex'),
      Uri.parse('https://api.openai.com/v1/models'),
      Uri.parse('https://auth.openai.com/'),
    ]);
  });

  test('refuses endpoints containing credentials or query data', () {
    for (final endpoint in <Uri>[
      Uri.parse('https://user:secret@example.test/'),
      Uri.parse('https://example.test/?token=secret'),
      Uri.parse('file:///tmp/probe'),
    ]) {
      expect(
        () => CodexNetworkProbe.argumentsFor(<Uri>[endpoint]),
        throwsFormatException,
      );
    }
  });

  test('parses HTTP auth responses as reachability, not network failure', () {
    final output = jsonEncode(<String, Object?>{
      'host': 'api.openai.com',
      'scheme': 'https',
      'status': 401,
      'proxy': <String, Object?>{
        'scheme': 'http',
        'host': '127.0.0.1',
        'port': 7890,
      },
    });

    final result = CodexNetworkProbe.parseOutput(output).single;

    expect(result.host, 'api.openai.com');
    expect(result.secure, isTrue);
    expect(result.statusCode, 401);
    expect(result.reachedServer, isTrue);
    expect(result.proxyHost, '127.0.0.1');
    expect(result.proxyPort, 7890);
    expect(result.proxyScheme, 'http');
  });

  test('parses DNS and TLS failures without retaining raw error text', () {
    final output = <Map<String, Object?>>[
      <String, Object?>{
        'host': 'api.example.test',
        'scheme': 'https',
        'error': 'gaierror',
        'errno': -2,
      },
      <String, Object?>{
        'host': 'auth.example.test',
        'scheme': 'https',
        'error': 'SSLCertVerificationError',
      },
    ].map(jsonEncode).join('\n');

    final results = CodexNetworkProbe.parseOutput(output);

    expect(results, hasLength(2));
    expect(results.first.errorType, 'gaierror');
    expect(results.first.errorNumber, -2);
    expect(results.last.errorType, 'SSLCertVerificationError');
  });
}
