import 'package:ccpocket_ui/features/session_list/widgets/codex_usage_summary.dart';
import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/models/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Codex usage refresh hint follows the selected locale', (
    tester,
  ) async {
    const expectedHints = <String, String>{
      'en': 'Refresh Codex usage',
      'zh': '刷新 Codex 用量',
      'ja': 'Codex の使用量を更新',
      'ko': 'Codex 사용량 새로고침',
    };

    for (final entry in expectedHints.entries) {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(entry.key),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: CodexUsageSummary(
              usage: UsageInfo(
                provider: 'codex',
                fiveHour: UsageWindow(utilization: 5, resetsAt: ''),
              ),
              onTap: _noOp,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final refreshHint = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.hint == entry.value,
      );
      expect(refreshHint, findsOneWidget, reason: entry.key);
    }
  });
}

void _noOp() {}
