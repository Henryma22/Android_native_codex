import 'dart:convert';

/// App-owned transcript record used to project the local app-server stream
/// onto CC Pocket's ChatEntry model.
///
/// The history store still accepts a list of strings for backwards
/// compatibility. New records are encoded with [toStored], while older
/// human-readable lines are parsed by [fromStored]. This lets the UI keep
/// stable IDs/timestamps and tool metadata without invalidating existing
/// local session history.
enum CodexTranscriptKind {
  user,
  assistant,
  reasoning,
  tool,
  toolResult,
  system,
  error,
  status,
}

class CodexTranscriptEntry {
  const CodexTranscriptEntry({
    required this.id,
    required this.kind,
    required this.text,
    required this.timestamp,
    this.model = 'gpt-6-luna',
    this.toolName,
    this.data = const <String, dynamic>{},
  });

  factory CodexTranscriptEntry.fromStored(String raw) {
    final cleaned = _stripAnsi(raw).trim();
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map && decoded['schema'] == _schema) {
        final kind = _kindFrom(decoded['kind'] as String?);
        final timestamp = DateTime.tryParse(
          decoded['timestamp'] as String? ?? '',
        );
        final data = decoded['data'];
        return CodexTranscriptEntry(
          id: decoded['id'] as String? ?? _legacyId(cleaned),
          kind: kind,
          text: decoded['text'] as String? ?? '',
          timestamp: timestamp ?? DateTime.now(),
          model: decoded['model'] as String? ?? 'gpt-6-luna',
          toolName: decoded['toolName'] as String?,
          data: data is Map
              ? <String, dynamic>{
                  for (final entry in data.entries)
                    if (entry.key is String) entry.key as String: entry.value,
                }
              : const <String, dynamic>{},
        );
      }
    } on Object {
      // Legacy display lines are intentionally handled below.
    }
    return _fromLegacy(cleaned);
  }

  final String id;
  final CodexTranscriptKind kind;
  final String text;
  final DateTime timestamp;
  final String model;
  final String? toolName;
  final Map<String, dynamic> data;

  CodexTranscriptEntry copyWith({
    String? text,
    CodexTranscriptKind? kind,
    String? model,
    String? toolName,
    Map<String, dynamic>? data,
  }) {
    return CodexTranscriptEntry(
      id: id,
      kind: kind ?? this.kind,
      text: text ?? this.text,
      timestamp: timestamp,
      model: model ?? this.model,
      toolName: toolName ?? this.toolName,
      data: data ?? this.data,
    );
  }

  String toStored() => jsonEncode(<String, dynamic>{
    'schema': _schema,
    'id': id,
    'kind': kind.name,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'model': model,
    if (toolName != null) 'toolName': toolName,
    if (data.isNotEmpty) 'data': data,
  });

  String get displayLine {
    final label = switch (kind) {
      CodexTranscriptKind.user => 'You',
      CodexTranscriptKind.assistant => 'Codex',
      CodexTranscriptKind.reasoning => 'Thinking',
      CodexTranscriptKind.tool || CodexTranscriptKind.toolResult => 'Tool',
      CodexTranscriptKind.system => 'System',
      CodexTranscriptKind.error => 'error',
      CodexTranscriptKind.status => 'Status',
    };
    return '$label: $text';
  }

  static const _schema = 'codex.transcript.v1';

  static CodexTranscriptKind _kindFrom(String? raw) {
    for (final kind in CodexTranscriptKind.values) {
      if (kind.name == raw) return kind;
    }
    return CodexTranscriptKind.system;
  }

  static CodexTranscriptEntry _fromLegacy(String raw) {
    final separator = raw.indexOf(':');
    final label = separator > 0 ? raw.substring(0, separator).trim() : '';
    final text = separator > 0 ? raw.substring(separator + 1).trimLeft() : raw;
    final normalized = label.toLowerCase();
    final kind = switch (normalized) {
      'you' || 'user' => CodexTranscriptKind.user,
      'assistant' || 'agent' || 'codex' => CodexTranscriptKind.assistant,
      'thinking' || 'reasoning' => CodexTranscriptKind.reasoning,
      'tool' => CodexTranscriptKind.tool,
      'tool result' => CodexTranscriptKind.toolResult,
      'error' || 'stderr' => CodexTranscriptKind.error,
      'status' => CodexTranscriptKind.status,
      _ => CodexTranscriptKind.system,
    };
    final data = _tryDecodeMap(text);
    return CodexTranscriptEntry(
      id: _legacyId(raw),
      kind: kind,
      text: text,
      timestamp: DateTime.now(),
      data: data,
    );
  }

  static Map<String, dynamic> _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return <String, dynamic>{
          for (final entry in decoded.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
      }
    } on Object {
      // Plain tool/status text is valid legacy data.
    }
    return const <String, dynamic>{};
  }

  static String _legacyId(String value) {
    // A deterministic ID is sufficient for old records and avoids creating a
    // new ID every rebuild of the message list.
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'legacy-$hash';
  }

  static String _stripAnsi(String value) =>
      value.replaceAll(RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~])'), '');
}

/// Runtime housekeeping diagnostics that do not describe a failed turn.
///
/// Codex may write these to stderr while starting a local app-server. They are
/// useful in native logs, but must not become conversation bubbles or replace
/// a saved session's last message.
bool isBenignCodexRuntimeDiagnostic(String? value) {
  final normalized = (value ?? '')
      .replaceAll(RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~])'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  if (normalized.contains('failed to load models cache')) return true;
  // The model manager may fail to refresh its disposable child-process
  // catalog while a turn is otherwise healthy. This is a runtime
  // housekeeping diagnostic, not a user conversation message; the model
  // catalog client already has bundled/cache/app-server fallbacks. The
  // exact child-process error differs across CLI releases, so match the
  // stable manager/category message instead of one timeout wording.
  if (normalized.contains('codex_models_manager::manager') &&
      normalized.contains('failed to refresh available models')) {
    return true;
  }
  // A restored app-server can close its previous thread/read stream while the
  // new session client is attaching. Codex logs this as an error even though
  // the resumed thread becomes ready and remains usable. Do not surface this
  // transport hand-off noise as a conversation failure.
  if (normalized.contains('read interrupted by close') &&
      normalized.contains('another thread')) {
    return true;
  }
  // The Linux app-server probes its optional bubblewrap sandbox during
  // startup. PRoot is already the outer execution boundary on Android, so
  // the guest cannot create Linux user namespaces; the probe logs this
  // capability warning even though thread/start succeeds and the session is
  // usable. Keep it out of conversation/error bubbles without hiding actual
  // turn failures.
  if (normalized.contains("codex's linux sandbox") &&
      normalized.contains('bubblewrap') &&
      normalized.contains('user namespaces')) {
    return true;
  }
  const lockMarkers = <String>[
    'try_lock() not supported',
    'lock() not supported',
    'thread writer coordination lock',
    'thread-store internal error',
  ];
  if (lockMarkers.any(normalized.contains)) return true;
  if (!normalized.contains('failed to clean up stale arg0 temp dirs')) {
    return false;
  }
  return normalized.contains('permission denied') ||
      normalized.contains('os error 13') ||
      normalized.contains('try_lock() not supported') ||
      normalized.contains('lock() not supported') ||
      normalized.contains('operation not permitted');
}
