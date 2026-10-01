import 'dart:async';

import 'package:flutter/material.dart';

import 'core/application/codex_cli_arguments.dart';
import 'core/application/codex_mcp_server_summary.dart';
import 'core/application/codex_plugin_summary.dart';

/// Settings for the MCP configuration owned by the currently selected local
/// Codex session.
///
/// MCP configuration is session-scoped in this app because every session has
/// its own CODEX_HOME. The page therefore never pretends that a change affects
/// every workspace or every session.
class CodexMcpSettingsPage extends StatefulWidget {
  const CodexMcpSettingsPage({
    required this.onLoadServers,
    required this.onLoadStatuses,
    required this.onAddServer,
    required this.onRemoveServer,
    required this.onLogin,
    this.onLoadPlugins,
    this.onInstallPlugin,
    this.onRemovePlugin,
    this.onSetPluginEnabled,
    this.onLoadPluginMarketplaces,
    this.onAddPluginMarketplace,
    this.onRemovePluginMarketplace,
    this.onUpgradePluginMarketplace,
    super.key,
  });

  final Future<List<CodexMcpServerSummary>> Function() onLoadServers;
  final Future<List<CodexMcpServerStatusSummary>> Function() onLoadStatuses;
  final Future<void> Function(CodexMcpAddRequest request) onAddServer;
  final Future<void> Function(String name) onRemoveServer;
  final Future<void> Function(String name) onLogin;
  final Future<List<CodexPluginSummary>> Function({bool forceRefetch})?
  onLoadPlugins;
  final Future<void> Function(String pluginName, String marketplaceName)?
  onInstallPlugin;
  final Future<void> Function(String pluginId)? onRemovePlugin;
  final Future<void> Function(String pluginId, bool enabled)?
  onSetPluginEnabled;
  final Future<List<CodexPluginMarketplaceSummary>> Function({
    bool forceRefetch,
  })?
  onLoadPluginMarketplaces;
  final Future<void> Function(CodexPluginMarketplaceAddRequest request)?
  onAddPluginMarketplace;
  final Future<void> Function(String marketplaceName)?
  onRemovePluginMarketplace;
  final Future<void> Function(String? marketplaceName)?
  onUpgradePluginMarketplace;

  @override
  State<CodexMcpSettingsPage> createState() => _CodexMcpSettingsPageState();
}

class _CodexMcpSettingsPageState extends State<CodexMcpSettingsPage> {
  late Future<List<CodexMcpServerSummary>> _servers;
  late Future<List<CodexMcpServerStatusSummary>> _statuses;
  final _busyServers = <String>{};
  final _busyPlugins = <String>{};
  final _busyMarketplaces = <String>{};
  Future<List<CodexPluginSummary>>? _plugins;
  Future<List<CodexPluginMarketplaceSummary>>? _marketplaces;
  var _upgradingAllMarketplaces = false;
  var _adding = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _text(String zh, String en) => _zh ? zh : en;

  String _errorDetail(Object error) {
    final message = '$error'
        .replaceFirst('CodexSessionException: ', '')
        .replaceFirst('FormatException: ', '');
    if (!_zh) return message;
    return switch (message) {
      'Codex thread is not ready' ||
      'The Codex thread is not ready.' => '当前 Codex 会话线程尚未就绪。',
      'Codex session workspace is not ready' => '当前会话工作区尚未就绪。',
      'MCP server name is invalid.' => 'MCP 服务器名称无效。',
      'Plugin id is invalid.' => '插件 ID 无效。',
      'Codex MCP server config is not an object.' => 'MCP 服务器配置格式无效。',
      'Codex MCP status data is not a list.' => 'MCP 连接状态格式无效。',
      _ => message,
    };
  }

  @override
  void initState() {
    super.initState();
    _servers = widget.onLoadServers();
    _statuses = widget.onLoadStatuses();
    _plugins = widget.onLoadPlugins?.call();
    _marketplaces = widget.onLoadPluginMarketplaces?.call();
  }

  void _refresh() {
    setState(() {
      _servers = widget.onLoadServers();
      _statuses = widget.onLoadStatuses();
      _plugins = widget.onLoadPlugins?.call(forceRefetch: true);
      _marketplaces = widget.onLoadPluginMarketplaces?.call(forceRefetch: true);
    });
  }

