import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_hardware.dart';
import 'package:zxing_lib/qrcode.dart';
import 'package:zxing_lib/zxing.dart';

const _upi = 'upi://pay?pa=lakshmi.kirana@ybl&pn=Lakshmi%20Kirana&mc=5411&tr=STQ1234567890&mode=02&purpose=00';
const _white = 0xFFFFFFFF;
const _black = 0xFF000000;

/// A phone SCREENSHOT of a UPI app's "My QR" card: tall canvas, text bars around the code, a logo over the centre.
AskodoxScanImage _screenshot({bool dark = false, int module = 7, int width = 1080, int height = 2340}) {
  final bg = dark ? 0xFF121212 : 0xFFF2F2F7;
  final ink = dark ? _white : _black;
  final paper = dark ? _black : _white;
  final px = Int32List(width * height)..fillRange(0, width * height, bg);
  void rect(int x0, int y0, int w, int h, int colour) {
    for (var y = y0; y < y0 + h && y < height; y++) {
      for (var x = x0; x < x0 + w && x < width; x++) {
        px[y * width + x] = colour;
      }
    }
  }

  // Header + footer text lines (dark blocks the finder must ignore).
  for (var i = 0; i < 6; i++) {
    rect(90, 180 + i * 70, 600 - i * 60, 34, ink);
    rect(90, 1750 + i * 70, 820 - i * 90, 34, ink);
  }
  final matrix = QRCodeWriter().encode(_upi, BarcodeFormat.qrCode, 0, 0,
      const EncodeHint(errorCorrectionLevel: ErrorCorrectionLevel.H, margin: 2));
  final size = matrix.width * module;
  final x0 = (width - size) ~/ 2, y0 = 650;
  rect(x0 - 30, y0 - 30, size + 60, size + 60, paper);
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      rect(x0 + x * module, y0 + y * module, module, module, matrix.get(x, y) ? ink : paper);
    }
  }
  // Brand logo over the middle (UPI cards use high error correction for this).
  final logo = size ~/ 6;
  rect(x0 + (size - logo) ~/ 2, y0 + (size - logo) ~/ 2, logo, logo, 0xFF5F259F);
  return AskodoxScanImage(width, height, px);
}

void main() {
  test('a UPI QR screenshot (text around it, logo in the middle) is read exactly, as the app scales it', () {
    final shot = _screenshot();
    final scaled = askodoxShrink(shot, 2000 / 2340);
    expect(askodoxDecodeQrPixels(scaled), _upi);
  });

  test('a dark-mode (inverted) QR card is read', () {
    expect(askodoxDecodeQrPixels(_screenshot(dark: true)), _upi);
  });

  test('a small QR in a big photo is read', () {
    expect(askodoxDecodeQrPixels(_screenshot(module: 3, width: 1500, height: 2000)), _upi);
  });

  test('crop and shrink keep the picture honest; a blank photo finds nothing', () {
    final img = AskodoxScanImage(4, 2, Int32List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    final c = askodoxCropCentre(img, 0.5);
    expect([c.width, c.height, c.argb.toList()], [2, 1, [2, 3]]);
    final s = askodoxShrink(AskodoxScanImage(2, 2, Int32List.fromList([_white, _white, _black, _black])), 0.5);
    expect([s.width, s.height], [1, 1]);
    expect(s.argb[0] & 0xFF, 127, reason: 'box average of two white + two black pixels');
    expect(askodoxDecodeQrPixels(AskodoxScanImage(60, 60, Int32List(3600)..fillRange(0, 3600, _white))), isNull);
  });
}
