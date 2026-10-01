import 'dart:async';

import 'package:flutter/services.dart';

class AppHostAccessResult {
  const AppHostAccessResult({
    required this.state,
    required this.identity,
    required this.path,
    this.readable = false,
    this.writable = false,
    this.entryCount,
    this.reason,
  });

  factory AppHostAccessResult.fromMap(Map<Object?, Object?> value) {
    return AppHostAccessResult(
      state: value['state'] as String? ?? 'unavailable',
      identity: value['identity'] as String? ?? 'app',
      path: value['path'] as String? ?? '/storage/emulated/0/Codex/Workspaces',
      readable: value['readable'] as bool? ?? false,
      writable: value['writable'] as bool? ?? false,
      entryCount: (value['entryCount'] as num?)?.toInt(),
      reason: value['reason'] as String?,
    );
  }

  final String state;
  final String identity;
  final String path;
  final bool readable;
  final bool writable;
  final int? entryCount;
  final String? reason;

  bool get isAvailable => state == 'available';

  String get label {
    switch (state) {
      case 'available':
        return 'Available';
      case 'missing':
        return 'Missing';
      case 'denied':
        return 'Denied';
      case 'failed':
        return 'Failed';
      default:
        return 'Unavailable';
    }
  }
}

class AppHostAccessProbe {
  static const _channel = MethodChannel('io.henry.codex/native_probe');

  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openHostAccessSettings');
    } on MissingPluginException {
      throw PlatformException(
        code: 'host_access_settings_unavailable',
        message: 'Android storage access settings are unavailable.',
      );
    }
  }

  Future<AppHostAccessResult> run() async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('probeAppHostAccess')
          .timeout(const Duration(seconds: 4));
      if (raw is Map<Object?, Object?>) {
        return AppHostAccessResult.fromMap(raw);
      }
      return const AppHostAccessResult(
        state: 'failed',
        identity: 'app',
        path: '/storage/emulated/0/Codex/Workspaces',
        reason: 'Native App UID host probe returned an invalid result.',
      );
    } on MissingPluginException {
      return const AppHostAccessResult(
        state: 'unavailable',
        identity: 'app',
        path: '/storage/emulated/0/Codex/Workspaces',
        reason: 'Native App UID host probe is not available on this platform.',
      );
    } on TimeoutException {
      return const AppHostAccessResult(
        state: 'failed',
        identity: 'app',
        path: '/storage/emulated/0/Codex/Workspaces',
        reason: 'Native App UID host probe timed out.',
      );
    } on PlatformException catch (error) {
      return AppHostAccessResult(
        state: 'failed',
        identity: 'app',
        path: '/storage/emulated/0/Codex/Workspaces',
        reason: error.message ?? error.code,
      );
    }
  }
}
