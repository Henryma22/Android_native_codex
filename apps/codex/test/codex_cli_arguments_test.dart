import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_cli_arguments.dart';

void main() {
  group('tokenizeCodexCommand', () {
    test('preserves quoted whitespace and empty arguments', () {
      expect(
        tokenizeCodexCommand(
          r'plugin add "repo name@local" --config "" --label '
          "'project tools'",
        ),
        <String>[
          'plugin',
          'add',
          'repo name@local',
          '--config',
          '',
          '--label',
          'project tools',
        ],
      );
    });

    test('supports escaped separators and never evaluates shell syntax', () {
      expect(
        tokenizeCodexCommand(r'mcp add --name local\ server --exec "$(id)"'),
        <String>['mcp', 'add', '--name', 'local server', '--exec', r'$(id)'],
      );
    });

    test('concatenates adjacent quoted and unquoted segments', () {
      expect(tokenizeCodexCommand('model set "gpt 6"-luna'), <String>[
        'model',
        'set',
        'gpt 6-luna',
      ]);
    });

    test('rejects an unclosed quote before a command can run', () {
      expect(
        () => tokenizeCodexCommand('plugin add "unfinished'),
        throwsFormatException,
      );
    });
  });

  group('codexCliCommandRoute', () {
    test('routes MCP listing to the active session configuration', () {
      expect(
        codexCliCommandRoute(<String>['mcp', 'list']),
        CodexCliCommandRoute.mcpList,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'list', '--json']),
        CodexCliCommandRoute.mcpList,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'get', 'local-server']),
        CodexCliCommandRoute.mcpGet,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'status', '--json']),
        CodexCliCommandRoute.mcpStatus,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'remove', 'local-server']),
        CodexCliCommandRoute.mcpRemove,
      );
      expect(
        codexCliCommandRoute(<String>[
          'mcp',
          'add',
          'local-server',
          '--url',
          'https://example.test/mcp',
        ]),
        CodexCliCommandRoute.mcpAdd,
      );
    });

    test('keeps other read-only diagnostics executable', () {
      expect(
        codexCliCommandRoute(<String>['debug', 'models']),
        CodexCliCommandRoute.execute,
      );
    });

    test('routes account and update actions to their app-owned flows', () {
      expect(
        codexCliCommandRoute(<String>['login']),
        CodexCliCommandRoute.accountSettings,
      );
      expect(
        codexCliCommandRoute(<String>['logout']),
        CodexCliCommandRoute.accountSettings,
      );
      expect(
        codexCliCommandRoute(<String>['update']),
        CodexCliCommandRoute.updaterSettings,
      );
    });

    test(
      'does not route CLI session commands into the isolated operation home',
      () {
        expect(
          codexCliCommandRoute(<String>['fork', '--last']),
          CodexCliCommandRoute.appSessionUi,
        );
        expect(
          codexCliCommandRoute(<String>['resume', '--last']),
          CodexCliCommandRoute.appSessionUi,
        );
      },
    );

    test('routes MCP removal to the active session config writer', () {
      expect(
        codexCliCommandRoute(<String>['mcp', 'remove', 'local']),
        CodexCliCommandRoute.mcpRemove,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'add', 'local']),
        CodexCliCommandRoute.mcpAdd,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'login', 'local']),
        CodexCliCommandRoute.mcpAuthentication,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'logout', 'local']),
        CodexCliCommandRoute.mcpAuthentication,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'marketplace', 'upgrade']),
        CodexCliCommandRoute.pluginConfiguration,
      );
      expect(
        codexCliCommandRoute(<String>['mcp', 'add', '--help']),
        CodexCliCommandRoute.execute,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'list']),
        CodexCliCommandRoute.pluginList,
      );
      expect(
        codexCliCommandRoute(<String>['thread', 'list']),
        CodexCliCommandRoute.threadList,
      );
    });
  });

  group('Codex plugin command parsing', () {
    test('routes plugin listing and marketplace operations', () {
      expect(
        codexCliCommandRoute(<String>['plugin', 'list', '--json']),
        CodexCliCommandRoute.pluginList,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'marketplace', 'list']),
        CodexCliCommandRoute.pluginMarketplaceList,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'add', 'formatter@local']),
        CodexCliCommandRoute.pluginConfiguration,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'enable', 'formatter@local']),
        CodexCliCommandRoute.pluginConfiguration,
      );
      expect(
        codexCliCommandRoute(<String>['plugin', 'disable', 'formatter@local']),
        CodexCliCommandRoute.pluginConfiguration,
      );
      expect(
        codexCliCommandRoute(<String>[
          'plugin',
          'marketplace',
          'upgrade',
          'local',
        ]),
        CodexCliCommandRoute.pluginConfiguration,
      );
    });

    test('parses plugin and marketplace mutations', () {
      final list = CodexPluginListRequest.parse(<String>[
        'plugin',
        'list',
        '--marketplace',
        'local',
        '--available',
        '--json',
      ]);
      expect(list.marketplaceName, 'local');
      expect(list.available, isTrue);
      expect(list.jsonOutput, isTrue);

      final install = CodexPluginInstallRequest.parse(<String>[
        'plugin',
        'add',
        'formatter@local',
        '--json',
      ]);
      expect(install.pluginName, 'formatter');
      expect(install.marketplaceName, 'local');
      expect(install.jsonOutput, isTrue);

      final remove = CodexPluginRemoveRequest.parse(<String>[
        'plugin',
        'remove',
        'formatter@local',
      ]);
      expect(remove.pluginId, 'formatter@local');
      expect(
        CodexPluginRemoveRequest.parse(<String>[
          'plugin',
          'remove',
          'formatter',
          '--marketplace',
          'local',
        ]).pluginId,
        'formatter@local',
      );

      final enable = CodexPluginToggleRequest.parse(<String>[
        'plugin',
        'enable',
        'formatter@local',
        '--json',
      ], enabled: true);
      expect(enable.pluginId, 'formatter@local');
      expect(enable.enabled, isTrue);
      expect(enable.jsonOutput, isTrue);

      final disable = CodexPluginToggleRequest.parse(<String>[
        'plugin',
        'disable',
        'formatter',
        '--marketplace',
        'local',
      ], enabled: false);
      expect(disable.pluginId, 'formatter@local');
      expect(disable.enabled, isFalse);

      final addMarketplace = CodexPluginMarketplaceAddRequest.parse(<String>[
        'plugin',
        'marketplace',
        'add',
        'owner/repo',
        '--ref',
        'main',
        '--sparse',
        'plugins/formatter',
        '--json',
      ]);
      expect(addMarketplace.source, 'owner/repo');
      expect(addMarketplace.refName, 'main');
      expect(addMarketplace.sparsePaths, <String>['plugins/formatter']);
      expect(addMarketplace.jsonOutput, isTrue);

      final removeMarketplace = CodexPluginMarketplaceRemoveRequest.parse(
        <String>['plugin', 'marketplace', 'remove', 'local', '--json'],
      );
      expect(removeMarketplace.marketplaceName, 'local');
      expect(removeMarketplace.jsonOutput, isTrue);

      final upgrade = CodexPluginMarketplaceUpgradeRequest.parse(<String>[
        'plugin',
        'marketplace',
        'upgrade',
      ]);
      expect(upgrade.marketplaceName, isNull);
      expect(upgrade.jsonOutput, isFalse);
    });

    test('rejects ambiguous or incomplete plugin mutations', () {
      expect(
        () => CodexPluginInstallRequest.parse(<String>[
          'plugin',
          'add',
          'formatter',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginInstallRequest.parse(<String>[
          'plugin',
          'add',
          'formatter@local',
          '--marketplace',
          'other',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginMarketplaceRemoveRequest.parse(<String>[
          'plugin',
          'marketplace',
          'remove',
          '--json',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginMarketplaceAddRequest.parse(<String>[
          'plugin',
          'marketplace',
          'add',
          'owner/repo',
          '--sparse',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginListRequest.parse(<String>[
          'plugin',
          'list',
          '--available',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginRemoveRequest.parse(<String>[
          'plugin',
          'remove',
          'formatter@local',
          '--marketplace',
          'other',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexPluginToggleRequest.parse(<String>[
          'plugin',
          'enable',
          'formatter',
        ], enabled: true),
        throwsFormatException,
      );
    });
  });

  group('Codex thread list command parsing', () {
    test('accepts the default list without options', () {
      final request = CodexThreadListRequest.parse(<String>['thread', 'list']);
      expect(request.archived, isFalse);
      expect(request.searchTerm, isNull);
      expect(request.jsonOutput, isFalse);
    });

    test('parses archived, search, and JSON options', () {
      final request = CodexThreadListRequest.parse(<String>[
        'thread',
        'list',
        '--archived',
        '--search',
        'runtime fix',
        '--json',
      ]);
      expect(request.archived, isTrue);
      expect(request.searchTerm, 'runtime fix');
      expect(request.jsonOutput, isTrue);
    });

    test('rejects an incomplete or unknown thread list option', () {
      expect(
        () => CodexThreadListRequest.parse(<String>[
          'thread',
          'list',
          '--search',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexThreadListRequest.parse(<String>[
          'thread',
          'list',
          '--unsupported',
        ]),
        throwsFormatException,
      );
    });
  });

  group('CodexMcpLoginRequest', () {
    test('parses a server name without accepting extra CLI flags', () {
      expect(
        CodexMcpLoginRequest.parse(<String>['mcp', 'login', 'linear']).name,
        'linear',
      );
      expect(
        () => CodexMcpLoginRequest.parse(<String>[
          'mcp',
          'login',
          'linear',
          '--scopes',
          'read',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexMcpLoginRequest.parse(<String>['mcp', 'login', '\n']),
        throwsFormatException,
      );
    });
  });

  group('CodexMcpLogoutRequest', () {
    test('parses a server name and rejects extra CLI flags', () {
      expect(
        CodexMcpLogoutRequest.parse(<String>['mcp', 'logout', 'linear']).name,
        'linear',
      );
      expect(
        () => CodexMcpLogoutRequest.parse(<String>[
          'mcp',
          'logout',
          'linear',
          '--json',
        ]),
        throwsFormatException,
      );
      expect(
        () => CodexMcpLogoutRequest.parse(<String>['mcp', 'logout', '\n']),
        throwsFormatException,
      );
    });
  });

  group('CodexMcpAddRequest', () {
    test('parses stdio command, args, and repeated environment values', () {
      final request = CodexMcpAddRequest.parse(<String>[
        'mcp',
        'add',
        'local.server',
        '--env',
        'API_KEY=TEST_SECRET',
        '--',
        'node',
        'server.js',
        '--label',
        'local tools',
      ]);
      expect(request.name, 'local.server');
      expect(request.config, <String, Object?>{
        'command': 'node',
        'args': <String>['server.js', '--label', 'local tools'],
        'env': <String, String>{'API_KEY': 'TEST_SECRET'},
      });
    });

    test(
      'parses streamable HTTP URL with bearer environment variable name',
      () {
        final request = CodexMcpAddRequest.parse(<String>[
          'mcp',
          'add',
          'remote',
          '--url',
          'https://example.test/mcp',
          '--bearer-token-env-var',
          'REMOTE_MCP_TOKEN',
        ]);
        expect(request.config, <String, Object?>{
          'url': 'https://example.test/mcp',
          'bearer_token_env_var': 'REMOTE_MCP_TOKEN',
        });
      },
    );

    test(
      'rejects invalid URLs, unsupported options, and duplicate env keys',
      () {
        expect(
          () => CodexMcpAddRequest.parse(<String>[
            'mcp',
            'add',
            'remote',
            '--url',
            'file:///etc/passwd',
          ]),
          throwsFormatException,
        );
        expect(
          () => CodexMcpAddRequest.parse(<String>[
            'mcp',
            'add',
            'remote',
            '--url',
            'https://user:pass@example.test/mcp',
          ]),
          throwsFormatException,
        );
        expect(
          () => CodexMcpAddRequest.parse(<String>[
            'mcp',
            'add',
            'local',
            '--env',
            'A=1',
            '--env',
            'A=2',
            '--',
            'node',
          ]),
          throwsFormatException,
        );
      },
    );
  });
}
