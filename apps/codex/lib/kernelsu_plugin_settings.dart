import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/root_profile_probe.dart';
import 'services/kernelsu_plugin_service.dart';

/// Settings-only control surface for reviewed KernelSU plugin archives.
///
/// The thread surface never exposes this flow. A plugin is first staged and
/// risk-classified, then an explicit settings action applies it. R3/R4 modules
/// are installed disabled. Boot-sensitive R4 actions require a separate
/// details-bearing confirmation, but are not permanently denied.
class KernelSuPluginSettingsSection extends StatefulWidget {
  const KernelSuPluginSettingsSection({required this.zh, super.key});

  final bool zh;

  @override
  State<KernelSuPluginSettingsSection> createState() =>
      _KernelSuPluginSettingsSectionState();
}

class _KernelSuPluginSettingsSectionState
    extends State<KernelSuPluginSettingsSection> {
  final _service = const KernelSuPluginService();
  final _rootProfileProbe = const RootProfileProbe();
  KernelSuCapability _capability = const KernelSuCapability(
    available: false,
    state: 'not_checked',
  );
  KernelSuPluginStage? _stage;
  RootProfileProbeResult? _profileProbe;
  List<KernelSuPluginModule> _installedModules = const <KernelSuPluginModule>[];
  bool _moduleInstalled = false;
  bool _moduleEnabled = false;
  bool _moduleDisabled = false;
  bool _capabilityBusy = false;
  bool _profileProbeBusy = false;
  bool _moduleListBusy = false;
  bool _busy = false;
  String? _message;

  bool get _zh => widget.zh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_restoreStagedArchive());
    });
  }

  Future<void> _restoreStagedArchive() async {
    try {
      final stage = await _service.restoreStage();
      if (!mounted || stage == null || _stage != null) return;
      setState(() {
        _stage = stage;
        _message = _zh ? '已恢复上次校验的插件归档；请刷新已安装模块以读取当前状态' : 'Restored the last verified plugin archive; refresh installed modules to read its current state';
      });
    } catch (error) {
      // A missing or invalid staged archive is not a settings-page failure.
      // The explicit import action remains available.
      if (mounted && _stage == null) {
        setState(() => _message = _errorText(error));
      }
    }
  }

  @override
  void didUpdateWidget(covariant KernelSuPluginSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zh != widget.zh) setState(() {});
  }

  Future<void> _refreshCapability() async {
    if (_busy || _capabilityBusy) return;
    setState(() {
      _capabilityBusy = true;
      _message = null;
    });
    try {
      final capability = await _service.probe();
      if (!mounted) return;
      setState(() {
        _capability = capability;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _capability = const KernelSuCapability(
          available: false,
          state: 'unavailable',
        );
        _message = _errorText(error);
      });
    } finally {
      if (mounted) setState(() => _capabilityBusy = false);
    }
  }

  Future<void> _pickAndStage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final archive = await _service.pickArchive();
      if (archive == null) return;
      final stage = await _service.stage(
        requestId: 'codex-${DateTime.now().microsecondsSinceEpoch}',
        archive: archive,
      );
      if (!mounted) return;
      setState(() {
        _stage = stage;
        _moduleInstalled = false;
        _moduleEnabled = false;
        _moduleDisabled = false;
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _probeRootProfile() async {
    if (_busy || _profileProbeBusy) return;
    setState(() => _profileProbeBusy = true);
    try {
      final result = await _rootProfileProbe.run();
      if (mounted) setState(() => _profileProbe = result);
    } finally {
      if (mounted) setState(() => _profileProbeBusy = false);
    }
  }

  Future<void> _refreshInstalledModules() async {
    if (_busy || _moduleListBusy) return;
    setState(() {
      _moduleListBusy = true;
      _message = null;
    });
    try {
      final operation = await _service.list();
      if (!mounted) return;
      final modules = operation.modules;
      final stage = _stage;
      final current = stage == null
          ? null
          : modules.where((module) => module.id == stage.moduleId).firstOrNull;
      setState(() {
        _installedModules = modules;
        if (stage != null) {
          _moduleInstalled = current != null;
          _moduleEnabled = current?.enabled == true;
          _moduleDisabled = current != null && !current.enabled;
        }
        _message = _zh
            ? '已读取 ${modules.length} 个 KernelSU 模块'
            : 'Read ${modules.length} KernelSU module(s)';
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _moduleListBusy = false);
    }
  }

  Future<void> _apply({required bool approval}) async {
    final stage = _stage;
    if (_busy || stage == null) return;
    if (stage.effectiveRisk == 'R4' &&
        !await _confirmR4Operation(stage, enabling: false)) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final operation = await _service.install(
        stage,
        confirmation: approval ? 'user' : 'none',
      );
      if (!mounted) return;
      setState(() {
        _moduleInstalled =
            operation.operations.contains('install') || _moduleInstalled;
        _moduleEnabled = operation.operations.contains('enable');
        _moduleDisabled = operation.operations.contains('disable');
        _message = stage.requiresExplicitEnable && _moduleDisabled
            ? (_zh
                  ? '已安装为禁用状态；核对影响后可单独启用'
                  : 'Installed disabled; review the impact before enabling')
            : _zh
            ? '已完成：${operation.operations.join('、')}'
            : 'Completed: ${operation.operations.join(', ')}';
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableHighRiskModule() async {
    final stage = _stage;
    if (_busy || stage == null || !_moduleInstalled || !_moduleDisabled) {
      return;
    }
    if (stage.effectiveRisk == 'R4' &&
        !await _confirmR4Operation(stage, enabling: true)) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final operation = await _service.enable(
        stage,
        confirmation: stage.effectiveRisk == 'R4' ? 'user' : 'none',
      );
      if (!mounted) return;
      setState(() {
        _moduleInstalled = true;
        _moduleEnabled = true;
        _moduleDisabled = false;
        final reboot = stage.requiresReboot
            ? (_zh ? '；按模块要求重启后生效' : '; reboot as requested by the module')
            : '';
        _message = stage.effectiveRisk == 'R4'
            ? (_zh
                  ? '已在明确确认后启用：${operation.moduleId}$reboot'
                  : 'Enabled after explicit review: ${operation.moduleId}$reboot')
            : _zh
            ? '已通过设备凭据启用：${operation.moduleId}$reboot'
            : 'Enabled after device-credential confirmation: ${operation.moduleId}$reboot';
      });
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableModule() async {
    final stage = _stage;
    if (_busy || stage == null || !_moduleInstalled || !_moduleEnabled) return;
    await _runModuleOperation(
      () => _service.disable(stage),
      onSuccess: (operation) {
        _moduleInstalled = true;
        _moduleEnabled = false;
        _moduleDisabled = true;
        return _zh
            ? '已禁用：${operation.moduleId}'
            : 'Disabled: ${operation.moduleId}';
      },
    );
  }

  Future<void> _uninstallModule() async {
    final stage = _stage;
    if (_busy || stage == null || !_moduleInstalled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_zh ? '卸载 KernelSU 插件？' : 'Uninstall KernelSU plugin?'),
        content: Text(
          _zh
              ? '这会从 KernelSU 中移除 ${stage.moduleId}，但不会删除当前已校验的本地回滚归档。'
              : 'This removes ${stage.moduleId} from KernelSU but keeps the verified local rollback archive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            key: const ValueKey('kernelsu_uninstall_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_zh ? '卸载' : 'Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runModuleOperation(
      () => _service.uninstall(stage),
      onSuccess: (operation) {
        _moduleInstalled = false;
        _moduleEnabled = false;
        _moduleDisabled = false;
        return _zh
            ? '已卸载：${operation.moduleId}'
            : 'Uninstalled: ${operation.moduleId}';
      },
    );
  }

  Future<void> _rollbackModule() async {
    final stage = _stage;
    if (_busy || stage == null || !_moduleInstalled) return;
    if (stage.effectiveRisk == 'R4' &&
        !await _confirmR4Operation(stage, enabling: false)) {
      return;
    }
    await _runModuleOperation(
      () => _service.rollback(
        stage,
        confirmation: stage.requiresApproval ? 'user' : 'none',
      ),
      onSuccess: (operation) {
        _moduleInstalled = true;
        _moduleEnabled = operation.operations.contains('enable');
        _moduleDisabled = operation.operations.contains('disable');
        return _zh
            ? '已回滚 ${operation.moduleId}；如需查看回滚版本，请重新导入该归档。'
            : 'Rolled back ${operation.moduleId}; re-import the archive to review the restored version.';
      },
    );
  }

  Future<void> _runDeclaredAction(String actionId) async {
    final stage = _stage;
    if (_busy || stage == null || !_moduleInstalled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_zh ? '运行插件操作？' : 'Run plugin action?'),
        content: Text(
          _zh
              ? '将对已安装的 ${stage.moduleId} 执行其 manifest 声明的操作：$actionId。'
              : 'Run the manifest-declared action "$actionId" for ${stage.moduleId}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            key: ValueKey('kernelsu_action_confirm_$actionId'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_zh ? '运行' : 'Run'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runModuleOperation(
      () => _service.runAction(stage, actionId, confirmation: 'user'),
      onSuccess: (operation) => _zh
          ? '已运行插件操作：${operation.moduleId} / $actionId'
          : 'Plugin action completed: ${operation.moduleId} / $actionId',
    );
  }

  Future<void> _runModuleOperation(
    Future<KernelSuPluginOperation> Function() operation, {
    required String Function(KernelSuPluginOperation operation) onSuccess,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await operation();
      if (!mounted) return;
      setState(() => _message = onSuccess(result));
    } catch (error) {
      if (mounted) setState(() => _message = _errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmR4Operation(
    KernelSuPluginStage stage, {
    required bool enabling,
  }) async {
    final bootEntries = stage.archiveEntries
        .where(
          (entry) => RegExp(
            r'boot|vbmeta|dtbo|partition|raw[_-]?block|bootloader|kernel|mtd|super\.img',
            caseSensitive: false,
          ).hasMatch(entry),
        )
        .toList(growable: false);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            key: ValueKey(
              'kernelsu_r4_confirm_${enabling ? 'enable' : 'install'}',
            ),
            title: Text(
              _zh
                  ? '确认启动链 / 分区敏感操作'
                  : 'Confirm boot/partition-sensitive operation',
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    enabling
                        ? (_zh
                              ? '启用后，模块可能在本次运行或下次启动时执行相关操作。请先核对设备型号、当前 slot、实际目标和可用恢复方式。错误操作可能导致设备无法启动；应用不提供零风险保证。'
                              : 'After enabling, the module may act now or during the next boot. Verify the device model, active slot, exact target, and a usable recovery path first. A mistake may prevent boot; the app cannot promise zero risk.')
                        : (_zh
                              ? '此归档按内容被标为启动链 / 分区敏感。应用会先安装为禁用状态；安装不会自动启用。继续前请核对归档和下方摘要。'
                              : 'The archive was classified as boot/partition-sensitive from its contents. It will be installed disabled and will not be enabled automatically. Review the archive and summary before continuing.'),
                  ),
                  const SizedBox(height: 12),
                  Text('${_zh ? '模块' : 'Module'}: ${stage.moduleId}'),
                  if (stage.review.overlayRoots.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_zh ? '声明目标' : 'Declared targets'}: ${stage.review.overlayRoots.join(', ')}',
                    ),
                  ],
                  if (bootEntries.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${_zh ? '启动链相关成员' : 'Boot-related members'}: ${bootEntries.join(', ')}',
                    ),
                  ],
                  if (stage.requiresReboot) ...[
                    const SizedBox(height: 6),
                    Text(
                      _zh
                          ? '插件声明需要重启。'
                          : 'The plugin declares that a reboot is required.',
                    ),
                  ],
                  const SizedBox(height: 8),
                  SelectableText('SHA-256: ${stage.sha256}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                key: ValueKey(
                  'kernelsu_r4_${enabling ? 'enable' : 'install'}_confirm',
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  _zh
                      ? '我已核对目标与恢复方式，继续'
                      : 'I verified the target and recovery path',
                ),
              ),
            ],
          ),
        ) ==
        true;
  }

  String _errorText(Object error) {
    if (error is PlatformException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return error.code;
    }
    return '$error'.replaceFirst('FormatException: ', '').trim();
  }

  Widget _reviewValue(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        SelectableText(value.isEmpty ? (_zh ? '未声明' : 'Not declared') : value),
      ],
    ),
  );

  Widget _reviewList(String label, List<String> values) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        SelectableText(
          values.isEmpty
              ? (_zh ? '无' : 'None')
              : values.map((value) => '• $value').join('\n'),
        ),
      ],
    ),
  );

  Widget _reviewDetails(KernelSuPluginStage stage) {
    final review = stage.review;
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const ValueKey('kernelsu_plugin_review'),
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(_zh ? '查看声明与归档内容' : 'Review declarations and archive'),
      subtitle: Text(
        _zh ? 'manifest 是插件自述；风险等级由归档内容计算。预览有长度上限，不等同于完整代码审计。' : 'Manifest fields are self-declared; risk is computed from archive contents. Previews are bounded, not a complete code audit.',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reviewValue(_zh ? '插件名称' : 'Name', review.name),
              _reviewValue(_zh ? '版本' : 'Version', review.version),
              _reviewValue(_zh ? '作者' : 'Author', review.author),
              _reviewValue(_zh ? '描述' : 'Description', review.description),
              _reviewValue(
                _zh ? 'manifest 自报风险' : 'Manifest risk hint',
                review.riskHint,
              ),
              _reviewValue(
                _zh ? '声明可回滚' : 'Declares reversible',
                review.reversible ? (_zh ? '是' : 'Yes') : (_zh ? '否' : 'No'),
              ),
              _reviewList(
                _zh ? '声明能力' : 'Declared capabilities',
                review.capabilities,
              ),
              _reviewList(_zh ? '覆盖路径' : 'Overlay roots', review.overlayRoots),
              _reviewList(
                _zh ? '备份目标' : 'Backup targets',
                review.backupTargets,
              ),
              _reviewList(_zh ? '健康检查' : 'Health checks', review.healthChecks),
              _reviewList(_zh ? '可执行操作' : 'Actions', review.actions),
              const SizedBox(height: 12),
              Text(
                _zh
                    ? '归档成员 (${stage.entryCount})'
                    : 'Archive members (${stage.entryCount})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (stage.archiveEntries.isEmpty)
                Text(_zh ? '未返回成员清单' : 'No member list returned')
              else
                SelectableText(
                  stage.archiveEntries.map((entry) => '• $entry').join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              if (stage.archiveEntriesTruncated)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _zh
                        ? '部分成员路径过长，显示内容已截断。'
                        : 'Some long member paths are truncated.',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _zh ? '关键文本文件预览' : 'Reviewable text-file previews',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (review.files.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _zh
                        ? '未发现可预览的脚本或策略文本。'
                        : 'No reviewable scripts or policy text found.',
                  ),
                ),
              for (final file in review.files)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    file.path,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(
                    '${file.sizeBytes} B${file.truncated ? (_zh ? ' · 预览截断' : ' · preview truncated') : ''}',
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SelectableText(
                          file.content ??
                              (_zh
                                  ? '不是有效 UTF-8 文本，未显示预览；应按二进制/不可审阅内容处理。'
                                  : 'Not valid UTF-8 text; no preview is available. Treat it as opaque content.'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (review.files.any(
                (file) => file.truncated || file.content == null,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _zh ? '存在截断或非文本文件；SHA-256 覆盖完整归档，但此处预览不覆盖其完整内容。' : 'Some content is truncated or non-text. SHA-256 covers the full archive, but these previews do not.',
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final capability = _capability;
    final stage = _stage;
    final capabilityText = _capabilityBusy
        ? (_zh ? '检查中…' : 'Checking…')
        : capability.state == 'not_checked'
        ? (_zh ? '尚未检查；点右侧刷新' : 'Not checked; tap refresh')
        : capability.available
        ? (_zh ? 'KernelSU 模块工作流可用' : 'KernelSU module workflow available')
        : (_zh
              ? '模块工作流不可用；普通 Root 不受此项替代'
              : 'Module workflow unavailable; ordinary Root is not replaced by this flow');
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.admin_panel_settings_outlined,
              color: colors.primary,
            ),
            title: Text(_zh ? 'KernelSU 插件' : 'KernelSU plugins'),
            subtitle: Text(
              _zh
                  ? '$capabilityText。系统与 boot 变更优先使用可回退模块，但经具体授权的直接路径仍可用。'
                  : '$capabilityText. Reversible modules are preferred for system and boot changes, while explicitly authorized direct paths remain available.',
            ),
            trailing: _capabilityBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: _zh ? '刷新' : 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: _busy
                        ? null
                        : () => unawaited(_refreshCapability()),
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(
              _zh ? '导入并检查插件归档' : 'Import and inspect plugin archive',
            ),
            subtitle: Text(
              _zh ? '先验证 ZIP、manifest、路径、摘要和风险；不会自动启用。' : 'Validate the ZIP, manifest, paths, digest, and risk before applying.',
            ),
            onTap: _busy ? null : _pickAndStage,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(
              _zh
                  ? '检查 KernelSU Root Profile'
                  : 'Inspect KernelSU Root Profile',
            ),
            subtitle: Text(
              _zh
                  ? '只读检查实际 UID、SELinux、capabilities 和关键路径权限；点击后可能弹出 KernelSU 授权。'
                  : 'Read-only UID, SELinux, capabilities, and path checks. KernelSU may request authorization after tapping.',
            ),
            trailing: _profileProbeBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _busy || _profileProbeBusy ? null : _probeRootProfile,
          ),
          if (_profileProbe != null) _rootProfileProbeDetails(_profileProbe!),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: Text(_zh ? '刷新已安装模块' : 'Refresh installed modules'),
            subtitle: Text(
              _installedModules.isEmpty
                  ? (_zh
                        ? '只在点击后执行一次只读的 ksud module list，不会自动触发。'
                        : 'Runs the read-only ksud module list only after tapping; it is not automatic.')
                  : (_zh
                        ? '已读取 ${_installedModules.length} 个模块'
                        : '${_installedModules.length} modules loaded'),
            ),
            trailing: _moduleListBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onTap: _busy || _moduleListBusy ? null : _refreshInstalledModules,
          ),
          if (_installedModules.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('kernelsu_installed_modules'),
              leading: const Icon(Icons.extension_outlined),
              title: Text(_zh ? '已安装模块' : 'Installed modules'),
              children: [
                for (final module in _installedModules)
                  ListTile(
                    dense: true,
                    title: Text(module.name.isEmpty ? module.id : module.name),
                    subtitle: Text(
                      '${module.id}${module.version.isEmpty ? '' : ' · ${module.version}'}${module.author.isEmpty ? '' : ' · ${module.author}'}',
                    ),
                    trailing: Text(
                      module.enabled
                          ? (_zh ? '已启用' : 'enabled')
                          : (_zh ? '已禁用' : 'disabled'),
                    ),
                  ),
              ],
            ),
          if (stage != null) ...[
            const Divider(height: 1),
            _reviewDetails(stage),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                stage.effectiveRisk == 'R1'
                    ? Icons.verified_outlined
                    : Icons.warning_amber_outlined,
                color: stage.effectiveRisk == 'R1'
                    ? colors.primary
                    : colors.error,
              ),
              title: Text(stage.moduleId),
              subtitle: Text(
                _zh
                    ? '有效风险 ${stage.effectiveRisk} · ${stage.entryCount} 个归档成员 · ${(stage.archiveSizeBytes / 1024).ceil()} KiB${stage.requiresReboot ? ' · 需要重启' : ''}\nSHA-256 ${stage.sha256}'
                    : 'Effective risk ${stage.effectiveRisk} · ${stage.entryCount} entries · ${(stage.archiveSizeBytes / 1024).ceil()} KiB${stage.requiresReboot ? ' · reboot required' : ''}\nSHA-256 ${stage.sha256}',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(
                    stage.effectiveRisk == 'R1'
                        ? (_zh ? '应用 R1 插件' : 'Apply R1 plugin')
                        : stage.effectiveRisk == 'R3'
                        ? (_zh ? '审批安装为禁用状态' : 'Approve install (disabled)')
                        : stage.effectiveRisk == 'R4'
                        ? (_zh
                              ? '审阅启动链影响并安装为禁用状态'
                              : 'Review boot impact and install disabled')
                        : (_zh
                              ? '审批并安装（保持可回滚）'
                              : 'Approve and install with rollback'),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _apply(approval: stage.requiresApproval),
                ),
              ),
            ),
            if (stage.requiresExplicitEnable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  stage.effectiveRisk == 'R4'
                      ? (_zh
                            ? 'R4 会先安装为禁用状态。启用前会显示归档目标、关键成员和摘要，再由你明确确认；该软路由不保证设备绝不变砖。'
                            : 'R4 is installed disabled first. Before enabling, the app shows declared targets, relevant members, and the digest for explicit confirmation. This soft route cannot guarantee the device will never be bricked.')
                      : (_zh
                            ? 'R3 会先安装为禁用状态。启用仍需要 Android 系统 PIN、图案或密码确认。'
                            : 'R3 is installed disabled first. Enabling still requires Android PIN, pattern, or password confirmation.'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            if (stage.requiresExplicitEnable &&
                _moduleInstalled &&
                _moduleDisabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(
                      stage.effectiveRisk == 'R4'
                          ? (_zh
                                ? '审阅影响并确认启用'
                                : 'Review impact and confirm enable')
                          : (_zh
                                ? '通过设备凭据启用'
                                : 'Enable with device credential'),
                    ),
                    onPressed: _busy ? null : _enableHighRiskModule,
                  ),
                ),
              ),
            if (_moduleInstalled) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _moduleEnabled
                        ? (_zh ? '当前状态：已启用' : 'Current state: enabled')
                        : (_moduleDisabled
                              ? (_zh ? '当前状态：已禁用' : 'Current state: disabled')
                              : (_zh
                                    ? '当前状态：已安装'
                                    : 'Current state: installed')),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_moduleEnabled)
                      OutlinedButton.icon(
                        key: const ValueKey('kernelsu_plugin_disable'),
                        icon: const Icon(Icons.pause_circle_outline),
                        label: Text(_zh ? '禁用' : 'Disable'),
                        onPressed: _busy ? null : _disableModule,
                      ),
                    if (_moduleDisabled)
                      OutlinedButton.icon(
                        key: const ValueKey('kernelsu_plugin_enable'),
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(_zh ? '启用' : 'Enable'),
                        onPressed: _busy ? null : _enableHighRiskModule,
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('kernelsu_plugin_rollback'),
                      icon: const Icon(Icons.undo_outlined),
                      label: Text(_zh ? '回滚上一版本' : 'Rollback previous'),
                      onPressed: _busy ? null : _rollbackModule,
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('kernelsu_plugin_uninstall'),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(_zh ? '卸载' : 'Uninstall'),
                      onPressed: _busy ? null : _uninstallModule,
                    ),
                  ],
                ),
              ),
              if (stage.review.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in stage.review.actions)
                        OutlinedButton.icon(
                          key: ValueKey('kernelsu_plugin_action_$action'),
                          icon: const Icon(Icons.bolt_outlined),
                          label: Text(_zh ? '运行 $action' : 'Run $action'),
                          onPressed: _busy
                              ? null
                              : () => _runDeclaredAction(action),
                        ),
                    ],
                  ),
                ),
            ],
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _message!,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rootProfileProbeDetails(RootProfileProbeResult result) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (result.state) {
      'root' => _zh ? 'Root 可用' : 'Root available',
      'smoke_passed' => _zh ? '样本检查通过' : 'Sample checks passed',
      'review_needed' => _zh ? '需要调整或复核' : 'Needs review',
      'denied' => _zh ? 'Root 不可用' : 'Root unavailable',
      'context_unavailable' =>
        _zh ? 'KernelSU Root 调用被拒绝' : 'KernelSU Root invocation rejected',
      'profile_incompatible' =>
        _zh ? 'KernelSU 权限配置不兼容' : 'KernelSU profile is incompatible',
      _ => _zh ? '检查失败' : 'Probe failed',
    };
    final reason = result.state == 'context_unavailable'
        ? (_zh
              ? 'KernelSU 拒绝了正常 Root 调用。请检查本应用当前 KernelSU profile 是否允许 UID 0；应用不要求自定义 SELinux 域，也不会修改 profile。'
              : 'KernelSU rejected the normal Root invocation. Check whether this app profile is allowed to obtain UID 0; the app does not require or modify a custom SELinux domain.')
        : result.state == 'profile_incompatible'
        ? (_zh
              ? 'Root 启动器只核对实际 UID 0，不会要求固定执行域、附加组或能力掩码。能力、组、SELinux 和 Linux NoNewPrivs 仅显示为诊断信息。'
              : 'The Root launcher verifies actual UID 0 only; it does not require a fixed domain, supplementary groups, or capability mask. Capabilities, groups, SELinux, and Linux NoNewPrivs are diagnostics only.')
        : result.reason;
    String yesNo(bool value) =>
        value ? (_zh ? '是' : 'yes') : (_zh ? '否' : 'no');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label · UID ${result.uid} · ${result.context}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                'UID/GID ${result.uid}/${result.gid} · '
                'SELinux ${result.selinux} · '
                '${_zh ? 'Android 组' : 'Android groups'} ${result.groups} · '
                'Linux NoNewPrivs ${result.linuxNoNewPrivs} (${_zh ? '仅记录' : 'reported only'})\n'
                'CapEff ${result.capEff} · '
                'CapPrm ${result.capPrm} · '
                'CapInh ${result.capInh} · '
                'CapBnd ${result.capBnd} · '
                'CapAmb ${result.capAmb}\n'
                '${_zh ? '系统数据可读' : 'System data readable'} ${yesNo(result.systemDataReadable)} · '
                '${_zh ? '全局读取样本' : 'Global read samples'} ${yesNo(result.globalReadSamplesPassed)} · '
                '${_zh ? '工作区可写' : 'Workspace writable'} ${yesNo(result.workspaceWritable)} · '
                '${_zh ? '必需组 root/inet/readproc' : 'required groups root/inet/readproc'} ${yesNo(result.requiredGroupsPresent)} · '
                '${_zh ? '网络组(3003)' : 'inet group (3003)'} ${yesNo(result.networkGroupPresent)} · '
                '${_zh ? '进程读取组(3009)' : 'readproc group (3009)'} ${yesNo(result.readProcGroupPresent)}\n'
                '${_zh ? '应用运行目录可读写' : 'App runtime dirs readable/writable'} '
                '${yesNo(result.appFilesAccessible)}/${yesNo(result.appNoBackupAccessible)} · '
                '${_zh ? '应用数据/安装目录可读' : 'App data/install roots readable'} '
                '${yesNo(result.appDataRootReadable)}/${yesNo(result.appInstallRootReadable)}\n'
                '${_zh ? '块设备别名枚举完成/只读/总数/可写' : 'Block aliases complete/read-only/total/writable'} '
                '${yesNo(result.blockAliasEnumerationComplete)}/${yesNo(result.blockAliasesReadOnly)}/'
                '${result.blockAliasCount}/${result.writableBlockAliasCount} · '
                '${_zh ? '高危写入样本' : 'protected write samples'} '
                '${yesNo(result.protectedWriteSamplesPassed)}\n'
                '${_zh ? 'Boot 节点存在/可写' : 'Boot node present/writable'} '
                '${yesNo(result.bootBlockPresent)}/${yesNo(result.bootBlockWritable)} · '
                '${_zh ? 'KernelSU 目录存在/可写' : 'KSU dirs present/writable'} '
                '${yesNo(result.protectedRootPresent)}/${yesNo(result.protectedRootsWritable)}\n'
                '${_zh ? '系统配置存在/可读/可写' : 'System config present/readable/writable'} '
                '${yesNo(result.systemConfigPresent)}/${yesNo(result.systemConfigReadable)}/${yesNo(result.systemConfigWritable)} · '
                '${_zh ? 'Vendor 配置可读/可写' : 'Vendor config readable/writable'} '
                '${yesNo(result.vendorConfigReadable)}/${yesNo(result.vendorConfigWritable)}\n'
                '${_zh ? '进程状态可读' : 'Process status readable'} ${yesNo(result.procStatusReadable)} · '
                '${_zh ? 'SELinux 状态可读/可写' : 'SELinux state readable/writable'} '
                '${yesNo(result.selinuxStateReadable)}/${yesNo(result.selinuxStateWritable)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                _zh
                    ? '$reason 这些是样本权限检查，不代表所有系统路径均安全。'
                          'KernelSU Root Profile 的 NO_NEW_PRIVS 开关与上面的 Linux 字段不同，请在 KernelSU 管理器中确认已启用。'
                    : '$reason These are sample permission checks, not proof for every system path. '
                          'KernelSU Root Profile NO_NEW_PRIVS is separate from the Linux field above; confirm it in KernelSU Manager.',
                style: TextStyle(
                  color: result.smokePassed
                      ? colors.onSurfaceVariant
                      : colors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
