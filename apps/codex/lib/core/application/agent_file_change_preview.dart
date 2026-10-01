import 'dart:convert';

import '../domain/backend.dart';
import '../domain/change_set.dart';
import '../domain/workspace.dart';

/// A server-proposed file change prepared for the approval UI.
///
/// [changeSet] is present only when the protocol supplied complete new text
/// and the current host snapshot was readable. A server diff by itself is
/// still useful for review, but it cannot be committed or backed up by the
/// managed ChangeSet API without inventing the missing file contents.
class AgentFileChangePreview {
  const AgentFileChangePreview({
    required this.path,
    required this.kind,
    required this.diff,
    this.current,
    this.changeSet,
    this.issue,
  });

  final String path;
  final String kind;
  final String diff;
  final TextFileSnapshot? current;
  final TextChangeSet? changeSet;
  final String? issue;

  bool get isManaged => changeSet != null;
}

class AgentFileChangePreviewService {
  Future<List<AgentFileChangePreview>> prepare({
    required Backend backend,
    required WorkspaceHandle workspace,
    required Map<String, dynamic> params,
  }) async {
    final rawChanges = params['changes'];
    if (rawChanges is! List) {
      return const <AgentFileChangePreview>[
        AgentFileChangePreview(
          path: '<unknown>',
          kind: 'unknown',
          diff: '',
          issue: 'The file-change request did not include a changes list.',
        ),
      ];
    }
    if (rawChanges.isEmpty) {
      return const <AgentFileChangePreview>[
        AgentFileChangePreview(
          path: '<empty>',
          kind: 'unknown',
          diff: '',
          issue: 'The file-change request contained no file entries.',
        ),
      ];
    }

    final previews = <AgentFileChangePreview>[];
    for (final rawChange in rawChanges) {
      if (rawChange is! Map) {
        previews.add(
          const AgentFileChangePreview(
            path: '<invalid>',
            kind: 'unknown',
            diff: '',
            issue: 'The server returned a non-object file entry.',
          ),
        );
        continue;
      }
      final change = <String, dynamic>{
        for (final entry in rawChange.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final rawPath =
          _string(change['path']) ??
          _string(change['relativePath']) ??
          _string(change['file']);
      final kind = _string(change['kind']) ?? 'change';
      if (rawPath == null || rawPath.isEmpty) {
        previews.add(
          AgentFileChangePreview(
            path: '<missing path>',
            kind: kind,
            diff: _string(change['diff']) ?? '',
            issue: 'The server file entry did not include a path.',
          ),
        );
        continue;
      }

      final relativePath = _relativePath(workspace.ref, rawPath);
      if (relativePath == null) {
        previews.add(
          AgentFileChangePreview(
            path: rawPath,
            kind: kind,
            diff: _string(change['diff']) ?? '',
            issue: 'The proposed path is outside the selected workspace.',
          ),
        );
        continue;
      }

      TextFileSnapshot? current;
      String? issue;
      try {
        current = await backend.snapshotText(workspace, relativePath);
      } on BackendException catch (error) {
        issue = 'Could not read current snapshot: ${error.message}';
      } catch (error) {
        issue = 'Could not read current snapshot: $error';
      }

      final proposedContent =
          _string(change['proposedContent']) ??
          _string(change['newContent']) ??
          _string(change['after']) ??
          _string(change['content']);
      TextChangeSet? changeSet;
      if (current != null && proposedContent != null) {
        changeSet = TextChangeSet(
          backendId: backend.descriptor.id,
          workspace: workspace,
          relativePath: relativePath,
          before: current,
          proposedContent: proposedContent,
          diff: buildUnifiedDiff(
            path: relativePath,
            before: current.content,
            after: proposedContent,
          ),
        );
      } else if (proposedContent == null && issue == null) {
        issue = 'The server supplied only a diff; managed backup needs complete new text.';
      }

      previews.add(
        AgentFileChangePreview(
          path: relativePath,
          kind: kind,
          diff:
              changeSet?.diff ??
              _string(change['diff']) ??
              const JsonEncoder.withIndent('  ').convert(change),
          current: current,
          changeSet: changeSet,
          issue: issue,
        ),
      );
    }
    return previews;
  }

  static String? _string(Object? value) => value is String ? value : null;

  static String? _relativePath(WorkspaceRef workspace, String rawPath) {
    final normalizedHost = workspace.hostPath.endsWith('/')
        ? workspace.hostPath.substring(0, workspace.hostPath.length - 1)
        : workspace.hostPath;
    final relative = rawPath == normalizedHost
        ? null
        : rawPath.startsWith('$normalizedHost/')
        ? rawPath.substring(normalizedHost.length + 1)
        : rawPath.startsWith('/')
        ? null
        : rawPath;
    if (relative == null || relative.isEmpty || relative.endsWith('/')) {
      return null;
    }
    final segments = relative.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f),
    )) {
      return null;
    }
    return relative;
  }
}
