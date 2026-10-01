enum CodexRuntimeState { missing, available, verified, failed }

class CodexRuntimeDescriptor {
  const CodexRuntimeDescriptor({
    required this.state,
    this.command,
    this.version,
    this.reason,
    this.home,
    this.identity,
    this.source,
    this.abi,
    this.sha256,
    this.license,
    this.bundle,
    this.companionCount,
    this.appProbeState,
    this.appProbeReason,
  });

  factory CodexRuntimeDescriptor.fromMap(Map<Object?, Object?> value) {
    final rawState = value['state'] as String? ?? 'failed';
    final state = switch (rawState) {
      'missing' => CodexRuntimeState.missing,
      'available' => CodexRuntimeState.available,
      'verified' => CodexRuntimeState.verified,
      _ => CodexRuntimeState.failed,
    };
    return CodexRuntimeDescriptor(
      state: state,
      command: value['command'] as String?,
      version: value['version'] as String?,
      reason: value['reason'] as String?,
      home: value['home'] as String?,
      identity: value['identity'] as String?,
      source: value['source'] as String?,
      abi: value['abi'] as String?,
      sha256: value['sha256'] as String?,
      license: value['license'] as String?,
      bundle: value['bundle'] as String?,
      companionCount: (value['companionCount'] as num?)?.toInt(),
      appProbeState: value['appProbeState'] as String?,
      appProbeReason: value['appProbeReason'] as String?,
    );
  }

  final CodexRuntimeState state;
  final String? command;
  final String? version;
  final String? reason;
  final String? home;
  final String? identity;
  final String? source;
  final String? abi;
  final String? sha256;
  final String? license;
  final String? bundle;
  final int? companionCount;
  final String? appProbeState;
  final String? appProbeReason;

  bool get usable =>
      (state == CodexRuntimeState.available ||
          state == CodexRuntimeState.verified) &&
      command != null;

  String get label {
    switch (state) {
      case CodexRuntimeState.missing:
        return 'Missing';
      case CodexRuntimeState.available:
        return 'Available';
      case CodexRuntimeState.verified:
        return 'Verified';
      case CodexRuntimeState.failed:
        return 'Failed';
    }
  }
}