  Future<void> _add() async {
    final request = await showDialog<CodexMcpAddRequest>(
      context: context,
      builder: (_) => const _CodexMcpAddDialog(),
    );
    if (!mounted || request == null || _adding) return;
    setState(() => _adding = true);
    try {
      await widget.onAddServer(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'MCP 服务器“${request.name}”已添加到当前 session。',
              'MCP server “${request.name}” was added to this session.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(CodexMcpServerSummary server) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text('移除 MCP 服务器？', 'Remove MCP server?')),
            content: Text(
              _text(
                '将从当前 session 的 Codex 配置中移除“${server.name}”；其他 session 不受影响。',
                'Remove “${server.name}” from this session’s Codex config? Other sessions are unchanged.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                key: const ValueKey('mcp_remove_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text('移除', 'Remove')),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed || _busyServers.contains(server.name)) return;
    setState(() => _busyServers.add(server.name));
    try {
      await widget.onRemoveServer(server.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '已从当前 session 移除“${server.name}”。',
              'Removed “${server.name}” from this session.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyServers.remove(server.name));
    }
  }

  Future<void> _login(CodexMcpServerSummary server) async {
    if (_busyServers.contains(server.name)) return;
    setState(() => _busyServers.add(server.name));
    try {
      await widget.onLogin(server.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '已为“${server.name}”打开授权流程。完成浏览器授权后刷新状态。',
              'Authorization for “${server.name}” was opened. Finish it in the browser, then refresh status.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyServers.remove(server.name));
    }
  }

  Future<void> _installPlugin(CodexPluginSummary plugin) async {
    final callback = widget.onInstallPlugin;
    if (callback == null || _busyPlugins.contains(plugin.id)) return;
    setState(() => _busyPlugins.add(plugin.id));
    try {
      await callback(plugin.name, plugin.marketplaceName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '插件“${plugin.name}”已安装到当前 session。',
              'Plugin “${plugin.name}” was installed for this session.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyPlugins.remove(plugin.id));
    }
  }

  Future<void> _removePlugin(CodexPluginSummary plugin) async {
    final callback = widget.onRemovePlugin;
    if (callback == null || _busyPlugins.contains(plugin.id)) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text('卸载插件？', 'Uninstall plugin?')),
            content: Text(
              _text(
                '将从当前 session 卸载“${plugin.name}”；其他 session 不受影响。',
                'Uninstall “${plugin.name}” from this session? Other sessions are unchanged.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                key: const ValueKey('plugin_remove_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text('卸载', 'Uninstall')),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    setState(() => _busyPlugins.add(plugin.id));
    try {
      await callback(plugin.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '插件“${plugin.name}”已从当前 session 卸载。',
              'Plugin “${plugin.name}” was uninstalled from this session.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyPlugins.remove(plugin.id));
    }
  }

  Future<void> _setPluginEnabled(
    CodexPluginSummary plugin,
    bool enabled,
  ) async {
    final callback = widget.onSetPluginEnabled;
    if (callback == null || _busyPlugins.contains(plugin.id)) return;
    setState(() => _busyPlugins.add(plugin.id));
    try {
      await callback(plugin.id, enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? _text(
                    '插件“${plugin.name}”已启用。',
                    'Plugin “${plugin.name}” was enabled.',
                  )
                : _text(
                    '插件“${plugin.name}”已停用。',
                    'Plugin “${plugin.name}” was disabled.',
                  ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyPlugins.remove(plugin.id));
    }
  }

  Future<void> _addMarketplace() async {
    final callback = widget.onAddPluginMarketplace;
    if (callback == null) return;
    final request = await showDialog<CodexPluginMarketplaceAddRequest>(
      context: context,
      builder: (_) => const _CodexPluginMarketplaceAddDialog(),
    );
    if (!mounted || request == null) return;
    setState(() => _upgradingAllMarketplaces = true);
    try {
      await callback(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '插件市场“${request.source}”已添加。',
              'Plugin marketplace “${request.source}” was added.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _upgradingAllMarketplaces = false);
    }
  }

  Future<void> _removeMarketplace(
    CodexPluginMarketplaceSummary marketplace,
  ) async {
    final callback = widget.onRemovePluginMarketplace;
    if (callback == null || _busyMarketplaces.contains(marketplace.name)) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_text('移除插件市场？', 'Remove plugin marketplace?')),
            content: Text(
              _text(
                '将从当前 session 移除“${marketplace.title}”及其本地市场配置。',
                'Remove “${marketplace.title}” and its local marketplace configuration from this session?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_text('取消', 'Cancel')),
              ),
              FilledButton(
                key: const ValueKey('marketplace_remove_confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_text('移除', 'Remove')),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    setState(() => _busyMarketplaces.add(marketplace.name));
    try {
      await callback(marketplace.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              '已移除插件市场“${marketplace.title}”。',
              'Removed plugin marketplace “${marketplace.title}”.',
            ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyMarketplaces.remove(marketplace.name));
    }
  }

  Future<void> _upgradeMarketplace(String? marketplaceName) async {
    final callback = widget.onUpgradePluginMarketplace;
    if (callback == null) return;
    final key = marketplaceName?.trim() ?? '';
    if (key.isEmpty && _upgradingAllMarketplaces) return;
    if (key.isNotEmpty && _busyMarketplaces.contains(key)) return;
    setState(() {
      if (key.isEmpty) {
        _upgradingAllMarketplaces = true;
      } else {
        _busyMarketplaces.add(key);
      }
    });
    try {
      await callback(key.isEmpty ? null : key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            key.isEmpty
                ? _text('插件市场已刷新。', 'Plugin marketplaces refreshed.')
                : _text(
                    '插件市场“$key”已刷新。',
                    'Plugin marketplace “$key” was refreshed.',
                  ),
          ),
        ),
      );
      _refresh();
    } on Object catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          if (key.isEmpty) {
            _upgradingAllMarketplaces = false;
          } else {
            _busyMarketplaces.remove(key);
          }
        });
      }
    }
  }

  void _showError(Object error) {
    final message = _errorDetail(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _text('MCP 操作失败：$message', 'MCP operation failed: $message'),
        ),
      ),
    );
  }

  Widget _errorTile(Object error) => ListTile(
    leading: const Icon(Icons.error_outline),
    title: Text(_text('读取失败', 'Unable to load')),
    subtitle: Text(_errorDetail(error)),
    trailing: IconButton(
      tooltip: _text('重试', 'Retry'),
      onPressed: _refresh,
      icon: const Icon(Icons.refresh),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_text('MCP 与插件', 'MCP & plugins')),
        actions: [
          IconButton(
            key: const ValueKey('mcp_refresh_button'),
            tooltip: _text('刷新', 'Refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          final futures = <Future<Object?>>[_servers, _statuses];
          final plugins = _plugins;
          if (plugins != null) futures.add(plugins);
          final marketplaces = _marketplaces;
          if (marketplaces != null) futures.add(marketplaces);
          await Future.wait(futures);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _text(
                          '这里管理当前 session 的 Codex MCP 配置。每个 session 使用独立的 CODEX_HOME，修改不会覆盖其他 session；敏感 token 不会显示在列表中。',
                          'This manages the selected session’s Codex MCP config. Each session has an isolated CODEX_HOME, so changes do not affect other sessions; secret tokens are not shown in the list.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _text('MCP 服务器', 'MCP servers'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('mcp_add_server_button'),
                  onPressed: _adding ? null : _add,
                  icon: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_text('添加', 'Add')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<CodexMcpServerSummary>>(
              future: _servers,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _errorTile(snapshot.error!);
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final servers = snapshot.data!;
                if (servers.isEmpty) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.extension_outlined),
                      title: Text(
                        _text('尚未配置 MCP 服务器', 'No MCP servers configured'),
                      ),
                      subtitle: Text(
                        _text(
                          '添加 stdio 或 HTTP MCP 服务后，它会出现在当前 session 的工具列表中。',
                          'Add a stdio or HTTP MCP server to make it available to this session.',
                        ),
                      ),
                    ),
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var index = 0; index < servers.length; index++) ...[
                        if (index > 0)
                          Divider(height: 1, color: scheme.outlineVariant),
                        _serverTile(servers[index]),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Text(
              _text('连接状态', 'Connection status'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<CodexMcpServerStatusSummary>>(
              future: _statuses,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _errorTile(snapshot.error!);
                if (!snapshot.hasData) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final statuses = snapshot.data!;
                if (statuses.isEmpty) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.link_off),
                      title: Text(_text('暂无状态数据', 'No status data')),
                      subtitle: Text(
                        _text(
                          '当前没有可查询的 MCP 连接。',
                          'There are no MCP connections to query.',
                        ),
                      ),
                    ),
                  );
                }
                return Card(
                  child: Column(
                    children: [
                      for (var index = 0; index < statuses.length; index++) ...[
                        if (index > 0)
                          Divider(height: 1, color: scheme.outlineVariant),
                        ListTile(
                          leading: Icon(
                            statuses[index].runtimeStatus == 'connected'
                                ? Icons.check_circle_outline
                                : Icons.sync_problem_outlined,
                            color: statuses[index].runtimeStatus == 'connected'
                                ? Colors.green
                                : scheme.primary,
                          ),
                          title: Text(statuses[index].name),
                          subtitle: Text(
                            statuses[index].displayLine(chinese: _zh),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            _buildMarketplaceSection(scheme),
            _buildPluginSection(scheme),
            const SizedBox(height: 12),
            Text(
              _text(
                '插件目录和市场均以当前 Codex CLI/app-server 返回的能力为准；所有变更只作用于当前 session。',
                'The plugin catalog and marketplaces follow the installed Codex CLI/app-server; changes apply only to this session.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _serverTile(CodexMcpServerSummary server) {
    final busy = _busyServers.contains(server.name);
    return ListTile(
      key: ValueKey('mcp_server_${server.name}'),
      leading: Icon(
        server.enabled ? Icons.extension_outlined : Icons.pause_circle_outline,
      ),
      title: Text(server.name),
      subtitle: Text(server.displayLine(chinese: _zh)),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        key: ValueKey('mcp_actions_${server.name}'),
        enabled: !busy,
        onSelected: (value) {
          if (value == 'login') unawaited(_login(server));
          if (value == 'remove') unawaited(_remove(server));
        },
        itemBuilder: (context) => [
          if (server.transport == 'http')
            PopupMenuItem(
              value: 'login',
              child: Text(_text('浏览器 OAuth 登录', 'Browser OAuth login')),
            ),
          PopupMenuItem(value: 'remove', child: Text(_text('移除', 'Remove'))),
        ],
        icon: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.more_vert),
      ),
    );
  }

  Widget _buildPluginSection(ColorScheme scheme) {
    final pluginsFuture = _plugins;
    if (widget.onLoadPlugins == null || pluginsFuture == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(
          _text('插件目录', 'Plugin catalog'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<CodexPluginSummary>>(
          future: pluginsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _errorTile(snapshot.error!);
            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final plugins = snapshot.data!;
            if (plugins.isEmpty) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.extension_off_outlined),
                  title: Text(_text('暂无插件', 'No plugins found')),
                  subtitle: Text(
                    _text(
                      '当前 Codex app-server 没有返回可用插件。',
                      'The current Codex app-server returned no plugins.',
                    ),
                  ),
                ),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < plugins.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, color: scheme.outlineVariant),
                    _pluginTile(plugins[index]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMarketplaceSection(ColorScheme scheme) {
    final marketplacesFuture = _marketplaces;
    if (widget.onLoadPluginMarketplaces == null || marketplacesFuture == null) {
      return const SizedBox.shrink();
    }
    final canMutate = widget.onAddPluginMarketplace != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _text('插件市场', 'Plugin marketplaces'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.onUpgradePluginMarketplace != null)
              IconButton(
                key: const ValueKey('marketplace_upgrade_all'),
                tooltip: _text('刷新全部市场', 'Refresh all marketplaces'),
                onPressed: _upgradingAllMarketplaces
                    ? null
                    : () => unawaited(_upgradeMarketplace(null)),
                icon: _upgradingAllMarketplaces
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            if (canMutate)
              FilledButton.icon(
                key: const ValueKey('marketplace_add_button'),
                onPressed: _upgradingAllMarketplaces ? null : _addMarketplace,
                icon: const Icon(Icons.add),
                label: Text(_text('添加', 'Add')),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<CodexPluginMarketplaceSummary>>(
          future: marketplacesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _errorTile(snapshot.error!);
            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            final marketplaces = snapshot.data!;
            if (marketplaces.isEmpty) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(_text('暂无插件市场', 'No plugin marketplaces')),
                  subtitle: Text(
                    _text(
                      '添加 Git 或本地来源后，市场中的插件会出现在下方目录。',
                      'Add a Git or local source to make its plugins appear in the catalog below.',
                    ),
                  ),
                ),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var index = 0; index < marketplaces.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, color: scheme.outlineVariant),
                    _marketplaceTile(marketplaces[index]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _marketplaceTile(CodexPluginMarketplaceSummary marketplace) {
    final busy = _busyMarketplaces.contains(marketplace.name);
    final canMutate = widget.onRemovePluginMarketplace != null;
    return ListTile(
      key: ValueKey('marketplace_${marketplace.name}'),
      leading: const Icon(Icons.storefront_outlined),
      title: Text(marketplace.title),
      subtitle: Text(marketplace.displayLine(chinese: _zh)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onUpgradePluginMarketplace != null)
            IconButton(
              key: ValueKey('marketplace_upgrade_${marketplace.name}'),
              tooltip: _text('刷新', 'Refresh'),
              onPressed: busy
                  ? null
                  : () => unawaited(_upgradeMarketplace(marketplace.name)),
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          if (canMutate)
            IconButton(
              key: ValueKey('marketplace_remove_${marketplace.name}'),
              tooltip: _text('移除', 'Remove'),
              onPressed: busy
                  ? null
                  : () => unawaited(_removeMarketplace(marketplace)),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }

  Widget _pluginTile(CodexPluginSummary plugin) {
    final busy = _busyPlugins.contains(plugin.id);
    final version = plugin.localVersion ?? plugin.version;
    return ListTile(
      key: ValueKey('plugin_${plugin.id}'),
      leading: Icon(
        plugin.installed ? Icons.extension : Icons.extension_outlined,
      ),
      title: Text(plugin.name),
      subtitle: Text(
        [
          plugin.marketplaceDisplayName ?? plugin.marketplaceName,
          if (version != null) 'v$version',
          plugin.enabled ? _text('已启用', 'enabled') : _text('已停用', 'disabled'),
        ].join(' · '),
      ),
      trailing: !plugin.installed
          ? widget.onInstallPlugin == null
                ? null
                : FilledButton.tonal(
                    key: ValueKey('plugin_install_${plugin.id}'),
                    onPressed: busy
                        ? null
                        : () => unawaited(_installPlugin(plugin)),
                    child: Text(_text('安装', 'Install')),
                  )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onSetPluginEnabled != null)
                  IconButton(
                    key: ValueKey('plugin_toggle_${plugin.id}'),
                    tooltip: plugin.enabled
                        ? _text('停用插件', 'Disable plugin')
                        : _text('启用插件', 'Enable plugin'),
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _setPluginEnabled(plugin, !plugin.enabled),
                          ),
                    icon: Icon(
                      plugin.enabled
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                  ),
                if (widget.onRemovePlugin != null)
                  OutlinedButton(
                    key: ValueKey('plugin_remove_${plugin.id}'),
                    onPressed: busy
                        ? null
                        : () => unawaited(_removePlugin(plugin)),
                    child: Text(_text('卸载', 'Uninstall')),
                  ),
              ],
            ),
    );
  }
}

class _CodexMcpAddDialog extends StatefulWidget {
  const _CodexMcpAddDialog();

  @override
  State<_CodexMcpAddDialog> createState() => _CodexMcpAddDialogState();
}

class _CodexMcpAddDialogState extends State<_CodexMcpAddDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _env = TextEditingController();
  final _bearerTokenEnv = TextEditingController();
  var _transport = 'stdio';
  String? _error;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _command.dispose();
    _args.dispose();
    _env.dispose();
    _bearerTokenEnv.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _text('请输入服务器名称。', 'Enter a server name.'));
      return;
    }
    try {
      final config = <String, Object?>{};
      if (_transport == 'http') {
        final rawUrl = _url.text.trim();
        final uri = Uri.tryParse(rawUrl);
        if (uri == null ||
            !uri.hasAuthority ||
            !const <String>{
              'http',
              'https',
            }.contains(uri.scheme.toLowerCase()) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment) {
          throw FormatException(
            _text('请输入有效的 HTTP(S) 地址。', 'Enter a valid HTTP(S) URL.'),
          );
        }
        config['url'] = rawUrl;
        final tokenEnv = _bearerTokenEnv.text.trim();
        if (tokenEnv.isNotEmpty) {
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tokenEnv)) {
            throw FormatException(
              _text(
                'Bearer token 环境变量名无效。',
                'The bearer-token environment variable name is invalid.',
              ),
            );
          }
          config['bearer_token_env_var'] = tokenEnv;
        }
      } else {
        final command = _command.text.trim();
        if (command.isEmpty) {
          throw FormatException(
            _text('请输入 stdio 启动命令。', 'Enter a stdio launch command.'),
          );
        }
        final args = _args.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        final env = <String, String>{};
        for (final rawEntry in _env.text.split('\n')) {
          final entry = rawEntry.trim();
          if (entry.isEmpty) continue;
          final equals = entry.indexOf('=');
          if (equals <= 0) {
            throw FormatException(
              _text(
                '环境变量必须使用 KEY=VALUE 格式。',
                'Environment entries must use KEY=VALUE.',
              ),
            );
          }
          final key = entry.substring(0, equals);
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
            throw FormatException(
              _text('环境变量名无效。', 'The environment variable name is invalid.'),
            );
          }
          env[key] = entry.substring(equals + 1);
        }
        config['command'] = command;
        config['args'] = args;
        if (env.isNotEmpty) config['env'] = env;
      }
      Navigator.of(context).pop(CodexMcpAddRequest(name: name, config: config));
    } on FormatException catch (error) {
      setState(() => _error = error.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHttp = _transport == 'http';
    return AlertDialog(
      title: Text(_text('添加 MCP 服务器', 'Add MCP server')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('mcp_add_name_field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: _text('名称', 'Name')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('mcp_add_transport_field'),
              value: _transport,
              decoration: InputDecoration(
                labelText: _text('传输方式', 'Transport'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'stdio',
                  child: Text(_text('stdio 本地命令', 'stdio command')),
                ),
                DropdownMenuItem(
                  value: 'http',
                  child: Text(_text('HTTP(S) 服务', 'HTTP(S) server')),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _transport = value);
              },
            ),
            const SizedBox(height: 12),
            if (isHttp) ...[
              TextField(
                key: const ValueKey('mcp_add_url_field'),
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: _text('HTTP(S) 地址', 'HTTP(S) URL'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bearerTokenEnv,
                decoration: InputDecoration(
                  labelText: _text(
                    'Bearer token 环境变量（可选）',
                    'Bearer-token env var (optional)',
                  ),
                ),
              ),
            ] else ...[
              TextField(
                key: const ValueKey('mcp_add_command_field'),
                controller: _command,
                decoration: InputDecoration(
                  labelText: _text('启动命令', 'Launch command'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _args,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _text('参数（每行一个）', 'Arguments (one per line)'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _env,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _text(
                    '环境变量（每行 KEY=VALUE，可选）',
                    'Environment (KEY=VALUE per line, optional)',
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_text('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('mcp_add_confirm'),
          onPressed: _submit,
          child: Text(_text('添加', 'Add')),
        ),
      ],
    );
  }
}

class _CodexPluginMarketplaceAddDialog extends StatefulWidget {
  const _CodexPluginMarketplaceAddDialog();

  @override
  State<_CodexPluginMarketplaceAddDialog> createState() =>
      _CodexPluginMarketplaceAddDialogState();
}

class _CodexPluginMarketplaceAddDialogState
    extends State<_CodexPluginMarketplaceAddDialog> {
  final _source = TextEditingController();
  final _ref = TextEditingController();
  final _sparse = TextEditingController();
  String? _error;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  String _text(String zh, String en) => _zh ? zh : en;

  @override
  void dispose() {
    _source.dispose();
    _ref.dispose();
    _sparse.dispose();
    super.dispose();
  }

  void _submit() {
    final source = _source.text.trim();
    if (source.isEmpty || source.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      setState(
        () => _error = _text(
          '请输入 Git 或本地插件市场来源。',
          'Enter a Git or local plugin marketplace source.',
        ),
      );
      return;
    }
    final ref = _ref.text.trim();
    if (ref.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      setState(
        () =>
            _error = _text('ref 不能包含控制字符。', 'ref contains control characters.'),
      );
      return;
    }
    final sparsePaths = _sparse.text
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    Navigator.of(context).pop(
      CodexPluginMarketplaceAddRequest(
        source: source,
        refName: ref.isEmpty ? null : ref,
        sparsePaths: sparsePaths,
        jsonOutput: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_text('添加插件市场', 'Add plugin marketplace')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('marketplace_source_field'),
              controller: _source,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _text('来源', 'Source'),
                hintText: 'owner/repo 或 /path/to/marketplace',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('marketplace_ref_field'),
              controller: _ref,
              decoration: InputDecoration(
                labelText: _text('Git ref（可选）', 'Git ref (optional)'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('marketplace_sparse_field'),
              controller: _sparse,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _text(
                  '稀疏路径（每行一个，可选）',
                  'Sparse paths (one per line, optional)',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_text('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('marketplace_add_confirm'),
          onPressed: _submit,
          child: Text(_text('添加', 'Add')),
        ),
      ],
    );
  }
}
