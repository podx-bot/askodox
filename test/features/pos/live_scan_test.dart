import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_hardware.dart';

void main() {
  test('camera frame brightness (with row padding) becomes grey ARGB pixels for the barcode reader', () {
    // 3 x 2 picture, rows padded to 4 bytes.
    final y = Uint8List.fromList([10, 20, 30, 99, 40, 50, 60, 99]);
    final image = askodoxScanImageFromLuma(y, 3, 2, 4);
    expect(image.width, 3);
    expect(image.height, 2);
    expect(image.argb[0] & 0xFFFFFF, 0x0A0A0A);
    expect(image.argb[2] & 0xFFFFFF, 0x1E1E1E);
    expect(image.argb[3] & 0xFFFFFF, 0x282828, reason: 'the padding byte of row 1 is skipped');
    expect(image.argb[5] & 0xFFFFFF, 0x3C3C3C);
    expect(image.argb[0] >> 24 & 0xFF, 0xFF);
  });
}
