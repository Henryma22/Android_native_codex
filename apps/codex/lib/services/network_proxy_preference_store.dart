import 'package:flutter/services.dart';

/// Stores an optional device-local HTTP proxy used by app and PRoot workers.
/// An empty endpoint means "use Android's automatically detected proxy".
class NetworkProxyPreferenceStore {
  static const _channel = MethodChannel('io.henry.codex/app_preferences');

  Future<String> loadEndpoint() async {
    try {
      return await _channel.invokeMethod<String>('loadHttpProxyEndpoint') ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<void> saveEndpoint(String endpoint) async {
    try {
      await _channel.invokeMethod<void>(
        'saveHttpProxyEndpoint',
        <String, Object?>{'endpoint': endpoint},
      );
    } on MissingPluginException {
      // Non-Android embeddings have no persistent Android network settings.
    }
  }
}
