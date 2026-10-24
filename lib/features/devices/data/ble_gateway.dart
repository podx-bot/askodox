import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ble_standards.dart';

/// A BLE device seen in a scan.
class AskodoxBleDevice {
  const AskodoxBleDevice({required this.id, required this.name, required this.rssi, this.serviceUuids = const []});
  final String id; // remote id (Android: Bluetooth address) -- stays on the phone
  final String name;
  final int rssi;
  final List<String> serviceUuids;
}

class AskodoxBleException implements Exception {
  const AskodoxBleException(this.code, [this.detail = '']);

  /// permission_denied | scan_failed | connect_failed | discover_failed
  final String code;
  final String detail;
  @override
  String toString() => 'AskodoxBleException($code, $detail)';
}

/// The phone's Bluetooth LE radio, injectable so the Add-Device flow is
/// tested without hardware (tests are NOT a hardware verification).
abstract interface class AskodoxBleGateway {
  Future<bool> isSupported();
  Future<bool> isOn();
  Future<void> requestTurnOn();
  Future<List<AskodoxBleDevice>> scan(Duration timeout);
  Future<void> connect(String id);
  Future<List<String>> discoverServices(String id);

  /// Decoded readings from the standard profiles the device offers
  /// (notifications where supported, otherwise one read).
  Stream<AskodoxReading> readings(String id);
  Future<void> disconnect(String id);
}

String _code(Object error, String fallback) {
  final text = '$error'.toLowerCase();
  return text.contains('permission') || text.contains('denied') ? 'permission_denied' : fallback;
}

class FlutterBluePlusGateway implements AskodoxBleGateway {
  const FlutterBluePlusGateway();

  @override
  Future<bool> isSupported() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isOn() async {
    try {
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3));
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> requestTurnOn() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // The user declined or the platform cannot; the UI keeps "Bluetooth is off".
    }
  }

  @override
  Future<List<AskodoxBleDevice>> scan(Duration timeout) async {
    final found = <String, AskodoxBleDevice>{};
    StreamSubscription<List<ScanResult>>? sub;
    try {
      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.str;
          final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
          found[id] = AskodoxBleDevice(
            id: id,
            name: name,
            rssi: r.rssi,
            serviceUuids: [for (final g in r.advertisementData.serviceUuids) g.toString()],
          );
        }
      });
      await FlutterBluePlus.startScan(timeout: timeout);
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first.timeout(timeout + const Duration(seconds: 5));
    } catch (error) {
      throw AskodoxBleException(_code(error, 'scan_failed'), '$error');
    } finally {
      await sub?.cancel();
    }
    final list = found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  @override
  Future<void> connect(String id) async {
    try {
      await BluetoothDevice.fromId(id).connect(timeout: const Duration(seconds: 15));
    } catch (error) {
      throw AskodoxBleException(_code(error, 'connect_failed'), '$error');
    }
  }

  @override
  Future<List<String>> discoverServices(String id) async {
    try {
      final services = await BluetoothDevice.fromId(id).discoverServices();
      return [for (final s in services) s.uuid.toString()];
    } catch (error) {
      throw AskodoxBleException(_code(error, 'discover_failed'), '$error');
    }
  }

  @override
  Stream<AskodoxReading> readings(String id) {
    final controller = StreamController<AskodoxReading>();
    final subs = <StreamSubscription<List<int>>>[];
    Future<void> start() async {
      try {
        final services = await BluetoothDevice.fromId(id).discoverServices();
        for (final service in services) {
          for (final characteristic in service.characteristics) {
            final uuid = characteristic.uuid.toString();
            final short = askodoxShortUuid(uuid);
            if (!askodoxBleProfiles.any((p) => p.characteristic == short)) continue;
            void push(List<int> bytes) {
              final reading = askodoxDecode(uuid, bytes);
              if (reading != null && !controller.isClosed) controller.add(reading);
            }

            final props = characteristic.properties;
            if (props.notify || props.indicate) {
              subs.add(characteristic.onValueReceived.listen(push));
              await characteristic.setNotifyValue(true);
            } else if (props.read) {
              push(await characteristic.read());
            }
          }
        }
      } catch (error) {
        if (!controller.isClosed) controller.addError(AskodoxBleException('discover_failed', '$error'));
      }
    }

    controller.onListen = () => unawaited(start());
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  @override
  Future<void> disconnect(String id) async {
    try {
      await BluetoothDevice.fromId(id).disconnect();
    } catch (_) {
      // already disconnected
    }
  }
}

final askodoxBleGatewayProvider = Provider<AskodoxBleGateway>((ref) => const FlutterBluePlusGateway());
