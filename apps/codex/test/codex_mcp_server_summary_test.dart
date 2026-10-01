import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_mcp_server_summary.dart';

void main() {
  test('summarizes MCP transports without retaining secret config values', () {
    const secrets = <String>[
      'URL_PASSWORD_SECRET',
      'QUERY_TOKEN_SECRET',
      'HEADER_TOKEN_SECRET',
      'ARGUMENT_TOKEN_SECRET',
      'ENV_VALUE_SECRET',
    ];
    final servers = CodexMcpServerSummary.parse(<String, Object?>{
      'remote': <String, Object?>{
        'enabled': true,
        'url':
            'https://user:URL_PASSWORD_SECRET@mcp.example.test/v1'
            '?token=QUERY_TOKEN_SECRET#private',
        'bearer_token_env_var': 'REMOTE_TOKEN',
        'http_headers': <String, String>{
          'Authorization': 'HEADER_TOKEN_SECRET',
        },
      },
      'local': <String, Object?>{
        'enabled': false,
        'command': '/usr/bin/mcp-server',
        'args': <String>['--token', 'ARGUMENT_TOKEN_SECRET'],
        'env': <String, String>{'MCP_TOKEN': 'ENV_VALUE_SECRET'},
      },
    });

    expect(servers.map((server) => server.name), <String>['local', 'remote']);
    final output = servers
        .map((server) => server.displayLine(chinese: false))
        .join('\n');
    final jsonOutput = servers
        .map((server) => jsonEncode(server.toSafeJsonMap()))
        .join('\n');
    expect(output, contains('local · disabled · stdio · mcp-server · 2 args'));
    expect(
      output,
      contains('remote · enabled · HTTP · https://mcp.example.test'),
    );
    for (final secret in secrets) {
      expect(output, isNot(contains(secret)));
      expect(jsonOutput, isNot(contains(secret)));
    }
  });

  test('treats absent server config as an empty list', () {
    expect(CodexMcpServerSummary.parse(null), isEmpty);
  });

  test('rejects malformed top-level server config', () {
    expect(
      () => CodexMcpServerSummary.parse(<String>['not', 'a', 'map']),
      throwsFormatException,
    );
  });

  test(
    'summarizes live MCP health without exposing tools or server errors',
    () {
      const privateError = 'PRIVATE_MCP_ERROR_AND_TOKEN';
      final statuses = CodexMcpServerStatusSummary.parse(<Object?>[
        <String, Object?>{
          'name': 'remote-mcp',
          'runtimeStatus': 'authenticationRequired',
          'authStatus': 'notLoggedIn',
          'tools': <String, Object?>{'private_tool_name': <String, Object?>{}},
          'toolsError': privateError,
          'serverCapabilities': <String, Object?>{'private': privateError},
        },
      ]);

      expect(statuses.single.toolCount, 1);
      expect(statuses.single.hasToolsError, isTrue);
      expect(
        statuses.single.displayLine(chinese: false),
        'remote-mcp · authentication required · not logged in · 1 tools · tool discovery error',
      );
      final safeJson = jsonEncode(statuses.single.toSafeJsonMap());
      expect(safeJson, contains('authenticationRequired'));
      expect(safeJson, isNot(contains(privateError)));
      expect(safeJson, isNot(contains('private_tool_name')));
    },
  );

  test('rejects malformed live MCP status data', () {
    expect(
      () => CodexMcpServerStatusSummary.parse(<String, Object?>{}),
      throwsFormatException,
    );
    expect(
      () => CodexMcpServerStatusSummary.parse(<Object?>[
        <String, Object?>{'runtimeStatus': 'connected'},
      ]),
      throwsFormatException,
    );
  });
}
