/// Safe, user-facing metadata for a thread returned by the local app-server.
///
/// The protocol also exposes rollout paths and other implementation details.
/// They are intentionally not copied into this model so a CLI transcript can
/// show useful history without leaking the app-server's internal storage
/// layout. The workspace cwd is retained because it is part of the user's
/// session identity.
class CodexThreadSummary {
  const CodexThreadSummary({
    required this.id,
    required this.sessionId,
    this.name,
    required this.preview,
    required this.cwd,
    this.model,
    required this.modelProvider,
    this.reasoningEffort,
    required this.cliVersion,
    required this.source,
    required this.status,
    required this.activeFlags,
    required this.createdAt,
    required this.updatedAt,
    this.recencyAt,
  });

  final String id;
  final String sessionId;
  final String? name;
  final String preview;
  final String cwd;
  final String? model;
  final String modelProvider;
  final String? reasoningEffort;
  final String cliVersion;
  final String source;
  final String status;
  final List<String> activeFlags;
  final int createdAt;
  final int updatedAt;
  final int? recencyAt;

  bool get isActive => status == 'active';

  String get displayTitle {
    final explicitName = name?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }
    final firstLine = preview
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return firstLine.isEmpty ? id : firstLine;
  }

  Map<String, Object?> toSafeJsonMap() => <String, Object?>{
    'id': id,
    'sessionId': sessionId,
    if (name != null) 'name': name,
    'preview': preview,
    if (cwd.isNotEmpty) 'cwd': cwd,
    if (model != null) 'model': model,
    if (modelProvider.isNotEmpty) 'modelProvider': modelProvider,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    if (cliVersion.isNotEmpty) 'cliVersion': cliVersion,
    if (source.isNotEmpty) 'source': source,
    'status': status,
    if (activeFlags.isNotEmpty) 'activeFlags': activeFlags,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (recencyAt != null) 'recencyAt': recencyAt,
  };

  String displayLine({required bool chinese}) {
    final statusText = switch (status) {
      'active' => chinese ? '运行中' : 'active',
      'idle' => chinese ? '空闲' : 'idle',
      'systemError' => chinese ? '系统错误' : 'system error',
      'notLoaded' => chinese ? '未加载' : 'not loaded',
      _ => status,
    };
    final modelText = model == null || model!.isEmpty ? '' : ' · $model';
    final effortText = reasoningEffort == null || reasoningEffort!.isEmpty
        ? ''
        : ' · ${reasoningEffort!}';
    final activeText = activeFlags.isEmpty
        ? ''
        : ' · ${activeFlags.join(', ')}';
    return '$displayTitle [$id] · $statusText$modelText$effortText$activeText';
  }

  static CodexThreadSummary parse(Object? value) {
    if (value is! Map) {
      throw const FormatException('Codex thread entry is not an object.');
    }
    final id = _requiredText(value['id'], 'thread id');
    final sessionId = _optionalText(value['sessionId']) ?? id;
    final statusValue = value['status'];
    var status = 'unknown';
    var activeFlags = const <String>[];
    if (statusValue is String) {
      status = _safeText(statusValue);
    } else if (statusValue is Map) {
      final type = _optionalText(statusValue['type']);
      if (type != null) status = _safeText(type);
      final rawFlags = statusValue['activeFlags'];
      if (rawFlags is List) {
        activeFlags = List<String>.unmodifiable(
          rawFlags
              .whereType<String>()
              .map(_safeText)
              .where((flag) => flag.isNotEmpty),
        );
      }
    }
    return CodexThreadSummary(
      id: id,
      sessionId: sessionId,
      name: _optionalText(value['name']),
      preview: _optionalPreview(value['preview']) ?? '',
      cwd: _optionalText(value['cwd']) ?? '',
      model: _optionalText(value['model']),
      modelProvider: _optionalText(value['modelProvider']) ?? '',
      reasoningEffort: _optionalText(value['reasoningEffort']),
      cliVersion: _optionalText(value['cliVersion']) ?? '',
      source: _optionalText(value['source']) ?? '',
      status: status,
      activeFlags: activeFlags,
      createdAt: _timestamp(value['createdAt']),
      updatedAt: _timestamp(value['updatedAt']),
      recencyAt: _nullableTimestamp(value['recencyAt']),
    );
  }

  static String _requiredText(Object? value, String field) {
    final text = _optionalText(value);
    if (text == null) throw FormatException('Codex $field is missing.');
    return text;
  }

  static String? _optionalText(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return _safeText(value);
  }

  static String? _optionalPreview(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', ' ')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s{2,}'), ' ').trimRight())
        .join('\n')
        .trim();
  }

  static String _safeText(String value) => value
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static int _timestamp(Object? value) => value is num ? value.toInt() : 0;

  static int? _nullableTimestamp(Object? value) =>
      value is num ? value.toInt() : null;
}

class CodexThreadListPage {
  const CodexThreadListPage({
    required this.threads,
    this.nextCursor,
    this.backwardsCursor,
  });

  final List<CodexThreadSummary> threads;
  final String? nextCursor;
  final String? backwardsCursor;

  static CodexThreadListPage parseResponse(Map<String, dynamic> response) {
    final rawThreads = response['data'];
    if (rawThreads is! List) {
      throw const FormatException(
        'Codex thread list response has no data list.',
      );
    }
    return CodexThreadListPage(
      threads: List<CodexThreadSummary>.unmodifiable(
        rawThreads.map(CodexThreadSummary.parse),
      ),
      nextCursor: _cursor(response['nextCursor']),
      backwardsCursor: _cursor(response['backwardsCursor']),
    );
  }

  static String? _cursor(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}
