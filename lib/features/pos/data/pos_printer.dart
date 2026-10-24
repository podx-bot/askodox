import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sends ESC/POS bytes to a receipt printer. Three links:
///  - Bluetooth LE printers with a writable GATT characteristic (plain device id),
///  - Classic Bluetooth (SPP / RFCOMM) printers paired in Android settings (`classic:<MAC>`),
///  - USB printers with a bulk OUT endpoint (`usb:<device name>`), via the native
///    `com.askodox.app/hardware` channel.
/// Network (Wi-Fi / LAN) printers are NOT supported. No printer model is verified
/// until a real one is tested.
abstract interface class AskodoxPrinterTransport {
  Future<void> write(String deviceId, Uint8List bytes);
}

class AskodoxPrinterException implements Exception {
  const AskodoxPrinterException(this.code, [this.detail = '']);

  /// connect_failed | no_writable_characteristic | write_failed | permission_requested
  /// | bluetooth_off | usb_not_found
  final String code;
  final String detail;

  String message(bool te) => switch (code) {
        'connect_failed' => te ? 'ప్రింటర్‌కి కనెక్ట్ కాలేదు. ఆన్‌లో ఉందా, దగ్గరగా ఉందా చూడండి.' : 'Could not connect. Is the printer on and close by?',
        'no_writable_characteristic' => te
            ? 'ఈ పరికరం BLE ప్రింట్ ఛానల్ ఇవ్వలేదు. క్లాసిక్ బ్లూటూత్ ప్రింటర్ అయితే ఫోన్ సెట్టింగ్స్‌లో జత చేసి "జత చేసినవి" నుండి ఎంచుకోండి.'
            : 'This device offers no BLE print channel. If it is a Classic Bluetooth printer, pair it in phone settings and pick it under "Paired".',
        'permission_requested' => te ? 'అనుమతి అడిగాం — ఇచ్చిన తర్వాత మళ్ళీ ప్రయత్నించండి.' : 'Permission asked — allow it, then try again.',
        'bluetooth_off' => te ? 'బ్లూటూత్ ఆఫ్‌లో ఉంది.' : 'Bluetooth is off.',
        'usb_not_found' => te ? 'USB ప్రింటర్ కనెక్ట్ అయి లేదు.' : 'The USB printer is not connected.',
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

/// A printer the phone already knows (paired Classic Bluetooth or attached USB).
class AskodoxNativePrinter {
  const AskodoxNativePrinter({required this.id, required this.name, required this.kind, this.hint = false});

  /// `classic:<MAC>` or `usb:<device name>` — the id the routing transport understands.
  final String id;
  final String name;

  /// classic | usb
  final String kind;

  /// The device reports a printer class (imaging / USB printer) — a hint only.
  final bool hint;
}

/// The native side of Classic Bluetooth + USB printing (`AskodoxHardware.kt`).
class AskodoxNativePrinters {
  const AskodoxNativePrinters([this.channel = const MethodChannel('com.askodox.app/hardware')]);
  final MethodChannel channel;

  static AskodoxPrinterException _error(PlatformException e) => AskodoxPrinterException(
        switch (e.code) {
          'permission_requested' => 'permission_requested',
          'bluetooth_off' || 'no_bluetooth' => 'bluetooth_off',
          'not_found' => 'usb_not_found',
          _ => 'write_failed',
        },
        e.message ?? '',
      );

  Future<List<AskodoxNativePrinter>> paired() async {
    try {
      final rows = await channel.invokeListMethod<Map>('bondedPrinters') ?? const [];
      return [
        for (final r in rows)
          AskodoxNativePrinter(
            id: 'classic:${r['address']}',
            name: '${r['name'] ?? ''}'.isEmpty ? '${r['address']}' : '${r['name']}',
            kind: 'classic',
            hint: r['imaging'] == true,
          ),
      ];
    } on PlatformException catch (e) {
      throw _error(e);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<AskodoxNativePrinter>> usb() async {
    try {
      final rows = await channel.invokeListMethod<Map>('usbPrinters') ?? const [];
      return [
        for (final r in rows)
          AskodoxNativePrinter(id: 'usb:${r['device']}', name: '${r['name']}', kind: 'usb', hint: r['printerClass'] == true),
      ];
    } on PlatformException catch (e) {
      throw _error(e);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> send(String id, Uint8List bytes) async {
    try {
      if (id.startsWith('classic:')) {
        await channel.invokeMethod<bool>('sendClassic', {'address': id.substring(8), 'bytes': bytes});
      } else if (id.startsWith('usb:')) {
        await channel.invokeMethod<bool>('sendUsb', {'device': id.substring(4), 'bytes': bytes});
      } else {
        throw const AskodoxPrinterException('write_failed', 'unknown printer link');
      }
    } on PlatformException catch (e) {
      final err = _error(e);
      // A Classic link that cannot open is a connect failure, not a write failure.
      if (err.code == 'write_failed' && id.startsWith('classic:')) throw AskodoxPrinterException('connect_failed', err.detail);
      throw err;
    }
  }
}

final askodoxNativePrintersProvider = Provider<AskodoxNativePrinters>((ref) => const AskodoxNativePrinters());

/// Routes by the saved id: `classic:` / `usb:` go native, anything else is BLE.
class AskodoxRoutingPrinterTransport implements AskodoxPrinterTransport {
  const AskodoxRoutingPrinterTransport(this.native, [this.ble = const BlePrinterTransport()]);
  final AskodoxNativePrinters native;
  final AskodoxPrinterTransport ble;

  @override
  Future<void> write(String deviceId, Uint8List bytes) {
    if (deviceId.startsWith('classic:') || deviceId.startsWith('usb:')) return native.send(deviceId, bytes);
    return ble.write(deviceId, bytes);
  }
}

final askodoxPrinterTransportProvider = Provider<AskodoxPrinterTransport>(
  (ref) => AskodoxRoutingPrinterTransport(ref.watch(askodoxNativePrintersProvider)),
);

/// The link a saved printer id uses: ble | classic | usb.
String askodoxPrinterLink(String id) => id.startsWith('classic:') ? 'classic' : (id.startsWith('usb:') ? 'usb' : 'ble');

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
