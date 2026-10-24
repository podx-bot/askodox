import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/multi.dart';
import 'package:zxing_lib/zxing.dart';

import '../../../services/chat_attachment_service.dart';
import '../../../services/media_picker.dart';
import '../../devices/data/ble_gateway.dart';
import '../domain/pos_scale.dart';

/// Barcode scanning from a camera PHOTO, decoded on the phone in pure Dart
/// (zxing_lib: EAN / UPC / Code 128 / QR ...). A live camera-preview scanner
/// (mobile_scanner) was tried and dropped: adding it broke the OTP SMS-consent
/// flow when the app returns from the background (emulator A/B, 2026-10-24).
/// Injectable so the counter is tested without a camera.
abstract interface class AskodoxBarcodeScanner {
  /// The barcode text, or null if the person cancelled. Throws
  /// [AskodoxScanException] when a photo was taken but no barcode was found.
  Future<String?> scan(BuildContext context);
}

class AskodoxScanException implements Exception {
  const AskodoxScanException(this.code);

  /// not_found | camera_failed
  final String code;

  String message(bool te) => code == 'not_found'
      ? (te ? 'ఫోటోలో బార్‌కోడ్ కనబడలేదు. దగ్గరగా, వెలుతురులో, నేరుగా తీయండి — లేదా నంబర్ టైప్ చేయండి.'
          : 'No barcode found in the photo. Shoot closer, in good light, straight on — or type the number.')
      : (te ? 'కెమెరా తెరవలేకపోయాను.' : 'Could not open the camera.');
}

class PhotoBarcodeScanner implements AskodoxBarcodeScanner {
  const PhotoBarcodeScanner(this._picker);
  final AskodoxMediaPicker _picker;

  @override
  Future<String?> scan(BuildContext context) async {
    List<ChatAttachment> picked;
    try {
      picked = await _picker.pick('camera');
    } catch (_) {
      throw const AskodoxScanException('camera_failed');
    }
    final photo = picked.where((p) => p.isImage).firstOrNull;
    if (photo == null) return null;
    final image = await askodoxDecodeForScan(photo.bytes);
    final code = await compute(askodoxDecodeBarcodePixels, image);
    if (code == null) throw const AskodoxScanException('not_found');
    return code;
  }
}

/// Every barcode in ONE photo (the exit check of a self-shopping list).
abstract interface class AskodoxMultiBarcodeScanner {
  /// The distinct barcodes seen; null when cancelled; empty when none was found.
  Future<List<String>?> scanAll(BuildContext context);
}

class PhotoMultiBarcodeScanner implements AskodoxMultiBarcodeScanner {
  const PhotoMultiBarcodeScanner(this._picker);
  final AskodoxMediaPicker _picker;

  @override
  Future<List<String>?> scanAll(BuildContext context) async {
    List<ChatAttachment> picked;
    try {
      picked = await _picker.pick('camera');
    } catch (_) {
      throw const AskodoxScanException('camera_failed');
    }
    final photo = picked.where((p) => p.isImage).firstOrNull;
    if (photo == null) return null;
    // Bigger than a single scan: many small barcodes in one picture.
    final image = await askodoxDecodeForScan(photo.bytes, maxSide: 2400);
    return compute(askodoxDecodeAllBarcodesPixels, image);
  }
}

final askodoxMultiBarcodeScannerProvider =
    Provider<AskodoxMultiBarcodeScanner>((ref) => PhotoMultiBarcodeScanner(ref.watch(askodoxMediaPickerProvider)));

/// All DIFFERENT barcodes in the pixels (as taken, then turned 90° for codes lying the other way).
/// The same barcode on two packets is reported once -- quantities are counted by hand.
List<String> askodoxDecodeAllBarcodesPixels(AskodoxScanImage image) {
  final found = <String>[];
  void attempt(int w, int h, List<int> px) {
    try {
      final bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(w, h, px)));
      final results = GenericMultipleBarcodeReader(MultiFormatReader()).decodeMultiple(bitmap, const DecodeHint(tryHarder: true));
      for (final r in results) {
        final text = r.text.trim();
        if (text.isNotEmpty && !found.contains(text)) found.add(text);
      }
    } catch (_) {
      // nothing readable in this orientation
    }
  }

  attempt(image.width, image.height, image.argb);
  final w = image.width, h = image.height;
  final turned = Int32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      turned[x * h + (h - 1 - y)] = image.argb[y * w + x];
    }
  }
  attempt(h, w, turned);
  return found;
}

final askodoxBarcodeScannerProvider =
    Provider<AskodoxBarcodeScanner>((ref) => PhotoBarcodeScanner(ref.watch(askodoxMediaPickerProvider)));

