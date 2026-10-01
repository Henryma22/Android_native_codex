import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket_ui/widgets/adaptive_context_menu.dart';
import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/models/messages.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';
import 'package:ccpocket_ui/widgets/session_card.dart';

void main() {
  testWidgets('localizes an empty session preview in Chinese', (tester) async {
    var actionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RecentSessionCard(
            session: RecentSession(
              sessionId: 'empty-session',
              provider: 'codex',
              name: null,
              summary: '',
              firstPrompt: '',
              created: '2026-09-23T00:00:00Z',
              modified: '2026-09-23T00:00:00Z',
              gitBranch: '',
              projectPath: '/workspace/demo',
              isSidechain: false,
            ),
            onTap: () {},
            onLongPress: () {},
            onShowActions: (_) => actionCount++,
            onTogglePinned: () {},
            compact: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('（无描述）'), findsOneWidget);
    expect(find.text('(no description)'), findsNothing);

    expect(
      tester.getSize(
        find.byKey(const ValueKey('recent_session_pin_empty-session_button')),
      ),
      const Size(48, 48),
    );

    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byType(AdaptiveContextMenuRegion))
          .getSemanticsData()
          .hasAction(SemanticsAction.longPress),
      isTrue,
    );
    semantics.dispose();

    await tester.longPress(find.byType(RecentSessionCard));
    await tester.pumpAndSettle();
    expect(actionCount, 1);
  });

  testWidgets('grouped empty named session omits duplicate metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RecentSessionCard(
            session: RecentSession(
              sessionId: 'named-empty-session',
              provider: 'codex',
              name: 'demo',
              summary: '',
              firstPrompt: '',
              created: '2026-09-23T00:00:00Z',
              modified: '2026-09-23T00:00:00Z',
              gitBranch: '',
              projectPath: '/workspace/demo',
              isSidechain: false,
            ),
            onTap: () {},
            hideProjectBadge: true,
            compact: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('demo'), findsOneWidget);
    expect(find.text('（无描述）'), findsNothing);
  });
}
