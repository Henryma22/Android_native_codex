import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/application/codex_model_catalog.dart';
import 'core/domain/backend.dart';
import 'core/domain/runtime.dart';
import 'backends/compatibility/linux_compatibility_backend.dart';
import 'services/app_host_access_probe.dart';
import 'services/codex_cli_updater.dart';
import 'services/network_proxy_preference_store.dart';
import 'kernelsu_plugin_settings.dart';

String _modelCatalogErrorText(Object? error, {required bool zh}) {
  if (error is BackendException) {
    if (error.message == 'No cached CLI model catalog.') {
      return zh ? '点击读取 CLI 模型目录' : 'Tap to read the CLI model catalog';
    }
    return error.message;
  }
  final text = '$error'.replaceFirst('BackendException: ', '').trim();
  if (text.isEmpty || text == 'null') return zh ? '未知错误' : 'Unknown error';
  return text;
}

bool _isNoCachedModelCatalog(Object? error) =>
    error is BackendException &&
    error.message == 'No cached CLI model catalog.';

String _accessLabel(AppHostAccessResult access, bool zh) {
  return switch (access.state) {
    'available' => zh ? '可用' : 'Available',
    'missing' => zh ? '缺少' : 'Missing',
    'denied' => zh ? '应用 UID 受限' : 'App UID restricted',
    'failed' => zh ? '失败' : 'Failed',
    _ => zh ? '不可用' : 'Unavailable',
  };
}

/// The local settings surface keeps CC Pocket's sectioned-card information
/// architecture, while replacing remote-machine and multi-agent controls with
/// the single on-device Codex runtime that this app actually owns.
class CodexPocketSettingsPage extends StatefulWidget {
  const CodexPocketSettingsPage({
    required this.runtime,
    required this.onRefresh,
    this.compatibilityRuntime,
    this.compatibilityCliVersion,
    this.hostAccess,
    this.onInstallCompatibilityRootfs,
    this.onUpdateCompatibilityCodex,
    this.onRollbackCompatibilityCodex,
    this.onOpenHostAccessSettings,
    this.loginBuilder,
    this.loginRevision,
    this.modelCatalog,
    this.onRefreshModelCatalog,
    this.model = 'gpt-6-luna',
    this.effort = 'low',
    this.approvalPolicy = 'on-request',
    this.sandbox = 'workspace-write',
    this.themeMode = ThemeMode.system,
    this.locale,
    this.onThemeModeChanged,
    this.onLocaleChanged,
    this.onModelChanged,
    this.onEffortChanged,
    this.onApprovalPolicyChanged,
    this.onSandboxChanged,
    this.onOpenModelProviders,
    this.onOpenMcpSettings,
    super.key,
  });

  final Future<CodexRuntimeDescriptor> runtime;
  final Future<CodexRuntimeDescriptor> Function() onRefresh;
  final Future<CompatibilityRuntimeDescriptor>? compatibilityRuntime;
  final String? compatibilityCliVersion;
  final Future<AppHostAccessResult>? hostAccess;
  final Future<CompatibilityRuntimeDescriptor?> Function()?
  onInstallCompatibilityRootfs;
  final Future<CodexCliUpdateResult> Function()? onUpdateCompatibilityCodex;
  final Future<CodexCliUpdateResult> Function()? onRollbackCompatibilityCodex;
  final Future<void> Function()? onOpenHostAccessSettings;
  final WidgetBuilder? loginBuilder;
  final ValueListenable<int>? loginRevision;
  final Future<CodexModelCatalog>? modelCatalog;
  final Future<CodexModelCatalog> Function()? onRefreshModelCatalog;
  final String model;
  final String effort;
  final String approvalPolicy;
  final String sandbox;
  final ThemeMode themeMode;
  final Locale? locale;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<Locale?>? onLocaleChanged;
  final ValueChanged<String>? onModelChanged;
  final ValueChanged<String>? onEffortChanged;
  final ValueChanged<String>? onApprovalPolicyChanged;
  final ValueChanged<String>? onSandboxChanged;
  final Future<void> Function()? onOpenModelProviders;
  final Future<void> Function()? onOpenMcpSettings;

  @override
  State<CodexPocketSettingsPage> createState() =>
      _CodexPocketSettingsPageState();
}

class _CodexPocketSettingsPageState extends State<CodexPocketSettingsPage> {
  late Future<CodexRuntimeDescriptor> _runtime;
  Future<CompatibilityRuntimeDescriptor>? _compatibilityRuntime;
  String? _activeCompatibilityCliVersion;
  var _indentSize = 2;
  var _autoRenameSessions = true;
  var _showToolDetails = true;
  var _diffMode = _DiffMode.quickActions;
  late var _theme = _SettingsChoice.fromThemeMode(widget.themeMode);
  late var _language = _LanguageChoice.fromLocale(widget.locale);
  var _cliUpdateBusy = false;
  var _compatibilityRootfsInstallBusy = false;
  late var _model = widget.model;
  late var _effort = widget.effort;
  late var _approvalPolicy = widget.approvalPolicy;
  late var _sandbox = widget.sandbox;
  Future<CodexModelCatalog>? _modelCatalog;

