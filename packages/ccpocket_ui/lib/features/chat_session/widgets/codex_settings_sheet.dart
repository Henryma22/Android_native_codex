import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../widgets/codex_effort_slider.dart';

class CodexSettingsSheet extends StatefulWidget {
  final List<String> models;
  final Future<List<String>> Function()? loadModelOptions;
  final Map<String, List<ReasoningEffort>> modelEfforts;
  final Map<String, List<String>> modelServiceTiers;
  final String initialModel;
  final ReasoningEffort initialEffort;
  final CodexSpeed initialSpeed;
  final bool showExtendedEfforts;
  final bool initialShowAdvanced;
  final void Function(String model, ReasoningEffort effort) onModelChanged;
  final void Function(String model, ReasoningEffort effort) onEffortChanged;
  final ValueChanged<CodexSpeed> onSpeedChanged;

  const CodexSettingsSheet({
    super.key,
    required this.models,
    this.loadModelOptions,
    required this.modelEfforts,
    required this.modelServiceTiers,
    required this.initialModel,
    required this.initialEffort,
    required this.initialSpeed,
    this.showExtendedEfforts = false,
    this.initialShowAdvanced = false,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onSpeedChanged,
  });

  @override
  State<CodexSettingsSheet> createState() => _CodexSettingsSheetState();
}

class _CodexSettingsSheetState extends State<CodexSettingsSheet> {
  late String _model = widget.initialModel;
  late ReasoningEffort _effort = widget.initialEffort;
  late CodexSpeed _speed = widget.initialSpeed;
  late bool _showAdvanced = widget.initialShowAdvanced;

  List<ReasoningEffort> get _efforts =>
      widget.modelEfforts[_model] ?? const [ReasoningEffort.none];

  bool get _supportsFast => codexSupportsFast(_model, widget.modelServiceTiers);

  void _selectEffort(ReasoningEffort effort) {
    if (effort == _effort) return;
    setState(() => _effort = effort);
    widget.onEffortChanged(_model, effort);
  }

  void _selectSpeed(CodexSpeed speed) {
    if (speed == _speed || (speed == CodexSpeed.fast && !_supportsFast)) return;
    setState(() => _speed = speed);
    widget.onSpeedChanged(speed);
  }

