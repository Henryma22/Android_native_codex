import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/workspace_pane_chrome.dart';

/// Fixed Material app bar for the Android session list screen.
///
/// Android uses this ordinary app bar with a single body scroll surface. That
/// avoids making NestedScrollView arbitrate a drag between an outer and inner
/// scroll position on high-refresh devices.
class SessionListAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onDisconnect;
  final double? toolbarHeight;
  final String? runtimeLabel;

  const SessionListAppBar({
    super.key,
    required this.onTitleTap,
    required this.onDisconnect,
    this.toolbarHeight,
    this.runtimeLabel,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      title: _sessionListTitle(
        onTitleTap: onTitleTap,
        title: l.appTitle,
        runtimeLabel: runtimeLabel,
      ),
      actions: _sessionListActions(context, onDisconnect: onDisconnect),
    );
  }
}

/// SliverAppBar for the session list screen.
///
/// Desktop and iOS keep the existing floating/snap behavior. Android uses
/// [SessionListAppBar] instead so the inner session list owns the gesture.
class SessionListSliverAppBar extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onDisconnect;
  final bool forceElevated;
  final double? toolbarHeight;
  final String? runtimeLabel;

  const SessionListSliverAppBar({
    super.key,
    required this.onTitleTap,
    required this.onDisconnect,
    this.forceElevated = false,
    this.toolbarHeight,
    this.runtimeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    return SliverAppBar(
      // On Android the content below this header is already the only
      // vertically scrolling surface. Keeping the toolbar pinned avoids
      // giving NestedScrollView an outer collapse range to arbitrate before
      // handing the drag to the inner session list.
      pinned: isAndroid,
      // Keeping the outer app bar floating on Android makes NestedScrollView
      // arbitrate the same drag between two scroll positions, which is
      // especially visible as missed handoff frames on high-refresh devices.
      floating: !isAndroid,
      // On Android this SliverAppBar is coordinated with the inner session
      // ListView by NestedScrollView. A snap animation makes a single touch
      // gesture compete with that inner scroll position and can present as a
      // dropped, non-following drag on high-refresh phones. Keep the existing
      // desktop/iOS behavior while letting Android settle continuously.
      snap: !isAndroid,
      forceElevated: forceElevated,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      title: _sessionListTitle(
        onTitleTap: onTitleTap,
        title: AppLocalizations.of(context).appTitle,
        runtimeLabel: runtimeLabel,
      ),
      actions: _sessionListActions(context, onDisconnect: onDisconnect),
    );
  }
}

Widget _sessionListTitle({
  required VoidCallback onTitleTap,
  required String title,
  required String? runtimeLabel,
}) {
  return GestureDetector(
    onTap: onTitleTap,
    child: _SessionListTitle(title: title, subtitle: runtimeLabel),
  );
}

List<Widget> _sessionListActions(
  BuildContext context, {
  required VoidCallback onDisconnect,
}) => const <Widget>[];

class SessionListPaneHeader extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenGallery;
  final VoidCallback? onDisconnect;
  final VoidCallback? onTogglePaneVisibility;
  final String? runtimeLabel;

  const SessionListPaneHeader({
    super.key,
    required this.onTitleTap,
    required this.onOpenSettings,
    this.onOpenGallery,
    this.onDisconnect,
    this.onTogglePaneVisibility,
    this.runtimeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final openGallery = onOpenGallery;
    final disconnect = onDisconnect;
    final togglePaneVisibility = onTogglePaneVisibility;
    final chrome = resolveWorkspacePaneChrome(
      platform: Theme.of(context).platform,
      isAdaptiveWorkspace: true,
      isLeftPaneVisible: true,
      slot: WorkspacePaneSlot.left,
    );
    final titleStyle = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w700);
    final actionGap = chrome.useMacOSAdaptiveChrome ? 8.0 : 0.0;

    return SizedBox(
      height: chrome.toolbarHeight,
      child: Padding(
        padding: chrome.headerPadding(
          // Keep the 56dp mobile toolbar tall enough for 48dp action targets.
          vertical: chrome.useMacOSAdaptiveChrome ? 10 : 4,
        ),
        child: Row(
          children: [
            if (!chrome.useMacOSAdaptiveChrome)
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: _SessionListTitle(
                    key: const ValueKey('session_list_pane_title'),
                    title: l.appTitle,
                    subtitle: runtimeLabel,
                    titleStyle: titleStyle,
                  ),
                ),
              )
            else
              const Expanded(
                child: MacOSWindowDragHandle(child: SizedBox.expand()),
              ),
            _PaneHeaderActionButton(
              key: const ValueKey('settings_button'),
              tooltip: l.settings,
              onPressed: onOpenSettings,
              icon: Badge(
                isLabelVisible: false,
                smallSize: 8,
                child: const Icon(Icons.settings),
              ),
              compact: chrome.useMacOSAdaptiveChrome,
            ),
            if (openGallery != null ||
                disconnect != null ||
                togglePaneVisibility != null)
              SizedBox(width: actionGap),
            if (openGallery != null)
              _PaneHeaderActionButton(
                key: const ValueKey('gallery_button'),
                tooltip: l.gallery,
                onPressed: openGallery,
                icon: const Icon(Icons.collections_outlined),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
            if (openGallery != null &&
                (disconnect != null || togglePaneVisibility != null))
              SizedBox(width: actionGap),
            if (disconnect != null)
              _PaneHeaderActionButton(
                key: const ValueKey('disconnect_button'),
                tooltip: l.disconnect,
                onPressed: disconnect,
                icon: const Icon(Icons.link_off),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
            if (disconnect != null && togglePaneVisibility != null)
              SizedBox(width: actionGap),
            if (togglePaneVisibility != null)
              _PaneHeaderActionButton(
                key: const ValueKey('collapse_left_pane_button'),
                tooltip: l.hideSessions,
                onPressed: togglePaneVisibility,
                icon: const Icon(Icons.chevron_left),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionListTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;

  const _SessionListTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.titleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final theme = Theme.of(context);
    final defaultTitleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    if (subtitle == null || subtitle.isEmpty) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle ?? defaultTitleStyle,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle ?? defaultTitleStyle,
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _PaneHeaderActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  final bool compact;

  const _PaneHeaderActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: compact
          ? resolveWorkspacePaneChrome(
              platform: Theme.of(context).platform,
              isAdaptiveWorkspace: true,
              isLeftPaneVisible: true,
              slot: WorkspacePaneSlot.left,
            ).compactButtonStyle()
          : null,
      constraints: compact
          ? null
          : const BoxConstraints(minWidth: 48, minHeight: 48),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: icon,
    );
  }
}
