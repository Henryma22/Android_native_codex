import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_session_client.dart';
import 'package:codex/core/application/codex_cli_arguments.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/core/domain/image_attachment.dart';
import 'package:codex/core/domain/session.dart';
import 'package:codex/backends/fake/fake_backend.dart';

void main() {
  test(
    'generates an isolated Luna low title without changing the thread',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _AutomaticTitleCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        settings: const CodexTurnSettings(
          model: 'gpt-5.6-luna',
          reasoningEffort: 'high',
        ),
        processFactory: (_) => process,
      );
      final events = <CodexSessionEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start();
      expect(
        await client.generateAutomaticThreadTitle('Fix session title handling'),
        'Fix session title handling',
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.threadId, 'thread-1');
      expect(
        events
            .where((event) => event.type == CodexSessionEventType.threadName)
            .map((event) => event.text),
        contains('Fix session title handling'),
      );
      final writes = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .toList(growable: false);
      final titleThread = writes.firstWhere(
        (message) =>
            message['method'] == 'thread/start' &&
            (message['params'] as Map<Object?, Object?>)['ephemeral'] == true,
      );
      final titleParams = titleThread['params'] as Map<Object?, Object?>;
      expect(titleParams['model'], 'gpt-5.6-luna');
      expect(titleParams['approvalPolicy'], 'never');
      expect(titleParams['sandbox'], 'read-only');
      expect(titleParams['threadSource'], 'system');
      expect(titleParams['dynamicTools'], isEmpty);
      expect(
        (titleParams['config']
            as Map<Object?, Object?>)['model_reasoning_effort'],
        'low',
      );
      expect(
        ((titleParams['config'] as Map<Object?, Object?>)['mcp_servers']
            as Map<Object?, Object?>)['fixture-mcp'],
        <String, Object?>{'enabled': false},
      );
      final titleTurn = writes.firstWhere(
        (message) =>
            message['method'] == 'turn/start' &&
            (message['params'] as Map<Object?, Object?>)['threadId'] ==
                'title-thread-1',
      );
      expect((titleTurn['params'] as Map<Object?, Object?>)['effort'], 'low');
      expect(
        writes.any(
          (message) =>
              message['method'] == 'thread/name/set' &&
              (message['params'] as Map<Object?, Object?>)['threadId'] ==
                  'thread-1',
        ),
        isTrue,
      );
      expect(
        writes.any(
          (message) =>
              message['method'] == 'thread/unsubscribe' &&
              (message['params'] as Map<Object?, Object?>)['threadId'] ==
                  'title-thread-1',
        ),
        isTrue,
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test(
    'does not generate a title with a non-Luna conversation model',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        settings: const CodexTurnSettings(model: 'gpt-5.6-sol'),
        processFactory: (_) => process,
      );

      await client.start();
      expect(
        await client.generateAutomaticThreadTitle('Fix title generation'),
        isNull,
      );
      expect(
        process.writes
            .map(jsonDecode)
            .whereType<Map<Object?, Object?>>()
            .any(
              (message) =>
                  message['method'] == 'config/read' ||
                  (message['method'] == 'thread/start' &&
                      (message['params']
                              as Map<Object?, Object?>)['ephemeral'] ==
                          true),
            ),
        isFalse,
      );

      await client.dispose();
    },
  );

  test('uses the configured third-party model for automatic titles', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _AutomaticTitleCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      settings: const CodexTurnSettings(model: 'deepseek-flash'),
      automaticTitleModel: 'deepseek-flash',
      automaticTitleEffort: 'high',
      processFactory: (_) => process,
    );

    await client.start();
    expect(
      await client.generateAutomaticThreadTitle('Summarize the provider fix'),
      'Fix session title handling',
    );

    final writes = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .toList(growable: false);
    final titleThread = writes.firstWhere(
      (message) =>
          message['method'] == 'thread/start' &&
          (message['params'] as Map<Object?, Object?>)['ephemeral'] == true,
    );
    final titleParams = titleThread['params'] as Map<Object?, Object?>;
    expect(titleParams['model'], 'deepseek-flash');
    expect(
      (titleParams['config']
          as Map<Object?, Object?>)['model_reasoning_effort'],
      'high',
    );
    final titleTurn = writes.firstWhere(
      (message) =>
          message['method'] == 'turn/start' &&
          (message['params'] as Map<Object?, Object?>)['threadId'] ==
              'title-thread-1',
    );
    expect((titleTurn['params'] as Map<Object?, Object?>)['effort'], 'high');

    await client.dispose();
  });

  test(
    'reads MCP server summaries from the active app-server session',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        mcpServers: <String, dynamic>{
          'local-mcp': <String, dynamic>{
            'enabled': true,
            'command': '/usr/bin/mcp-server',
            'args': <String>['--token', 'MCP_ARGUMENT_SECRET'],
            'env': <String, String>{'MCP_TOKEN': 'MCP_ENV_SECRET'},
          },
        },
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final servers = await client.readMcpServers();

      expect(servers, hasLength(1));
      expect(servers.single.name, 'local-mcp');
      final reads = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'config/read')
          .toList(growable: false);
      expect(reads, hasLength(1));
      final params = reads.single['params'] as Map<Object?, Object?>;
      expect(params['includeLayers'], isFalse);
      expect(params['cwd'], isA<String>());
      expect(
        servers.single.displayLine(chinese: false),
        isNot(contains('MCP_ARGUMENT_SECRET')),
      );
      expect(
        servers.single.displayLine(chinese: false),
        isNot(contains('MCP_ENV_SECRET')),
      );

      await client.dispose();
    },
  );

  test(
    'adds an MCP server with a versioned session config write and verifies it',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      const config = <String, Object?>{
        'command': 'node',
        'args': <String>['server.js', '--flag'],
      };

      await client.start();
      await client.addMcpServer(
        const CodexMcpAddRequest(name: 'local.server', config: config),
      );

      final messages = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .toList(growable: false);
      expect(
        messages.where((message) => message['method'] == 'config/read'),
        hasLength(2),
      );
      final write = messages.singleWhere(
        (message) => message['method'] == 'config/batchWrite',
      );
      final params = write['params'] as Map<Object?, Object?>;
      final edit = (params['edits'] as List).single as Map<Object?, Object?>;
      expect(edit['keyPath'], 'mcp_servers."local.server"');
      expect(edit['value'], config);
      expect(edit['mergeStrategy'], 'replace');
      expect(params['expectedVersion'], 'user-config-v1');
      expect(params['reloadUserConfig'], isTrue);
      expect(process.mcpServers['local.server'], config);

      await client.dispose();
    },
  );

  test('reads plugin summaries from the active app-server session', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess(
      pluginMarketplaces: <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'local-marketplace',
          'interface': <String, dynamic>{'displayName': 'Local tools'},
          'plugins': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'formatter@local-marketplace',
              'name': 'Formatter',
              'version': '1.2.0',
              'installed': true,
              'enabled': true,
            },
            <String, dynamic>{
              'id': 'reviewer@local-marketplace',
              'name': 'Reviewer',
              'installed': false,
              'enabled': false,
            },
          ],
        },
      ],
      pluginFeaturedIds: const <String>['formatter@local-marketplace'],
    );
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final plugins = await client.readPlugins();
    final marketplaces = await client.readPluginMarketplaces();

    expect(plugins, hasLength(2));
    expect(plugins.first.marketplaceName, 'local-marketplace');
    expect(plugins.first.marketplaceDisplayName, 'Local tools');
    expect(plugins.first.id, 'formatter@local-marketplace');
    expect(plugins.first.version, '1.2.0');
    expect(plugins.first.installed, isTrue);
    expect(plugins.first.featured, isTrue);
    expect(plugins.last.installed, isFalse);
    expect(plugins.last.enabled, isFalse);
    expect(marketplaces, hasLength(1));
    expect(marketplaces.single.name, 'local-marketplace');
    expect(marketplaces.single.displayName, 'Local tools');
    expect(marketplaces.single.pluginCount, 2);

    final requests = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .where((message) => message['method'] == 'plugin/list')
        .toList(growable: false);
    expect(requests, hasLength(2));
    final params = requests.first['params'] as Map<Object?, Object?>;
    expect(params['cwds'], isA<List>());
    expect(plugins.first.toSafeJsonMap().keys, isNot(contains('path')));

    await client.dispose();
  });

  test(
    'falls back to the base plugin-list request on an older server',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        rejectPluginListParams: true,
        pluginMarketplaces: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'legacy-marketplace',
            'plugins': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'legacy@legacy-marketplace',
                'name': 'Legacy',
                'installed': true,
              },
            ],
          },
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final plugins = await client.readPlugins(forceRefetch: true);

      expect(plugins.single.id, 'legacy@legacy-marketplace');
      final requests = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'plugin/list')
          .toList(growable: false);
      expect(requests, hasLength(2));
      expect(
        (requests.first['params'] as Map<Object?, Object?>).keys,
        containsAll(<String>['cwds', 'forceRefetch']),
      );
      expect(requests.last['params'], isNull);

      await client.dispose();
    },
  );

  test(
    'reads paginated thread summaries from the active app-server session',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        threadListPages: <List<Map<String, dynamic>>>[
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'thread-older',
              'sessionId': 'session-older',
              'preview': 'Older thread',
              'cwd': '/workspace/project',
              'modelProvider': 'openai',
              'status': <String, String>{'type': 'idle'},
              'createdAt': 100,
              'updatedAt': 100,
            },
          ],
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'thread-active',
              'name': 'Current thread',
              'preview': 'Current prompt',
              'cwd': '/workspace/project',
              'model': 'gpt-5.6-luna',
              'modelProvider': 'openai',
              'reasoningEffort': 'low',
              'status': <String, dynamic>{
                'type': 'active',
                'activeFlags': <String>['waitingOnApproval'],
              },
              'createdAt': 200,
              'updatedAt': 300,
            },
          ],
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final threads = await client.readThreads(
        archived: true,
        searchTerm: 'current',
      );

      expect(threads.map((thread) => thread.id), <String>[
        'thread-older',
        'thread-active',
      ]);
      final listRequests = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'thread/list')
          .toList(growable: false);
      expect(listRequests, hasLength(2));
      final firstParams = listRequests.first['params'] as Map<Object?, Object?>;
      expect(firstParams['archived'], isTrue);
      expect(firstParams['searchTerm'], 'current');
      expect(firstParams['sortKey'], 'updated_at');
      expect(firstParams['sortDirection'], 'desc');
      expect(firstParams['useStateDbOnly'], isTrue);
      expect(firstParams['cwd'], isA<String>());
      expect(
        (listRequests[1]['params'] as Map<Object?, Object?>)['cursor'],
        'thread-page-2',
      );

      await client.dispose();
    },
  );

  test(
    'falls back to core thread-list params on an older app-server',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        rejectExtendedThreadListParams: true,
        threadListPages: <List<Map<String, dynamic>>>[
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'thread-old',
              'preview': 'unrelated history',
              'cwd': '/workspace/project',
            },
          ],
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'thread-match',
              'preview': 'runtime compatibility',
              'cwd': '/workspace/project',
            },
          ],
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final threads = await client.readThreads(searchTerm: 'compatibility');

      expect(threads.map((thread) => thread.id), <String>['thread-match']);
      final listRequests = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'thread/list')
          .toList(growable: false);
      expect(listRequests, hasLength(3));
      final richParams = listRequests.first['params'] as Map<Object?, Object?>;
      expect(richParams['useStateDbOnly'], isTrue);
      final fallbackParams = listRequests[1]['params'] as Map<Object?, Object?>;
      expect(fallbackParams, <String, dynamic>{
        'archived': false,
        'limit': 100,
      });
      expect(
        (listRequests[2]['params'] as Map<Object?, Object?>)['cursor'],
        'thread-page-2',
      );
      expect(
        (listRequests[2]['params'] as Map<Object?, Object?>).keys,
        containsAll(<String>['archived', 'limit', 'cursor']),
      );

      await client.dispose();
    },
  );

  test(
    'runs plugin and marketplace mutations through the active app-server',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        pluginMarketplaces: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'local-marketplace',
            'path': '/private/local-marketplace',
            'plugins': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'formatter'},
            ],
          },
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final installResponse = await client.installPlugin(
        const CodexPluginInstallRequest(
          pluginName: 'formatter',
          marketplaceName: 'local-marketplace',
          jsonOutput: false,
        ),
      );
      expect(installResponse['installed'], isTrue);

      final uninstallResponse = await client.uninstallPlugin(
        'formatter@local-marketplace',
      );
      expect(uninstallResponse['uninstalled'], isTrue);

      final toggleResponse = await client.setPluginEnabled(
        'formatter@local-marketplace',
        false,
      );
      expect(toggleResponse['status'], 'ok');

      final addResponse = await client.addPluginMarketplace(
        const CodexPluginMarketplaceAddRequest(
          source: 'owner/repo',
          refName: 'main',
          sparsePaths: <String>['plugins/formatter'],
          jsonOutput: false,
        ),
      );
      expect(addResponse['marketplaceName'], 'owner-repo');

      final removeResponse = await client.removePluginMarketplace('owner-repo');
      expect(removeResponse['removed'], isTrue);

      final upgradeResponse = await client.upgradePluginMarketplace(null);
      expect(upgradeResponse['upgradedRoots'], isA<List>());

      final messages = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .toList(growable: false);
      final install = messages.singleWhere(
        (message) => message['method'] == 'plugin/install',
      );
      expect(install['params'], <String, dynamic>{
        'pluginName': 'formatter',
        'marketplacePath': '/private/local-marketplace',
      });
      expect(
        messages.singleWhere(
          (message) => message['method'] == 'plugin/uninstall',
        )['params'],
        <String, String>{'pluginId': 'formatter@local-marketplace'},
      );
      expect(
        messages.singleWhere(
          (message) => message['method'] == 'config/value/write',
        )['params'],
        <String, dynamic>{
          'keyPath': 'plugins.formatter@local-marketplace.enabled',
          'value': false,
          'mergeStrategy': 'replace',
          'filePath': null,
          'expectedVersion': null,
        },
      );
      expect(
        messages.singleWhere(
          (message) => message['method'] == 'marketplace/add',
        )['params'],
        <String, dynamic>{
          'source': 'owner/repo',
          'refName': 'main',
          'sparsePaths': <String>['plugins/formatter'],
        },
      );
      expect(
        messages.singleWhere(
          (message) => message['method'] == 'marketplace/remove',
        )['params'],
        <String, String>{'marketplaceName': 'owner-repo'},
      );
      expect(
        messages.singleWhere(
          (message) => message['method'] == 'marketplace/upgrade',
        )['params'],
        isEmpty,
      );

      await client.dispose();
    },
  );

  test(
    'does not overwrite an MCP server owned by another config layer',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        mcpServers: <String, dynamic>{
          'existing': <String, dynamic>{'url': 'https://example.test/mcp'},
        },
        mcpLayers: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': <String, dynamic>{'type': 'user', 'profile': null},
            'version': 'user-config-v1',
            'config': <String, dynamic>{'mcp_servers': <String, dynamic>{}},
          },
          <String, dynamic>{
            'name': <String, dynamic>{'type': 'project'},
            'version': 'project-config-v1',
            'config': <String, dynamic>{
              'mcp_servers': <String, dynamic>{
                'existing': <String, dynamic>{
                  'url': 'https://example.test/mcp',
                },
              },
            },
          },
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      await expectLater(
        client.addMcpServer(
          const CodexMcpAddRequest(
            name: 'existing',
            config: <String, Object?>{'command': 'node'},
          ),
        ),
        throwsA(
          isA<CodexSessionException>().having(
            (error) => error.message,
            'message',
            contains('another config layer'),
          ),
        ),
      );
      expect(
        process.writes
            .map(jsonDecode)
            .whereType<Map<Object?, Object?>>()
            .where((message) => message['method'] == 'config/batchWrite'),
        isEmpty,
      );

      await client.dispose();
    },
  );

  test('reports an MCP add as unverified when the effective config does not change', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess(applyMcpRemoval: false);
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    await expectLater(
      client.addMcpServer(
        const CodexMcpAddRequest(
          name: 'unverified',
          config: <String, Object?>{'command': 'node'},
        ),
      ),
      throwsA(
        isA<CodexSessionException>().having(
          (error) => error.message,
          'message',
          contains('could not be verified'),
        ),
      ),
    );

    await client.dispose();
  });

  test(
    'removes one MCP server with a versioned, key-safe config edit',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        mcpServers: <String, dynamic>{
          'local.server': <String, dynamic>{
            'command': '/usr/bin/mcp-server',
            'env': <String, String>{'TOKEN': 'MCP_REMOVE_SECRET'},
          },
        },
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      await client.removeMcpServer('local.server');

      final messages = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .toList(growable: false);
      final reads = messages
          .where((message) => message['method'] == 'config/read')
          .toList(growable: false);
      expect(reads, hasLength(2));
      expect(
        (reads.first['params'] as Map<Object?, Object?>)['includeLayers'],
        isTrue,
      );
      expect(
        (reads.last['params'] as Map<Object?, Object?>)['includeLayers'],
        isFalse,
      );

      final write = messages.singleWhere(
        (message) => message['method'] == 'config/batchWrite',
      );
      final params = write['params'] as Map<Object?, Object?>;
      final edit = (params['edits'] as List).single as Map<Object?, Object?>;
      expect(edit['keyPath'], 'mcp_servers."local.server"');
      expect(edit['value'], isNull);
      expect(edit['mergeStrategy'], 'replace');
      expect(params['filePath'], isNull);
      expect(params['expectedVersion'], 'user-config-v1');
      expect(params['reloadUserConfig'], isTrue);
      expect(process.mcpServers, isNot(contains('local.server')));
      expect(process.writes.join('\n'), isNot(contains('MCP_REMOVE_SECRET')));

      await client.dispose();
    },
  );

  test(
    'does not remove a server also defined by a higher config layer',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final server = <String, dynamic>{'command': 'mcp-server'};
      final process = _ScriptedCodexProcess(
        mcpServers: <String, dynamic>{'shared': server},
        mcpLayers: <Map<String, dynamic>>[
          <String, dynamic>{
            'name': <String, dynamic>{
              'type': 'user',
              'file': '/codex/config.toml',
              'profile': null,
            },
            'version': 'user-config-v1',
            'config': <String, dynamic>{
              'mcp_servers': <String, dynamic>{'shared': server},
            },
          },
          <String, dynamic>{
            'name': <String, dynamic>{
              'type': 'project',
              'dotCodexFolder': '/workspace/.codex',
            },
            'version': 'project-config-v1',
            'config': <String, dynamic>{
              'mcp_servers': <String, dynamic>{'shared': server},
            },
          },
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      await expectLater(
        client.removeMcpServer('shared'),
        throwsA(
          isA<CodexSessionException>().having(
            (error) => error.message,
            'message',
            contains('another config layer'),
          ),
        ),
      );
      expect(
        process.writes
            .map(jsonDecode)
            .whereType<Map<Object?, Object?>>()
            .where((message) => message['method'] == 'config/batchWrite'),
        isEmpty,
      );

      await client.dispose();
    },
  );

  test(
    'reports a write as unverified when effective config still has the server',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        mcpServers: <String, dynamic>{
          'local': <String, dynamic>{'command': 'mcp'},
        },
        applyMcpRemoval: false,
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      await expectLater(
        client.removeMcpServer('local'),
        throwsA(
          isA<CodexSessionException>().having(
            (error) => error.message,
            'message',
            contains('remains in the effective config'),
          ),
        ),
      );

      await client.dispose();
    },
  );

  test(
    'reads paginated live MCP status without retaining server details',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      const privateError = 'PRIVATE_MCP_ERROR_AND_TOKEN';
      final process = _ScriptedCodexProcess(
        mcpStatusPages: <List<Map<String, dynamic>>>[
          <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'local-mcp',
              'runtimeStatus': 'connected',
              'authStatus': 'bearerToken',
              'tools': <String, dynamic>{'read_file': <String, dynamic>{}},
              'toolsError': privateError,
              'serverCapabilities': <String, dynamic>{
                'sensitive': privateError,
              },
            },
          ],
          <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'remote-mcp',
              'runtimeStatus': 'authenticationRequired',
              'authStatus': 'notLoggedIn',
              'tools': <String, dynamic>{},
            },
          ],
        ],
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final statuses = await client.readMcpServerStatuses();

      expect(statuses, hasLength(2));
      expect(statuses.first.runtimeStatus, 'connected');
      expect(statuses.first.toolCount, 1);
      expect(statuses.first.hasToolsError, isTrue);
      final displayed = statuses
          .map((status) => status.displayLine(chinese: false))
          .join('\n');
      final serialized = jsonEncode(
        statuses.map((status) => status.toSafeJsonMap()).toList(),
      );
      expect(
        displayed,
        contains('local-mcp · connected · bearer token · 1 tools'),
      );
      expect(displayed, isNot(contains(privateError)));
      expect(serialized, isNot(contains(privateError)));

      final requests = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'mcpServerStatus/list')
          .toList(growable: false);
      expect(requests, hasLength(2));
      final firstParams = requests.first['params'] as Map<Object?, Object?>;
      expect(firstParams['threadId'], 'thread-1');
      expect(firstParams['detail'], 'toolsAndAuthOnly');
      expect(firstParams['limit'], 100);
      expect(requests.last['params'], containsPair('cursor', 'mcp-page-2'));

      await client.dispose();
    },
  );

  test(
    'starts MCP OAuth on the active thread and sanitizes completion events',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      final events = <CodexSessionEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start();
      expect(
        await client.beginMcpOAuthLogin('linear'),
        Uri.parse('https://mcp.example.test/authorize?state=fixture'),
      );
      await Future<void>.delayed(Duration.zero);

      final request = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .singleWhere(
            (message) => message['method'] == 'mcpServer/oauth/login',
          );
      expect(request['params'], <String, Object?>{
        'name': 'linear',
        'threadId': 'thread-1',
      });
      final completion = events.singleWhere(
        (event) => event.type == CodexSessionEventType.mcpOAuth,
      );
      expect(completion.params, <String, dynamic>{
        'name': 'linear',
        'success': true,
      });
      expect(completion.threadId, 'thread-1');
      expect(process.writes.join('\n'), isNot(contains('PRIVATE_OAUTH_ERROR')));

      await client.dispose();
      await subscription.cancel();
    },
  );

  test('rejects non-HTTP MCP OAuth authorization URLs', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess(
      mcpOAuthAuthorizationUrl: 'javascript:alert(1)',
    );
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    await expectLater(
      client.beginMcpOAuthLogin('linear'),
      throwsA(
        isA<CodexSessionException>().having(
          (error) => error.message,
          'message',
          contains('invalid MCP authorization URL'),
        ),
      ),
    );

    await client.dispose();
  });

  test('manual rename cancels an in-flight automatic title', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _AutomaticTitleCodexProcess(completeTitle: false);
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final titleFuture = client.generateAutomaticThreadTitle(
      'Generate an automatic title',
    );
    await process.titleTurnStarted.future;
    await Future<void>.delayed(Duration.zero);
    await client.setThreadName('My manual title');

    expect(await titleFuture, isNull);
    final nameRequests = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .where((message) => message['method'] == 'thread/name/set')
        .map((message) => message['params'] as Map<Object?, Object?>)
        .toList(growable: false);
    expect(nameRequests, <Map<Object?, Object?>>[
      <String, Object?>{'threadId': 'thread-1', 'name': 'My manual title'},
    ]);

    await client.dispose();
  });

  test('initializes a thread and streams agent deltas over JSON-RPC', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );
    final events = <CodexSessionEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start();
    expect(client.threadId, 'thread-1');
    final bootstrap = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'thread/start');
    expect(bootstrap['params'], containsPair('skipGitRepoCheck', true));
    expect(bootstrap['params'], containsPair('model', 'gpt-6-luna'));
    final instructions =
        (bootstrap['params'] as Map<Object?, Object?>)['developerInstructions']
            as String;
    expect(instructions, contains('PRoot guest identity'));
    expect(instructions, contains('normal KernelSU profile'));
    expect(instructions, contains('real Android UID 0'));
    expect(instructions, contains('universal privilege broker'));
    expect(instructions, contains('Ordinary resolved absolute paths'));
    expect(
      instructions,
      contains('Ordinary and unclassified Root operations remain direct'),
    );
    expect(instructions, contains('intended change'));
    expect(instructions, contains('belongs to the named session'));
    expect(instructions, contains('per-command prompt'));
    expect(
      instructions,
      contains('complete Android host root bind at `/android`'),
    );
    expect(instructions, contains('not kernel'));
    expect(instructions, contains('NO_NEW_PRIVS'));
    expect(instructions, contains('distinct from Linux'));
    expect(
      (bootstrap['params'] as Map<Object?, Object?>)['config'],
      containsPair('model_reasoning_effort', 'low'),
    );

    await client.sendPrompt('inspect the fixture');
    await Future<void>.delayed(Duration.zero);

    expect(
      events.any(
        (event) =>
            event.type == CodexSessionEventType.assistantDelta &&
            event.text == 'fixture response',
      ),
      isTrue,
    );
    expect(
      events.any(
        (event) =>
            event.type == CodexSessionEventType.status && event.text == 'idle',
      ),
      isTrue,
    );
    expect(process.writes, contains(predicate<String>(_isTurnStart)));
    final turn = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'turn/start');
    expect(turn['params'], containsPair('model', 'gpt-6-luna'));
    expect(turn['params'], containsPair('effort', 'low'));

    await client.dispose();
    await subscription.cancel();
  });

  test(
    'recovers an assistant message delivered only by item completion',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(emitFinalAgentMessageOnly: true);
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      final events = <CodexSessionEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start();
      await client.sendPrompt('completion-only fixture');
      await Future<void>.delayed(Duration.zero);

      expect(
        events.where(
          (event) => event.type == CodexSessionEventType.assistantDelta,
        ),
        hasLength(1),
      );
      expect(
        events
            .singleWhere(
              (event) => event.type == CodexSessionEventType.assistantDelta,
            )
            .text,
        'fixture completion response',
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test(
    'forks a thread and resumes it from the provider rollout path',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess(
        threadPath: '/home/codex/sessions/source/rollouts/source.jsonl',
        forkThreadId: 'thread-forked',
        forkThreadPath: '/home/codex/sessions/source/rollouts/forked.jsonl',
      );
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      expect(
        client.threadPath,
        '/home/codex/sessions/source/rollouts/source.jsonl',
      );

      final fork = await client.forkThread();
      expect(fork.threadId, 'thread-forked');
      expect(
        fork.threadPath,
        '/home/codex/sessions/source/rollouts/forked.jsonl',
      );
      final forkRequest = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'thread/fork');
      expect(forkRequest['params'], containsPair('threadId', 'thread-1'));

      await client.dispose();

      final resumeProcess = _ScriptedCodexProcess(
        threadId: 'thread-forked',
        threadPath: '/home/codex/sessions/forked/rollouts/forked.jsonl',
      );
      final resumedClient = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        resumeThreadId: 'thread-forked',
        resumeThreadPath: '/home/codex/sessions/forked/rollouts/forked.jsonl',
        processFactory: (_) => resumeProcess,
      );

      await resumedClient.start();
      expect(
        resumedClient.threadPath,
        '/home/codex/sessions/forked/rollouts/forked.jsonl',
      );
      final resumeRequest = resumeProcess.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['method'] == 'thread/resume');
      expect(
        resumeRequest['params'],
        containsPair(
          'path',
          '/home/codex/sessions/forked/rollouts/forked.jsonl',
        ),
      );

      await resumedClient.dispose();
    },
  );

  test('emits only the current thread name update', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );
    final events = <CodexSessionEvent>[];
    final subscription = client.events.listen(events.add);
    await client.start();

    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'thread/name/updated',
      'params': <String, dynamic>{
        'threadId': 'another-thread',
        'threadName': 'Do not apply',
      },
    });
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'thread/name/updated',
      'params': <String, dynamic>{
        'threadId': 'thread-1',
        'threadName': '  Generated by Codex  ',
      },
    });
    await Future<void>.delayed(Duration.zero);

    final names = events
        .where((event) => event.type == CodexSessionEventType.threadName)
        .toList(growable: false);
    expect(names, hasLength(1));
    expect(names.single.text, 'Generated by Codex');
    expect(names.single.threadId, 'thread-1');

    await client.dispose();
    await subscription.cancel();
  });

  test('persists a manual name on the current Codex thread', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );
    await client.start();

    await client.setThreadName('  My named session  ');

    final request = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'thread/name/set');
    expect(request['params'], <String, String>{
      'threadId': 'thread-1',
      'name': 'My named session',
    });

    await client.dispose();
  });

  test('does not start a new thread only to rename an empty session', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await expectLater(
      client.setThreadName('My session'),
      throwsA(isA<CodexSessionException>()),
    );
    expect(process.writes, isEmpty);
    await client.dispose();
  });

  test('uses the Codex app-server image input wire shape', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.sendPrompt(
      'inspect this',
      images: <ImageAttachment>[
        ImageAttachment(
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
          mimeType: 'image/png',
        ),
      ],
    );

    final turn = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'turn/start');
    final input = (turn['params'] as Map<Object?, Object?>)['input'] as List;
    expect(input.last, <String, String>{
      'type': 'image',
      'url': 'data:image/png;base64,AQID',
    });
    expect(input.last, isNot(contains('image_url')));

    await client.dispose();
  });

  test('root sessions request global read visibility and honor selected approval policy', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      identity: ExecutionIdentity.root,
      settings: const CodexTurnSettings(
        approvalPolicy: 'on-request',
        sandbox: 'workspace-write',
      ),
      processFactory: (_) => process,
    );

    await client.start();

    final bootstrap = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'thread/start');
    final params = bootstrap['params'] as Map<Object?, Object?>;
    expect(params['sandbox'], 'danger-full-access');
    expect(params['approvalPolicy'], 'on-request');

    await client.sendPrompt('check root approval behavior');
    final turn = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'turn/start');
    expect(
      (turn['params'] as Map<Object?, Object?>)['approvalPolicy'],
      'on-request',
    );
    expect(
      (turn['params'] as Map<Object?, Object?>)['sandboxPolicy'],
      <String, String>{'type': 'dangerFullAccess'},
    );

    await client.dispose();
  });

  test('can start a new process after an explicit stop', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final processes = <_ScriptedCodexProcess>[];
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) {
        final process = _ScriptedCodexProcess();
        processes.add(process);
        return process;
      },
    );

    await client.start();
    await client.stop();
    await client.start();

    expect(processes, hasLength(2));
    expect(client.threadId, 'thread-1');

    await client.dispose();
  });

  test(
    'two session clients keep independent processes alive concurrently',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final processA = _ScriptedCodexProcess(threadId: 'thread-a');
      final processB = _ScriptedCodexProcess(threadId: 'thread-b');
      final clientA = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => processA,
      );
      final clientB = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => processB,
      );

      await Future.wait<void>(<Future<void>>[clientA.start(), clientB.start()]);
      expect(clientA.threadId, 'thread-a');
      expect(clientB.threadId, 'thread-b');
      expect(processA.stopped, isFalse);
      expect(processB.stopped, isFalse);

      await clientA.stop();
      expect(processA.stopped, isTrue);
      expect(processB.stopped, isFalse);

      await clientB.sendPrompt('keep the second session alive');
      expect(processB.writes, contains(predicate<String>(_isTurnStart)));

      await clientA.dispose();
      await clientB.dispose();
    },
  );

  test('resumes an explicitly requested saved thread', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess(threadId: 'thread-restored');
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      resumeThreadId: 'thread-restored',
      processFactory: (_) => process,
    );

    await client.start();

    expect(client.threadId, 'thread-restored');
    final bootstrap = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'thread/resume');
    expect(bootstrap['params'], containsPair('threadId', 'thread-restored'));
    expect(
      (bootstrap['params'] as Map<Object?, Object?>)['developerInstructions'],
      contains('PRoot guest identity'),
    );
    expect(
      process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['method'] == 'thread/start'),
      isEmpty,
    );

    await client.dispose();
  });

  test(
    'surfaces tool approval requests and sends the selected decision',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ApprovalCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final approvalFuture = client.events.firstWhere(
        (event) => event.type == CodexSessionEventType.approval,
      );
      final turn = client.sendPrompt('run the fixture command');
      final approval = await approvalFuture;

      expect(approval.requestId, 'approval-1');
      expect(approval.requestMethod, 'item/commandExecution/requestApproval');
      expect(approval.params?['command'], 'echo fixture');

      await client.respondToRequest(approval.requestId!, <String, dynamic>{
        'decision': 'decline',
      });
      await turn;

      final responses = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where((message) => message['id'] == 'approval-1')
          .toList();
      expect(responses, hasLength(1));
      expect(responses.single['result'], <String, dynamic>{
        'decision': 'decline',
      });

      await client.dispose();
    },
  );

  test('surfaces file-change approval and sends an accept decision', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final approvalFuture = client.events.firstWhere(
      (event) => event.type == CodexSessionEventType.approval,
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'file-change-1',
      'method': 'item/fileChange/requestApproval',
      'params': <String, dynamic>{
        'availableDecisions': <String>['accept', 'decline'],
        'changes': <Map<String, String>>[
          <String, String>{
            'path': 'README.md',
            'proposedContent': '# updated by agent\n',
          },
        ],
      },
    });
    final approval = await approvalFuture;

    expect(approval.requestId, 'file-change-1');
    expect(approval.requestMethod, 'item/fileChange/requestApproval');
    expect(approval.params?['changes'], isA<List<Object?>>());

    await client.respondToApproval(approval, approved: true);

    final response = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'file-change-1');
    expect(response['result'], <String, dynamic>{'decision': 'accept'});

    await client.dispose();
  });

  test(
    'sends acceptForSession only for an advertised approval choice',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );

      await client.start();
      final approvalFuture = client.events.firstWhere(
        (event) => event.type == CodexSessionEventType.approval,
      );
      process._emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'file-change-session-1',
        'method': 'item/fileChange/requestApproval',
        'params': <String, dynamic>{
          'availableDecisions': <String>[
            'accept',
            'acceptForSession',
            'decline',
          ],
          'changes': <Object?>[],
        },
      });
      final approval = await approvalFuture;

      await client.respondToApproval(
        approval,
        approved: true,
        forSession: true,
      );

      final response = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['id'] == 'file-change-session-1');
      expect(response['result'], <String, dynamic>{
        'decision': 'acceptForSession',
      });

      await client.dispose();
    },
  );

  test('rejects a session approval the app-server did not advertise', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final approvalFuture = client.events.firstWhere(
      (event) => event.type == CodexSessionEventType.approval,
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'file-change-session-unavailable',
      'method': 'item/fileChange/requestApproval',
      'params': <String, dynamic>{
        'availableDecisions': <String>['accept', 'decline'],
        'changes': <Object?>[],
      },
    });
    final approval = await approvalFuture;

    await expectLater(
      client.respondToApproval(approval, approved: true, forSession: true),
      throwsA(isA<CodexSessionException>()),
    );
    expect(
      process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .where(
            (message) => message['id'] == 'file-change-session-unavailable',
          ),
      isEmpty,
    );

    await client.dispose();
  });

  test(
    'round-trips an advertised persistent approval rule unchanged',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      const decision = <String, dynamic>{
        'acceptWithExecpolicyAmendment': <String, dynamic>{
          'execpolicy_amendment': <String>['npm', 'test'],
        },
      };

      await client.start();
      final approvalFuture = client.events.firstWhere(
        (event) => event.type == CodexSessionEventType.approval,
      );
      process._emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'command-policy-1',
        'method': 'item/commandExecution/requestApproval',
        'params': <String, dynamic>{
          'availableDecisions': <Object?>['accept', decision, 'cancel'],
        },
      });
      final approval = await approvalFuture;

      await client.respondToApproval(
        approval,
        approved: true,
        decisionOverride: decision,
      );

      final response = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .firstWhere((message) => message['id'] == 'command-policy-1');
      expect(response['result'], <String, dynamic>{'decision': decision});

      await client.dispose();
    },
  );

  test('uses the permissions approval response shape', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final approvalFuture = client.events.firstWhere(
      (event) => event.type == CodexSessionEventType.approval,
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'permissions-1',
      'method': 'item/permissions/requestApproval',
      'params': <String, dynamic>{
        'permissions': <String, dynamic>{
          'fileSystem': <String, dynamic>{
            'write': <String>['README.md'],
          },
        },
      },
    });
    final approval = await approvalFuture;
    await client.respondToApproval(approval, approved: true);

    final response = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'permissions-1');
    expect(response['result'], <String, dynamic>{
      'scope': 'turn',
      'permissions': <String, dynamic>{
        'fileSystem': <String, dynamic>{
          'write': <String>['README.md'],
        },
      },
    });

    final sessionApprovalFuture = client.events.firstWhere(
      (event) => event.type == CodexSessionEventType.approval,
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'permissions-session-1',
      'method': 'item/permissions/requestApproval',
      'params': <String, dynamic>{
        'permissions': <String, dynamic>{
          'fileSystem': <String, dynamic>{
            'write': <String>['README.md'],
          },
        },
      },
    });
    final sessionApproval = await sessionApprovalFuture;
    await client.respondToApproval(
      sessionApproval,
      approved: true,
      forSession: true,
    );
    final sessionResponse = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'permissions-session-1');
    expect(sessionResponse['result'], <String, dynamic>{
      'scope': 'session',
      'permissions': <String, dynamic>{
        'fileSystem': <String, dynamic>{
          'write': <String>['README.md'],
        },
      },
    });

    await client.dispose();
  });

  test('surfaces user-input requests and sends an answer map', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final approvalFuture = client.events.firstWhere(
      (event) => event.type == CodexSessionEventType.approval,
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'question-1',
      'method': 'item/tool/requestUserInput',
      'params': <String, dynamic>{
        'questions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'language',
            'header': 'Language',
            'question': 'Which language should the fixture use?',
            'options': <Map<String, String>>[
              <String, String>{
                'label': 'Dart',
                'description': 'Use the Dart fixture path.',
              },
            ],
          },
        ],
      },
    });
    final approval = await approvalFuture;

    expect(approval.requestId, 'question-1');
    expect(approval.requestMethod, 'item/tool/requestUserInput');
    expect(approval.params?['questions'], isA<List<Object?>>());

    await client.respondToRequest(approval.requestId!, <String, dynamic>{
      'answers': <String, dynamic>{
        'language': <String, dynamic>{
          'answers': <String>['Dart'],
        },
      },
    });

    final response = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'question-1');
    expect(response['result'], <String, dynamic>{
      'answers': <String, dynamic>{
        'language': <String, dynamic>{
          'answers': <String>['Dart'],
        },
      },
    });

    await client.dispose();
  });

  test('routes MCP elicitation through the MCP result envelope', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final elicitationFuture = client.events.firstWhere(
      (event) =>
          event.type == CodexSessionEventType.approval &&
          event.requestMethod == 'mcpServer/elicitation/request',
    );
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'mcp-form-1',
      'method': 'mcpServer/elicitation/request',
      'params': <String, dynamic>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'serverName': 'fixture',
        'mode': 'form',
        'message': 'Choose a target',
        'requestedSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'target': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['target'],
        },
      },
    });
    final elicitation = await elicitationFuture;
    expect(elicitation.params?['mode'], 'form');
    expect(elicitation.params?['serverName'], 'fixture');

    await client.respondToRequest('mcp-form-1', <String, dynamic>{
      'action': 'accept',
      'content': <String, dynamic>{'target': 'device'},
    });
    final response = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'mcp-form-1');
    expect(response['result'], <String, dynamic>{
      'action': 'accept',
      'content': <String, dynamic>{'target': 'device'},
    });

    await client.dispose();
  });

  test('rejects unknown server requests with a JSON-RPC error', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _ScriptedCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );
    final events = <CodexSessionEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start();
    process._emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': 'unsupported-1',
      'method': 'item/tool/requestUnknown',
      'params': <String, dynamic>{'questions': <Object?>[]},
    });
    await Future<void>.delayed(Duration.zero);

    expect(
      events.any(
        (event) =>
            event.type == CodexSessionEventType.error &&
            event.text!.contains('Unsupported app-server request'),
      ),
      isTrue,
    );
    final response = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['id'] == 'unsupported-1');
    expect(response['error'], <String, dynamic>{
      'code': -32601,
      'message': 'Unsupported server request: item/tool/requestUnknown',
    });

    await client.dispose();
    await subscription.cancel();
  });

  test('interrupts an active turn before stopping the process', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _BlockingTurnCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );

    await client.start();
    final turn = client.sendPrompt('start a long fixture turn');
    final turnError = expectLater(turn, throwsA(isA<CodexSessionException>()));
    await process.turnStarted.future;
    await client.stop();
    await turnError;

    final interrupt = process.writes
        .map(jsonDecode)
        .whereType<Map<Object?, Object?>>()
        .firstWhere((message) => message['method'] == 'turn/interrupt');
    expect(interrupt['params'], <String, String>{
      'threadId': 'thread-1',
      'turnId': 'turn-1',
    });

    await client.dispose();
  });

  test('settles an interrupt from the deferred RPC response when no terminal event arrives', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _InterruptResponseCodexProcess();
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) => process,
    );
    final events = <CodexSessionEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start();
    await client.sendPrompt('keep this turn active');
    await client.interrupt();
    await client.events.firstWhere(
      (event) =>
          event.type == CodexSessionEventType.status &&
          event.method == 'turn/interrupted',
    );

    expect(
      events.any(
        (event) =>
            event.type == CodexSessionEventType.status && event.text == 'idle',
      ),
      isTrue,
    );
    expect(
      process.writes.any(
        (value) => jsonDecode(value)['method'] == 'turn/interrupt',
      ),
      isTrue,
    );

    await client.dispose();
    await subscription.cancel();
  });

  test(
    'streams PTY command input, resize, and termination on one connection',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _InteractiveCommandCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      final output = <String>[];
      await client.start();

      final command = client.executeCommand(
        const <String>['sh'],
        tty: true,
        onOutput: (text, isStderr) =>
            output.add('${isStderr ? 'err' : 'out'}:$text'),
      );
      await process.commandStarted.future;
      await client.writeCommandInput('echo hello\n');
      await client.resizeCommand(rows: 40, cols: 120);
      await client.interrupt();

      final result = await command;
      expect(result.exitCode, 130);
      expect(output, contains('out:pty-output\n'));
      final writes = process.writes
          .map(jsonDecode)
          .whereType<Map<Object?, Object?>>()
          .toList(growable: false);
      final start = writes.firstWhere(
        (message) => message['method'] == 'command/exec',
      );
      final startParams = start['params'] as Map<Object?, Object?>;
      expect(startParams['tty'], isTrue);
      expect(startParams['streamStdin'], isTrue);
      expect(startParams['streamStdoutStderr'], isTrue);
      expect(startParams['size'], <String, int>{'rows': 24, 'cols': 80});
      final write = writes.firstWhere(
        (message) => message['method'] == 'command/exec/write',
      );
      expect(
        utf8.decode(
          base64.decode((write['params'] as Map)['deltaBase64'] as String),
        ),
        'echo hello\n',
      );
      expect(
        (writes.firstWhere(
              (message) => message['method'] == 'command/exec/resize',
            )['params']
            as Map<Object?, Object?>)['size'],
        <String, int>{'rows': 40, 'cols': 120},
      );
      expect(
        (writes.firstWhere(
              (message) => message['method'] == 'command/exec/terminate',
            )['params']
            as Map<Object?, Object?>)['processId'],
        startsWith('session-command-'),
      );
      await client.dispose();
    },
  );

  test(
    'emits only one exit event when process stop races a late exit',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ScriptedCodexProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        processFactory: (_) => process,
      );
      final events = <CodexSessionEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start();
      final firstExit = client.events.firstWhere(
        (event) => event.type == CodexSessionEventType.exit,
      );
      process.emitExecutionEvent(const ExecutionEvent.exit(0));
      await firstExit;
      process.emitExecutionEvent(const ExecutionEvent.exit(-1));
      await Future<void>.delayed(Duration.zero);

      expect(
        events.where((event) => event.type == CodexSessionEventType.exit),
        hasLength(1),
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test('ignores late events from an exited process after restart', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final processes = <_ScriptedCodexProcess>[];
    final client = CodexSessionClient(
      backend: backend,
      workspace: workspace,
      argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
      processFactory: (_) {
        final process = _ScriptedCodexProcess();
        processes.add(process);
        return process;
      },
    );
    final events = <CodexSessionEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start();
    processes.single.emitExecutionEvent(const ExecutionEvent.exit(0));
    await Future<void>.delayed(Duration.zero);

    await client.start();
    expect(processes, hasLength(2));

    processes.first.emitExecutionEvent(const ExecutionEvent.exit(-1));
    processes.first.emitExecutionEvent(
      const ExecutionEvent.error('stale process error'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.threadId, 'thread-1');
    expect(
      events.where((event) => event.type == CodexSessionEventType.exit),
      hasLength(1),
    );
    expect(
      events.where((event) => event.text == 'stale process error'),
      isEmpty,
    );

    await client.dispose();
    await subscription.cancel();
  });
}

