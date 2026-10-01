import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/runtime.dart';

void main() {
  test('keeps an uninstalled runtime distinct from a failed probe', () {
    const missing = CodexRuntimeDescriptor(
      state: CodexRuntimeState.missing,
      reason: 'runtime bundle is absent',
    );
    const failed = CodexRuntimeDescriptor(
      state: CodexRuntimeState.failed,
      reason: 'version probe failed',
    );

    expect(missing.label, 'Missing');
    expect(missing.usable, isFalse);
    expect(failed.label, 'Failed');
    expect(failed.usable, isFalse);
  });

  test('maps a verified native runtime result', () {
    final result = CodexRuntimeDescriptor.fromMap(<Object?, Object?>{
      'state': 'verified',
      'command': '/data/user/0/io.henry.codex/files/codex-runtime/bin/codex',
      'identity': 'root',
      'home': '/data/user/0/io.henry.codex/files/codex-home',
      'version': 'codex 0.1.0',
      'source': 'vendor-artifact:codex-cli-0.1.0',
      'abi': 'arm64-v8a',
      'sha256': 'a' * 64,
      'license': 'Apache-2.0',
      'bundle': 'verified',
      'companionCount': 5,
    });

    expect(result.usable, isTrue);
    expect(result.label, 'Verified');
    expect(result.version, 'codex 0.1.0');
    expect(result.identity, 'root');
    expect(result.home, endsWith('/codex-home'));
    expect(result.source, contains('vendor-artifact'));
    expect(result.abi, 'arm64-v8a');
    expect(result.sha256, 'a' * 64);
    expect(result.license, 'Apache-2.0');
    expect(result.bundle, 'verified');
    expect(result.companionCount, 5);
  });

  test('preserves the direct App UID probe when root fallback is selected', () {
    final result = CodexRuntimeDescriptor.fromMap(<Object?, Object?>{
      'state': 'verified',
      'command': '/data/local/tmp/io.henry.codex/codex-runtime/bin/codex',
      'identity': 'root',
      'appProbeState': 'failed',
      'appProbeReason': 'Permission denied (os error 13)',
    });

    expect(result.identity, 'root');
    expect(result.appProbeState, 'failed');
    expect(result.appProbeReason, contains('Permission denied'));
  });
}
