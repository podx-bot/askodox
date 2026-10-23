import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sends ESC/POS bytes to a receipt printer. Only Bluetooth LE printers that
/// expose a writable GATT characteristic are handled; Classic Bluetooth (SPP)
/// printers, USB and network printers are NOT supported yet (stated in the app).
/// No printer model is verified until a real one is tested.
abstract interface class AskodoxPrinterTransport {
  Future<void> write(String deviceId, Uint8List bytes);
}

class AskodoxPrinterException implements Exception {
  const AskodoxPrinterException(this.code, [this.detail = '']);

  /// connect_failed | no_writable_characteristic | write_failed
  final String code;
  final String detail;

  String message(bool te) => switch (code) {
        'connect_failed' => te ? 'ప్రింటర్‌కి కనెక్ట్ కాలేదు. ఆన్‌లో ఉందా, దగ్గరగా ఉందా చూడండి.' : 'Could not connect. Is the printer on and close by?',
        'no_writable_characteristic' => te
            ? 'ఈ పరికరం BLE ప్రింట్ ఛానల్ ఇవ్వలేదు (క్లాసిక్ బ్లూటూత్ ప్రింటర్ కావచ్చు — ఇంకా సపోర్ట్ లేదు).'
            : 'This device offers no BLE print channel (it may be a Classic Bluetooth printer — not supported yet).',
        _ => te ? 'ప్రింట్ పంపలేకపోయాను.' : 'Could not send the print.',
      };
}

/// Splits [bytes] into chunks the BLE link can carry.
List<Uint8List> askodoxChunks(Uint8List bytes, int size) {
  final out = <Uint8List>[];
  for (var i = 0; i < bytes.length; i += size) {
    out.add(Uint8List.sublistView(bytes, i, min(i + size, bytes.length)));
  }
  return out;
}

class BlePrinterTransport implements AskodoxPrinterTransport {
  const BlePrinterTransport();

  @override
  Future<void> write(String deviceId, Uint8List bytes) async {
    final device = BluetoothDevice.fromId(deviceId);
    try {
      await device.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      throw AskodoxPrinterException('connect_failed', '$e');
    }
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? target;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.writeWithoutResponse || c.properties.write) {
            target ??= c;
            if (c.properties.writeWithoutResponse) {
              target = c;
              break;
            }
          }
        }
      }
      if (target == null) throw const AskodoxPrinterException('no_writable_characteristic');
      final size = max(20, min(180, device.mtuNow - 3));
      final noResponse = target.properties.writeWithoutResponse;
      for (final chunk in askodoxChunks(bytes, size)) {
        await target.write(chunk, withoutResponse: noResponse);
      }
    } on AskodoxPrinterException {
      rethrow;
    } catch (e) {
      throw AskodoxPrinterException('write_failed', '$e');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}

final askodoxPrinterTransportProvider = Provider<AskodoxPrinterTransport>((ref) => const BlePrinterTransport());

const askodoxPosPrinterKey = 'askodox.pos.printer.v1';

class AskodoxSavedPrinter {
  const AskodoxSavedPrinter({required this.id, required this.name, this.paperMm = 58});
  final String id;
  final String name;
  final int paperMm;

  static Future<AskodoxSavedPrinter?> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final m = jsonDecode(prefs.getString(askodoxPosPrinterKey) ?? '') as Map;
      return AskodoxSavedPrinter(id: '${m['id']}', name: '${m['name']}', paperMm: (m['paper_mm'] as num?)?.toInt() ?? 58);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(askodoxPosPrinterKey, jsonEncode({'id': id, 'name': name, 'paper_mm': paperMm}));
  }
}
