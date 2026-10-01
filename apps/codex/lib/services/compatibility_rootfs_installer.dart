import 'package:flutter/services.dart';

import '../backends/compatibility/linux_compatibility_backend.dart';

/// Lets the user import/update the Linux/PRoot environment from a local folder.
/// The Android side owns manifest verification, KernelSU installation, and the
/// post-install PRoot probe; this client only transports the result.
class CompatibilityRootfsInstaller {
  const CompatibilityRootfsInstaller({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel(
    'io.henry.codex/linux_compatibility_runtime',
  );

  final MethodChannel _channel;

  /// Returns null only when the user cancels the folder picker.
  Future<CompatibilityRuntimeDescriptor?> pickAndInstall() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('pickAndInstallRootfs');
      if (raw == null) return null;
      if (raw is! Map<Object?, Object?> || raw['state'] != 'verified') {
        throw PlatformException(
          code: 'compatibility_rootfs_install_failed',
          message: 'The installed Linux compatibility runtime did not verify.',
        );
      }
      return CompatibilityRuntimeDescriptor.fromMap(raw);
    } on MissingPluginException {
      throw PlatformException(
        code: 'compatibility_rootfs_install_unavailable',
        message: 'Linux compatibility rootfs import is not available on this platform.',
      );
    }
  }
}
