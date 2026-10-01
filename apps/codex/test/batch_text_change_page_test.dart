import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/batch_text_change_page.dart';

void main() {
  testWidgets('keeps batch previews compact on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: BatchTextChangePage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('batch-search')), 'fixture');
    await tester.enterText(
      find.byKey(const Key('batch-replacement')),
      'sample',
    );
    await tester.tap(find.byKey(const Key('batch-scan')));
    await tester.pumpAndSettle();

    expect(find.text('Matched files: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('previews, commits, and restores a batch replacement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: BatchTextChangePage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('batch-search')), 'fixture');
    await tester.enterText(
      find.byKey(const Key('batch-replacement')),
      'sample',
    );
    await tester.tap(find.byKey(const Key('batch-scan')));
    await tester.pumpAndSettle();

    expect(find.text('Matched files: 2'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch-commit')));
    await tester.pumpAndSettle();
    expect(find.text('Approve batch write?'), findsOneWidget);
    await tester.tap(find.text('Approve batch write'));
    await tester.pumpAndSettle();

    expect(find.text('Batch write results'), findsOneWidget);
    expect(find.text('Succeeded: 2 · Failed: 0'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('batch-restore')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('batch-restore')));
    await tester.pumpAndSettle();
    expect(find.text('Restore batch backups?'), findsOneWidget);
    await tester.tap(find.text('Restore backups'));
    await tester.pumpAndSettle();

    expect(find.text('Batch restore results'), findsOneWidget);
    expect(find.textContaining('restored: fake-backup-'), findsNWidgets(2));
  });
}
