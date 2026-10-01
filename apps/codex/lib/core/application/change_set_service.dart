import '../domain/backend.dart';
import '../domain/change_set.dart';
import '../domain/workspace.dart';

class ChangeSetService {
  Future<TextChangeSet> preview({
    required Backend backend,
    required WorkspaceHandle workspace,
    required String relativePath,
    required String proposedContent,
  }) async {
    final before = await backend.snapshotText(workspace, relativePath);
    return TextChangeSet(
      backendId: backend.descriptor.id,
      workspace: workspace,
      relativePath: relativePath,
      before: before,
      proposedContent: proposedContent,
      diff: buildUnifiedDiff(
        path: relativePath,
        before: before.content,
        after: proposedContent,
      ),
    );
  }

  Future<WriteReceipt> commit({
    required Backend backend,
    required TextChangeSet changeSet,
  }) async {
    if (!changeSet.hasChanges) {
      throw const BackendException('No changes to commit.');
    }
    return backend.writeText(
      changeSet.workspace,
      changeSet.relativePath,
      expectedVersion: changeSet.before.version,
      content: changeSet.proposedContent,
    );
  }

  Future<WriteReceipt> restore({
    required Backend backend,
    required TextChangeSet changeSet,
    required WriteReceipt receipt,
    String? expectedVersion,
  }) {
    return backend.restoreText(
      changeSet.workspace,
      changeSet.relativePath,
      backupId: receipt.backupId,
      expectedVersion: expectedVersion ?? receipt.afterVersion,
    );
  }
}
