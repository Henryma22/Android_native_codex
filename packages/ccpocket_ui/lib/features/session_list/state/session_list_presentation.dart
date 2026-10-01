import '../../../models/messages.dart';

String sessionPinKey({
  required String? provider,
  required String projectPath,
  required String sessionId,
}) => '${provider ?? Provider.codex.value}\n$projectPath\n$sessionId';

String recentSessionPinKey(RecentSession session) => sessionPinKey(
  provider: session.provider,
  projectPath: session.projectPath,
  sessionId: session.sessionId,
);

String? runningSessionPinKey(SessionInfo session) {
  final providerSessionId = session.providerSessionId;
  if (providerSessionId == null || providerSessionId.isEmpty) return null;
  return sessionPinKey(
    provider: session.provider,
    projectPath: session.projectPath,
    sessionId: providerSessionId,
  );
}

List<T> prioritizePinned<T>(
  Iterable<T> items, {
  required bool Function(T item) isPinned,
  bool Function(T item)? isProjectPinned,
}) {
  final pinned = <T>[];
  final pinnedProjects = <T>[];
  final others = <T>[];
  for (final item in items) {
    if (isPinned(item)) {
      pinned.add(item);
    } else if (isProjectPinned?.call(item) ?? false) {
      pinnedProjects.add(item);
    } else {
      others.add(item);
    }
  }
  return [...pinned, ...pinnedProjects, ...others];
}