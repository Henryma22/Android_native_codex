import 'package:flutter/services.dart';

import '../core/domain/custom_provider.dart';

/// Android-backed provider storage. The native side encrypts the complete
/// provider document with an Android Keystore key; the Dart side only keeps
/// the key in memory while a session is using it.
class CustomProviderStore {
  static const _channel = MethodChannel('io.henry.codex/app_preferences');

  Future<List<CustomProviderConfig>> load() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('loadCustomProviders');
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) => CustomProviderConfig.fromMap(item))
            .where((item) => item.id.isNotEmpty && item.baseUrl.isNotEmpty)
            .toList(growable: false);
      }
    } on MissingPluginException {
      // Widget tests and non-Android embeddings have no native store.
    } on PlatformException {
      // A provider store failure must not prevent local Codex from opening.
    }
    return const <CustomProviderConfig>[];
  }

  Future<void> save(CustomProviderConfig provider) async {
    try {
      await _channel.invokeMethod<void>('saveCustomProvider', provider.toMap());
    } on MissingPluginException {
      // No persistence in widget tests.
    } on PlatformException {
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _channel.invokeMethod<void>(
        'deleteCustomProvider',
        <String, String>{'id': id},
      );
    } on MissingPluginException {
      // No persistence in widget tests.
    }
  }

  Future<String?> loadActiveId() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'loadActiveProviderId',
      );
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> saveActiveId(String? id) async {
    try {
      await _channel.invokeMethod<void>(
        'saveActiveProviderId',
        <String, Object?>{'id': id},
      );
    } on MissingPluginException {
      // No persistence in widget tests.
    }
  }

  Future<String?> loadProviderMode() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'loadModelProviderMode',
      );
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> saveProviderMode(String mode) async {
    try {
      await _channel.invokeMethod<void>(
        'saveModelProviderMode',
        <String, Object?>{'mode': mode},
      );
    } on MissingPluginException {
      // No persistence in widget tests.
    }
  }
}
