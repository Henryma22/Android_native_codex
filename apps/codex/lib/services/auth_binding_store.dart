import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Identifies the credential generation a local Codex session belongs to.
///
/// The value is intentionally a monotonic generation, not an account name or
/// token.  A session from an older generation may still be displayed as local
/// history, but it must not silently resume against a newly selected account.
class AuthBindingStore {
  AuthBindingStore._();

  static const _channel = MethodChannel('io.henry.codex/app_preferences');
  static const defaultGeneration = 1;

  /// Shared in-process state lets Settings invalidate already-mounted session
  /// pages without making the pages own an auth client or a credential.
  static final currentGeneration = ValueNotifier<int>(defaultGeneration);

  static Future<int>? _loadOperation;
  static var _loaded = false;

  static Future<int> loadCurrent() {
    if (_loaded) return Future<int>.value(currentGeneration.value);
    final pending = _loadOperation;
    if (pending != null) return pending;
    final operation = _loadCurrentImpl();
    _loadOperation = operation;
    return operation.whenComplete(() {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    });
  }

  static Future<int> _loadCurrentImpl() async {
    var generation = defaultGeneration;
    try {
      final raw = await _channel.invokeMethod<Object?>('loadAuthGeneration');
      if (raw is num && raw.toInt() > 0) generation = raw.toInt();
    } on MissingPluginException {
      // Widget tests and non-Android embeddings use the in-memory generation.
    } on PlatformException {
      // A missing preference must not prevent the local shell from starting.
    }
    _loaded = true;
    currentGeneration.value = generation;
    return generation;
  }

  /// Advances the generation after an explicit login/logout/account change.
  ///
  /// No credential is returned or persisted by this API.  If the preference
  /// channel is unavailable, the in-process generation still protects pages
  /// for the lifetime of the app process.
  static Future<int> advance() async {
    await loadCurrent();
    var next = currentGeneration.value + 1;
    try {
      final raw = await _channel.invokeMethod<Object?>('advanceAuthGeneration');
      if (raw is num && raw.toInt() > 0) next = raw.toInt();
    } on MissingPluginException {
      // Keep the in-memory fallback above.
    } on PlatformException {
      // Keep the in-memory fallback above.
    }
    _loaded = true;
    currentGeneration.value = next;
    return next;
  }
}