bool _isTurnStart(String value) {
  final message = jsonDecode(value) as Map<Object?, Object?>;
  return message['method'] == 'turn/start';
}

class _AutomaticTitleCodexProcess implements InteractiveExecution {
  _AutomaticTitleCodexProcess({this.completeTitle = true});

  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  final Completer<void> titleTurnStarted = Completer<void>();
  final bool completeTitle;
  var _titleThreadStarted = false;
  var stopped = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    final params =
        message['params'] as Map<Object?, Object?>? ??
        const <Object?, Object?>{};
    if (id == null) return;

    if (method == 'thread/start' || method == 'thread/resume') {
      final isTitleThread = params['ephemeral'] == true;
      final threadId = isTitleThread ? 'title-thread-1' : 'thread-1';
      _titleThreadStarted = _titleThreadStarted || isTitleThread;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/started',
        'params': <String, dynamic>{
          'thread': <String, String>{'id': threadId},
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': threadId},
        },
      });
      return;
    }

    if (method == 'config/read') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'config': <String, dynamic>{
            'additional': <String, dynamic>{
              'mcp_servers': <String, dynamic>{
                'fixture-mcp': <String, dynamic>{'enabled': true},
              },
            },
          },
        },
      });
      return;
    }

    if (method == 'turn/start' &&
        params['threadId'] == 'title-thread-1' &&
        _titleThreadStarted) {
      titleTurnStarted.complete();
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'threadId': 'title-thread-1',
          'turn': <String, String>{'id': 'title-turn-1'},
        },
      });
      if (completeTitle) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'item/completed',
          'params': <String, dynamic>{
            'threadId': 'title-thread-1',
            'turnId': 'title-turn-1',
            'item': <String, String>{
              'type': 'agentMessage',
              'text': '{"title":"Fix session title handling"}',
            },
          },
        });
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'turn/completed',
          'params': <String, dynamic>{
            'threadId': 'title-thread-1',
            'turn': <String, String>{
              'id': 'title-turn-1',
              'status': 'completed',
            },
          },
        });
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'turn': <String, String>{'id': 'title-turn-1'},
        },
      });
      return;
    }

    if (method == 'turn/interrupt' && params['threadId'] == 'title-thread-1') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/interrupted',
        'params': <String, dynamic>{
          'threadId': 'title-thread-1',
          'turn': <String, String>{
            'id': 'title-turn-1',
            'status': 'interrupted',
          },
        },
      });
    }

    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
    if (method == 'thread/name/set') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/name/updated',
        'params': <String, dynamic>{
          'threadId': params['threadId'],
          'threadName': params['name'],
        },
      });
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_events.isClosed) await _events.close();
  }

  void _emitJson(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}

