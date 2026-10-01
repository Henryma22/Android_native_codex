import 'dart:convert';

/// Bounded, structured title generation for a Codex thread.
///
/// The temporary title turn is always started with the session's selected Luna
/// model at low effort. It receives no transcript markup, tools, or permissions.
abstract final class CodexThreadTitle {
  static const maximumCharacters = 36;
  static const maximumPromptBytes = 960;

  static Map<String, Object?> get outputSchema => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'title': <String, Object?>{
        'type': 'string',
        'minLength': 1,
        'maxLength': maximumCharacters,
      },
    },
    'required': <String>['title'],
    'additionalProperties': false,
  };

  static String promptFor(String userMessage) {
    const prefix =
        'Generate a concise, single-line task title of at most '
        '$maximumCharacters characters and under five words where possible. '
        'Start with an imperative verb. Capitalize only the first word unless '
        'the user\'s language, proper nouns, acronyms, or code terms require '
        'otherwise. Preserve ticket references exactly. Write in the user\'s '
        'language. Do not use quotes, markdown, or trailing punctuation. '
        'Do not answer the request.\n\nUser prompt:\n';
    final remainingBytes = maximumPromptBytes - utf8.encode(prefix).length;
    final bounded = StringBuffer();
    var bytes = 0;
    for (final rune in userMessage.trim().runes) {
      final character = String.fromCharCode(rune);
      final length = utf8.encode(character).length;
      if (bytes + length > remainingBytes) break;
      bounded.write(character);
      bytes += length;
    }
    return '$prefix$bounded';
  }

  /// Disable inherited MCP servers as well as the app-server's built-in tools.
  static Map<String, Object?> isolatedConfig(
    Map<String, dynamic> effectiveMcpServers,
  ) {
    return <String, Object?>{
      'features.apps': false,
      'features.code_mode': false,
      'features.code_mode_only': false,
      'features.context_management': false,
      'features.current_time_reminder': false,
      'features.deferred_executor': false,
      'features.enable_fanout': false,
      'features.goals': false,
      'features.hooks': false,
      'features.image_generation': false,
      'features.memories': false,
      'features.multi_agent': false,
      'features.multi_agent_v2': false,
      'features.plugins': false,
      'features.request_permissions_tool': false,
      'features.shell_snapshot': false,
      'features.shell_tool': false,
      'features.standalone_web_search': false,
      'features.token_budget': false,
      'features.tool_suggest': false,
      'features.unified_exec': false,
      'features.view_image': false,
      'orchestrator.skills.enabled': false,
      'skills.include_instructions': false,
      'tools.experimental_request_user_input.enabled': false,
      'tools.update_plan.enabled': false,
      'web_search': 'disabled',
      'mcp_servers': <String, Object?>{
        for (final name in effectiveMcpServers.keys)
          name: <String, Object?>{'enabled': false},
      },
    };
  }

  static String? parse(String response) {
    if (!response.trimLeft().startsWith('{')) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(response);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || decoded['title'] is! String) return null;
    final raw = (decoded['title'] as String)
        .trim()
        .replaceAll(RegExp(r"""^["'`“”‘’]+|["'`“”‘’]+$"""), '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ')
        .replaceFirst(RegExp(r'[.?!]+$'), '')
        .trim();
    if (raw.isEmpty) return null;
    return String.fromCharCodes(raw.runes.take(maximumCharacters));
  }
}
