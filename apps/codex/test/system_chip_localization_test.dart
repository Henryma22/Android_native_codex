import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/models/messages.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';
import 'package:ccpocket_ui/widgets/bubbles/system_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Codex system notices are localized for Chinese users', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Column(
            children: [
              SystemChip(
                message: SystemMessage(
                  subtype: 'Code Mode unavailable; using direct tools.',
                ),
              ),
              SystemChip(
                message: SystemMessage(
                  subtype: 'Optional MCP worker is unavailable on the current network. The local Codex session remains available without that worker.',
                ),
              ),
              SystemChip(
                message: SystemMessage(
                  subtype: 'session_created',
                  provider: 'codex',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('系统: 代码模式不可用，已改用直接工具。'), findsOneWidget);
    expect(find.text('系统: 网络下可选 MCP 不可用；本地 Codex 仍可继续。'), findsOneWidget);
    expect(find.text('会话已启动'), findsOneWidget);
  });

  testWidgets('long localized system notices stay within phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SystemChip(
            message: SystemMessage(
              subtype: 'Optional MCP worker is unavailable on the current network. The local Codex session remains available without that worker.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final longNotice = find.textContaining('MCP 不可用');
    final chip = find.ancestor(of: longNotice, matching: find.byType(Chip));
    expect(chip, findsOneWidget);
    expect(tester.getSize(chip).width, lessThanOrEqualTo(336));
    expect(find.text('系统: 网络下可选 MCP 不可用；本地 Codex 仍可继续。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
