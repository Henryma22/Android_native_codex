import 'package:flutter/services.dart';

/// Connects the Local Session lifecycle to Android's foreground service.
///
/// Widget tests and non-Android builds have no native service, so this adapter
/// intentionally treats a missing plugin as a no-op.
class SessionLifecycle {
  static const _channel = MethodChannel('io.henry.codex/local_backend');
  static var _owners = 0;
  static Future<void>? _startOperation;

  static Future<void> start() async {
    _owners++;
    if (_owners > 1) {
      final operation = _startOperation;
      if (operation != null) {
        try {
          await operation;
        } catch (_) {
          _owners = _owners > 0 ? _owners - 1 : 0;
          rethrow;
        }
      }
      return;
    }
    final operation = _startNative();
    _startOperation = operation;
    try {
      await operation;
    } catch (_) {
      _owners = _owners > 0 ? _owners - 1 : 0;
      rethrow;
    } finally {
      if (identical(_startOperation, operation)) _startOperation = null;
    }
  }

  static Future<void> stop() async {
    if (_owners == 0) return;
    _owners--;
    if (_owners > 0) return;
    final starting = _startOperation;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        return;
      }
      // Another session may have acquired an owner while the first Android
      // foreground request was settling. In that case this stop belongs to
      // the old zero-owner moment and must not tear down the shared service.
      if (_owners > 0) return;
    }
    try {
      await _channel.invokeMethod<void>('stopSessionForeground');
    } on MissingPluginException {
      // Expected on non-Android test platforms.
    }
  }

  static Future<void> _startNative() async {
    try {
      final notificationsAllowed = await _channel.invokeMethod<bool>(
        'requestSessionNotificationPermission',
      );
      if (notificationsAllowed == false) {
        throw const SessionNotificationPermissionDenied();
      }
      await _channel.invokeMethod<void>('startSessionForeground');
    } on MissingPluginException {
      // Expected on non-Android test platforms.
    }
  }
}

class SessionNotificationPermissionDenied implements Exception {
  const SessionNotificationPermissionDenied();

  @override
  String toString() =>
      'Session notifications are disabled. Allow notifications in Android '
      'settings, then start the session again.';
}
