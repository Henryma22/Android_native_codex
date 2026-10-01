import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/messages.dart';
import '../../../theme/app_theme.dart';

/// The compact Codex quota summary from CC Pocket's session-list UI.
///
/// The widget is presentation-only. The local Android app supplies a
/// [UsageInfo] snapshot and owns the RPC that produced it.
enum CodexUsageDisplayMode { remaining, used }

class CodexUsageSummary extends StatelessWidget {
  final UsageInfo usage;
  final CodexUsageDisplayMode displayMode;
  final VoidCallback? onTap;

  const CodexUsageSummary({
    super.key,
    required this.usage,
    this.displayMode = CodexUsageDisplayMode.remaining,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = switch (displayMode) {
      CodexUsageDisplayMode.remaining => l.usageDisplayModeRemaining,
      CodexUsageDisplayMode.used => l.usageDisplayModeUsed,
    };
    final metrics = <Widget>[
      if (usage.fiveHour != null)
        _UsageMetric(
          key: const ValueKey('codex_usage_5h_indicator'),
          label: '5h',
          window: usage.fiveHour!,
          displayMode: displayMode,
        ),
      if (usage.sevenDay != null)
        _UsageMetric(
          key: const ValueKey('codex_usage_1w_indicator'),
          label: '1w',
          window: usage.sevenDay!,
          displayMode: displayMode,
        ),
    ];
    final semanticMetrics = <String>[
      if (usage.fiveHour != null)
        '5h ${_displayPercentage(usage.fiveHour!, displayMode).toStringAsFixed(0)}%',
      if (usage.sevenDay != null)
        '1w ${_displayPercentage(usage.sevenDay!, displayMode).toStringAsFixed(0)}%',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('codex_usage_summary_button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Semantics(
          container: true,
          button: onTap != null,
          excludeSemantics: true,
          label: ['Codex $label', ...semanticMetrics].join(', '),
          hint: onTap == null ? null : l.usageRefreshHint,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // Keep the compact content aligned with CC Pocket's 44px target.
            alignment: const Alignment(1, -0.15),
            child: Row(
              key: const ValueKey('codex_usage_summary'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Codex $label',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final metric in metrics) ...[
                  const SizedBox(width: 8),
                  metric,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageMetric extends StatelessWidget {
  final String label;
  final UsageWindow window;
  final CodexUsageDisplayMode displayMode;

  const _UsageMetric({
    super.key,
    required this.label,
    required this.window,
    required this.displayMode,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = _displayPercentage(window, displayMode);
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>();
    final color = switch (displayMode) {
      CodexUsageDisplayMode.used =>
        percentage >= 90
            ? colorScheme.error
            : percentage >= 70
            ? Colors.orange
            : appColors?.statusOnline ?? colorScheme.primary,
      CodexUsageDisplayMode.remaining =>
        percentage <= 10
            ? colorScheme.error
            : percentage <= 30
            ? Colors.orange
            : appColors?.statusOnline ?? colorScheme.primary,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ${percentage.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 24,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (percentage / 100).clamp(0, 1),
              minHeight: 4,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

double _displayPercentage(
  UsageWindow window,
  CodexUsageDisplayMode displayMode,
) {
  final used = window.utilization.clamp(0, 100).toDouble();
  return displayMode == CodexUsageDisplayMode.remaining ? 100 - used : used;
}