  void _selectModel(String model) {
    if (model == _model) return;
    final efforts = widget.modelEfforts[model] ?? const [ReasoningEffort.none];
    final nextEffort = preferredCodexEffort(efforts, current: _effort);
    final supportsFast = codexSupportsFast(model, widget.modelServiceTiers);
    final previousSpeed = _speed;
    final nextSpeed = supportsFast ? _speed : CodexSpeed.standard;
    setState(() {
      _model = model;
      _effort = nextEffort;
      _speed = nextSpeed;
    });
    widget.onModelChanged(model, nextEffort);
    if (nextSpeed != previousSpeed) widget.onSpeedChanged(nextSpeed);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final panel = CodexSettingsPanel(
      model: _model,
      effort: _effort,
      speed: _speed,
      supportsFast: _supportsFast,
      onSpeedChanged: _selectSpeed,
      speedButtonKey: 'codex_speed_button',
      showAdvanced: _showAdvanced,
      advancedLabel: l.advanced,
      toggleButtonKey: 'codex_settings_advanced',
      onToggleMode: () => setState(() => _showAdvanced = !_showAdvanced),
      quickPanelKey: 'codex_settings_quick_panel',
      advancedPanelKey: 'codex_settings_advanced_panel',
      modelLabelKey: 'codex_settings_model_label',
      effortLabelKey: 'codex_settings_effort_label',
      quickChild: CodexEffortSlider(
        efforts: _efforts,
        value: _effort,
        onChanged: _selectEffort,
        sliderKey: 'codex_effort_slider',
        includeExtended: widget.showExtendedEfforts,
      ),
      advancedChild: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SettingsRow(
            key: const ValueKey('codex_model_advanced'),
            label: l.model,
            value: codexModelDisplayName(_model),
            onTap: () => _showModelPicker(context),
          ),
          _SettingsRow(
            key: const ValueKey('codex_effort_advanced'),
            label: l.effort,
            value: _localizedEffortLabel(context, _effort),
            onTap: () => _showEffortPicker(context),
          ),
          if (_supportsFast)
            _SettingsRow(
              key: const ValueKey('codex_speed_advanced'),
              label: _localizedSpeedTitle(context),
              value: _localizedSpeedLabel(context, _speed),
              onTap: () => _showSpeedPicker(context),
            ),
        ],
      ),
    );
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight < 420 ? constraints.maxHeight : 420.0)
              : 420.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: panel,
            ),
          );
        },
      ),
    );
  }

  void _showModelPicker(BuildContext context) {
    final loadModelOptions = widget.loadModelOptions;
    if (loadModelOptions != null) {
      var availableModels = _modelOptions(widget.models);
      var loadStarted = false;
      var loading = true;
      var loadFailed = false;

      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            if (!loadStarted) {
              loadStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(() async {
                  try {
                    final models = await loadModelOptions();
                    if (!sheetContext.mounted) return;
                    setSheetState(() {
                      availableModels = _modelOptions(models);
                      loading = false;
                      loadFailed = false;
                    });
                  } on Object {
                    if (!sheetContext.mounted) return;
                    setSheetState(() {
                      loading = false;
                      loadFailed = true;
                    });
                  }
                }());
              });
            }

            final zh = Localizations.localeOf(context).languageCode == 'zh';
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppLocalizations.of(context).model,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  if (loadFailed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          zh ? '模型目录暂不可用；当前模型仍可选择。' : 'Model catalog is unavailable; the current model remains selectable.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final value in availableModels)
                          ListTile(
                            key: ValueKey('codex_model_${value}_option'),
                            title: Text(codexModelDisplayName(value)),
                            trailing: value == _model
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.pop(sheetContext);
                              _selectModel(value);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
      return;
    }

    _showPicker<String>(
      context: context,
      title: AppLocalizations.of(context).model,
      values: widget.models,
      selected: _model,
      label: codexModelDisplayName,
      onSelected: _selectModel,
    );
  }

  List<String> _modelOptions(Iterable<String> models) {
    final options = <String>{
      for (final model in models)
        if (model.trim().isNotEmpty) model,
    };
    options.add(_model);
    return options.toList(growable: false);
  }

  void _showEffortPicker(BuildContext context) {
    _showPicker<ReasoningEffort>(
      context: context,
      title: AppLocalizations.of(context).effort,
      values: _efforts,
      selected: _effort,
      label: (effort) => _localizedEffortLabel(context, effort),
      subtitle: (effort) => effort == ReasoningEffort.ultra
          ? Localizations.localeOf(context).languageCode == 'zh'
              ? '消耗更多额度，并启用自动任务委派'
              : 'Uses more usage and automatic task delegation'
          : null,
      onSelected: _selectEffort,
    );
  }

  String _localizedEffortLabel(BuildContext context, ReasoningEffort effort) {
    return localizedCodexEffortLabel(
      effort,
      Localizations.localeOf(context).languageCode,
    );
  }

  String _localizedSpeedTitle(BuildContext context) =>
      switch (Localizations.localeOf(context).languageCode) {
        'zh' => '速度',
        'ja' => '速度',
        'ko' => '속도',
        _ => 'Speed',
      };

  String _localizedSpeedLabel(BuildContext context, CodexSpeed speed) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return switch ((languageCode, speed)) {
      ('zh', CodexSpeed.standard) => '标准',
      ('zh', CodexSpeed.fast) => '快速',
      ('ja', CodexSpeed.standard) => '標準',
      ('ja', CodexSpeed.fast) => '高速',
      ('ko', CodexSpeed.standard) => '표준',
      ('ko', CodexSpeed.fast) => '빠름',
      (_, CodexSpeed.standard) => 'Standard',
      (_, CodexSpeed.fast) => 'Fast',
    };
  }

  String _localizedSpeedSubtitle(BuildContext context, CodexSpeed speed) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return switch ((languageCode, speed)) {
      ('zh', CodexSpeed.standard) => '默认速度',
      ('zh', CodexSpeed.fast) => '速度提升 1.5 倍，消耗更多额度',
      ('ja', CodexSpeed.standard) => '既定の速度',
      ('ja', CodexSpeed.fast) => '1.5 倍速で、使用量が増えます',
      ('ko', CodexSpeed.standard) => '기본 속도',
      ('ko', CodexSpeed.fast) => '1.5배 빠르며 사용량이 증가합니다',
      (_, CodexSpeed.standard) => 'Default speed',
      (_, CodexSpeed.fast) => '1.5× speed, more usage',
    };
  }

  void _showSpeedPicker(BuildContext context) {
    _showPicker<CodexSpeed>(
      context: context,
      title: _localizedSpeedTitle(context),
      values: [CodexSpeed.standard, if (_supportsFast) CodexSpeed.fast],
      selected: _speed,
      label: (speed) => _localizedSpeedLabel(context, speed),
      subtitle: (speed) => _localizedSpeedSubtitle(context, speed),
      onSelected: _selectSpeed,
    );
  }

  void _showPicker<T>({
    required BuildContext context,
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    String? Function(T)? subtitle,
    required ValueChanged<T> onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final value in values)
                    ListTile(
                      key: value is ReasoningEffort
                          ? ValueKey('codex_effort_${value.value}_option')
                          : value is CodexSpeed
                          ? ValueKey('codex_speed_${value.value}_option')
                          : null,
                      title: Text(label(value)),
                      subtitle: subtitle == null || subtitle(value) == null
                          ? null
                          : Text(subtitle(value)!),
                      trailing: value == selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(sheetContext);
                        onSelected(value);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingsRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}
