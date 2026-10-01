import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/application/codex_model_catalog.dart';

/// Keeps the installed CLI's OpenAI model catalog available across sessions.
///
/// The cache is keyed by the Linux/PRoot CLI version and, for first-party
/// OpenAI catalogs, the current auth generation. A model catalog can depend on
/// account entitlements, so a successful account switch must not reuse the
/// previous account's model visibility. Third-party provider catalogs are
/// supplied directly from their saved provider configuration and never pass
/// through this store.
class CodexModelCatalogCache {
  CodexModelCatalogCache({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'io.henry.codex/app_preferences';
  static const _maxEncodedBytes = 128 * 1024;
  static const _cacheSchemaVersion = 2;
  static final Map<String, CodexModelCatalog> _memory =
      <String, CodexModelCatalog>{};

  final MethodChannel _channel;

  Future<CodexModelCatalog?> load({
    required String? cliVersion,
    int? authGeneration,
  }) async {
    final version = _normalizedVersion(cliVersion);
    if (version == null) return null;
    final generation = _normalizedAuthGeneration(authGeneration);
    final cacheKey = _cacheKey(version, generation);
    final memoryValue = _memory[cacheKey];
    if (memoryValue != null) return memoryValue;

    try {
      final encoded = await _channel.invokeMethod<String>(
        'loadCodexModelCatalogCache',
      );
      if (encoded == null || utf8.encode(encoded).length > _maxEncodedBytes) {
        return null;
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != _cacheSchemaVersion ||
          decoded['runtime'] != 'linux-proot' ||
          decoded['cliVersion'] != version ||
          (generation != null && decoded['authGeneration'] != generation) ||
          (generation == null && decoded['authGeneration'] != null)) {
        return null;
      }
      final rawModels = decoded['models'];
      if (rawModels is! List) return null;

      final models = <CodexModelDescriptor>[];
      for (final rawModel in rawModels) {
        if (rawModel is! Map<String, dynamic>) return null;
        final id = rawModel['id'];
        final displayName = rawModel['displayName'];
        final rawEfforts = rawModel['reasoningEfforts'];
        if (id is! String ||
            id.trim().isEmpty ||
            displayName is! String ||
            rawEfforts is! List ||
            rawEfforts.any((effort) => effort is! String)) {
          return null;
        }
        models.add(
          CodexModelDescriptor(
            id: id,
            displayName: displayName,
            reasoningEfforts: rawEfforts.cast<String>(),
            hidden: rawModel['hidden'] == true,
          ),
        );
      }
      if (models.isEmpty) return null;
      final catalog = CodexModelCatalog(models: models);
      _memory[cacheKey] = catalog;
      return catalog;
    } on Object {
      // A missing or corrupt cache must not prevent the CLI from loading its
      // authoritative catalog on demand.
      return null;
    }
  }

  Future<void> save({
    required String? cliVersion,
    int? authGeneration,
    required CodexModelCatalog catalog,
  }) async {
    final version = _normalizedVersion(cliVersion);
    if (version == null || catalog.models.isEmpty) return;
    final generation = _normalizedAuthGeneration(authGeneration);
    final encoded = jsonEncode(<String, Object?>{
      'schemaVersion': _cacheSchemaVersion,
      'runtime': 'linux-proot',
      'cliVersion': version,
      if (generation != null) 'authGeneration': generation,
      'models': catalog.models
          .map(
            (model) => <String, Object?>{
              'id': model.id,
              'displayName': model.displayName,
              'reasoningEfforts': model.reasoningEfforts,
              'hidden': model.hidden,
            },
          )
          .toList(growable: false),
    });
    if (utf8.encode(encoded).length > _maxEncodedBytes) return;

    _memory[_cacheKey(version, generation)] = catalog;
    try {
      await _channel.invokeMethod<void>(
        'saveCodexModelCatalogCache',
        <String, Object?>{'catalog': encoded},
      );
    } on Object {
      // In-memory caching still benefits the current process if Android
      // preference persistence is unavailable (for example, in widget tests).
    }
  }

  @visibleForTesting
  static void clearMemoryForTesting() => _memory.clear();

  static String? _normalizedVersion(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        !RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')
            .hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static int? _normalizedAuthGeneration(int? value) =>
      value != null && value > 0 ? value : null;

  static String _cacheKey(String version, int? authGeneration) =>
      'linux-proot:$version:${authGeneration == null ? 'legacy' : 'auth-$authGeneration'}';
}
