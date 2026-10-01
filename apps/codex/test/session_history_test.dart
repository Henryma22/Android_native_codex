import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/execution.dart';
import 'package:codex/core/domain/transcript.dart';
import 'package:codex/core/domain/workspace.dart';
import 'package:codex/services/session_history.dart';

void main() {
  test('decodes app-private history without making it an active session', () {
    final history = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/storage/emulated/0/Codex/Workspaces/demo',
      'status': 'stopped',
      'updatedAtEpochMs': 123,
      'sessionId': 'local-session-1',
      'threadId': 'thread-1',
      'threadPath':
          '/home/codex/sessions/local-session-1/rollouts/thread.jsonl',
      'customProviderId': 'deepseek-config',
      'title': 'Release checklist',
      'draft': 'continue from here',
      'queuedPrompts': <Object?>['then inspect the diff', 42],
      'codexModel': 'some-other-model',
      'codexEffort': 'high',
      'executionIdentity': 'root',
      'rootApprovalGranted': true,
      'codexSandbox': 'read-only',
      'codexApprovalPolicy': 'on-failure',
      'codexPlanMode': true,
      'pinned': true,
      'promptHistory': <Object?>['inspect the diff', 42],
      'entries': <Object?>['You: inspect', 'Codex: done', 42],
    });

    expect(history.backendId, 'local-android');
    expect(history.workspacePath, contains('/Workspaces/demo'));
    expect(history.sessionId, 'local-session-1');
    expect(history.threadId, 'thread-1');
    expect(
      history.threadPath,
      '/home/codex/sessions/local-session-1/rollouts/thread.jsonl',
    );
    expect(history.customProviderId, 'deepseek-config');
    expect(history.title, 'Release checklist');
    expect(history.displayTitle, 'Release checklist');
    expect(history.draft, 'continue from here');
    expect(history.queuedPrompts, <String>['then inspect the diff']);
    expect(history.codexModel, 'some-other-model');
    expect(history.codexEffort, 'high');
    expect(history.executionIdentity, ExecutionIdentity.root);
    expect(history.rootApprovalGranted, isTrue);
    expect(history.codexSandbox, 'read-only');
    expect(history.codexApprovalPolicy, 'on-failure');
    expect(history.codexPlanMode, isTrue);
    expect(history.pinned, isTrue);
    expect(history.promptHistory, <String>['inspect the diff']);
    expect(history.entries, <String>['You: inspect', 'Codex: done']);
    expect(history.shouldAutoResume, isFalse);
    expect(history.latestEntry, 'Codex: done');
    expect(history.preview, 'done');
    expect(history.workspaceName, 'demo');
    expect(history.matches('inspect'), isTrue);
    expect(history.matches('release checklist'), isTrue);
    expect(history.matches('missing'), isFalse);
  });

  test('preserves full-access mode when reopening a Root session', () {
    final history = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'linux-compatibility',
      'workspacePath': '/storage/emulated/0/Codex/Workspaces/root-demo',
      'status': 'stopped',
      'updatedAtEpochMs': 123,
      'sessionId': 'root-session-1',
      'executionIdentity': 'root',
      'codexSandbox': 'danger-full-access',
      'codexApprovalPolicy': 'never',
      'entries': const <Object?>[],
    });

    expect(history.executionIdentity, ExecutionIdentity.root);
    expect(history.codexSandbox, 'danger-full-access');
    expect(history.codexApprovalPolicy, 'never');
  });

  test(
    'auto-resumes durable sessions unless the user explicitly stopped them',
    () {
      final resumable = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'local-android',
        'workspacePath': '/workspace/demo',
        'status': 'ready',
        'updatedAtEpochMs': 123,
        'sessionId': 'local-session-1',
        'threadId': 'thread-1',
        'entries': const <Object?>[],
      });
      final stopped = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'local-android',
        'workspacePath': '/workspace/demo',
        'status': 'stopped',
        'updatedAtEpochMs': 123,
        'sessionId': 'local-session-2',
        'threadId': 'thread-2',
        'entries': const <Object?>[],
      });
      final legacy = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'local-android',
        'workspacePath': '/workspace/demo',
        'status': 'ready',
        'updatedAtEpochMs': 123,
        'threadId': 'thread-3',
        'entries': const <Object?>[],
      });

      expect(resumable.shouldAutoResume, isTrue);
      expect(stopped.shouldAutoResume, isFalse);
      expect(legacy.shouldAutoResume, isFalse);
    },
  );

  test('only resumes a history row from the current auth generation', () {
    final current = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/workspace/demo',
      'status': 'ready',
      'updatedAtEpochMs': 123,
      'sessionId': 'local-session-current',
      'threadId': 'thread-current',
      'authGeneration': 7,
      'entries': const <Object?>[],
    });
    final old = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/workspace/demo',
      'status': 'ready',
      'updatedAtEpochMs': 123,
      'sessionId': 'local-session-old',
      'threadId': 'thread-old',
      'authGeneration': 6,
      'entries': const <Object?>[],
    });
    final legacy = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/workspace/demo',
      'status': 'ready',
      'updatedAtEpochMs': 123,
      'sessionId': 'local-session-legacy',
      'threadId': 'thread-legacy',
      'entries': const <Object?>[],
    });

    expect(current.canAutoResumeForAuthGeneration(7), isTrue);
    expect(current.canAutoResumeForAuthGeneration(6), isFalse);
    expect(old.canAutoResumeForAuthGeneration(7), isFalse);
    expect(legacy.canAutoResumeForAuthGeneration(7), isFalse);
  });

  test(
    'third-party provider history is independent of OpenAI auth generation',
    () {
      final providerSession = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'linux-compatibility',
        'workspacePath': '/storage/emulated/0/Codex/Workspaces/demo',
        'status': 'ready',
        'updatedAtEpochMs': 123,
        'sessionId': 'custom-provider-session',
        'threadId': 'custom-provider-thread',
        'authGeneration': 6,
        'customProviderId': 'deepseek',
        'entries': const <Object?>[],
      });

      expect(providerSession.canAutoResumeForAuthGeneration(7), isTrue);
    },
  );

  test(
    'prefers Codex-generated names but preserves a manual session rename',
    () {
      final generated = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'local-android',
        'workspacePath': '/workspace/demo',
        'status': 'stopped',
        'updatedAtEpochMs': 1,
        'title': 'Build the settings page',
        'threadName': 'Settings UX implementation',
        'titleIsManual': false,
        'entries': const <Object?>[
          'You: Build the settings page',
          'Codex: The settings page is complete.',
          'You: Also check model switching',
          'Codex: The model menu opens quickly.',
        ],
      });
      expect(generated.generatedTitle, 'Build the settings page');
      expect(generated.displayTitle, 'Settings UX implementation');
      expect(generated.firstUserPrompt, 'Build the settings page');
      expect(generated.latestUserPrompt, 'Also check model switching');

      final legacyManual = SessionHistoryRecord.fromMap(<Object?, Object?>{
        'backendId': 'local-android',
        'workspacePath': '/workspace/demo',
        'status': 'stopped',
        'updatedAtEpochMs': 1,
        'title': 'My task name',
        'threadName': 'Codex generated name',
        'entries': const <Object?>['You: Build the settings page'],
      });
      expect(legacyManual.titleIsManual, isTrue);
      expect(legacyManual.displayTitle, 'My task name');

      final manualMatchingPrompt = SessionHistoryRecord.fromMap(
        <Object?, Object?>{
          'backendId': 'local-android',
          'workspacePath': '/workspace/demo',
          'status': 'stopped',
          'updatedAtEpochMs': 1,
          'title': 'Build the settings page',
          'threadName': 'Settings UX implementation',
          'titleIsManual': true,
          'entries': const <Object?>['You: Build the settings page'],
        },
      );
      expect(manualMatchingPrompt.displayTitle, 'Build the settings page');
    },
  );

  test('renders SAF document IDs as readable workspace names', () {
    const encodedPath = 'primary%3ACodex%2FWorkspaces%2Fvm-demo';
    const contentUri =
        'content://com.android.externalstorage.documents/tree/'
        'primary%3ACodex%2FWorkspaces%2Fvm-demo';
    final history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: encodedPath,
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[],
    );

    expect(
      humanReadableWorkspacePath(encodedPath),
      'primary:Codex/Workspaces/vm-demo',
    );
    expect(workspaceNameFromPath(encodedPath), 'vm-demo');
    expect(workspaceNameFromPath('SAF: $contentUri'), 'vm-demo');
    expect(history.workspacePath, encodedPath);
    expect(history.workspaceName, 'vm-demo');
  });

  test('does not restore Root approval from legacy workspace history', () {
    final history = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/workspace/demo',
      'executionIdentity': 'root',
      'rootApprovalGranted': true,
      'status': 'stopped',
      'updatedAtEpochMs': 1,
      'entries': const <Object?>[],
    });

    expect(history.executionIdentity, ExecutionIdentity.root);
    expect(history.rootApprovalGranted, isFalse);
  });

  test('serializes writes in enqueue order', () async {
    final queue = SessionHistoryWriteQueue();
    final firstGate = Completer<void>();
    final order = <String>[];

    final first = queue.enqueue(() async {
      order.add('first-start');
      await firstGate.future;
      order.add('first-end');
    });
    final second = queue.enqueue(() async {
      order.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, <String>['first-start']);

    firstGate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(order, <String>['first-start', 'first-end', 'second']);
  });

  test('turns structured assistant history into a readable preview', () {
    final history = SessionHistoryRecord.fromMap(<Object?, Object?>{
      'backendId': 'local-android',
      'workspacePath': '/workspace/demo',
      'status': 'stopped',
      'updatedAtEpochMs': 123,
      'entries': <Object?>[
        'Codex: \u001b[2m{"type":"agentMessage","text":"REALTURNOK"}\u001b[0m',
      ],
    });

    expect(history.preview, 'REALTURNOK');
  });

  test('uses the first user request as the generated session title', () {
    final history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: '/workspace/demo',
      status: 'stopped',
      updatedAtEpochMs: 123,
      entries: const <String>[
        'You: Build the settings page',
        'Codex: The settings page is complete and all tests passed.',
        'You: Now inspect the runtime',
      ],
    );

    expect(history.firstUserPrompt, 'Build the settings page');
    expect(history.latestUserPrompt, 'Now inspect the runtime');
    expect(history.generatedTitle, 'Build the settings page');
    expect(history.displayTitle, isNot(contains('tests passed')));
  });

  test('hides ANSI MCP transport diagnostics behind a readable notice', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: \u001b[31mERROR\u001b[0m rmcp::transport::worker: '
            'worker quit with fatal: transport channel closed',
      ],
    );

    expect(
      history.preview,
      'Optional MCP worker unavailable; the local Codex session continues without it.',
    );
  });

  test('hides the Android arg0 janitor lock diagnostic', () {
    final history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: WARNING: failed to clean up stale arg0 temp dirs: '
            'try_lock() not supported',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('hides the non-fatal models cache diagnostic', () {
    final history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: failed to load models cache: permission denied',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('hides the non-fatal model manager refresh timeout', () {
    final history = SessionHistoryRecord(
      backendId: 'local-android',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: 2026-09-22T03:16:52Z ERROR '
            'codex_models_manager::manager: failed to refresh available models: '
            'timeout waiting for child process to exit',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('hides model manager request timeout diagnostics from the preview', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'ready',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: ERROR codex_models_manager::manager: '
            'failed to refresh available models: request timed out',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('hides the non-fatal resumed thread read hand-off diagnostic', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'ready',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'stderr: read interrupted by close() on another thread',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('hides the expected PRoot bubblewrap capability diagnostic', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'ready',
      updatedAtEpochMs: 1,
      entries: const <String>[
        "stderr: ERROR codex_app_server: Codex's Linux sandbox uses "
            'bubblewrap and needs access to create user namespaces.',
      ],
    );

    expect(history.preview, 'Local Codex session');
  });

  test('keeps the last conversation visible after a trailing MCP notice', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'stopped',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'You: Reply exactly REALTURNOK and nothing else.',
        'Codex: REALTURNOK',
        'System: Optional MCP worker is unavailable on the current network.',
      ],
    );

    expect(history.preview, 'REALTURNOK');
  });

  test(
    'keeps a structured assistant preview ahead of a trailing MCP notice',
    () {
      final history = SessionHistoryRecord(
        backendId: 'local-android',
        workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
        status: 'stopped',
        updatedAtEpochMs: 1,
        entries: <String>[
          CodexTranscriptEntry(
            id: 'assistant-1',
            kind: CodexTranscriptKind.assistant,
            text: 'REALTURNOK',
            timestamp: DateTime(2026, 9, 20),
          ).toStored(),
          'System: Optional MCP worker is unavailable on the current network.',
        ],
      );

      expect(history.preview, 'REALTURNOK');
    },
  );

  test('hides provider TLS diagnostics behind a retryable notice', () {
    final history = SessionHistoryRecord(
      backendId: 'linux-compatibility',
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
      status: 'failed',
      updatedAtEpochMs: 1,
      entries: const <String>[
        'error: 2026-09-18T16:03:28Z ERROR codex_api::endpoint::responses_websocket: '
            'failed to connect to websocket: IO error: tls handshake eof',
      ],
    );

    expect(
      history.preview,
      'Provider network connection failed. Check Android Wi-Fi, mobile data, VPN, or proxy settings and retry. The local session remains available.',
    );
  });

  test('continues with the next write after a failed write', () async {
    final queue = SessionHistoryWriteQueue();
    final order = <String>[];

    final failed = queue.enqueue(() async {
      order.add('failed');
      throw StateError('fixture failure');
    });
    final next = queue.enqueue(() async {
      order.add('next');
    });

    await expectLater(failed, throwsA(isA<StateError>()));
    await next;
    expect(order, <String>['failed', 'next']);
  });
}
