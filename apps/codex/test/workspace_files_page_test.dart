import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/main.dart';

void main() {
  testWidgets('browses directories and opens a managed file change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceFilesPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('batch_text_change_button')));
    await tester.pumpAndSettle();
    expect(find.text('Batch text replacement'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workspace_tools_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host command'));
    await tester.pumpAndSettle();
    expect(find.text('Host command'), findsOneWidget);
    expect(find.text('Explicit argv execution'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(find.text('Managed text change'), findsOneWidget);
    expect(
      find.textContaining("void main() => print('fixture');"),
      findsOneWidget,
    );
  });
}
