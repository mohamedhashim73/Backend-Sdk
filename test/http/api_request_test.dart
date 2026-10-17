import 'dart:typed_data';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('infers a MIME type for a common image filename', () {
    final file = ApiMultipartFile(
      field: 'image',
      bytes: Uint8List(0),
      filename: 'avatar.JPG',
    ).toMultipartFile();

    expect(file.contentType.toString(), 'image/jpeg');
  });

  test('keeps an explicitly provided MIME type', () {
    final file = ApiMultipartFile(
      field: 'document',
      bytes: Uint8List(0),
      filename: 'file.bin',
      contentType: 'application/custom',
    ).toMultipartFile();

    expect(file.contentType.toString(), 'application/custom');
  });
}
