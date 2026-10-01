import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/session.dart';

void main() {
  SessionInteractionState state() => SessionInteractionState.initial(
    workspaceId: 'local|/storage/emulated/0/Codex/Workspaces/demo',
    sessionId: 'local-session-1',
  );

  test('keeps app session identity while provider thread is added later', () {
    final initial = state();
    final ready = initial.transition(
      SessionLifecycleEvent.ready,
      threadId: 'thread-1',
    );

    expect(
      initial.identity.workspaceId,
      'local|/storage/emulated/0/Codex/Workspaces/demo',
    );
    expect(ready.identity.sessionId, 'local-session-1');
    expect(ready.identity.threadId, 'thread-1');
    expect(ready.phase, SessionState.ready);
    expect(ready.isActive, isTrue);
  });

  test('maps a turn and approval without losing the resumable thread', () {
    final running = state()
        .transition(SessionLifecycleEvent.ready, threadId: 'thread-1')
        .transition(SessionLifecycleEvent.turnStarted);
    final waiting = running.transition(SessionLifecycleEvent.approvalRequested);
    final finished = waiting.transition(SessionLifecycleEvent.turnFinished);

    expect(running.phase, SessionState.running);
    expect(running.isTurnActive, isTrue);
    expect(waiting.phase, SessionState.waitingApproval);
    expect(waiting.canCompose, isFalse);
    expect(finished.phase, SessionState.ready);
    expect(finished.identity.threadId, 'thread-1');
  });

  test('allows pending prompts during disconnect and reconnect', () {
    final disconnected = state()
        .transition(SessionLifecycleEvent.ready, threadId: 'thread-1')
        .transition(SessionLifecycleEvent.disconnected);
    final reconnecting = disconnected.transition(
      SessionLifecycleEvent.reconnectRequested,
    );

    expect(disconnected.phase, SessionState.disconnected);
    expect(disconnected.canResume, isTrue);
    expect(disconnected.canQueuePrompt, isTrue);
    expect(reconnecting.phase, SessionState.reconnecting);
    expect(reconnecting.canQueuePrompt, isTrue);
  });

  test(
    'new session clears the provider thread but preserves local identity',
    () {
      final resumed = state().transition(
        SessionLifecycleEvent.ready,
        threadId: 'thread-1',
      );
      final fresh = resumed.transition(
        SessionLifecycleEvent.newSession,
        clearThread: true,
      );

      expect(fresh.phase, SessionState.stopped);
      expect(fresh.identity.sessionId, 'local-session-1');
      expect(fresh.identity.threadId, isNull);
      expect(fresh.canResume, isFalse);
    },
  );

  test('unknown provider statuses do not corrupt interaction state', () {
    final ready = state().transition(
      SessionLifecycleEvent.ready,
      threadId: 'thread-1',
    );
    final unchanged = ready.applyProviderStatus('compacting');

    expect(unchanged.phase, SessionState.ready);
    expect(unchanged.identity.threadId, 'thread-1');
  });
}
