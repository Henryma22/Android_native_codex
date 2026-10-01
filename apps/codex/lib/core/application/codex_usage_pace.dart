import 'codex_usage.dart';

enum CodexUsagePaceStage {
  onTrack,
  slightlyAhead,
  ahead,
  farAhead,
  slightlyBehind,
  behind,
  farBehind,
}

class CodexUsagePace {
  const CodexUsagePace({
    required this.stage,
    required this.expectedUsedPercent,
    required this.actualUsedPercent,
    required this.timeUntilLimit,
    required this.willLastToReset,
  });

  static const minimumReliableExpectedPercent = 3.0;

  final CodexUsagePaceStage stage;
  final double expectedUsedPercent;
  final double actualUsedPercent;
  final Duration? timeUntilLimit;
  final bool willLastToReset;

  bool get isReliable =>
      actualUsedPercent >= 100 ||
      expectedUsedPercent >= minimumReliableExpectedPercent;

  static CodexUsagePace? calculate({
    required CodexUsageWindow window,
    required Duration windowDuration,
    DateTime? now,
  }) {
    final resetsAt = window.resetsAt;
    if (resetsAt == null || windowDuration <= Duration.zero) return null;
    final currentTime = now ?? DateTime.now();
    final timeUntilReset = resetsAt.difference(currentTime);
    if (timeUntilReset <= Duration.zero || timeUntilReset > windowDuration) {
      return null;
    }
    final elapsed = windowDuration - timeUntilReset;
    final actual = window.usedPercent.clamp(0, 100).toDouble();
    if (elapsed == Duration.zero && actual > 0) return null;
    final expected =
        elapsed.inMicroseconds / windowDuration.inMicroseconds * 100;
    final delta = actual - expected;
    final projection = _projectLimit(
      actualUsedPercent: actual,
      elapsed: elapsed,
      timeUntilReset: timeUntilReset,
    );
    return CodexUsagePace(
      stage: _stageFor(delta),
      expectedUsedPercent: expected.clamp(0, 100),
      actualUsedPercent: actual,
      timeUntilLimit: projection.timeUntilLimit,
      willLastToReset: projection.willLastToReset,
    );
  }

  static CodexUsagePaceStage _stageFor(double delta) {
    final distance = delta.abs();
    if (distance <= 2) return CodexUsagePaceStage.onTrack;
    if (distance <= 6) {
      return delta >= 0
          ? CodexUsagePaceStage.slightlyAhead
          : CodexUsagePaceStage.slightlyBehind;
    }
    if (distance <= 12) {
      return delta >= 0
          ? CodexUsagePaceStage.ahead
          : CodexUsagePaceStage.behind;
    }
    return delta >= 0
        ? CodexUsagePaceStage.farAhead
        : CodexUsagePaceStage.farBehind;
  }

  static _LimitProjection _projectLimit({
    required double actualUsedPercent,
    required Duration elapsed,
    required Duration timeUntilReset,
  }) {
    if (actualUsedPercent >= 100) {
      return const _LimitProjection(
        timeUntilLimit: Duration.zero,
        willLastToReset: false,
      );
    }
    if (actualUsedPercent == 0) {
      return const _LimitProjection(
        timeUntilLimit: null,
        willLastToReset: true,
      );
    }
    if (elapsed <= Duration.zero) {
      return const _LimitProjection(
        timeUntilLimit: null,
        willLastToReset: false,
      );
    }
    final usagePerMicrosecond = actualUsedPercent / elapsed.inMicroseconds;
    final projectedMicroseconds =
        ((100 - actualUsedPercent) / usagePerMicrosecond).round();
    final timeUntilLimit = Duration(microseconds: projectedMicroseconds);
    if (timeUntilLimit >= timeUntilReset) {
      return const _LimitProjection(
        timeUntilLimit: null,
        willLastToReset: true,
      );
    }
    return _LimitProjection(
      timeUntilLimit: timeUntilLimit,
      willLastToReset: false,
    );
  }
}

class _LimitProjection {
  const _LimitProjection({
    required this.timeUntilLimit,
    required this.willLastToReset,
  });

  final Duration? timeUntilLimit;
  final bool willLastToReset;
}
