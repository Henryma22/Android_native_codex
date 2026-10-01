/// Safe, user-facing metadata returned by `permissionProfile/list`.
///
/// Permission profiles are owned by the installed Codex app-server. The
/// Android client only keeps the identifier and optional description; it does
/// not attempt to reconstruct the profile's filesystem or network rules.
class CodexPermissionProfileSummary {
  const CodexPermissionProfileSummary({
    required this.id,
    this.description,
    required this.allowed,
  });

  final String id;
  final String? description;
  final bool allowed;

  bool get isBuiltIn => id.startsWith(':');

  String displayLine({required bool chinese}) {
    final state = allowed
        ? (chinese ? '可用' : 'allowed')
        : (chinese ? '不可用' : 'not allowed');
    final detail = description == null ? '' : ' · $description';
    return '$id$detail · $state';
  }

  /// Parses the stable fields of a `permissionProfile/list` page.
  ///
  /// Unknown fields are intentionally ignored so a newer CLI can extend the
  /// profile metadata without breaking the Android client.
  static List<CodexPermissionProfileSummary> parseResponse(
    Map<String, dynamic> response,
  ) {
    final rawData = response['data'];
    if (rawData is! List) {
      throw const FormatException(
        'Codex permission profile response has no data list.',
      );
    }
    final profiles = <CodexPermissionProfileSummary>[];
    for (final rawProfile in rawData) {
      if (rawProfile is! Map) {
        throw const FormatException(
          'Codex permission profile entry is not an object.',
        );
      }
      final id = _label(rawProfile['id']);
      if (id == null) {
        throw const FormatException('Codex permission profile id is missing.');
      }
      profiles.add(
        CodexPermissionProfileSummary(
          id: id,
          description: _label(rawProfile['description']),
          allowed: rawProfile['allowed'] == true,
        ),
      );
    }
    return List<CodexPermissionProfileSummary>.unmodifiable(profiles);
  }

  static String? _label(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
