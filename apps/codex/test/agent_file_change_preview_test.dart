import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/agent_file_change_preview.dart';

void main() {
  test('builds a managed ChangeSet when new file text is present', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final handle = await backend.openWorkspace(workspace);

    final previews = await AgentFileChangePreviewService().prepare(
      backend: backend,
      workspace: handle,
      params: <String, dynamic>{
        'changes': <Map<String, String>>[
          <String, String>{
            'path': 'README.md',
            'kind': 'update',
            'proposedContent': '# updated fixture\n',
          },
        ],
      },
    );

    expect(previews, hasLength(1));
    expect(previews.single.isManaged, isTrue);
    expect(previews.single.changeSet!.before.version, 'fake-v1');
    expect(previews.single.diff, contains('-# codex fixture'));
    expect(previews.single.diff, contains('+# updated fixture'));
  });

  test('keeps a diff-only or outside-workspace request unmanageable', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final handle = await backend.openWorkspace(workspace);

    final previews = await AgentFileChangePreviewService().prepare(
      backend: backend,
      workspace: handle,
      params: <String, dynamic>{
        'changes': <Map<String, String>>[
          <String, String>{
            'path': '/storage/emulated/0/Codex/Workspaces/other/README.md',
            'diff': '--- outside',
          },
          <String, String>{
            'path': 'README.md',
            'diff': '--- README.md\n+++ README.md',
          },
        ],
      },
    );

    expect(previews, hasLength(2));
    expect(previews.first.isManaged, isFalse);
    expect(previews.first.issue, contains('outside'));
    expect(previews.last.isManaged, isFalse);
    expect(previews.last.issue, contains('complete new text'));
    expect(previews.last.diff, contains('--- README.md'));
  });
}
