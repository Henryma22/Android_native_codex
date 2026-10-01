import 'dart:async';

import 'package:flutter/material.dart';

import 'core/domain/custom_provider.dart';
import 'services/custom_provider_store.dart';

typedef ModelProviderSelectionChanged = void Function(
  String mode,
  CustomProviderConfig? selectedProvider,
);

class ModelProviderSettingsPage extends StatefulWidget {
  const ModelProviderSettingsPage({
    required this.selectedProvider,
    required this.thirdPartyEnabled,
    required this.onSelectionChanged,
    super.key,
  });

  final CustomProviderConfig? selectedProvider;
  final bool thirdPartyEnabled;
  final ModelProviderSelectionChanged onSelectionChanged;

  @override
  State<ModelProviderSettingsPage> createState() =>
      _ModelProviderSettingsPageState();
}

class _ModelProviderSettingsPageState extends State<ModelProviderSettingsPage> {
  final _store = CustomProviderStore();
  late CustomProviderConfig? _selectedProvider = widget.selectedProvider;
  late bool _thirdPartyEnabled = widget.thirdPartyEnabled;

  @override
  void didUpdateWidget(covariant ModelProviderSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedProvider = widget.selectedProvider;
    _thirdPartyEnabled = widget.thirdPartyEnabled;
  }

  Future<void> _selectOpenAi() async {
    await _store.saveProviderMode('openai');
    if (!mounted) return;
    setState(() => _thirdPartyEnabled = false);
    widget.onSelectionChanged('openai', _selectedProvider);
  }

  Future<void> _selectThirdParty() async {
    final provider = _selectedProvider;
    if (provider == null) {
      await _openThirdPartySettings();
      return;
    }
    await _store.saveActiveId(provider.id);
    await _store.saveProviderMode('third_party');
    if (!mounted) return;
    setState(() => _thirdPartyEnabled = true);
    widget.onSelectionChanged('third_party', provider);
  }

