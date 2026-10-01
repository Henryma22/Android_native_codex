import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/messages.dart';
import '../../theme/app_theme.dart';
import '../codex_environment_summary.dart';

class SystemChip extends StatelessWidget {
  final SystemMessage message;
  const SystemChip({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appColors = Theme.of(context).extension<AppColors>()!;
    final isCodexStarted =
        message.provider == 'codex' &&
        (message.subtype == 'init' || message.subtype == 'session_created');
    final subtype = switch (message.subtype) {
      'Code Mode unavailable; using direct tools.' =>
        l.codexCodeModeFallbackNotice,
      'Optional MCP worker is unavailable on the current network. The local Codex session remains available without that worker.' =>
        l.optionalMcpWorkerNotice,
      _ => message.subtype,
    };
    final label = isCodexStarted ? null : '${l.systemNoticeLabel}: $subtype';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 24,
          ),
          child: Chip(
            label: isCodexStarted
                ? CodexEnvironmentSummary(
                    leadingLabel: l.codexSessionStarted,
                    model: message.model,
                    reasoningEffort: message.modelReasoningEffort,
                    approvalPolicy: message.approvalPolicy,
                    approvalsReviewer: message.approvalsReviewer,
                    sandboxMode: message.sandboxMode,
                    showDefaultReasoning: true,
                  )
                : Text(label!, style: const TextStyle(fontSize: 12)),
            backgroundColor: appColors.systemChip,
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}
