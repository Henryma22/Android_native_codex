import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/transcript.dart';

void main() {
  test('round-trips structured transcript metadata', () {
    final original = CodexTranscriptEntry(
      id: 'tool-1',
      kind: CodexTranscriptKind.tool,
      text: '{"command":"pwd"}',
      timestamp: DateTime.utc(2026, 9, 20, 4, 0),
      toolName: 'commandExecution',
      data: const <String, dynamic>{
        'id': 'tool-1',
        'type': 'commandExecution',
        'command': 'pwd',
      },
    );

    final restored = CodexTranscriptEntry.fromStored(original.toStored());

    expect(restored.id, original.id);
    expect(restored.kind, CodexTranscriptKind.tool);
    expect(restored.timestamp, original.timestamp);
    expect(restored.toolName, 'commandExecution');
    expect(restored.data['command'], 'pwd');
  });

  test('keeps legacy display lines readable', () {
    final restored = CodexTranscriptEntry.fromStored('You: inspect the file');

    expect(restored.kind, CodexTranscriptKind.user);
    expect(restored.text, 'inspect the file');
    expect(restored.displayLine, 'You: inspect the file');
  });
}
