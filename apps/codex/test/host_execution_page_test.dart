import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/main.dart';

void main() {
  testWidgets('runs an argv request through the fake backend', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: HostExecutionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Explicit argv execution'), findsOneWidget);
    expect(
      find.textContaining(
        'Developer tools such as git, node, npm, npx, and python come from the Linux/PRoot guest',
      ),
      findsOneWidget,
    );
    expect(find.text('Probe native tools'), findsNothing);
    await tester.tap(find.text('Run command'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fake backend: id'), findsOneWidget);
    expect(find.textContaining('[exit 0]'), findsOneWidget);
  });

  testWidgets('does not leave a stop control after a completed command', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: HostExecutionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsNothing);
    await tester.tap(find.text('Run command'));
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('runs Root commands without a second per-command approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: HostExecutionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Root helper'));
    await tester.tap(find.text('Run command'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fake backend: id'), findsOneWidget);

    await tester.tap(find.text('Run command'));
    await tester.pumpAndSettle();
    expect(find.text('Approve root command?'), findsNothing);
    expect(find.textContaining('fake backend: id'), findsOneWidget);
  });
}
