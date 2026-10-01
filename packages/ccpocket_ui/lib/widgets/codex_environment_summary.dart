import 'package:flutter/material.dart';

import '../models/messages.dart';
import '../theme/app_theme.dart';

class CodexEnvironmentSummary extends StatelessWidget {
  final String? model;
  final String? reasoningEffort;
  final String? approvalPolicy;
  final String? approvalsReviewer;
  final String? sandboxMode;
  final bool showDefaultReasoning;
  final bool showApprovalMode;
  final bool compact;
  final String? leadingLabel;

  const CodexEnvironmentSummary({
    super.key,
    this.model,
    this.reasoningEffort,
    this.approvalPolicy,
    this.approvalsReviewer,
    this.sandboxMode,
    this.showDefaultReasoning = false,
    this.showApprovalMode = true,
    this.compact = false,
    this.leadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: compact ? 11 : 12,
      color: appColors.subtleText,
      height: 1.2,
    );
    final executionLabel = showApprovalMode
        ? _executionLabel(
            approvalPolicy: approvalPolicy,
            approvalsReviewer: approvalsReviewer,
            zh: zh,
          )
        : null;

    final children = <Widget>[
      if (leadingLabel != null) Text(leadingLabel!, style: textStyle),
      if (_displayModelSummary(
            model,
            reasoningEffort,
            showDefaultWhenUnset: showDefaultReasoning,
            zh: zh,
          )
          case final modelText?)
        Text(modelText, style: textStyle, overflow: TextOverflow.ellipsis),
      if (executionLabel != null)
        _EnvironmentMeta(
          icon: _executionIcon(
            approvalPolicy: approvalPolicy,
            approvalsReviewer: approvalsReviewer,
          ),
          label: executionLabel,
          compact: compact,
        ),
      _EnvironmentMeta(
        icon: _sandboxIcon(sandboxMode),
        label: _sandboxLabel(sandboxMode, zh: zh),
        compact: compact,
      ),
    ];

    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _EnvironmentMeta extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const _EnvironmentMeta({
    required this.icon,
    required this.label,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>()!;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: compact ? 11 : 12,
      color: appColors.subtleText,
      height: 1.2,
    );

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 12 : 14, color: appColors.subtleText),
            const SizedBox(width: 3),
            Text(label, style: textStyle, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

String? _displayModelSummary(
  String? model,
  String? raw, {
  required bool showDefaultWhenUnset,
  required bool zh,
}) {
  if (model == null || model.isEmpty) return null;
  if (raw == null || raw.isEmpty) {
    return showDefaultWhenUnset ? '$model ${zh ? '默认' : 'Default'}' : model;
  }
  ReasoningEffort? effort;
  for (final value in ReasoningEffort.values) {
    if (value.value == raw) {
      effort = value;
      break;
    }
  }
  final effortLabel = effort == null ? raw : _effortLabel(effort, zh: zh);
  return '$model $effortLabel';
}

String _effortLabel(ReasoningEffort effort, {required bool zh}) {
  if (!zh) return effort.label;
  return switch (effort.value) {
    'none' => '无',
    'minimal' => '最小',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    'max' => '最大',
    'ultra' => '超级',
    _ => effort.label,
  };
}

IconData _executionIcon({String? approvalPolicy, String? approvalsReviewer}) {
  if (approvalPolicy == 'on-request' &&
      isCodexAutoReviewApprovalsReviewer(approvalsReviewer)) {
    return Icons.auto_mode_outlined;
  }
  return switch (approvalPolicy) {
    'never' => Icons.flash_on,
    'on-failure' => Icons.tune,
    'untrusted' => Icons.verified_user_outlined,
    'on-request' || null || '' => Icons.tune,
    _ => Icons.tune,
  };
}

String? _executionLabel({
  String? approvalPolicy,
  String? approvalsReviewer,
  required bool zh,
}) {
  if (approvalPolicy == 'on-request' &&
      isCodexAutoReviewApprovalsReviewer(approvalsReviewer)) {
    return zh ? '自动审查' : 'Auto Review';
  }
  return switch (approvalPolicy) {
    'untrusted' => zh ? '不受信任' : 'Untrusted',
    'on-request' => zh ? '需要时询问' : 'On Request',
    'on-failure' => zh ? '需要时询问' : 'On Request',
    'never' => zh ? '从不询问' : 'Never Ask',
    null || '' => null,
    final other => other,
  };
}

IconData _sandboxIcon(String? sandboxMode) {
  return switch (sandboxMode) {
    'off' || 'danger-full-access' => Icons.warning_amber,
    _ => Icons.shield_outlined,
  };
}

String _sandboxLabel(String? sandboxMode, {required bool zh}) {
  return switch (sandboxMode) {
    'off' || 'danger-full-access' => zh ? '沙箱关闭' : 'Sandbox Off',
    'on' ||
    'workspace-write' ||
    'read-only' ||
    null ||
    '' => zh ? '沙箱' : 'Sandbox',
    final other => other,
  };
}
