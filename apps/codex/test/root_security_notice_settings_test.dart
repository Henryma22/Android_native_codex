import 'package:codex/ccpocket_local_settings.dart';
import 'package:codex/core/domain/runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Codex settings edit defaults, not the per-thread identity', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    String? selectedEffort;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: CodexPocketSettingsPage(
          runtime: Future<CodexRuntimeDescriptor>.value(runtime),
          onRefresh: () async => runtime,
          locale: const Locale('en'),
          model: 'gpt-6-luna',
          effort: 'low',
          approvalPolicy: 'never',
          sandbox: 'danger-full-access',
          onEffortChanged: (value) => selectedEffort = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_execution_identity_tile')),
      findsNothing,
    );
    expect(find.text('New-session default model'), findsOneWidget);
    expect(find.text('New-session default approval'), findsOneWidget);
    expect(find.text('New-session default sandbox'), findsOneWidget);

    final effortTitle = find.text('New-session default effort');
    await tester.ensureVisible(effortTitle);
    await tester.tap(effortTitle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    expect(selectedEffort, 'high');
  });
}
