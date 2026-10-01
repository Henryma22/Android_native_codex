import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:codex/codex_mcp_settings.dart';
import 'package:codex/ccpocket_local_settings.dart';
import 'package:codex/core/application/codex_cli_arguments.dart';
import 'package:codex/core/application/codex_mcp_server_summary.dart';
import 'package:codex/core/application/codex_plugin_summary.dart';
import 'package:codex/core/domain/runtime.dart';

void main() {
  testWidgets('MCP settings connect list, OAuth, add and remove callbacks', (
    tester,
  ) async {
    CodexMcpAddRequest? added;
    String? removed;
    String? loggedIn;
    const server = CodexMcpServerSummary(
      name: 'github',
      enabled: true,
      transport: 'http',
      endpointOrigin: 'https://mcp.example.test',
    );
    const status = CodexMcpServerStatusSummary(
      name: 'github',
      runtimeStatus: 'connected',
      authStatus: 'oauth',
      toolCount: 3,
      hasToolsError: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => const <CodexMcpServerSummary>[server],
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[
            status,
          ],
          onAddServer: (request) async => added = request,
          onRemoveServer: (name) async => removed = name,
          onLogin: (name) async => loggedIn = name,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MCP 服务器'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp_server_github')), findsOneWidget);
    expect(find.textContaining('已连接'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mcp_actions_github')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浏览器 OAuth 登录'));
    await tester.pumpAndSettle();
    expect(loggedIn, 'github');

    await tester.tap(find.byKey(const ValueKey('mcp_add_server_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mcp_add_name_field')),
      'local-tools',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mcp_add_command_field')),
      'npx',
    );
    await tester.tap(find.byKey(const ValueKey('mcp_add_confirm')));
    await tester.pumpAndSettle();
    expect(added?.name, 'local-tools');
    expect(added?.config['command'], 'npx');

    await tester.tap(find.byKey(const ValueKey('mcp_actions_github')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcp_remove_confirm')));
    await tester.pumpAndSettle();
    expect(removed, 'github');
  });

  testWidgets('MCP add dialog validates HTTP and stdio inputs', (tester) async {
    CodexMcpAddRequest? added;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => const <CodexMcpServerSummary>[],
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[],
          onAddServer: (request) async => added = request,
          onRemoveServer: (_) async {},
          onLogin: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcp_add_server_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mcp_add_name_field')),
      'remote',
    );
    await tester.tap(find.byKey(const ValueKey('mcp_add_transport_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTP(S) 服务'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mcp_add_url_field')),
      'https://mcp.example.test/path',
    );
    await tester.tap(find.byKey(const ValueKey('mcp_add_confirm')));
    await tester.pumpAndSettle();

    expect(added?.name, 'remote');
    expect(added?.config['url'], 'https://mcp.example.test/path');
  });

  testWidgets('plugin catalog uses the active session mutation callbacks', (
    tester,
  ) async {
    String? installed;
    String? removed;
    const available = CodexPluginSummary(
      marketplaceName: 'official',
      id: 'tools@official',
      name: 'tools',
      version: '1.0.0',
      installed: false,
      enabled: false,
      featured: true,
    );
    const installedPlugin = CodexPluginSummary(
      marketplaceName: 'official',
      id: 'docs@official',
      name: 'docs',
      localVersion: '2.0.0',
      installed: true,
      enabled: true,
      featured: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => const <CodexMcpServerSummary>[],
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[],
          onAddServer: (_) async {},
          onRemoveServer: (_) async {},
          onLogin: (_) async {},
          onLoadPlugins: ({forceRefetch = false}) async =>
              const <CodexPluginSummary>[available, installedPlugin],
          onInstallPlugin: (name, marketplace) async {
            installed = '$name@$marketplace';
          },
          onRemovePlugin: (id) async => removed = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('插件目录'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('plugin_install_tools@official')),
    );
    await tester.pumpAndSettle();
    expect(installed, 'tools@official');

    final removePlugin = find.byKey(
      const ValueKey('plugin_remove_docs@official'),
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(removePlugin);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plugin_remove_confirm')));
    await tester.pumpAndSettle();
    expect(removed, 'docs@official');
  });

  testWidgets('plugin catalog exposes an enablement toggle', (tester) async {
    String? toggled;
    bool? toggleValue;
    const plugin = CodexPluginSummary(
      marketplaceName: 'official',
      id: 'docs@official',
      name: 'docs',
      localVersion: '2.0.0',
      installed: true,
      enabled: true,
      featured: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => const <CodexMcpServerSummary>[],
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[],
          onAddServer: (_) async {},
          onRemoveServer: (_) async {},
          onLogin: (_) async {},
          onLoadPlugins: ({forceRefetch = false}) async =>
              const <CodexPluginSummary>[plugin],
          onSetPluginEnabled: (id, enabled) async {
            toggled = id;
            toggleValue = enabled;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('plugin_toggle_docs@official'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(toggled, 'docs@official');
    expect(toggleValue, isFalse);
  });

  testWidgets('plugin marketplace settings use active session mutations', (
    tester,
  ) async {
    CodexPluginMarketplaceAddRequest? added;
    String? removed;
    String? upgraded;
    const marketplace = CodexPluginMarketplaceSummary(
      name: 'official',
      displayName: 'Official tools',
      pluginCount: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => const <CodexMcpServerSummary>[],
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[],
          onAddServer: (_) async {},
          onRemoveServer: (_) async {},
          onLogin: (_) async {},
          onLoadPluginMarketplaces: ({forceRefetch = false}) async =>
              const <CodexPluginMarketplaceSummary>[marketplace],
          onAddPluginMarketplace: (request) async => added = request,
          onRemovePluginMarketplace: (name) async => removed = name,
          onUpgradePluginMarketplace: (name) async => upgraded = name,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final marketplaceTile = find.byKey(const ValueKey('marketplace_official'));
    await tester.ensureVisible(marketplaceTile);
    await tester.tap(
      find.byKey(const ValueKey('marketplace_upgrade_official')),
    );
    await tester.pumpAndSettle();
    expect(upgraded, 'official');

    await tester.tap(find.byKey(const ValueKey('marketplace_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('marketplace_source_field')),
      'owner/repo',
    );
    await tester.enterText(
      find.byKey(const ValueKey('marketplace_ref_field')),
      'main',
    );
    await tester.enterText(
      find.byKey(const ValueKey('marketplace_sparse_field')),
      'plugins\ntools',
    );
    await tester.tap(find.byKey(const ValueKey('marketplace_add_confirm')));
    await tester.pumpAndSettle();
    expect(added?.source, 'owner/repo');
    expect(added?.refName, 'main');
    expect(added?.sparsePaths, <String>['plugins', 'tools']);

    await tester.tap(find.byKey(const ValueKey('marketplace_remove_official')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('marketplace_remove_confirm')));
    await tester.pumpAndSettle();
    expect(removed, 'official');
  });

  testWidgets('CC Pocket settings exposes the MCP entrypoint', (tester) async {
    var opened = 0;
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          onOpenMcpSettings: () async => opened++,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('settings_mcp_tile'));
    await tester.drag(
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
