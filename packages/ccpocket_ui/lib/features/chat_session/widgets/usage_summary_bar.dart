import 'package:flutter/material.dart';

/// The original CC Pocket conversation usage strip.
///
/// Codex uses the same surface with its local app-server token counters. The
/// widget deliberately hides itself until there is real usage, matching the
/// upstream conversation screen rather than showing a settings placeholder.
class UsageSummaryBar extends StatelessWidget {
  final double totalCost;
  final Duration? totalDuration;
  final int inputTokens;
  final int cachedInputTokens;
  final int outputTokens;
  final int toolCalls;
  final int fileEdits;
  final int contextTokens;
  final int? contextWindow;

  const UsageSummaryBar({
    super.key,
    required this.totalCost,
    required this.totalDuration,
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.toolCalls,
    required this.fileEdits,
    this.contextTokens = 0,
    this.contextWindow,
  });

  bool get _hasCost => totalCost > 0;
  bool get _hasDuration =>
      totalDuration != null && totalDuration! > Duration.zero;
  bool get _hasTokenUsage =>
      inputTokens > 0 || cachedInputTokens > 0 || outputTokens > 0;
  bool get _hasToolUsage => toolCalls > 0 || fileEdits > 0;

  @override
  Widget build(BuildContext context) {
    if (!_hasCost && !_hasDuration && !_hasTokenUsage) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final items = <Widget>[];

    if (_hasCost) {
      items.add(
        _UsageStat(
          icon: Icons.attach_money,
          text: '\$${totalCost.toStringAsFixed(4)}',
        ),
      );
    }
    if (_hasDuration) {
      items.add(
        _UsageStat(
          icon: Icons.timer_outlined,
          text: _formatDuration(totalDuration!),
        ),
      );
    }
    if (_hasTokenUsage) {
      items.add(
        _UsageStat(
          icon: Icons.data_usage_outlined,
          leading: contextWindow != null && contextWindow! > 0
              ? _ContextUsageRing(
                  usedTokens: contextTokens,
                  contextWindow: contextWindow!,
                )
              : null,
          text: _formatTokenSummary(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            zh: zh,
          ),
        ),
      );
    }
    if (_hasToolUsage) {
      items.add(
        _UsageStat(
          icon: Icons.build_circle_outlined,
          text: _formatToolSummary(
            toolCalls: toolCalls,
            fileEdits: fileEdits,
            zh: zh,
          ),
        ),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '·',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      }
      children.add(items[i]);
    }

    return SizedBox(
      key: const ValueKey('usage_summary_bar'),
      height: 18,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      return '${minutes}m ${seconds}s';
    }
    return '${duration.inSeconds}s';
  }

  static String _formatTokenSummary({
    required int inputTokens,
    required int cachedInputTokens,
    required int outputTokens,
    required bool zh,
  }) {
    final effectiveInput = inputTokens + cachedInputTokens;
    final inText = _formatCompactNumber(effectiveInput);
    final outText = _formatCompactNumber(outputTokens);
    if (cachedInputTokens > 0) {
      final cacheText = _formatCompactNumber(cachedInputTokens);
      return zh
          ? '输入 $inText（缓存 $cacheText）/ 输出 $outText'
          : 'in $inText($cacheText) / out $outText';
    }
    return zh ? '输入 $inText / 输出 $outText' : 'in $inText / out $outText';
  }

  static String _formatToolSummary({
    required int toolCalls,
    required int fileEdits,
    required bool zh,
  }) {
    if (toolCalls <= 0) return zh ? '编辑 $fileEdits' : 'edits $fileEdits';
    if (fileEdits <= 0) return zh ? '工具 $toolCalls' : 'tools $toolCalls';
    return zh
        ? '工具 $toolCalls / 编辑 $fileEdits'
        : 'tools $toolCalls / edits $fileEdits';
  }

  static String _formatCompactNumber(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.toString();
  }
}

class _UsageStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? leading;

  const _UsageStat({required this.icon, required this.text, this.leading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading ??
            Icon(
              icon,
              size: 12,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ContextUsageRing extends StatelessWidget {
  const _ContextUsageRing({
    required this.usedTokens,
    required this.contextWindow,
  });

  final int usedTokens;
  final int contextWindow;

  @override
  Widget build(BuildContext context) {
    final progress = (usedTokens / contextWindow).clamp(0.0, 1.0);
    final color = Theme.of(context).colorScheme.onSurface;
    final percent = (progress * 100).round();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Semantics(
      label: zh ? '上下文使用量 $percent%' : 'Context usage $percent%',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: progress),
        duration: const Duration(milliseconds: 240),
        builder: (context, value, _) => SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 2,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}
