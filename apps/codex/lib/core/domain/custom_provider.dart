class CustomProviderConfig {
  const CustomProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.reasoningEfforts = const <String>['low'],
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;

  /// The effort values the configured provider/model accepts through the
  /// Responses API.  Codex cannot discover this for an arbitrary external
  /// provider, so it is explicit configuration rather than a guessed list.
  final List<String> reasoningEfforts;

  static const _defaultDeepSeekReasoningEfforts = <String>[
    'none',
    'low',
    'high',
    'max',
  ];

  static List<String> defaultReasoningEffortsForModel(String model) {
    if (model.trim().toLowerCase().startsWith('deepseek-')) {
      return _defaultDeepSeekReasoningEfforts;
    }
    return const <String>['low'];
  }

  /// Parses the compact comma-separated value used by the settings dialog.
  /// Unknown provider-specific labels are retained; the Codex runtime is the
  /// authority on whether a particular label is accepted by that provider.
  static List<String> parseReasoningEfforts(
    String raw, {
    required String model,
  }) {
    final values = raw
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (values.isEmpty) return defaultReasoningEffortsForModel(model);
    if (values.length > 8 ||
        values.any(
          (value) => !RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(value),
        )) {
      throw const FormatException(
        'Reasoning efforts must be comma-separated labels using letters, numbers, - or _.',
      );
    }
    return List<String>.unmodifiable(values.toSet());
  }

  /// Base URL expected by Codex's Responses API provider.
  ///
  /// Existing installations may have stored a full Chat Completions URL. Keep
  /// accepting that shape, but project it back to its API base so Codex can
  /// issue `/responses` requests. This does not make a chat-only endpoint
  /// Responses-compatible.
  Uri get responsesBaseUri {
    final raw = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !const <String>{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const FormatException('Provider URL must be an http(s) URL.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
        'Provider URL must not contain credentials, query parameters, or a fragment.',
      );
    }
    var path = uri.path;
    for (final suffix in const <String>['/chat/completions', '/responses']) {
      if (path.endsWith(suffix)) {
        path = path.substring(0, path.length - suffix.length);
        break;
      }
    }
    // DeepSeek's Codex integration uses the provider root and appends
    // `/responses` itself. Older OpenAI-compatible examples commonly stored
    // `/v1`; keeping that segment here would send the native Responses client
    // to `/v1/responses` instead of DeepSeek's documented `/responses` route.
    if (uri.host.toLowerCase() == 'api.deepseek.com' && path == '/v1') {
      path = '';
    }
    return uri.replace(path: path);
  }

  bool hasSameConfigurationAs(CustomProviderConfig? other) =>
      other != null &&
      id == other.id &&
      name == other.name &&
      baseUrl == other.baseUrl &&
      model == other.model &&
      apiKey == other.apiKey &&
      _sameList(reasoningEfforts, other.reasoningEfforts);

  CustomProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? model,
    String? apiKey,
    List<String>? reasoningEfforts,
  }) {
    return CustomProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
      reasoningEfforts: reasoningEfforts ?? this.reasoningEfforts,
    );
  }

  factory CustomProviderConfig.fromMap(Map<Object?, Object?> value) {
    final model = _text(value['model']);
    return CustomProviderConfig(
      id: _text(value['id']),
      name: _text(value['name']),
      baseUrl: _text(value['baseUrl']),
      model: model,
      apiKey: _text(value['apiKey']),
      reasoningEfforts: _efforts(value['reasoningEfforts'], model: model),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'reasoningEfforts': reasoningEfforts,
  };

  static String _text(Object? value) => value is String ? value.trim() : '';

  static List<String> _efforts(Object? value, {required String model}) {
    final raw = value is List ? value.whereType<String>().join(',') : '';
    try {
      return parseReasoningEfforts(raw, model: model);
    } on FormatException {
      return defaultReasoningEffortsForModel(model);
    }
  }

  static bool _sameList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
