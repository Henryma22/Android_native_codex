import 'workspace.dart';
import 'image_attachment.dart';

/// Conversation lifecycle exposed to the CC Pocket-style UI.
///
/// This is deliberately transport-neutral. A widget should not have to infer
/// whether a session is resumable by combining a raw status string with
/// process and request flags. The local app-server, a compatibility executor,
/// and fixture clients all project onto this same lifecycle.
enum SessionState {
  starting,
  ready,
  running,
  waitingApproval,
  reconnecting,
  disconnected,
  stopping,
  stopped,
  failed,
}

enum SessionLifecycleEvent {
  startRequested,
  ready,
  turnStarted,
  approvalRequested,
  turnFinished,
  reconnectRequested,
  disconnected,
  stopRequested,
  stopped,
  failed,
  newSession,
}

/// The stable identity shared by Home, the session page, and local history.
///
/// `sessionId` is the app-owned conversation identity. `threadId` is the
/// provider/app-server identity and may be absent before the first successful
/// start. Keeping both prevents a reconnect from accidentally creating a
/// second Home row for the same local conversation.
class SessionIdentity {
  const SessionIdentity({
    required this.workspaceId,
    required this.sessionId,
    this.threadId,
  });

  final String workspaceId;
  final String sessionId;
  final String? threadId;

  bool get isStable => workspaceId.trim().isNotEmpty && sessionId.isNotEmpty;

  SessionIdentity copyWith({String? threadId, bool clearThreadId = false}) {
    return SessionIdentity(
      workspaceId: workspaceId,
      sessionId: sessionId,
      threadId: clearThreadId ? null : (threadId ?? this.threadId),
    );
  }
}

/// Pure session interaction state machine used by the local UI.
///
/// The state machine owns only interaction semantics. It does not start a
/// process, persist data, or decide whether Android-native or Linux
/// compatibility execution is used.
class SessionInteractionState {
  const SessionInteractionState({
    required this.identity,
    this.phase = SessionState.stopped,
    this.error,
  });

  factory SessionInteractionState.initial({
    required String workspaceId,
    required String sessionId,
    String? threadId,
  }) {
    return SessionInteractionState(
      identity: SessionIdentity(
        workspaceId: workspaceId,
        sessionId: sessionId,
        threadId: threadId,
      ),
    );
  }

  final SessionIdentity identity;
  final SessionState phase;
  final String? error;

  SessionInteractionState withIdentity({
    required String workspaceId,
    required String sessionId,
    String? threadId,
  }) {
    return SessionInteractionState(
      identity: SessionIdentity(
        workspaceId: workspaceId,
        sessionId: sessionId,
        threadId: threadId,
      ),
      phase: phase,
      error: error,
    );
  }

  bool get hasProviderThread => identity.threadId?.isNotEmpty == true;

  bool get isActive => switch (phase) {
    SessionState.starting ||
    SessionState.ready ||
    SessionState.running ||
    SessionState.waitingApproval ||
    SessionState.reconnecting ||
    SessionState.disconnected ||
    SessionState.stopping => true,
    SessionState.failed => hasProviderThread,
    SessionState.stopped => false,
  };

  bool get isTurnActive => switch (phase) {
    SessionState.running || SessionState.waitingApproval => true,
    SessionState.starting ||
    SessionState.ready ||
    SessionState.reconnecting ||
    SessionState.disconnected ||
    SessionState.stopping ||
    SessionState.stopped ||
    SessionState.failed => false,
  };

  bool get canResume =>
      (phase == SessionState.disconnected ||
          phase == SessionState.failed ||
          phase == SessionState.stopped) &&
      hasProviderThread;

  bool get canCompose =>
      phase == SessionState.ready || phase == SessionState.running;

  /// Prompts may remain visible and queued while a provider turn is running.
  /// During a reconnect they are also accepted, matching CC Pocket's pending
  /// resume behavior; the coordinator drains them only after [ready].
  bool get canQueuePrompt =>
      phase == SessionState.running ||
      phase == SessionState.disconnected ||
      phase == SessionState.reconnecting;

