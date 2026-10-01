import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:codex/core/application/codex_thread_title.dart';

void main() {
  test('builds a Luna title prompt within the UTF-8 byte limit', () {
    final prompt = CodexThreadTitle.promptFor(
      List<String>.filled(300, '修复会话标题逻辑 ').join(),
    );

    expect(utf8.encode(prompt).length, lessThanOrEqualTo(960));
    expect(prompt, startsWith('Generate a concise'));
    expect(prompt, contains('User prompt:'));
  });

  test('parses and bounds a structured title without splitting Unicode', () {
    final title = CodexThreadTitle.parse(
      jsonEncode(<String, String>{'title': '  “修复会话标题逻辑!”  '}),
    );

    expect(title, '修复会话标题逻辑');
    expect(
      CodexThreadTitle.parse(
        jsonEncode(<String, String>{'title': '会话标题非常长' * 10}),
      )!.runes.length,
      CodexThreadTitle.maximumCharacters,
    );
    expect(CodexThreadTitle.parse('not json'), isNull);
    expect(CodexThreadTitle.parse('{"other":"value"}'), isNull);
  });

  test('isolates all configured MCP servers and execution tools', () {
    final config = CodexThreadTitle.isolatedConfig(<String, dynamic>{
      'fixture-mcp': <String, dynamic>{'enabled': true},
    });

    expect(config['features.shell_tool'], isFalse);
    expect(config['web_search'], 'disabled');
    expect(config['mcp_servers'], <String, Object?>{
      'fixture-mcp': <String, Object?>{'enabled': false},
    });
  });
}
