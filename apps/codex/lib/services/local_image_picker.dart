import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../core/domain/image_attachment.dart';

class LocalImagePicker {
  static const _channel = MethodChannel('io.henry.codex/native_probe');

  Future<List<ImageAttachment>> pickImages() async {
    final raw = await _channel.invokeMethod<Object?>('pickImages');
    if (raw == null) return const <ImageAttachment>[];
    if (raw is! List) {
      throw const FormatException(
        'Android returned an invalid image selection.',
      );
    }
    return raw
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'Android returned an invalid image attachment.',
            );
          }
          final bytes = item['bytes'];
          final mimeType = item['mimeType'];
          if (bytes is! Uint8List ||
              mimeType is! String ||
              !mimeType.startsWith('image/')) {
            throw const FormatException(
              'Android returned an invalid image attachment.',
            );
          }
          if (bytes.isEmpty) {
            throw const FormatException('The selected image is empty.');
          }
          return ImageAttachment(bytes: bytes, mimeType: mimeType);
        })
        .toList(growable: false);
  }
}
