import 'workspace.dart';

class TextFileSnapshot {
  const TextFileSnapshot({
    required this.relativePath,
    required this.content,
    required this.version,
    required this.sizeBytes,
    this.uid,
    this.gid,
    this.mode,
    this.isSymbolicLink = false,
  });

  final String relativePath;
  final String content;

  /// An opaque optimistic-concurrency token supplied by the backend.
  final String version;
  final int sizeBytes;
  final int? uid;
  final int? gid;
  final String? mode;
  final bool isSymbolicLink;
}

class WriteReceipt {
  const WriteReceipt({
    required this.backupId,
    required this.relativePath,
    required this.beforeVersion,
    required this.afterVersion,
    this.restored = false,
  });

  final String backupId;
  final String relativePath;
  final String beforeVersion;
  final String afterVersion;
  final bool restored;
}

class TextChangeSet {
  const TextChangeSet({
    required this.backendId,
    required this.workspace,
    required this.relativePath,
    required this.before,
    required this.proposedContent,
    required this.diff,
    this.receipt,
  });

  final String backendId;
  final WorkspaceHandle workspace;
  final String relativePath;
  final TextFileSnapshot before;
  final String proposedContent;
  final String diff;
  final WriteReceipt? receipt;

  bool get hasChanges => before.content != proposedContent;

  TextChangeSet withReceipt(WriteReceipt value) {
    return TextChangeSet(
      backendId: backendId,
      workspace: workspace,
      relativePath: relativePath,
      before: before,
      proposedContent: proposedContent,
      diff: diff,
      receipt: value,
    );
  }
}

String buildUnifiedDiff({
  required String path,
  required String before,
  required String after,
}) {
  if (before == after) return '';

  final beforeLines = before.split('\n');
  final afterLines = after.split('\n');
  var prefix = 0;
  while (prefix < beforeLines.length &&
      prefix < afterLines.length &&
      beforeLines[prefix] == afterLines[prefix]) {
    prefix++;
  }

  var beforeEnd = beforeLines.length - 1;
  var afterEnd = afterLines.length - 1;
  while (beforeEnd >= prefix &&
      afterEnd >= prefix &&
      beforeLines[beforeEnd] == afterLines[afterEnd]) {
    beforeEnd--;
    afterEnd--;
  }

  final lines = <String>['--- $path', '+++ $path'];
  lines.add('@@');
  lines.addAll(
    beforeLines.sublist(prefix, beforeEnd + 1).map((line) => '-$line'),
  );
  lines.addAll(
    afterLines.sublist(prefix, afterEnd + 1).map((line) => '+$line'),
  );
  return '${lines.join('\n')}\n';
}