/// Pixels of a photo, scaled so the long side is at most [maxSide] (speed), as ARGB ints.
Future<AskodoxScanImage> askodoxDecodeForScan(Uint8List bytes, {int maxSide = 1400}) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final first = (await probe.getNextFrame()).image;
  final w = first.width, h = first.height;
  first.dispose();
  final scale = math.max(w, h) > maxSide ? maxSide / math.max(w, h) : 1.0;
  final codec = await ui.instantiateImageCodec(bytes,
      targetWidth: (w * scale).round(), targetHeight: (h * scale).round());
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final out = AskodoxScanImage(image.width, image.height, askodoxRgbaToArgb(data));
  image.dispose();
  return out;
}

class AskodoxScanImage {
  const AskodoxScanImage(this.width, this.height, this.argb);
  final int width;
  final int height;
  final Int32List argb;
}

Int32List askodoxRgbaToArgb(Uint8List rgba) {
  final out = Int32List(rgba.length ~/ 4);
  for (var i = 0, j = 0; i < out.length; i++, j += 4) {
    out[i] = (rgba[j + 3] << 24) | (rgba[j] << 16) | (rgba[j + 1] << 8) | rgba[j + 2];
  }
  return out;
}

/// Decodes one barcode from ARGB pixels (tries the photo as taken, then turned 90°).
/// Top-level so it can run in a background isolate.
String? askodoxDecodeBarcodePixels(AskodoxScanImage image) {
  String? attempt(int w, int h, List<int> px) {
    try {
      final bitmap = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(w, h, px)));
      final text = MultiFormatReader().decode(bitmap, const DecodeHint(tryHarder: true)).text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null; // NotFound / Checksum / Format: no barcode here
    }
  }

  final direct = attempt(image.width, image.height, image.argb);
  if (direct != null) return direct;
  // Rotate 90° clockwise: new (x, y) = old (y, h - 1 - x).
  final w = image.width, h = image.height;
  final turned = Int32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      turned[x * h + (h - 1 - y)] = image.argb[y * w + x];
    }
  }
  return attempt(h, w, turned);
}

class AskodoxScaleException implements Exception {
  const AskodoxScaleException(this.code);

  /// connect_failed | no_reading | not_weighable
  final String code;

  String message(bool te) => switch (code) {
        'connect_failed' => te ? 'తూకం యంత్రానికి కనెక్ట్ కాలేదు.' : 'Could not connect to the scale.',
        'not_weighable' => te ? 'ఈ ఐటమ్ బరువుతో అమ్మేది కాదు.' : 'This item is not sold by weight.',
        _ => te
            ? 'స్థిరమైన బరువు రాలేదు. సరుకు పెట్టి కాసేపు ఆగండి, లేదా టైప్ చేయండి.'
            : 'No settled weight came. Place the item and wait, or type the weight.',
      };
}

/// Reads ONE settled weight from a standard Bluetooth LE weight scale (Weight
/// Scale Service 0x181D). Scales with a private protocol send nothing usable.
/// Never legal-for-trade proof: the cashier still sees and can change the number.
class AskodoxScaleReader {
  const AskodoxScaleReader(this._ble, {this.timeout = const Duration(seconds: 15)});
  final AskodoxBleGateway _ble;
  final Duration timeout;

  Future<int> readItemMilli(String deviceId, String itemUnit) async {
    try {
      await _ble.connect(deviceId);
    } catch (_) {
      throw const AskodoxScaleException('connect_failed');
    }
    final values = <double>[];
    var unit = 'kg';
    double? value;
    try {
      // Own timer + listen (no awaited cancel): a settled weight or the deadline ends the read.
      final done = Completer<double?>();
      final deadline = Timer(timeout, () {
        if (!done.isCompleted) done.complete(null);
      });
      final sub = _ble.readings(deviceId).where((r) => r.kind == 'weight').listen((r) {
        unit = r.unit;
        values.add(r.value);
        final settled = askodoxSettledWeight(values);
        if (settled != null && !done.isCompleted) done.complete(settled);
      }, onError: (Object _) {
        if (!done.isCompleted) done.complete(null);
      }, onDone: () {
        if (!done.isCompleted) done.complete(null);
      });
      value = await done.future;
      deadline.cancel();
      unawaited(sub.cancel());
      if (value == null) throw const AskodoxScaleException('no_reading');
      final milli = askodoxScaleToItemMilli(value, unit, itemUnit);
      if (milli == null) throw const AskodoxScaleException('not_weighable');
      if (milli <= 0) throw const AskodoxScaleException('no_reading');
      return milli;
    } on AskodoxScaleException {
      rethrow;
    } catch (_) {
      throw const AskodoxScaleException('no_reading');
    } finally {
      try {
        await _ble.disconnect(deviceId);
      } catch (_) {}
    }
  }
}

final askodoxScaleReaderProvider = Provider<AskodoxScaleReader>((ref) => AskodoxScaleReader(ref.watch(askodoxBleGatewayProvider)));
