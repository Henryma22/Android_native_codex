import 'package:flutter/material.dart';
import 'package:ccpocket_ui/features/session_list/widgets/codex_usage_summary.dart'
    as pocket_usage;
import 'package:ccpocket_ui/models/messages.dart' as pocket;

import 'core/application/codex_usage.dart';

/// The compact usage treatment used by the current CC Pocket home screen.
/// The data source is local app-server RPC in this app; the widget only owns
/// the presentation and remains independent from the runtime implementation.
enum CodexUsageDisplayMode { remaining, used }

class CcpocketCodexUsageSummary extends StatelessWidget {
  const CcpocketCodexUsageSummary({
    required this.usage,
    required this.zh,
    this.displayMode = CodexUsageDisplayMode.remaining,
    this.onTap,
    super.key,
  });

  final CodexUsageSnapshot usage;
  final bool zh;
  final CodexUsageDisplayMode displayMode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return pocket_usage.CodexUsageSummary(
      usage: _toPocketUsage(usage),
      displayMode: displayMode == CodexUsageDisplayMode.remaining
          ? pocket_usage.CodexUsageDisplayMode.remaining
          : pocket_usage.CodexUsageDisplayMode.used,
      onTap: onTap,
    );
  }

  pocket.UsageInfo _toPocketUsage(CodexUsageSnapshot value) {
    pocket.UsageWindow? window(CodexUsageWindow? source) {
      if (source == null) return null;
      return pocket.UsageWindow(
        utilization: source.usedPercent,
        resetsAt: source.resetsAt?.toIso8601String() ?? '',
      );
    }

    return pocket.UsageInfo(
      provider: pocket.Provider.codex.value,
      fiveHour: window(value.fiveHour),
      sevenDay: window(value.sevenDay),
    );
  }
}

// Kept as small compatibility helpers for old, unreachable settings widgets
// while the visible quota UI is now the original CC Pocket summary above the
// conversation. No settings page constructs those widgets anymore.
double codexUsageDisplayPercentage(
  CodexUsageWindow window,
  CodexUsageDisplayMode mode,
) {
  final used = window.usedPercent.clamp(0, 100).toDouble();
  return mode == CodexUsageDisplayMode.remaining ? 100 - used : used;
}

Color codexUsageIndicatorColor(
  BuildContext context,
  double percentage,
  CodexUsageDisplayMode mode,
) {
  final cs = Theme.of(context).colorScheme;
  return switch (mode) {
    CodexUsageDisplayMode.used =>
      percentage >= 90
          ? cs.error
          : percentage >= 70
          ? Colors.orange
          : cs.primary,
    CodexUsageDisplayMode.remaining =>
      percentage <= 10
          ? cs.error
          : percentage <= 30
          ? Colors.orange
          : cs.primary,
  };
}
