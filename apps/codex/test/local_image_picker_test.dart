import 'dart:typed_data';

import 'package:codex/services/local_image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.henry.codex/native_probe');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final picker = LocalImagePicker();

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'cancellation returns no attachments and the next selection still works',
    () async {
      var cancelled = true;
      final bytes = Uint8List.fromList([1, 2, 3]);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => cancelled
            ? <Object>[]
            : [
                <String, Object>{'bytes': bytes, 'mimeType': 'image/png'},
              ],
      );
      expect(await picker.pickImages(), isEmpty);
      cancelled = false;
      final images = await picker.pickImages();
      expect(images.single.bytes, bytes);
      expect(images.single.mimeType, 'image/png');
    },
  );

  test(
    'malformed or empty selections fail instead of silently dropping images',
    () async {
      for (final response in <Object>[
        'invalid',
        [null],
        [
          <String, Object>{'bytes': Uint8List(0), 'mimeType': 'image/png'},
        ],
        [
          <String, Object>{'bytes': Uint8List(1), 'mimeType': 'text/plain'},
        ],
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => response);
        await expectLater(picker.pickImages(), throwsFormatException);
      }
    },
  );

  test(
    'native read errors propagate and do not poison the next picker call',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'image_import_failed',
          message: 'Unreadable image',
        );
      });
      await expectLater(picker.pickImages(), throwsA(isA<PlatformException>()));
      messenger.setMockMethodCallHandler(channel, (_) async => <Object>[]);
      expect(await picker.pickImages(), isEmpty);
    },
  );
}
