import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/android_codex_agents.dart';

void main() {
  test('Root PRoot guidance exposes direct Android host commands', () {
    expect(androidCodexAgentInstructions, contains('## Android host commands'));
    expect(androidCodexAgentInstructions, contains('/android/<host-path>'));
    expect(
      androidCodexAgentInstructions,
      contains('/system/bin/pm list packages -3'),
    );
    expect(
      androidCodexAgentInstructions,
      contains('/system/bin/dumpsys package <package>'),
    );
    expect(
      androidCodexAgentInstructions,
      contains('if invocation fails, report its exact exit/error'),
    );
    expect(
      androidCodexAgentInstructions,
      contains(
        'The Android/Bionic developer-toolchain was retired and is not a fallback.',
      ),
    );
    expect(
      androidCodexAgentInstructions,
      contains(
        'use Android host executables for Android framework/device operations',
      ),
    );
  });
}
