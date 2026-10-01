import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_thread_summary.dart';

void main() {
  test('parses thread metadata and keeps rollout paths out of safe JSON', () {
    final page = CodexThreadListPage.parseResponse(<String, dynamic>{
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'thread-1',
          'sessionId': 'session-1',
          'name': 'Fix the runtime',
          'preview': 'Fix the runtime\nwith a second line',
          'cwd': '/workspace/project',
          'path': '/private/codex/rollouts/thread-1.jsonl',
          'model': 'gpt-5.6-luna',
          'modelProvider': 'openai',
          'reasoningEffort': 'low',
          'cliVersion': '0.156.1',
          'source': 'appServer',
          'status': <String, dynamic>{
            'type': 'active',
            'activeFlags': <String>['waitingOnApproval'],
          },
          'createdAt': 100,
          'updatedAt': 200,
          'recencyAt': 210,
        },
      ],
      'nextCursor': 'next-page',
      'backwardsCursor': 'previous-page',
    });

    expect(page.threads, hasLength(1));
    final thread = page.threads.single;
    expect(thread.displayTitle, 'Fix the runtime');
    expect(thread.isActive, isTrue);
    expect(thread.activeFlags, <String>['waitingOnApproval']);
    expect(thread.displayLine(chinese: true), contains('运行中'));
    expect(thread.toSafeJsonMap(), isNot(contains('path')));
    expect(thread.toSafeJsonMap()['cwd'], '/workspace/project');
    expect(page.nextCursor, 'next-page');
    expect(page.backwardsCursor, 'previous-page');
  });

  test('falls back to the preview when the thread has no explicit name', () {
    final thread = CodexThreadSummary.parse(<String, dynamic>{
      'id': 'thread-2',
      'preview': '\nFirst prompt\nsecond line',
      'status': <String, String>{'type': 'idle'},
    });

    expect(thread.sessionId, 'thread-2');
    expect(thread.displayTitle, 'First prompt');
    expect(thread.status, 'idle');
  });

  test('rejects a thread entry without an id', () {
    expect(
      () => CodexThreadSummary.parse(<String, dynamic>{'preview': 'missing'}),
      throwsFormatException,
    );
  });
}
