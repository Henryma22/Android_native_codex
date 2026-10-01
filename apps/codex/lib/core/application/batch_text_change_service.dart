import '../domain/backend.dart';
import '../domain/change_set.dart';
import '../domain/workspace.dart';

const int defaultBatchMaxFiles = 500;
const int defaultBatchMaxDepth = 32;
const int defaultBatchMaxFileBytes = 1024 * 1024;

class BatchTextChangePreview {
  const BatchTextChangePreview(this.changeSet);

  final TextChangeSet changeSet;

  String get relativePath => changeSet.relativePath;
}

class BatchScanIssue {
  const BatchScanIssue({required this.path, required this.message});

  final String path;
  final String message;
}

class BatchScanResult {
  const BatchScanResult({
    required this.scannedFiles,
    required this.previews,
    required this.issues,
    required this.maxFiles,
  });

  final int scannedFiles;
  final List<BatchTextChangePreview> previews;
  final List<BatchScanIssue> issues;
  final int maxFiles;

  bool get hasMatches => previews.isNotEmpty;
}

class BatchCommitFileResult {
  const BatchCommitFileResult({
    required this.preview,
    this.receipt,
    this.error,
  });

  final BatchTextChangePreview preview;
  final WriteReceipt? receipt;
  final String? error;

  bool get succeeded => receipt != null && error == null;
}

class BatchCommitResult {
  const BatchCommitResult(this.files);

  final List<BatchCommitFileResult> files;

  int get successfulCount => files.where((file) => file.succeeded).length;

  int get failedCount => files.length - successfulCount;

  bool get allSucceeded => files.isNotEmpty && failedCount == 0;
}

class BatchRestoreFileResult {
  const BatchRestoreFileResult({
    required this.commit,
    this.receipt,
    this.error,
  });

  final BatchCommitFileResult commit;
  final WriteReceipt? receipt;
  final String? error;

  bool get succeeded => receipt != null && error == null;
}

class BatchRestoreResult {
  const BatchRestoreResult(this.files);

  final List<BatchRestoreFileResult> files;

  int get successfulCount => files.where((file) => file.succeeded).length;

  int get failedCount => files.length - successfulCount;
}

