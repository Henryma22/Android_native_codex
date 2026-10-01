/// Safe, user-facing summary of a Codex plugin returned by app-server.
///
/// The app-server response also contains local paths, source descriptors, and
/// marketplace metadata that the session UI does not need. This model keeps
/// only the fields needed to render the list or its JSON form.
class CodexPluginSummary {
  const CodexPluginSummary({
    required this.marketplaceName,
    this.marketplaceDisplayName,
    required this.id,
    required this.name,
    this.version,
    this.localVersion,
    required this.installed,
    required this.enabled,
    required this.featured,
  });

  final String marketplaceName;
  final String? marketplaceDisplayName;
  final String id;
  final String name;
  final String? version;
  final String? localVersion;
  final bool installed;
  final bool enabled;
  final bool featured;

  Map<String, Object?> toSafeJsonMap() => <String, Object?>{
    'marketplace': marketplaceName,
    if (marketplaceDisplayName != null)
      'marketplaceDisplayName': marketplaceDisplayName,
    'id': id,
    'name': name,
    if (version != null) 'version': version,
    if (localVersion != null) 'localVersion': localVersion,
    'installed': installed,
    'enabled': enabled,
    'featured': featured,
  };

  String displayLine({required bool chinese}) {
    final installState = installed
        ? (chinese ? '已安装' : 'installed')
        : (chinese ? '未安装' : 'not installed');
    final enabledState = enabled
        ? (chinese ? '已启用' : 'enabled')
        : (chinese ? '已停用' : 'disabled');
    final versionValue = localVersion ?? version;
    final versionText = versionValue == null
        ? ''
        : (chinese ? ' · 版本 $versionValue' : ' · v$versionValue');
    final featuredText = featured ? (chinese ? ' · 推荐' : ' · featured') : '';
    final marketplace = marketplaceDisplayName ?? marketplaceName;
    return '$name [$id] · $marketplace · $installState · '
        '$enabledState$versionText$featuredText';
  }

  /// Parses the stable, non-secret portion of a `plugin/list` response.
  ///
  /// Unknown fields are ignored so a newer CLI can add metadata without
  /// breaking the Android client. Required collection/identity fields still
  /// fail loudly when the response is malformed.
  static List<CodexPluginSummary> parseResponse(Map<String, dynamic> response) {
    final rawMarketplaces = response['marketplaces'];
    if (rawMarketplaces is! List) {
      throw const FormatException(
        'Codex plugin list response has no marketplaces list.',
      );
    }

    final featuredIds = <String>{
      if (response['featuredPluginIds'] is List)
        for (final value in response['featuredPluginIds'] as List)
          if (value is String && value.trim().isNotEmpty) _safeLabel(value),
    };
    final summaries = <CodexPluginSummary>[];
    for (final rawMarketplace in rawMarketplaces) {
      if (rawMarketplace is! Map) {
        throw const FormatException(
          'Codex plugin marketplace is not an object.',
        );
      }
      final marketplaceName = _requiredLabel(
        rawMarketplace['name'],
        'marketplace',
      );
      final interface = rawMarketplace['interface'];
      final marketplaceDisplayName = interface is Map
          ? _optionalLabel(interface['displayName'])
          : null;
      final rawPlugins = rawMarketplace['plugins'];
      if (rawPlugins is! List) {
        throw const FormatException(
          'Codex plugin marketplace has no plugins list.',
        );
      }
      for (final rawPlugin in rawPlugins) {
        if (rawPlugin is! Map) {
          throw const FormatException('Codex plugin entry is not an object.');
        }
        final id = _requiredLabel(rawPlugin['id'], 'plugin id');
        final name = _requiredLabel(rawPlugin['name'], 'plugin name');
        summaries.add(
          CodexPluginSummary(
            marketplaceName: marketplaceName,
            marketplaceDisplayName: marketplaceDisplayName,
            id: id,
            name: name,
            version: _optionalLabel(rawPlugin['version']),
            localVersion: _optionalLabel(rawPlugin['localVersion']),
            installed: rawPlugin['installed'] == true,
            enabled: rawPlugin['enabled'] == true,
            featured: featuredIds.contains(id),
          ),
        );
      }
    }
    return summaries;
  }

  static String _requiredLabel(Object? value, String field) {
    final label = _optionalLabel(value);
    if (label == null) {
      throw FormatException('Codex plugin $field is missing.');
    }
    return label;
  }

  static String? _optionalLabel(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return _safeLabel(value);
  }

  static String _safeLabel(String value) => value
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

/// Stable, non-secret metadata for one marketplace returned by
/// `plugin/list`.
///
/// A marketplace is kept separate from its plugin entries so an empty
/// marketplace still has a real representation in Settings. Paths and raw
/// source descriptors are intentionally not surfaced: the mutation methods
/// use the app-server's own catalog identity instead of making the UI
/// reconstruct its storage layout.
class CodexPluginMarketplaceSummary {
  const CodexPluginMarketplaceSummary({
    required this.name,
    this.displayName,
    required this.pluginCount,
    this.loadError,
  });

  final String name;
  final String? displayName;
  final int pluginCount;
  final String? loadError;

  String get title => displayName ?? name;

  String displayLine({required bool chinese}) {
    final count = chinese
        ? '$pluginCount 个插件'
        : '$pluginCount ${pluginCount == 1 ? 'plugin' : 'plugins'}';
    if (loadError == null) return count;
    return '$count · ${chinese ? '加载失败' : 'load failed'}: $loadError';
  }

  /// Parses only the safe marketplace identity/count fields. Newer CLI
  /// fields are ignored so a catalog extension does not break Settings.
  static List<CodexPluginMarketplaceSummary> parseResponse(
    Map<String, dynamic> response,
  ) {
    final rawMarketplaces = response['marketplaces'];
    if (rawMarketplaces is! List) {
      throw const FormatException(
        'Codex plugin list response has no marketplaces list.',
      );
    }
    final summaries = <CodexPluginMarketplaceSummary>[];
    for (final rawMarketplace in rawMarketplaces) {
      if (rawMarketplace is! Map) {
        throw const FormatException(
          'Codex plugin marketplace is not an object.',
        );
      }
      final name = _requiredLabel(rawMarketplace['name'], 'marketplace');
      final interface = rawMarketplace['interface'];
      final displayName = interface is Map
          ? _optionalLabel(interface['displayName'])
          : null;
      final rawPlugins = rawMarketplace['plugins'];
      final pluginCount = rawPlugins is List ? rawPlugins.length : 0;
      final loadError = _optionalLabel(
        rawMarketplace['error'] ?? rawMarketplace['loadError'],
      );
      summaries.add(
        CodexPluginMarketplaceSummary(
          name: name,
          displayName: displayName,
          pluginCount: pluginCount,
          loadError: loadError,
        ),
      );
    }
    return List<CodexPluginMarketplaceSummary>.unmodifiable(summaries);
  }

  static String _requiredLabel(Object? value, String field) {
    final label = _optionalLabel(value);
    if (label == null) throw FormatException('Codex plugin $field is missing.');
    return label;
  }

  static String? _optionalLabel(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}
