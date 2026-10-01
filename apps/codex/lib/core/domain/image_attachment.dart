import 'dart:convert';
import 'dart:typed_data';

/// An image selected by the Android document picker.
///
/// The bytes stay in memory for the active turn. They are deliberately not
/// written into session history; history stores a small image-count marker so
/// a resumed session does not unexpectedly duplicate a large attachment.
class ImageAttachment {
  const ImageAttachment({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}
