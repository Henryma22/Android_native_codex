import 'package:flutter/material.dart';

import '../../models/messages.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

class PermissionRequestBubble extends StatefulWidget {
  final PermissionRequestMessage message;
  final bool isCodex;
  const PermissionRequestBubble({
    super.key,
    required this.message,
    this.isCodex = false,
  });

  @override
  State<PermissionRequestBubble> createState() =>
      _PermissionRequestBubbleState();
}

class _PermissionRequestBubbleState extends State<PermissionRequestBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final presentation = _localizedPermissionPresentation(
      widget.message.presentation,
      zh: Localizations.localeOf(context).languageCode == 'zh',
    );
    final detailLines = presentation.secondaryDetails;
    final inputStr = presentation.rawDetails;
    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: AppSpacing.bubbleMarginV,
        horizontal: AppSpacing.bubbleMarginH,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: appColors.permissionBubble,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: appColors.permissionBubbleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(Icons.security, size: 16, color: appColors.permissionIcon),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    presentation.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: appColors.subtleText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            presentation.summary,
            style: TextStyle(fontSize: 12, color: appColors.subtleText),
          ),
          if (presentation.primaryTarget != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: appColors.permissionBubble.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: appColors.permissionBubbleBorder.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
              child: Text(
                presentation.primaryTarget!,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: appColors.subtleText,
                ),
              ),
            ),
          ],
          if (detailLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in detailLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 6),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: appColors.subtleText,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          color: appColors.subtleText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(
              inputStr,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: appColors.subtleText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

PermissionPresentation _localizedPermissionPresentation(
  PermissionPresentation presentation, {
  required bool zh,
}) {
  if (!zh) return presentation;
  return PermissionPresentation(
    title: _localizedPermissionTitle(presentation.title),
    summary: _localizedPermissionSummary(presentation.summary),
    rawDetails: presentation.rawDetails,
    riskBadge: _localizedPermissionRiskBadge(presentation.riskBadge),
    scopeLabel: presentation.scopeLabel,
    primaryTargetLabel: _localizedPermissionTargetLabel(
      presentation.primaryTargetLabel,
    ),
    primaryTarget: _localizedPermissionTarget(presentation.primaryTarget),
    secondaryDetails: presentation.secondaryDetails
        .map(_localizedPermissionDetail)
        .toList(growable: false),
  );
}

String _localizedPermissionTitle(String title) {
  switch (title) {
    case 'Additional Permissions':
      return '额外权限';
    case 'Command Approval':
      return '命令审批';
    case 'File Change Approval':
      return '文件变更审批';
    case 'App Tool Approval':
      return '应用工具审批';
    case 'MCP Elicitation':
      return 'MCP 请求';
    case 'Plugin suggestion':
      return '插件建议';
  }
  if (title.startsWith('MCP: ')) return 'MCP：${title.substring(5)}';
  return title;
}

String _localizedPermissionSummary(String summary) {
  switch (summary) {
    case 'Allow command execution':
      return '允许执行命令';
    case 'Allow file changes':
      return '允许修改文件';
    case 'Grant additional access for this task':
      return '为此任务授予额外访问权限';
  }
  const prefix = 'Allow changes to ';
  if (summary.startsWith(prefix)) {
    final target = summary.substring(prefix.length);
    final fileCount = RegExp(r'^(\d+) files$').firstMatch(target);
    if (fileCount != null) return '允许修改 ${fileCount.group(1)} 个文件';
    return '允许修改 $target';
  }
  return summary;
}

String? _localizedPermissionRiskBadge(String? value) {
  if (value == null) return null;
  switch (value) {
    case 'Plugin':
      return '插件';
    case 'Connector':
      return '连接器';
    case 'App Tool':
      return '应用工具';
    case 'Question':
      return '问题';
    case 'Permissions':
      return '权限';
    case 'Command':
      return '命令';
    case 'File Changes':
      return '文件变更';
    case 'MCP':
      return 'MCP';
    default:
      return value;
  }
}

String? _localizedPermissionTargetLabel(String? value) {
  if (value == null) return null;
  const labels = <String, String>{
    'Command': '命令',
    'Files': '文件',
    'Requested': '请求',
    'Target': '目标',
  };
  return labels[value] ?? value;
}

String? _localizedPermissionTarget(String? value) {
  if (value == null) return null;
  return value.replaceFirstMapped(
    RegExp(r'\s\+(\d+) more$'),
    (match) => ' 还有 ${match.group(1)} 项',
  );
}

String _localizedPermissionDetail(String line) {
  const labels = <String, String>{
    'Server': '服务器',
    'Reason': '原因',
    'Why': '原因',
    'Grant root': '授予 Root',
    'Permissions': '权限',
    'Additional permissions': '额外权限',
    'Exec policy': '执行策略',
    'Network policy': '网络策略',
    'Command': '命令',
    'Files': '文件',
    'Target': '目标',
    'Requested': '请求',
  };
  for (final entry in labels.entries) {
    final prefix = '${entry.key}: ';
    if (line.startsWith(prefix)) {
      return '${entry.value}：${line.substring(prefix.length)}';
    }
  }
  return line;
}
