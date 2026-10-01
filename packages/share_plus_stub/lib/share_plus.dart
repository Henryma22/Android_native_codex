import 'package:flutter/foundation.dart';

/// Minimal API used by CC Pocket's message action bar.
///
/// The independent local Codex app keeps the original share affordance in the
/// UI, but does not pull CC Pocket's native sharing/plugin stack into its
/// local runtime. A future Android share-sheet adapter can replace this shim.
class SharePlus {
  SharePlus._();

  static final SharePlus instance = SharePlus._();

  Future<ShareResult> share(ShareParams params) async {
    debugPrint('Share requested for local Codex content (${params.text?.length ?? 0} chars).');
    return const ShareResult.unavailable();
  }
}

class ShareParams {
  const ShareParams({
    this.text,
    this.files = const [],
    this.fileNameOverrides = const [],
    this.sharePositionOrigin,
  });

  final String? text;
  final List<XFile> files;
  final List<String> fileNameOverrides;
  final Object? sharePositionOrigin;
}

/// Data-only stand-in for the share plugin's cross-platform file handle.
class XFile {
  const XFile.fromData(this.bytes, {this.mimeType});

  final List<int> bytes;
  final String? mimeType;
}

class ShareResult {
  const ShareResult._(this.status);

  const ShareResult.unavailable() : this._(ShareResultStatus.unavailable);

  final ShareResultStatus status;
}

enum ShareResultStatus { unavailable }