/// Scans a workspace and applies a replacement one file at a time.
///
/// Each write uses the version captured by its preview. The backend creates
/// the per-file backup, so a batch is deliberately not presented as a
/// cross-file transaction: a conflict can leave a partial result that is
/// reported explicitly and can be restored file by file.
class BatchTextChangeService {
  Future<BatchScanResult> scan({
    required Backend backend,
    required WorkspaceHandle workspace,
    required String search,
    required String replacement,
    int maxFiles = defaultBatchMaxFiles,
    int maxDepth = defaultBatchMaxDepth,
    int maxFileBytes = defaultBatchMaxFileBytes,
  }) async {
    if (search.isEmpty) {
      throw const BackendException('Search text must not be empty.');
    }
    if (maxFiles < 1 || maxDepth < 0 || maxFileBytes < 1) {
      throw const BackendException('Batch scan limits must be positive.');
    }

    final previews = <BatchTextChangePreview>[];
    final issues = <BatchScanIssue>[];
    var scannedFiles = 0;
    var stoppedAtLimit = false;

    Future<void> walk(String relativePath, int depth) async {
      if (stoppedAtLimit) return;
      List<WorkspaceEntry> entries;
      try {
        entries = await backend.listDirectory(
          workspace,
          relativePath: relativePath,
        );
      } catch (error) {
        issues.add(
          BatchScanIssue(
            path: relativePath.isEmpty ? '.' : relativePath,
            message: _errorMessage(error),
          ),
        );
        return;
      }

      for (final entry in entries) {
        if (stoppedAtLimit) return;
        if (entry.isDirectory) {
          if (depth >= maxDepth) {
            issues.add(
              BatchScanIssue(
                path: entry.relativePath,
                message: 'maximum scan depth $maxDepth reached',
              ),
            );
            continue;
          }
          await walk(entry.relativePath, depth + 1);
          continue;
        }

        if (scannedFiles >= maxFiles) {
          issues.add(
            BatchScanIssue(
              path: entry.relativePath,
              message: 'maximum file limit $maxFiles reached',
            ),
          );
          stoppedAtLimit = true;
          return;
        }
        scannedFiles++;

        if (entry.sizeBytes > maxFileBytes) {
          issues.add(
            BatchScanIssue(
              path: entry.relativePath,
              message: 'file exceeds the $maxFileBytes-byte text limit',
            ),
          );
          continue;
        }

        try {
          final before = await backend.snapshotText(
            workspace,
            entry.relativePath,
          );
          if (before.isSymbolicLink) {
            issues.add(
              BatchScanIssue(
                path: entry.relativePath,
                message: 'symbolic links are not eligible for batch writes',
              ),
            );
            continue;
          }
          final proposedContent = before.content.replaceAll(
            search,
            replacement,
          );
          if (proposedContent == before.content) continue;
          previews.add(
            BatchTextChangePreview(
              TextChangeSet(
                backendId: backend.descriptor.id,
                workspace: workspace,
                relativePath: before.relativePath,
                before: before,
                proposedContent: proposedContent,
                diff: buildUnifiedDiff(
                  path: before.relativePath,
                  before: before.content,
                  after: proposedContent,
                ),
              ),
            ),
          );
        } catch (error) {
          issues.add(
            BatchScanIssue(
              path: entry.relativePath,
              message: _errorMessage(error),
            ),
          );
        }
      }
    }

    await walk('', 0);
    previews.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    issues.sort((left, right) {
      final pathOrder = left.path.compareTo(right.path);
      return pathOrder == 0 ? left.message.compareTo(right.message) : pathOrder;
    });
    return BatchScanResult(
      scannedFiles: scannedFiles,
      previews: List.unmodifiable(previews),
      issues: List.unmodifiable(issues),
      maxFiles: maxFiles,
    );
  }

  Future<BatchCommitResult> commit({
    required Backend backend,
    required BatchScanResult scan,
  }) async {
    if (scan.previews.isEmpty) {
      throw const BackendException('No matching files to commit.');
    }
    final results = <BatchCommitFileResult>[];
    for (final preview in scan.previews) {
      final changeSet = preview.changeSet;
      try {
        final receipt = await backend.writeText(
          changeSet.workspace,
          changeSet.relativePath,
          expectedVersion: changeSet.before.version,
          content: changeSet.proposedContent,
        );
        results.add(BatchCommitFileResult(preview: preview, receipt: receipt));
      } catch (error) {
        results.add(
          BatchCommitFileResult(preview: preview, error: _errorMessage(error)),
        );
      }
    }
    return BatchCommitResult(List.unmodifiable(results));
  }

  Future<BatchRestoreResult> restore({
    required Backend backend,
    required BatchCommitResult commit,
  }) async {
    final results = <BatchRestoreFileResult>[];
    for (final file in commit.files) {
      final receipt = file.receipt;
      if (receipt == null) continue;
      final changeSet = file.preview.changeSet;
      try {
        final current = await backend.snapshotText(
          changeSet.workspace,
          changeSet.relativePath,
        );
        final restored = await backend.restoreText(
          changeSet.workspace,
          changeSet.relativePath,
          backupId: receipt.backupId,
          expectedVersion: current.version,
        );
        results.add(BatchRestoreFileResult(commit: file, receipt: restored));
      } catch (error) {
        results.add(
          BatchRestoreFileResult(commit: file, error: _errorMessage(error)),
        );
      }
    }
    return BatchRestoreResult(List.unmodifiable(results));
  }

  String _errorMessage(Object error) {
    if (error is BackendException) return error.message;
    return '$error';
  }
}
