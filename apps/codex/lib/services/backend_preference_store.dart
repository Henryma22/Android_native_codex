import 'package:flutter/services.dart';

/// Persists only the user's last local execution view.
///
/// The preference is a convenience, not a capability grant. The app still
/// probes the selected backend before restoring it and keeps Local Android as
/// the host workspace owner when the optional PRoot runtime is not verified.
/// Root session execution is selected separately at the session boundary.
class BackendPreferenceStore {
  static const _channel = MethodChannel('io.henry.codex/app_preferences');

  Future<String?> loadPreferredBackendId() async {
    try {
      final value = await _channel.invokeMethod<Object?>(
        'loadPreferredBackendId',
      );
      return value is String && value.isNotEmpty ? value : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      // A stale preference must never prevent the local app shell from
      // starting. The next explicit selection can recreate it.
      return null;
    }
  }

  Future<void> savePreferredBackendId(String backendId) async {
    if (backendId.isEmpty) return;
    try {
      await _channel.invokeMethod<void>(
        'savePreferredBackendId',
        <String, Object?>{'backendId': backendId},
      );
    } on MissingPluginException {
      // Widget tests and non-Android platforms have no native preference
      // store; the in-memory selection remains fully functional.
    } on PlatformException {
      // Preference persistence is best-effort and must not block execution.
    }
  }
}
