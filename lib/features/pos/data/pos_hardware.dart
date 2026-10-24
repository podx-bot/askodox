import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../devices/data/ble_gateway.dart';
import '../domain/pos_scale.dart';

/// Camera barcode scanning (ML Kit through mobile_scanner). Injectable so the
/// counter is tested without a camera; tests are NOT a hardware verification.
abstract interface class AskodoxBarcodeScanner {
  /// The first barcode seen, or null if the person closed the scanner.
  Future<String?> scan(BuildContext context);
}

class CameraBarcodeScanner implements AskodoxBarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const AskodoxBarcodeScanScreen()));
}

final askodoxBarcodeScannerProvider = Provider<AskodoxBarcodeScanner>((ref) => const CameraBarcodeScanner());

class AskodoxBarcodeScanScreen extends StatefulWidget {
  const AskodoxBarcodeScanScreen({super.key});

  @override
  State<AskodoxBarcodeScanScreen> createState() => _AskodoxBarcodeScanScreenState();
}

class _AskodoxBarcodeScanScreenState extends State<AskodoxBarcodeScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బార్‌కోడ్ స్కాన్' : 'Scan barcode')),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final value = b.rawValue;
              if (value != null && value.trim().isNotEmpty) {
                _done = true;
                Navigator.of(context).pop(value.trim());
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? (te ? 'కెమెరా అనుమతి ఇవ్వలేదు. సెట్టింగ్స్‌లో ఇవ్వండి లేదా బార్‌కోడ్ టైప్ చేయండి.' : 'Camera permission was not given. Allow it in Settings or type the barcode.')
                    : (te ? 'కెమెరా తెరవలేకపోయాను. బార్‌కోడ్ టైప్ చేయండి.' : 'Could not open the camera. Type the barcode instead.'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Text(
            te ? 'బార్‌కోడ్‌ను ఫ్రేమ్ మధ్యలో పెట్టండి.' : 'Hold the barcode in the middle of the frame.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)]),
          ),
        ),
      ]),
    );
  }
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
      final stream = _ble
          .readings(deviceId)
          .where((r) => r.kind == 'weight')
          .timeout(timeout, onTimeout: (sink) => sink.close());
      await for (final r in stream) {
        unit = r.unit;
        values.add(r.value);
        value = askodoxSettledWeight(values);
        if (value != null) break;
      }
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