  SessionInteractionState transition(
    SessionLifecycleEvent event, {
    String? threadId,
    String? error,
    bool clearThread = false,
  }) {
    final nextIdentity = clearThread
        ? identity.copyWith(clearThreadId: true)
        : threadId == null
        ? identity
        : identity.copyWith(threadId: threadId);
    final next = switch (event) {
      SessionLifecycleEvent.startRequested => SessionState.starting,
      SessionLifecycleEvent.ready => SessionState.ready,
      SessionLifecycleEvent.turnStarted => SessionState.running,
      SessionLifecycleEvent.approvalRequested => SessionState.waitingApproval,
      SessionLifecycleEvent.turnFinished => SessionState.ready,
      SessionLifecycleEvent.reconnectRequested => SessionState.reconnecting,
      SessionLifecycleEvent.disconnected => SessionState.disconnected,
      SessionLifecycleEvent.stopRequested => SessionState.stopping,
      SessionLifecycleEvent.stopped => SessionState.stopped,
      SessionLifecycleEvent.failed => SessionState.failed,
      SessionLifecycleEvent.newSession => SessionState.stopped,
    };
    return SessionInteractionState(
      identity: nextIdentity,
      phase: next,
      error: event == SessionLifecycleEvent.failed ? error : null,
    );
  }

  /// Maps the provider's display status onto the UI lifecycle. Unknown
  /// statuses intentionally leave the lifecycle unchanged; they can still be
  /// shown in the status line without breaking composer/resume behavior.
  SessionInteractionState applyProviderStatus(
    String status, {
    String? threadId,
  }) {
    final normalized = status.trim().toLowerCase();
    final event = switch (normalized) {
      'starting' => SessionLifecycleEvent.startRequested,
      'ready' || 'idle' => SessionLifecycleEvent.ready,
      'running' ||
      'thinking' ||
      'interrupting' => SessionLifecycleEvent.turnStarted,
      'waiting approval' ||
      'waiting' => SessionLifecycleEvent.approvalRequested,
      'stopped' => SessionLifecycleEvent.stopped,
      'failed' => SessionLifecycleEvent.failed,
      _ => null,
    };
    if (event == null) return this;
    return transition(event, threadId: threadId);
  }
}

class SessionRef {
  const SessionRef({
    required this.backendId,
    required this.providerSessionId,
    required this.workspace,
  });

  final String backendId;
  final String providerSessionId;
  final WorkspaceRef workspace;
}

enum CodexSessionEventType {
  status,
  threadName,
  user,
  assistantDelta,
  reasoningDelta,
  usage,
  tool,
  mcpOAuth,
  approval,
  stderr,
  error,
  exit,
  stopped,
}

class CodexSessionEvent {
  const CodexSessionEvent({
    required this.type,
    this.text,
    this.requestId,
    this.requestMethod,
    this.method,
    this.params,
    this.threadId,
    this.exitCode,
  });

  final CodexSessionEventType type;
  final String? text;
  final Object? requestId;
  final String? requestMethod;

  /// The app-server notification method that produced this event, when the
  /// event came from a JSON-RPC notification rather than a local lifecycle
  /// transition.  Keeping it lets the UI distinguish tool started/completed
  /// items without parsing a flattened display string.
  final String? method;
  final Map<String, dynamic>? params;
  final String? threadId;
  final int? exitCode;
}

/// Session operations exposed to the Chat UI independently of transport.
///
/// Local sessions speak Codex app-server JSON-RPC over an Android process.
/// Keeping this boundary here prevents the wire format from leaking into
/// widgets.
abstract interface class SessionClient {
  Stream<CodexSessionEvent> get events;

  String? get threadId;

  Future<void> start();

  Future<void> sendPrompt(
    String text, {
    List<ImageAttachment> images = const <ImageAttachment>[],
  });

  Future<void> respondToRequest(Object requestId, Map<String, dynamic> result);

  Future<void> respondToApproval(
    CodexSessionEvent approval, {
    required bool approved,
    bool forSession = false,
    Map<String, dynamic>? decisionOverride,
  });

  Future<void> interrupt();

  Future<void> stop();

  Future<void> dispose();
}