class _ScriptedCodexProcess implements InteractiveExecution {
  _ScriptedCodexProcess({
    this.threadId = 'thread-1',
    this.threadPath,
    this.forkThreadId = 'forked-thread-1',
    this.forkThreadPath,
    this.mcpOAuthAuthorizationUrl =
        'https://mcp.example.test/authorize?state=fixture',
    Map<String, dynamic> mcpServers = const <String, dynamic>{},
    this.mcpStatusPages = const <List<Map<String, dynamic>>>[],
    this.threadListPages = const <List<Map<String, dynamic>>>[],
    this.rejectExtendedThreadListParams = false,
    this.rejectPluginListParams = false,
    this.pluginMarketplaces = const <Map<String, dynamic>>[],
    this.pluginFeaturedIds = const <String>[],
    List<Map<String, dynamic>>? mcpLayers,
    this.applyMcpRemoval = true,
    this.emitFinalAgentMessageOnly = false,
  }) : mcpServers = Map<String, dynamic>.of(mcpServers),
       mcpLayers =
           mcpLayers ??
           <Map<String, dynamic>>[
             <String, dynamic>{
               'name': <String, dynamic>{
                 'type': 'user',
                 'file': '/codex/config.toml',
                 'profile': null,
               },
               'version': 'user-config-v1',
               'config': <String, dynamic>{
                 'mcp_servers': Map<String, dynamic>.of(mcpServers),
               },
             },
           ];

  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  final String threadId;
  final String? threadPath;
  final String forkThreadId;
  final String? forkThreadPath;
  final String mcpOAuthAuthorizationUrl;
  final Map<String, dynamic> mcpServers;
  final List<List<Map<String, dynamic>>> mcpStatusPages;
  final List<List<Map<String, dynamic>>> threadListPages;
  final bool rejectExtendedThreadListParams;
  final bool rejectPluginListParams;
  final List<Map<String, dynamic>> pluginMarketplaces;
  final List<String> pluginFeaturedIds;
  final List<Map<String, dynamic>> mcpLayers;
  final bool applyMcpRemoval;
  final bool emitFinalAgentMessageOnly;
  var stopped = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    if (id == null) return;
    if (method == 'thread/start' || method == 'thread/resume') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, dynamic>{
            'id': threadId,
            if (threadPath != null) 'path': threadPath,
          },
        },
      });
      return;
    }
    if (method == 'thread/fork') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, dynamic>{
            'id': forkThreadId,
            if (forkThreadPath != null) 'path': forkThreadPath,
          },
        },
      });
      return;
    }
    if (method == 'mcpServer/oauth/login') {
      final params = message['params'] as Map<Object?, Object?>;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'mcpServer/oauthLogin/completed',
        'params': <String, dynamic>{
          'name': params['name'],
          'threadId': params['threadId'],
          'success': true,
          'error': 'PRIVATE_OAUTH_ERROR',
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, String>{
          'authorizationUrl': mcpOAuthAuthorizationUrl,
        },
      });
      return;
    }
    if (method == 'config/read') {
      final params = message['params'] as Map<Object?, Object?>;
      final config = <String, dynamic>{
        'mcp_servers': Map<String, dynamic>.of(mcpServers),
      };
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'config': config,
          if (params['includeLayers'] == true) 'layers': mcpLayers,
        },
      });
      return;
    }
    if (method == 'config/batchWrite') {
      if (applyMcpRemoval) {
        final params = message['params'] as Map<Object?, Object?>;
        final edit = (params['edits'] as List).single as Map<Object?, Object?>;
        final keyPath = edit['keyPath'] as String;
        final name = jsonDecode(keyPath.substring('mcp_servers.'.length));
        if (name is String) {
          final value = edit['value'];
          if (value == null) {
            mcpServers.remove(name);
          } else {
            mcpServers[name] = value;
          }
          for (final layer in mcpLayers) {
            final source = layer['name'];
            final config = layer['config'];
            if (source is Map &&
                source['type'] == 'user' &&
                source['profile'] == null &&
                config is Map) {
              final servers = config['mcp_servers'];
              if (servers is Map) {
                if (value == null) {
                  servers.remove(name);
                } else {
                  servers[name] = value;
                }
              }
            }
          }
        }
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'status': 'ok'},
      });
      return;
    }
    if (method == 'mcpServerStatus/list') {
      final params = message['params'] as Map<Object?, Object?>;
      final cursor = params['cursor'];
      final pageIndex = cursor == 'mcp-page-2' ? 1 : 0;
      final nextCursor = pageIndex + 1 < mcpStatusPages.length
          ? 'mcp-page-${pageIndex + 2}'
          : null;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'data': pageIndex < mcpStatusPages.length
              ? mcpStatusPages[pageIndex]
              : <Map<String, dynamic>>[],
          'nextCursor': nextCursor,
        },
      });
      return;
    }
    if (method == 'thread/list') {
      final params = message['params'] as Map<Object?, Object?>;
      if (rejectExtendedThreadListParams &&
          (params.containsKey('cwd') ||
              params.containsKey('searchTerm') ||
              params.containsKey('sortKey') ||
              params.containsKey('sortDirection') ||
              params.containsKey('useStateDbOnly'))) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32602,
            'message': 'Unknown parameter useStateDbOnly',
          },
        });
        return;
      }
      final cursor = params['cursor'];
      final pageIndex = cursor == 'thread-page-2' ? 1 : 0;
      final nextCursor = pageIndex + 1 < threadListPages.length
          ? 'thread-page-${pageIndex + 2}'
          : null;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'data': pageIndex < threadListPages.length
              ? threadListPages[pageIndex]
              : <Map<String, dynamic>>[],
          'nextCursor': nextCursor,
          'backwardsCursor': null,
        },
      });
      return;
    }
    if (method == 'plugin/list') {
      final params = message['params'];
      if (rejectPluginListParams && params is Map && params.isNotEmpty) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32602,
            'message': 'Unknown parameter cwds',
          },
        });
        return;
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'marketplaces': pluginMarketplaces,
          'marketplaceLoadErrors': <Object?>[],
          'featuredPluginIds': pluginFeaturedIds,
        },
      });
      return;
    }
    if (method == 'plugin/install') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'installed': true,
          'authPolicy': 'on-request',
          'appsNeedingAuth': <Object?>[],
        },
      });
      return;
    }
    if (method == 'plugin/uninstall') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'uninstalled': true},
      });
      return;
    }
    if (method == 'config/value/write') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'status': 'ok',
          'version': 'user-config-v2',
        },
      });
      return;
    }
    if (method == 'marketplace/add') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'marketplaceName': 'owner-repo',
          'installedRoot': '/private/owner-repo',
          'alreadyAdded': false,
        },
      });
      return;
    }
    if (method == 'marketplace/remove') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'removed': true},
      });
      return;
    }
    if (method == 'marketplace/upgrade') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'selectedMarketplaces': <String>['owner-repo'],
          'upgradedRoots': <String>['/private/owner-repo'],
          'errors': <Object?>[],
        },
      });
      return;
    }
    if (method == 'turn/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, String>{'id': 'turn-1'},
        },
      });
      if (emitFinalAgentMessageOnly) {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'item/completed',
          'params': <String, dynamic>{
            'turnId': 'turn-1',
            'item': <String, String>{
              'type': 'agentMessage',
              'id': 'assistant-1',
              'text': 'fixture completion response',
            },
          },
        });
      } else {
        _emitJson(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'item/agentMessage/delta',
          'params': <String, String>{'delta': 'fixture response'},
        });
      }
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/completed',
        'params': <String, dynamic>{
          'turn': <String, String>{'status': 'completed'},
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, String>{'turnId': 'turn-1'},
      });
      return;
    }
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_events.isClosed) await _events.close();
  }

  void emitExecutionEvent(ExecutionEvent event) {
    _events.add(event);
  }

  void _emitJson(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}

