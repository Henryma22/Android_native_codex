import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/change_set.dart';
import 'package:codex/core/domain/workspace.dart';
import 'package:codex/main.dart';

void main() {
  testWidgets('previews and approves a fake backend change', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeSetPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Managed text change'), findsOneWidget);
    final contentField = find.byType(TextField).last;
    await tester.enterText(contentField, 'edited fixture\n');
    await tester.dragUntilVisible(
      find.text('Preview diff'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.text('Preview diff'));
    await tester.pumpAndSettle();

    expect(find.text('Diff preview'), findsOneWidget);
    expect(find.text('Commit with backup'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Commit with backup'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.text('Commit with backup'));
    await tester.pumpAndSettle();
    expect(find.text('Approve managed write?'), findsOneWidget);

    await tester.tap(find.text('Approve write'));
    await tester.pumpAndSettle();

    expect(find.text('Backup created'), findsOneWidget);
    expect(find.textContaining('fake-backup-'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore backup?'), findsOneWidget);
    expect(find.text('Restore preview'), findsOneWidget);
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    expect(
      (await backend.snapshotText(
        await backend.openWorkspace(workspace),
        'README.md',
      )).content,
      contains('fixture'),
    );
  });

  testWidgets('creates a backup without changing the fake file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final original = await backend.snapshotText(
      await backend.openWorkspace(workspace),
      'README.md',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeSetPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Create backup only'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.text('Create backup only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create backup'));
    await tester.pumpAndSettle();

    expect(find.text('Backup created'), findsOneWidget);
    expect(
      (await backend.snapshotText(
        await backend.openWorkspace(workspace),
        'README.md',
      )).content,
      original.content,
    );
  });

  testWidgets('surfaces a managed write conflict after approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _ConflictBackend();
    final workspace = (await backend.listWorkspaces()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeSetPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'conflicting edit\n');
    await tester.dragUntilVisible(
      find.text('Preview diff'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.text('Preview diff'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Commit with backup'),
      find.byType(ListView),
      const Offset(0, -240),
    );
    await tester.tap(find.text('Commit with backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve write'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('BackendException: conflict: external change'),
      findsOneWidget,
    );
    expect(find.text('Backup created'), findsNothing);
  });

  testWidgets('keeps an explicitly read-only backend gated in the shared UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _ReadOnlyFakeBackend();
    final workspace = (await backend.listWorkspaces()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeSetPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'This backend exposes snapshot and diff preview only',
      ),
      findsOneWidget,
    );
    expect(find.text('Preview diff'), findsOneWidget);
    expect(find.text('Create backup only'), findsNothing);
    expect(find.text('Commit with backup'), findsNothing);
    expect(find.text('Restore'), findsNothing);
  });
}

class _ReadOnlyFakeBackend extends FakeBackend {
  @override
  BackendDescriptor get descriptor => const BackendDescriptor(
    id: 'readonly-fixture',
    kind: BackendKind.localAndroid,
    displayName: 'Local Android (read-only fixture)',
    version: 'fixture',
    health: BackendHealth.verified,
    capabilities: CapabilitySnapshot(
      supported: true,
      available: true,
      verified: true,
      managedChangesSupported: false,
    ),
  );
}

class _ConflictBackend extends FakeBackend {
  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) async {
    throw const BackendException('conflict: external change detected.');
  }
}
