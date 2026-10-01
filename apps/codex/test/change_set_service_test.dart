import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/batch_text_change_service.dart';
import 'package:codex/core/application/change_set_service.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/core/domain/change_set.dart';
import 'package:codex/core/domain/workspace.dart';

void main() {
  test('builds a compact unified diff for a text change', () {
    final diff = buildUnifiedDiff(
      path: 'README.md',
      before: 'same\nold\nend\n',
      after: 'same\nnew\nend\n',
    );

    expect(diff, contains('--- README.md'));
    expect(diff, contains('-old'));
    expect(diff, contains('+new'));
  });

  test(
    'commit creates a backup and restore returns the original content',
    () async {
      final backend = FakeBackend();
      final workspace = await backend.openWorkspace(
        (await backend.listWorkspaces()).single,
      );
      final service = ChangeSetService();
      final original = await backend.snapshotText(workspace, 'README.md');
      final changeSet = await service.preview(
        backend: backend,
        workspace: workspace,
        relativePath: 'README.md',
        proposedContent: '${original.content}\nchanged\n',
      );

      final receipt = await service.commit(
        backend: backend,
        changeSet: changeSet,
      );
      expect(receipt.backupId, startsWith('fake-backup-'));
      expect(
        (await backend.snapshotText(workspace, 'README.md')).content,
        contains('changed'),
      );

      final restored = await service.restore(
        backend: backend,
        changeSet: changeSet,
        receipt: receipt,
      );
      expect(restored.restored, isTrue);
      expect(
        (await backend.snapshotText(workspace, 'README.md')).content,
        original.content,
      );
    },
  );

  test('commit rejects a target changed after preview', () async {
    final backend = FakeBackend();
    final workspace = await backend.openWorkspace(
      (await backend.listWorkspaces()).single,
    );
    final service = ChangeSetService();
    final before = await backend.snapshotText(workspace, 'README.md');
    final changeSet = await service.preview(
      backend: backend,
      workspace: workspace,
      relativePath: 'README.md',
      proposedContent: 'agent edit\n',
    );
    await backend.writeText(
      workspace,
      'README.md',
      expectedVersion: before.version,
      content: 'external edit\n',
    );

    await expectLater(
      service.commit(backend: backend, changeSet: changeSet),
      throwsA(
        isA<BackendException>().having(
          (error) => error.message,
          'message',
          contains('conflict'),
        ),
      ),
    );
  });

  test('creates a backup without writing file contents', () async {
    final backend = FakeBackend();
    final workspace = await backend.openWorkspace(
      (await backend.listWorkspaces()).single,
    );
    final before = await backend.snapshotText(workspace, 'README.md');
    final receipt = await backend.backupText(
      workspace,
      'README.md',
      expectedVersion: before.version,
    );

    expect(receipt.beforeVersion, before.version);
    expect(receipt.afterVersion, before.version);
    expect(
      (await backend.snapshotText(workspace, 'README.md')).content,
      before.content,
    );

    final write = await backend.writeText(
      workspace,
      'README.md',
      expectedVersion: before.version,
      content: 'agent applied\n',
    );
    await backend.restoreText(
      workspace,
      'README.md',
      backupId: receipt.backupId,
      expectedVersion: write.afterVersion,
    );
    expect(
      (await backend.snapshotText(workspace, 'README.md')).content,
      before.content,
    );
  });

  test('scans nested text files and prepares one preview per match', () async {
    final backend = FakeBackend();
    final workspace = await backend.openWorkspace(
      (await backend.listWorkspaces()).single,
    );

    final result = await BatchTextChangeService().scan(
      backend: backend,
      workspace: workspace,
      search: 'fixture',
      replacement: 'sample',
    );

    expect(result.scannedFiles, 2);
    expect(
      result.previews.map((preview) => preview.relativePath),
      containsAll(<String>['README.md', 'lib/main.dart']),
    );
    expect(
      result.previews.every((preview) => preview.changeSet.hasChanges),
      isTrue,
    );
    expect(result.issues, isEmpty);
  });

  test(
    'commits and restores every matched file with individual backups',
    () async {
      final backend = FakeBackend();
      final workspace = await backend.openWorkspace(
        (await backend.listWorkspaces()).single,
      );
      final service = BatchTextChangeService();

      final scan = await service.scan(
        backend: backend,
        workspace: workspace,
        search: 'fixture',
        replacement: 'sample',
      );
      final commit = await service.commit(backend: backend, scan: scan);

      expect(commit.successfulCount, 2);
      expect(commit.failedCount, 0);
      expect(
        (await backend.snapshotText(workspace, 'README.md')).content,
        contains('sample'),
      );
      expect(
        (await backend.snapshotText(workspace, 'lib/main.dart')).content,
        contains('sample'),
      );

      final restore = await service.restore(backend: backend, commit: commit);
      expect(restore.successfulCount, 2);
      expect(restore.failedCount, 0);
      expect(
        (await backend.snapshotText(workspace, 'README.md')).content,
        contains('fixture'),
      );
      expect(
        (await backend.snapshotText(workspace, 'lib/main.dart')).content,
        contains('fixture'),
      );
    },
  );

  test(
    'continues after one file conflict and restores successful files',
    () async {
      final backend = _BatchConflictBackend();
      final workspace = await backend.openWorkspace(
        (await backend.listWorkspaces()).single,
      );
      final service = BatchTextChangeService();
      final scan = await service.scan(
        backend: backend,
        workspace: workspace,
        search: 'fixture',
        replacement: 'sample',
      );

      final commit = await service.commit(backend: backend, scan: scan);
      expect(commit.successfulCount, 1);
      expect(commit.failedCount, 1);
      expect(
        commit.files
            .singleWhere((file) => file.preview.relativePath == 'lib/main.dart')
            .error,
        contains('conflict'),
      );

      final restore = await service.restore(backend: backend, commit: commit);
      expect(restore.successfulCount, 1);
      expect(restore.failedCount, 0);
      expect(
        (await backend.snapshotText(workspace, 'README.md')).content,
        contains('fixture'),
      );
    },
  );
}

class _BatchConflictBackend extends FakeBackend {
  @override
  Future<WriteReceipt> writeText(
    WorkspaceHandle workspace,
    String relativePath, {
    required String expectedVersion,
    required String content,
  }) {
    if (relativePath == 'lib/main.dart') {
      throw const BackendException('conflict: external change detected.');
    }
    return super.writeText(
      workspace,
      relativePath,
      expectedVersion: expectedVersion,
      content: content,
    );
  }
}