  Future<void> _openThirdPartySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomProviderSettingsPage(
          thirdPartyEnabled: _thirdPartyEnabled,
          onActiveProviderChanged: (provider) {
            if (!mounted) return;
            final nextThirdPartyEnabled =
                provider != null && _thirdPartyEnabled;
            setState(() {
              _selectedProvider = provider;
              _thirdPartyEnabled = nextThirdPartyEnabled;
            });
            widget.onSelectionChanged(
              nextThirdPartyEnabled ? 'third_party' : 'openai',
              provider,
            );
          },
          onProviderUpdated: (provider) {
            if (!mounted) return;
            setState(() => _selectedProvider = provider);
            widget.onSelectionChanged(
              _thirdPartyEnabled ? 'third_party' : 'openai',
              provider,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final selectedMode = _thirdPartyEnabled ? 'third_party' : 'openai';
    return Scaffold(
      appBar: AppBar(title: Text(zh ? '模型来源' : 'Model source')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: const ValueKey('model_provider_openai_option'),
              leading: Radio<String>(
                value: 'openai',
                groupValue: selectedMode,
                onChanged: (_) => unawaited(_selectOpenAi()),
              ),
              title: Text(zh ? 'OpenAI 订阅' : 'OpenAI subscription'),
              subtitle: Text(
                zh ? '使用已登录的 OpenAI 账号；第三方配置会保留但不参与请求。' : 'Use the signed-in OpenAI account. Saved third-party configurations remain inactive.',
              ),
              onTap: () => unawaited(_selectOpenAi()),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            key: const ValueKey('model_provider_third_party_card'),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const ValueKey('model_provider_third_party_option'),
                  leading: Radio<String>(
                    value: 'third_party',
                    groupValue: selectedMode,
                    onChanged: (_) => unawaited(_selectThirdParty()),
                  ),
                  title: Text(zh ? '第三方服务商' : 'Third-party provider'),
                  subtitle: Text(
                    _selectedProvider == null
                        ? (zh
                              ? '选择第三方 API 作为请求来源'
                              : 'Use a third-party API as the request source')
                        : '${zh ? (_thirdPartyEnabled ? '当前启用' : '已配置') : (_thirdPartyEnabled ? 'Active' : 'Configured')}: ${_selectedProvider!.name} · ${_selectedProvider!.model}',
                  ),
                  onTap: () => unawaited(_selectThirdParty()),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                ListTile(
                  key: const ValueKey('model_provider_manage_third_party'),
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  leading: const Icon(Icons.tune_outlined),
                  title: Text(
                    zh ? '第三方服务商配置' : 'Third-party provider settings',
                  ),
                  subtitle: Text(
                    _selectedProvider == null
                        ? (zh
                              ? '添加 API 地址、模型和密钥；保存后仍需在上方启用'
                              : 'Add an API URL, model, and key; saving does not activate it')
                        : '${_selectedProvider!.name} · ${_selectedProvider!.model} · ${zh ? (_thirdPartyEnabled ? '当前启用' : '已配置，未启用') : (_thirdPartyEnabled ? 'Active' : 'Configured, inactive')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_openThirdPartySettings()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            zh
                ? 'OpenAI 订阅与第三方 API 是互斥的请求来源。切换后所有已打开 session 和新 session 都使用所选来源；正在生成的响应会停止，历史保留，下一条消息会创建新 thread。'
                : 'The sources are mutually exclusive. Switching updates every open session and future sessions. In-flight turns stop; visible history stays, and the next message starts a thread with the selected source.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class CustomProviderSettingsPage extends StatefulWidget {
  const CustomProviderSettingsPage({
    this.thirdPartyEnabled = false,
    this.onActiveProviderChanged,
    this.onProviderUpdated,
    super.key,
  });

  final bool thirdPartyEnabled;
  final ValueChanged<CustomProviderConfig?>? onActiveProviderChanged;
  final ValueChanged<CustomProviderConfig>? onProviderUpdated;

  @override
  State<CustomProviderSettingsPage> createState() =>
      _CustomProviderSettingsPageState();
}

class _CustomProviderSettingsPageState
    extends State<CustomProviderSettingsPage> {
  final _store = CustomProviderStore();
  var _providers = const <CustomProviderConfig>[];
  String? _activeId;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final providers = await _store.load();
    final activeId = await _store.loadActiveId();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _activeId = providers.any((item) => item.id == activeId)
          ? activeId
          : null;
      _loading = false;
    });
  }

  Future<void> _edit([CustomProviderConfig? existing]) async {
    final value = await showDialog<CustomProviderConfig>(
      context: context,
      builder: (_) => _ProviderEditorDialog(existing: existing),
    );
    if (!mounted || value == null) return;
    try {
      value.responsesBaseUri;
      await _store.save(value);
      await _load();
      if (_activeId == value.id) {
        final updated = _providers
            .where((provider) => provider.id == value.id)
            .firstOrNull;
        if (updated != null) widget.onProviderUpdated?.call(updated);
      }
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _select(String id) async {
    await _store.saveActiveId(id);
    // Choosing which third-party configuration to keep ready is not the same
    // as switching the app's request source. If no source has ever been
    // chosen, make OpenAI the explicit default; activation remains on the
    // parent Model Source page.
    if (await _store.loadProviderMode() == null) {
      await _store.saveProviderMode('openai');
    }
    if (!mounted) return;
    setState(() => _activeId = id);
    widget.onActiveProviderChanged?.call(
      _providers.where((item) => item.id == id).firstOrNull,
    );
  }

  Future<void> _delete(CustomProviderConfig provider) async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh ? '删除第三方模型配置？' : 'Delete provider configuration?'),
        content: Text(
          zh
              ? '将删除“${provider.name}”及其保存的 API key。'
              : 'This will delete “${provider.name}” and its saved API key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(zh ? '删除' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(provider.id);
    if (_activeId == provider.id) {
      await _store.saveActiveId(null);
      await _store.saveProviderMode('openai');
      widget.onActiveProviderChanged?.call(null);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '第三方服务商配置' : 'Third-party provider configuration'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zh
                              ? '在这里保存兼容 Codex Responses API 的服务商、模型和 API key（由 Android Keystore 加密保存）。此页只管理第三方配置，不会切换当前请求来源；请返回“模型来源”选择 OpenAI 订阅或第三方服务商。会话、工具和审批仍由本地 Codex app-server 管理。'
                              : 'Save a Codex Responses API-compatible provider, model, and API key here (encrypted with Android Keystore). This page only manages third-party configurations; it does not switch the active request source. Return to Model Source to choose OpenAI subscription or a third-party provider. Threads, tools, and approvals remain managed by the local Codex app-server.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                zh
                                    ? '密钥边界：Codex 子命令环境会过滤该 key，但 key 仍存在 app-server 进程环境中；Root/UID 0 下的工具可能读取它。只在信任该会话执行环境时启用第三方 provider。'
                                    : 'Credential boundary: Codex child-command environments filter this key, but it remains in the app-server process environment; Root/UID 0 tools may be able to inspect it. Enable a third-party provider only when you trust the session execution environment.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_providers.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(zh ? '尚未添加第三方模型' : 'No providers configured'),
                      subtitle: Text(
                        zh ? '添加后返回上一级“模型来源”菜单，再选择第三方服务商启用。' : 'After adding one, return to the parent Model Source menu and choose the third-party source to activate it.',
                      ),
                    ),
                  ),
                for (final provider in _providers)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: Icon(
                        _activeId == provider.id
                            ? widget.thirdPartyEnabled
                                  ? Icons.check_circle
                                  : Icons.bookmark_added_outlined
                            : Icons.radio_button_unchecked,
                        color: _activeId == provider.id
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      title: Text(provider.name),
                      subtitle: Text(
                        '${widget.thirdPartyEnabled && _activeId == provider.id
                            ? (zh ? '当前启用' : 'Active')
                            : _activeId == provider.id
                            ? (zh ? '已选配置，当前使用 OpenAI' : 'Selected config; OpenAI is active')
                            : (zh ? '已保存，未启用' : 'Saved, inactive')} · '
                        '${provider.model}\n${provider.baseUrl}\n'
                        '${zh ? '推理' : 'Reasoning'}: '
                        '${provider.reasoningEfforts.join(', ')}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () => _select(provider.id),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') unawaited(_edit(provider));
                          if (value == 'delete') unawaited(_delete(provider));
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(zh ? '编辑' : 'Edit'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(zh ? '删除' : 'Delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: Text(zh ? '添加服务商' : 'Add provider'),
                ),
              ],
            ),
    );
  }
}

class _ProviderEditorDialog extends StatefulWidget {
  const _ProviderEditorDialog({this.existing});

  final CustomProviderConfig? existing;

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _baseUrl = TextEditingController(
    text: widget.existing?.baseUrl ?? '',
  );
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _apiKey = TextEditingController(
    text: widget.existing?.apiKey ?? '',
  );
  late final _reasoningEfforts = TextEditingController(
    text:
        (widget.existing?.reasoningEfforts ??
                CustomProviderConfig.defaultReasoningEffortsForModel(
                  widget.existing?.model ?? '',
                ))
            .join(', '),
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _reasoningEfforts.dispose();
    super.dispose();
  }

  void _save() {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final name = _name.text.trim();
    final baseUrl = _baseUrl.text.trim();
    final model = _model.text.trim();
    if (name.isEmpty || baseUrl.isEmpty || model.isEmpty) {
      setState(
        () => _error = zh
            ? '名称、Responses API 地址和模型 ID 不能为空。'
            : 'Name, Responses API URL, and model ID are required.',
      );
      return;
    }
    List<String> reasoningEfforts;
    try {
      reasoningEfforts = CustomProviderConfig.parseReasoningEfforts(
        _reasoningEfforts.text,
        model: model,
      );
      CustomProviderConfig(
        id: widget.existing?.id ?? 'validation',
        name: name,
        baseUrl: baseUrl,
        model: model,
        apiKey: _apiKey.text.trim(),
        reasoningEfforts: reasoningEfforts,
      ).responsesBaseUri;
    } on FormatException catch (error) {
      setState(
        () => _error = zh ? '地址或推理档位无效：${error.message}' : error.message,
      );
      return;
    }
    final id =
        widget.existing?.id ??
        '${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '')}-${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).pop(
      CustomProviderConfig(
        id: id,
        name: name,
        baseUrl: baseUrl,
        model: model,
        apiKey: _apiKey.text.trim(),
        reasoningEfforts: reasoningEfforts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? (zh ? '添加第三方模型' : 'Add third-party model')
            : (zh ? '编辑第三方模型' : 'Edit third-party model'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('provider_name_field'),
              controller: _name,
              decoration: InputDecoration(labelText: zh ? '名称' : 'Name'),
            ),
            TextField(
              key: const ValueKey('provider_base_url_field'),
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: zh ? 'Responses API 基础地址' : 'Responses API base URL',
                hintText: 'https://api.example.com/v1',
                helperText: zh
                    ? '示例：https://api.deepseek.com（不要追加 /v1）；需支持 Responses API。'
                    : 'Example: https://api.deepseek.com (omit /v1); requires Responses API.',
                helperMaxLines: 3,
              ),
            ),
            TextField(
              key: const ValueKey('provider_model_field'),
              controller: _model,
              decoration: InputDecoration(
                labelText: zh ? '模型 ID' : 'Model ID',
                hintText: zh ? '例如 deepseek-flash' : 'e.g. deepseek-flash',
              ),
            ),
            TextField(
              key: const ValueKey('provider_efforts_field'),
              controller: _reasoningEfforts,
              decoration: InputDecoration(
                labelText: zh
                    ? '推理档位（逗号分隔，可选）'
                    : 'Reasoning effort (comma-separated, optional)',
                hintText: 'low, high, max',
                helperText: zh ? '服务商未提供能力发现时，由这里决定会话可选档位。' : 'Sets session options when the provider has no capability discovery.',
                helperMaxLines: 2,
              ),
            ),
            TextField(
              key: const ValueKey('provider_api_key_field'),
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: zh ? 'API key（可选）' : 'API key (optional)',
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          key: const ValueKey('provider_save_button'),
          onPressed: _save,
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}
