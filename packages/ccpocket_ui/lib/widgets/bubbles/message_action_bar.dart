import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// Gemini-style action bar shown below assistant messages.
class MessageActionBar extends StatelessWidget {
  final String textToCopy;
  final bool isPlainTextMode;
  final VoidCallback? onTogglePlainText;
  final VoidCallback? onFork;

  const MessageActionBar({
    super.key,
    required this.textToCopy,
    this.isPlainTextMode = false,
    this.onTogglePlainText,
    this.onFork,
  });

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final plainTextLabel = switch (locale) {
      'zh' => isPlainTextMode ? '显示格式化文本' : '显示纯文本',
      'ja' => isPlainTextMode ? '書式付きで表示' : 'プレーンテキストで表示',
      'ko' => isPlainTextMode ? '서식 있는 텍스트로 표시' : '일반 텍스트로 표시',
      _ => isPlainTextMode ? 'Show formatted text' : 'Show plain text',
    };

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.bubbleMarginH,
        right: AppSpacing.bubbleMarginH,
        top: 2,
        bottom: 4,
      ),
      child: Row(
        children: [
          _ActionIcon(
            key: const ValueKey('copy_button'),
            icon: Icons.content_copy,
            size: 18,
            color: appColors.subtleText,
            tooltip: l.copy,
            onTap: () {
              Clipboard.setData(ClipboardData(text: textToCopy));
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).copied),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          _ActionIcon(
            key: const ValueKey('plain_text_toggle'),
            icon: Icons.text_fields,
            size: 18,
            color: isPlainTextMode ? primaryColor : appColors.subtleText,
            tooltip: plainTextLabel,
            onTap: onTogglePlainText,
          ),
          const SizedBox(width: 16),
          _ActionIcon(
            key: const ValueKey('share_button'),
            icon: Icons.share,
            size: 18,
            color: appColors.subtleText,
            tooltip: l.share,
            onTap: () {
              SharePlus.instance.share(ShareParams(text: textToCopy));
            },
          ),
          if (onFork != null) ...[
            const SizedBox(width: 16),
            _ActionIcon(
              key: const ValueKey('fork_button'),
              icon: Icons.call_split,
              size: 18,
              color: appColors.subtleText,
              tooltip: l.forkConversation,
              onTap: onFork,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _ActionIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        child: SizedBox.square(
          dimension: 48,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: size, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