  String _text(String zh, String en) =>
      _language == _LanguageChoice.english ? en : zh;

  String _settingValueLabel(String value, {required bool zh}) {
    return switch (value) {
      'none' => zh ? '无' : 'None',
      'minimal' => zh ? '最小' : 'Minimal',
      'low' => zh ? '低' : 'Low',
      'medium' => zh ? '中' : 'Medium',
      'high' => zh ? '高' : 'High',
      'xhigh' => zh ? '极高' : 'Extra high',
      'max' => zh ? '最大' : 'Maximum',
      'ultra' => zh ? '极致' : 'Ultra',
      'on-request' => zh ? '按需审批' : 'On request',
      'on-failure' => zh ? '失败时审批' : 'On failure',
      'never' => zh ? '从不审批' : 'Never',
      'workspace-write' => zh ? '工作区可写' : 'Workspace write',
      'read-only' => zh ? '只读' : 'Read only',
      'danger-full-access' => zh ? '完全访问' : 'Full access',
      _ => value,
    };
  }

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime;
    _compatibilityRuntime = widget.compatibilityRuntime;
    _activeCompatibilityCliVersion = widget.compatibilityCliVersion;
    _modelCatalog = widget.modelCatalog;
  }

  @override
  void didUpdateWidget(covariant CodexPocketSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _runtime = widget.runtime;
    }
    if (!identical(
      oldWidget.compatibilityRuntime,
      widget.compatibilityRuntime,
    )) {
      _compatibilityRuntime = widget.compatibilityRuntime;
    }
    if (oldWidget.compatibilityCliVersion != widget.compatibilityCliVersion) {
      _activeCompatibilityCliVersion = widget.compatibilityCliVersion;
    }
    if (!identical(oldWidget.modelCatalog, widget.modelCatalog)) {
      _modelCatalog = widget.modelCatalog;
    }
    _model = widget.model;
    _effort = widget.effort;
    _approvalPolicy = widget.approvalPolicy;
    _sandbox = widget.sandbox;
    _theme = _SettingsChoice.fromThemeMode(widget.themeMode);
    _language = _LanguageChoice.fromLocale(widget.locale);
  }

  Future<void> _refresh() async {
    final future = widget.onRefresh();
    setState(() {
      _runtime = future;
    });
    try {
      await _runtime;
    } catch (_) {
      // The runtime card renders the failure state. The settings surface stays
      // usable so the user can open the runtime diagnostics page.
    }
  }

  Future<void> _installCompatibilityRootfs() async {
    final install = widget.onInstallCompatibilityRootfs;
    if (install == null || _compatibilityRootfsInstallBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _text('安装或更新 Linux 兼容环境？', 'Install or update Linux compatibility?'),
        ),
        content: Text(
          _text(
            '选择包含 ARM64 rootfs 压缩包和对应 manifest 的文件夹。应用会通过当前 KernelSU profile 安装并验证；已有会话数据和 guest home 会保留。安装期间不会停止运行中的 Codex 会话，更新只影响之后启动的新会话。',
            'Choose a folder containing the ARM64 rootfs archive and its matching manifest. The app installs and verifies it through the current KernelSU profile, preserving guest home and session data. Running Codex sessions continue on their existing runtime; the update applies to new sessions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_text('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_text('选择文件夹', 'Choose folder')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _compatibilityRootfsInstallBusy = true);
    try {
      final runtime = await install();
      if (!mounted || runtime == null) return;
      setState(() {
        _compatibilityRuntime = Future<CompatibilityRuntimeDescriptor>.value(
          runtime,
        );
        _activeCompatibilityCliVersion = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Linux/PRoot 环境已安装并通过设备验证。',
              'Linux/PRoot runtime installed and verified on this device.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _compatibilityRuntime = Future<CompatibilityRuntimeDescriptor>.value(
          CompatibilityRuntimeDescriptor(
            state: CompatibilityRuntimeState.failed,
            version: null,
            reason: '$error',
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('兼容环境安装失败：$error', 'Runtime install failed: $error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _compatibilityRootfsInstallBusy = false);
    }
  }

  Future<void> _updateCompatibilityCodex() async {
    final update = widget.onUpdateCompatibilityCodex;
    if (update == null || _cliUpdateBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('更新 Codex CLI？', 'Update Codex CLI?')),
        content: Text(
          _text(
            '从 npm 官方源更新应用私有 Linux/PRoot 环境中的 CLI。旧版本会保留；更新不会替换运行中的 session，新版本从之后启动的 session 生效。',
            'Updates the CLI in the app-private Linux/PRoot environment from the official npm registry. The previous version is retained; running sessions are unchanged and new sessions use the selected version.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_text('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_text('检查并更新', 'Check and update')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _cliUpdateBusy = true);
    try {
      final result = await update();
      if (!mounted) return;
      setState(() => _activeCompatibilityCliVersion = result.installedVersion);
      var modelRefreshFailed = false;
      final refreshModels = widget.onRefreshModelCatalog;
      if (result.updated && refreshModels != null) {
        final refreshedCatalog = refreshModels();
        setState(() {
          _modelCatalog = refreshedCatalog;
        });
        try {
          await refreshedCatalog;
        } on Object {
          modelRefreshFailed = true;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.updated
                ? _text(
                    'Codex CLI 已更新至 ${result.installedVersion}；新会话将使用该版本${modelRefreshFailed ? '；模型列表刷新失败，可点“模型”重试' : '，模型列表已刷新'}',
                    'Codex CLI updated to ${result.installedVersion}; new sessions will use it${modelRefreshFailed ? '; model list refresh failed—tap Model to retry' : '; model list refreshed'}',
                  )
                : _text(
                    'Codex CLI 已是最新版本 ${result.installedVersion}',
                    'Codex CLI is already up to date (${result.installedVersion})',
                  ),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is BackendException ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('更新失败：$message', 'Update failed: $message')),
        ),
      );
    } finally {
      if (mounted) setState(() => _cliUpdateBusy = false);
    }
  }

  Future<void> _rollbackCompatibilityCodex() async {
    final rollback = widget.onRollbackCompatibilityCodex;
    if (rollback == null || _cliUpdateBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text('回退 Codex CLI？', 'Roll back Codex CLI?')),
        content: Text(
          _text(
            '切换到当前版本之前最近的可用版本；如果没有保留的旧 overlay，则恢复 rootfs 自带版本。只影响之后新启动的会话，正在运行的会话不会被终止或切换。',
            'Switches to the newest available version older than the current one, or to the CLI bundled in the rootfs if no older overlay is retained. Only future sessions are affected; running sessions are not stopped or switched.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_text('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_text('确认回退', 'Roll back')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _cliUpdateBusy = true);
    try {
      final result = await rollback();
      if (!mounted) return;
      setState(() => _activeCompatibilityCliVersion = result.installedVersion);
      final refreshModels = widget.onRefreshModelCatalog;
      var modelRefreshFailed = false;
      if (result.updated && refreshModels != null) {
        final refreshedCatalog = refreshModels();
        setState(() {
          _modelCatalog = refreshedCatalog;
        });
        try {
          await refreshedCatalog;
        } on Object {
          modelRefreshFailed = true;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Codex CLI 已回退至 ${result.installedVersion}${modelRefreshFailed ? '；模型列表刷新失败，可点“模型”重试' : '；仅影响之后启动的会话'}',
              'Codex CLI rolled back to ${result.installedVersion}${modelRefreshFailed ? '; model list refresh failed—tap Model to retry' : '; future sessions only'}',
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is BackendException ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('回退失败：$message', 'Rollback failed: $message')),
        ),
      );
    } finally {
      if (mounted) setState(() => _cliUpdateBusy = false);
    }
  }

  Future<void> _selectRuntimeSetting({
    required String title,
    required String settingKey,
    required List<String> values,
    required String current,
    required ValueChanged<String>? onChanged,
  }) async {
    await _selectChoice(
      title: title,
      values: values,
      current: current,
      displayValue: (value) =>
          _settingValueLabel(value, zh: _language != _LanguageChoice.english),
      onChanged: (value) {
        onChanged?.call(value);
        setState(() {
          if (settingKey == 'model') _model = value;
          if (settingKey == 'effort') _effort = value;
          if (settingKey == 'approval') _approvalPolicy = value;
          if (settingKey == 'sandbox') _sandbox = value;
        });
      },
    );
  }

  void _handleModelChanged(String value, CodexModelCatalog? catalog) {
    widget.onModelChanged?.call(value);
    final descriptor = catalog?.models.cast<CodexModelDescriptor?>().firstWhere(
      (candidate) => candidate?.id == value,
      orElse: () => null,
    );
    final efforts = descriptor?.reasoningEfforts ?? const <String>[];
    final nextEffort = efforts.contains(_effort)
        ? _effort
        : efforts.isEmpty
        ? _effort
        : efforts.first;
    if (nextEffort != _effort) {
      _effort = nextEffort;
      widget.onEffortChanged?.call(nextEffort);
    }
  }

  Widget _buildLoginSection(BuildContext context) {
    final builder = widget.loginBuilder;
    if (builder == null) return const SizedBox.shrink();
    final revision = widget.loginRevision;
    final card = revision == null
        ? builder(context)
        : ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, _, _) => builder(context),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: _text('Codex 登录', 'Codex login')),
        card,
      ],
    );
  }

  Widget _buildCodexSettingsCard(BuildContext context, ColorScheme cs) {
    final zh = _language != _LanguageChoice.english;
    return FutureBuilder<CodexModelCatalog>(
      future: _modelCatalog,
      builder: (context, snapshot) {
        final catalog = snapshot.data;
        final models = <String>[
          if (catalog != null) ...catalog.modelIds,
          if (catalog == null || !catalog.modelIds.contains(_model)) _model,
        ];
        final modelSubtitle = catalog != null
            ? '$_model · ${catalog.models.length} ${_text('个 CLI 模型', 'CLI models')}'
            : snapshot.hasError
            ? '$_model · ${_modelCatalogErrorText(snapshot.error, zh: zh)}${_isNoCachedModelCatalog(snapshot.error) ? '' : _text('，点击重试', ', tap to retry')}'
            : snapshot.connectionState == ConnectionState.waiting
            ? '$_model · ${_text('正在读取 CLI 模型目录…', 'Reading the CLI model catalog…')}'
            : '$_model · ${_text('点击读取 CLI 模型目录', 'Tap to read the CLI model catalog')}';
        return _SettingsCard(
          children: [
            ListTile(
              key: const ValueKey('settings_model_tile'),
              leading: Icon(Icons.model_training_outlined, color: cs.primary),
              title: Text(_text('新会话默认模型', 'New-session default model')),
              subtitle: Text(modelSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (catalog == null && widget.onRefreshModelCatalog != null) {
                  final future = snapshot.hasError || _modelCatalog == null
                      ? widget.onRefreshModelCatalog!()
                      : _modelCatalog!;
                  setState(() {
                    _modelCatalog = future;
                  });
                  try {
                    final loaded = await future;
                    if (!mounted) return;
                    await _selectRuntimeSetting(
                      title: _text('新会话默认模型', 'New-session default model'),
                      settingKey: 'model',
                      values: loaded.modelIds,
                      current: _model,
                      onChanged: (value) => _handleModelChanged(value, loaded),
                    );
                  } catch (_) {
                    // The FutureBuilder renders the retryable failure state.
                  }
                  return;
                }
                await _selectRuntimeSetting(
                  title: _text('新会话默认模型', 'New-session default model'),
                  settingKey: 'model',
                  values: models,
                  current: _model,
                  onChanged: (value) => _handleModelChanged(value, catalog),
                );
              },
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.speed_outlined, color: cs.primary),
              title: Text(_text('新会话默认推理档位', 'New-session default effort')),
              subtitle: Text(
                _settingValueLabel(
                  _effort,
                  zh: _language != _LanguageChoice.english,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final modelDescriptor = catalog?.models
                    .where((candidate) => candidate.id == _model)
                    .firstOrNull;
                final catalogEfforts = modelDescriptor?.reasoningEfforts;
                final values =
                    catalogEfforts != null && catalogEfforts.isNotEmpty
                    ? <String>{...catalogEfforts, _effort}.toList()
                    : <String>{
                        'minimal',
                        'low',
                        'medium',
                        'high',
                        'xhigh',
                        _effort,
                      }.toList();
                unawaited(
                  _selectRuntimeSetting(
                    title: _text('推理档位', 'Reasoning effort'),
                    settingKey: 'effort',
                    values: values,
                    current: _effort,
                    onChanged: widget.onEffortChanged,
                  ),
                );
              },
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.shield_outlined, color: cs.primary),
              title: Text(_text('新会话默认审批策略', 'New-session default approval')),
              subtitle: Text(
                _settingValueLabel(
                  _approvalPolicy,
                  zh: _language != _LanguageChoice.english,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectRuntimeSetting(
                title: _text('审批策略', 'Approval policy'),
                settingKey: 'approval',
                values: const ['on-request', 'on-failure', 'never'],
                current: _approvalPolicy,
                onChanged: widget.onApprovalPolicyChanged,
              ),
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.shield_outlined, color: cs.primary),
              title: Text(_text('新会话默认沙盒', 'New-session default sandbox')),
              subtitle: Text(
                _settingValueLabel(
                  _sandbox,
                  zh: _language != _LanguageChoice.english,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectRuntimeSetting(
                title: _text('沙盒', 'Sandbox'),
                settingKey: 'sandbox',
                values: const [
                  'danger-full-access',
                  'workspace-write',
                  'read-only',
                ],
                current: _sandbox,
                onChanged: widget.onSandboxChanged,
              ),
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              key: const ValueKey('settings_model_provider_tile'),
              leading: Icon(Icons.alt_route_outlined, color: cs.primary),
              title: Text(_text('模型来源', 'Model source')),
              subtitle: Text(
                _text(
                  '选择 OpenAI 订阅或第三方 API；第三方服务商配置位于下一层',
                  'Choose OpenAI subscription or a third-party API; provider settings are nested one level below',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onOpenModelProviders == null
                  ? null
                  : () => unawaited(widget.onOpenModelProviders!()),
            ),
            if (widget.onOpenMcpSettings != null) ...[
              _Divider(color: cs.outlineVariant),
              ListTile(
                key: const ValueKey('settings_mcp_tile'),
                leading: Icon(Icons.extension_outlined, color: cs.primary),
                title: Text(_text('MCP 与插件', 'MCP & plugins')),
                subtitle: Text(
                  _text(
                    '管理当前 session 的 MCP 服务并查看实时连接状态',
                    'Manage MCP servers and live connection status for this session',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(widget.onOpenMcpSettings!()),
              ),
            ],
            _Divider(color: cs.outlineVariant),
            SwitchListTile(
              key: const ValueKey('settings_auto_rename_toggle'),
              secondary: Icon(
                Icons.drive_file_rename_outline,
                color: cs.primary,
              ),
              title: Text(_text('自动命名 Codex 会话', 'Auto-name Codex sessions')),
              subtitle: Text(
                _text(
                  '首个智能体回复后使用会话标题更新列表',
                  'Update the list after the first assistant reply',
                ),
              ),
              value: _autoRenameSessions,
              onChanged: (value) => setState(() => _autoRenameSessions = value),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectChoice({
    required String title,
    required List<String> values,
    required String current,
    required ValueChanged<String> onChanged,
    String Function(String value)? displayValue,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final value in values)
              ListTile(
                title: Text(displayValue?.call(value) ?? value),
                trailing: value == current
                    ? const Icon(Icons.check)
                    : const SizedBox(width: 24),
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    onChanged(selected);
  }

  Widget _buildRuntimeSection(BuildContext context, ColorScheme cs, bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSectionHeader(title: zh ? '设备与运行时' : 'Device & runtime'),
        _SettingsCard(
          children: [
            ListTile(
              key: const ValueKey('settings_runtime_tile'),
              leading: Icon(Icons.memory_outlined, color: cs.primary),
              title: Text(zh ? 'Codex 运行环境' : 'Codex runtime'),
              subtitle: Text(
                zh
                    ? 'Codex CLI 与 app-server 在本机 Linux/PRoot 中运行；git、Node.js、npm、npx 和 Python 使用 Debian guest 工具。Android 系统命令由 Root 会话直接调用宿主。'
                    : 'Codex CLI and app-server run in local Linux/PRoot; git, Node.js, npm, npx and Python come from the Debian guest. Root sessions call Android host commands directly.',
              ),
            ),
            if (widget.onInstallCompatibilityRootfs != null) ...[
              _Divider(color: cs.outlineVariant),
              FutureBuilder<CompatibilityRuntimeDescriptor>(
                future: _compatibilityRuntime,
                builder: (context, snapshot) {
                  final runtime = snapshot.data;
                  final stateLabel = runtime == null
                      ? _text(
                          '正在检查 Linux/PRoot 环境…',
                          'Checking Linux/PRoot runtime…',
                        )
                      : switch (runtime.state) {
                          CompatibilityRuntimeState.missing => _text(
                            '未安装',
                            'Not installed',
                          ),
                          CompatibilityRuntimeState.available => _text(
                            '待验证',
                            'Needs verification',
                          ),
                          CompatibilityRuntimeState.verified => _text(
                            '已验证',
                            'Verified',
                          ),
                          CompatibilityRuntimeState.failed => _text(
                            '检查失败',
                            'Probe failed',
                          ),
                        };
                  final version = runtime?.version;
                  final activeCliVersion = _activeCompatibilityCliVersion;
                  final versionSummary = <String>[
                    if (version != null) version,
                    if (activeCliVersion != null)
                      _text(
                        '活动 CLI $activeCliVersion',
                        'active CLI $activeCliVersion',
                      ),
                  ].join(' · ');
                  final reason = runtime == null
                      ? null
                      : switch (runtime.state) {
                          CompatibilityRuntimeState.missing => _text(
                            '尚未安装 Linux ARM64 rootfs。',
                            'No Linux ARM64 rootfs is installed.',
                          ),
                          CompatibilityRuntimeState.available => _text(
                            'PRoot 已就绪；安装 rootfs 后才能运行会话。',
                            'PRoot is ready; install a rootfs before running sessions.',
                          ),
                          CompatibilityRuntimeState.verified => _text(
                            'ARM64 rootfs 与设备侧 PRoot 探测均已通过。',
                            'ARM64 rootfs and on-device PRoot probe both passed.',
                          ),
                          CompatibilityRuntimeState.failed => runtime.reason,
                        };
                  return ListTile(
                    key: const ValueKey(
                      'settings_compatibility_rootfs_install',
                    ),
                    leading: _compatibilityRootfsInstallBusy
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : Icon(Icons.terminal, color: cs.primary),
                    title: Text(
                      _text('Linux/PRoot 兼容环境', 'Linux/PRoot compatibility'),
                    ),
                    subtitle: Text(
                      [
                        if (version != null)
                          '$stateLabel · $versionSummary'
                        else
                          stateLabel,
                        if (reason != null && reason.isNotEmpty) reason,
                        _text(
                          '从本地 ARM64 rootfs 与 manifest 安装或更新，保留 guest home',
                          'Install/update from a local ARM64 rootfs and manifest; guest home is preserved',
                        ),
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _compatibilityRootfsInstallBusy
                        ? null
                        : _installCompatibilityRootfs,
                  );
                },
              ),
            ],
            if (widget.onUpdateCompatibilityCodex != null) ...[
              _Divider(color: cs.outlineVariant),
              ListTile(
                key: const ValueKey('settings_codex_cli_update'),
                leading: _cliUpdateBusy
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Icon(Icons.system_update_alt, color: cs.primary),
                title: Text(_text('更新 Codex 命令行工具', 'Update Codex CLI')),
                subtitle: Text(
                  _text(
                    '仅更新应用私有 Linux/PRoot 环境中的 CLI；新会话生效，运行中 session 不会被替换',
                    'Updates only the app-private Linux/PRoot CLI; new sessions use it and running sessions are not replaced',
                  ),
                ),
                onTap: _cliUpdateBusy ? null : _updateCompatibilityCodex,
              ),
            ],
            if (widget.onRollbackCompatibilityCodex != null) ...[
              _Divider(color: cs.outlineVariant),
              ListTile(
                key: const ValueKey('settings_codex_cli_rollback'),
                leading: _cliUpdateBusy
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Icon(Icons.restore_outlined, color: cs.primary),
                title: Text(_text('回退 Codex 命令行工具', 'Roll back Codex CLI')),
                subtitle: Text(
                  _text(
                    '切换到保留的旧版本或 rootfs 自带版本；仅影响新会话',
                    'Switch to a retained older version or the rootfs CLI; future sessions only',
                  ),
                ),
                onTap: _cliUpdateBusy ? null : _rollbackCompatibilityCodex,
              ),
            ],
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.account_tree_outlined, color: cs.primary),
              title: Text(zh ? '执行策略' : 'Execution strategy'),
              subtitle: Text(
                zh ? '新会话默认使用 Root + 本机 Linux/PRoot Codex；可按会话切换到 App UID。' : 'New sessions use Root + local Linux/PRoot Codex by default; switch to App UID per session when needed.',
              ),
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              key: const ValueKey('settings_runtime_refresh'),
              leading: Icon(Icons.refresh, color: cs.primary),
              title: Text(zh ? '刷新本地能力' : 'Refresh local capabilities'),
              subtitle: Text(
                zh
                    ? '重新检查 Linux/PRoot、工作区与设备能力'
                    : 'Recheck Linux/PRoot, workspace, and device capabilities',
              ),
              onTap: () => unawaited(_refresh()),
            ),
            if (widget.hostAccess != null) ...[
              _Divider(color: cs.outlineVariant),
              FutureBuilder<AppHostAccessResult>(
                future: widget.hostAccess,
                builder: (context, snapshot) {
                  final access = snapshot.data;
                  return ListTile(
                    key: const ValueKey('settings_host_access_tile'),
                    leading: Icon(Icons.folder_outlined, color: cs.primary),
                    title: Text(zh ? '工作区存储' : 'Workspace storage'),
                    subtitle: Text(
                      access == null
                          ? (zh ? '检查中…' : 'Checking…')
                          : '${_accessLabel(access, zh)} · ${access.path}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: widget.onOpenHostAccessSettings,
                  );
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCodexSection(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: 'CODEX'),
        _buildCodexSettingsCard(context, cs),
      ],
    );
  }

  Widget _buildGeneralSection(BuildContext context, ColorScheme cs, bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: zh ? '通用' : 'General'),
        _SettingsCard(
          children: [
            ListTile(
              leading: Icon(Icons.palette_outlined, color: cs.primary),
              title: Text(zh ? '主题' : 'Theme'),
              subtitle: Text(_theme.label(zh)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectChoice(
                title: zh ? '主题' : 'Theme',
                values: _SettingsChoice.values.map((e) => e.label(zh)).toList(),
                current: _theme.label(zh),
                onChanged: (value) {
                  final selected = _SettingsChoice.values.firstWhere(
                    (choice) => choice.label(zh) == value,
                  );
                  setState(() => _theme = selected);
                  widget.onThemeModeChanged?.call(selected.themeMode);
                },
              ),
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.language_outlined, color: cs.primary),
              title: Text(zh ? '语言' : 'Language'),
              subtitle: Text(_language.label(zh)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectChoice(
                title: zh ? '语言' : 'Language',
                values: _LanguageChoice.values
                    .map((choice) => choice.label(zh))
                    .toList(),
                current: _language.label(zh),
                onChanged: (value) {
                  final selected = _LanguageChoice.values.firstWhere(
                    (choice) => choice.label(zh) == value,
                  );
                  setState(() => _language = selected);
                  widget.onLocaleChanged?.call(selected.locale);
                },
              ),
            ),
            _Divider(color: cs.outlineVariant),
            SwitchListTile(
              secondary: Icon(Icons.visibility_outlined, color: cs.primary),
              title: Text(zh ? '显示工具调用详情' : 'Show tool details'),
              subtitle: Text(
                zh
                    ? '在会话中保留命令、审批与差异内容的展开状态'
                    : 'Keep commands, approvals, and diffs visible in sessions',
              ),
              value: _showToolDetails,
              onChanged: (value) => setState(() => _showToolDetails = value),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditorSection(BuildContext context, ColorScheme cs, bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: zh ? '编辑器' : 'Editor'),
        _SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      zh ? '缩进大小' : 'Indent size',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  SegmentedButton<int>(
                    key: const ValueKey('settings_indent_size_segment'),
                    segments: [
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: {_indentSize},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _indentSize = selection.single),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            _Divider(color: cs.outlineVariant),
            ListTile(
              leading: Icon(Icons.code, color: cs.primary),
              title: Text(zh ? '代码字体' : 'Code font'),
              subtitle: Text(_text('等宽字体 · 12 磅', 'Monospace · 12pt')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showInfo(
                zh ? '代码字体' : 'Code font',
                zh
                    ? '当前使用 Android 可用的 monospace 字体。'
                    : 'Uses the Android-compatible monospace font.',
              ),
            ),
            _Divider(color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    zh ? 'Diff 交互' : 'Diff interaction',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<_DiffMode>(
                    key: const ValueKey('settings_diff_mode_segment'),
                    segments: [
                      ButtonSegment(
                        value: _DiffMode.quickActions,
                        label: Text(zh ? '快捷操作' : 'Quick actions'),
                      ),
                      ButtonSegment(
                        value: _DiffMode.scrollFirst,
                        label: Text(zh ? '先滚动' : 'Scroll first'),
                      ),
                    ],
                    selected: {_diffMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _diffMode = selection.single),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRootSection(bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: _text('Root 能力', 'Root capabilities')),
        KernelSuPluginSettingsSection(zh: zh),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context, bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: zh ? '关于' : 'About'),
        _SettingsCard(
          children: [
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: Text(_text('Android 版 Codex', 'Codex for Android')),
              subtitle: Text(
                zh ? '本地运行 · 复用 CC Pocket 会话界面 · Root 优先使用已验证的 Linux/PRoot' : 'Local runtime · CC Pocket session UI · Root prefers verified Linux/PRoot',
              ),
            ),
            _Divider(color: Theme.of(context).colorScheme.outlineVariant),
            ListTile(
              leading: Icon(
                Icons.verified_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(zh ? '前端来源' : 'Frontend source'),
              subtitle: Text(
                zh ? 'CC Pocket 会话列表、输入栏、工具调用、审批与差异查看组件' : 'CC Pocket session list, composer, tool call, approval, and diff components',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkSection(bool zh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SettingsSectionHeader(title: zh ? '网络连接' : 'Network'),
        _NetworkProxySettingsCard(zh: zh),
      ],
    );
  }

  Widget _buildFooterSection(bool zh, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Text(
          zh ? 'Codex · 本地 Android' : 'Codex · local Android',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = _language != _LanguageChoice.english;
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '设置' : 'Settings')),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView.builder(
          key: const ValueKey('codex_settings_scroll'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: 9,
          itemBuilder: (context, index) => switch (index) {
            0 => _buildRuntimeSection(context, cs, zh),
            1 => _buildLoginSection(context),
            2 => _buildCodexSection(context, cs),
            3 => _buildGeneralSection(context, cs, zh),
            4 => _buildEditorSection(context, cs, zh),
            5 => _buildRootSection(zh),
            6 => _buildAboutSection(context, zh),
            7 => _buildNetworkSection(zh),
            8 => _buildFooterSection(zh, cs),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Future<void> _showInfo(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_text('知道了', 'Got it')),
          ),
        ],
      ),
    );
  }
}

class _NetworkProxySettingsCard extends StatefulWidget {
  const _NetworkProxySettingsCard({required this.zh});

  final bool zh;

  @override
  State<_NetworkProxySettingsCard> createState() =>
      _NetworkProxySettingsCardState();
}

class _NetworkProxySettingsCardState extends State<_NetworkProxySettingsCard> {
  final _store = NetworkProxyPreferenceStore();
  late final TextEditingController _controller;
  var _loading = true;
  var _saving = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final endpoint = await _store.loadEndpoint();
      if (!mounted) return;
      _controller.text = endpoint;
      setState(() => _loading = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = widget.zh ? '读取代理设置失败' : 'Could not read proxy settings';
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final endpoint = _controller.text.trim();
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _store.saveEndpoint(endpoint);
      if (!mounted) return;
      setState(() {
        _status = endpoint.isEmpty
            ? (widget.zh
                  ? '已清除自定义代理，将自动探测 Android 系统代理。'
                  : 'Custom proxy cleared; Android system proxy auto-detection is enabled.')
            : (widget.zh
                  ? '已保存；仅对新启动的本地会话生效。'
                  : 'Saved; applies to newly started local sessions only.');
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.code == 'invalid_http_proxy_endpoint'
            ? (widget.zh
                  ? '格式无效。请输入 HTTP 代理 host:port；IPv6 请写成 [地址]:端口。'
                  : 'Invalid format. Enter HTTP proxy host:port, or [IPv6]:port.')
            : (widget.zh
                  ? '保存代理设置失败：${error.message ?? error.code}'
                  : 'Could not save proxy settings: ${error.message ?? error.code}');
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = widget.zh ? '保存失败：$error' : 'Save failed: $error';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.zh
                    ? 'Root/PRoot 进程可能不继承 VPN 应用的按 UID 路由。若 VPN 提供本地 HTTP 或 Mixed 端口，可在此填写；不要填 SOCKS 端口。'
                    : 'Root/PRoot processes may not inherit per-UID VPN routing. Enter your VPN app’s local HTTP or mixed port here; do not use a SOCKS-only port.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('network_http_proxy_endpoint'),
                controller: _controller,
                enabled: !_loading && !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                decoration: InputDecoration(
                  labelText: widget.zh
                      ? '自定义 HTTP 代理（可选）'
                      : 'Custom HTTP proxy (optional)',
                  hintText: '127.0.0.1:7890',
                  helperText: widget.zh
                      ? '留空使用 Android 自动探测；支持 host:port 或 [IPv6]:port。'
                      : 'Leave empty for Android auto-detection; accepts host:port or [IPv6]:port.',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(
                  _status!,
                  key: const ValueKey('network_http_proxy_status'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('network_http_proxy_auto'),
                      onPressed: _loading || _saving
                          ? null
                          : () {
                              _controller.clear();
                              unawaited(_save());
                            },
                      child: Text(widget.zh ? '自动检测' : 'Auto-detect'),
                    ),
                    FilledButton.tonal(
                      key: const ValueKey('network_http_proxy_save'),
                      onPressed: _loading || _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.zh ? '保存代理' : 'Save proxy'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme(
        data: ListTileTheme.of(context).copyWith(
          dense: true,
          minVerticalPadding: 4,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, indent: 16, endIndent: 16, color: color);
  }
}

enum _DiffMode { quickActions, scrollFirst }

enum _SettingsChoice {
  system,
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
    _SettingsChoice.system => ThemeMode.system,
    _SettingsChoice.light => ThemeMode.light,
    _SettingsChoice.dark => ThemeMode.dark,
  };

  String label(bool zh) => switch (this) {
    _SettingsChoice.system => zh ? '跟随系统' : 'System default',
    _SettingsChoice.light => zh ? '浅色' : 'Light',
    _SettingsChoice.dark => zh ? '深色' : 'Dark',
  };

  static _SettingsChoice fromThemeMode(ThemeMode value) => switch (value) {
    ThemeMode.light => _SettingsChoice.light,
    ThemeMode.dark => _SettingsChoice.dark,
    ThemeMode.system => _SettingsChoice.system,
  };
}

enum _LanguageChoice {
  system,
  chinese,
  english;

  Locale? get locale => switch (this) {
    _LanguageChoice.system => null,
    _LanguageChoice.chinese => const Locale('zh'),
    _LanguageChoice.english => const Locale('en'),
  };

  String label(bool zh) => switch (this) {
    _LanguageChoice.system => zh ? '跟随系统' : 'System default',
    _LanguageChoice.chinese => '简体中文',
    _LanguageChoice.english => 'English',
  };

  static _LanguageChoice fromLocale(Locale? value) =>
      switch (value?.languageCode) {
        'zh' => _LanguageChoice.chinese,
        'en' => _LanguageChoice.english,
        _ => _LanguageChoice.system,
      };
}