class _ApprovalCodexProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  int? _turnRequestId;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    if (id == null) return;
    if (method == 'thread/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': 'thread-1'},
        },
      });
      return;
    }
    if (method == 'turn/start') {
      _turnRequestId = id as int;
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, String>{'id': 'turn-1'},
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'approval-1',
        'method': 'item/commandExecution/requestApproval',
        'params': <String, String>{'command': 'echo fixture'},
      });
      return;
    }
    if (method == null && id == 'approval-1') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/completed',
        'params': <String, dynamic>{},
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': _turnRequestId,
        'result': <String, String>{'turnId': 'turn-1'},
      });
      return;
    }
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }

  void _emitJson(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}

class _BlockingTurnCodexProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  final turnStarted = Completer<void>();

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    if (id == null) return;
    if (method == 'thread/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': 'thread-1'},
        },
      });
      return;
    }
    if (method == 'turn/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, String>{'id': 'turn-1'},
        },
      });
      if (!turnStarted.isCompleted) turnStarted.complete();
      return;
    }
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }

  void _emitJson(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}

class _InterruptResponseCodexProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    if (method == 'thread/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': 'thread-1'},
        },
      });
      return;
    }
    if (method == 'turn/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, String>{'id': 'turn-1'},
        },
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{'turnId': 'turn-1'},
      });
      return;
    }
    if (method == 'turn/interrupt') {
      // Deliberately return only the deferred RPC response; the client must
      // still settle the local turn when a compatible server omits a terminal
      // notification.
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      return;
    }
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }

  void _emitJson(Map<String, dynamic> value) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(value)}\n'));
  }
}

class _InteractiveCommandCodexProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  final commandStarted = Completer<void>();
  String? _commandRequestId;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final method = message['method'];
    final id = message['id'];
    final params = message['params'] as Map<Object?, Object?>? ?? const {};
    if (method == 'thread/start') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, String>{'id': 'thread-1'},
        },
      });
      return;
    }
    if (method == 'command/exec') {
      _commandRequestId = '$id';
      if (!commandStarted.isCompleted) commandStarted.complete();
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'command/exec/outputDelta',
        'params': <String, dynamic>{
          'processId': params['processId'],
          'stream': 'stdout',
          'deltaBase64': base64Encode(utf8.encode('pty-output\n')),
          'capReached': false,
        },
      });
      return;
    }
    if (method == 'command/exec/terminate') {
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      _emitJson(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': _commandRequestId,
        'result': <String, dynamic>{
          'exitCode': 130,
          'stdout': '',
          'stderr': '',
        },
      });
      return;
    }
    _emitJson(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }

  void _emitJson(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}
