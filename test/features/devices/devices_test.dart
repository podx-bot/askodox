import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/devices/data/ble_gateway.dart';
import 'package:podx/features/devices/data/device_repository.dart';
import 'package:podx/features/devices/data/ptt_repository.dart';
import 'package:podx/features/devices/domain/ble_standards.dart';
import 'package:podx/features/devices/domain/pairing_flow.dart';
import 'package:podx/features/devices/presentation/device_screens.dart';
import 'package:podx/features/devices/presentation/ptt_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBle implements AskodoxBleGateway {
  _FakeBle({this.supported = true, this.on = true, this.scanError, this.devices = const [], this.sends = const []});
  final List<AskodoxReading> sends;
  final bool supported;
  final bool on;
  final String? scanError;
  final List<AskodoxBleDevice> devices;
  final connected = <String>[];
  final disconnected = <String>[];

  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> isOn() async => on;
  @override
  Future<void> requestTurnOn() async {}
  @override
  Future<List<AskodoxBleDevice>> scan(Duration timeout) async {
    if (scanError != null) throw AskodoxBleException(scanError!);
    return devices;
  }

  @override
  Future<void> connect(String id) async => connected.add(id);
  @override
  Future<List<String>> discoverServices(String id) async => ['0000181d-0000-1000-8000-00805f9b34fb'];
  @override
  Stream<AskodoxReading> readings(String id) => Stream.fromIterable(sends);
  @override
  Future<void> disconnect(String id) async => disconnected.add(id);
}

class _Client implements ApiClient {
  _Client(this.reply);
  final Map<String, Object?> Function(String path, Object? body) reply;
  final posts = <String, Object?>{};

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(reply(path, null) as T);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts[path] = body;
    return ApiSuccess(reply(path, body) as T);
  }

  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{} as T);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
  await tester.pumpAndSettle();
}

void main() {
  group('BLE standard decoders (Bluetooth SIG GATT)', () {
    test('weight: SI 0.005 kg, imperial 0.01 lb, 0xFFFF unsuccessful', () {
      // 70.0 kg = 14000 * 0.005
      expect(askodoxDecodeWeight([0x00, 0xB0, 0x36])!.value, closeTo(70.0, 1e-9));
      expect(askodoxDecodeWeight([0x01, 0x58, 0x1B])!.unit, 'lb'); // 7000 * 0.01 = 70 lb
      expect(askodoxDecodeWeight([0x00, 0xFF, 0xFF]), isNull);
      expect(askodoxDecodeWeight([0x00]), isNull);
    });

    test('environment temperature / humidity', () {
      expect(askodoxDecodeEnvTemperature([0x2A, 0x09])!.value, closeTo(23.46, 1e-9)); // 2346
      expect(askodoxDecodeEnvTemperature([0x18, 0xFC])!.value, closeTo(-10.0, 1e-9)); // -1000
      expect(askodoxDecodeEnvTemperature([0x00, 0x80]), isNull);
      expect(askodoxDecodeHumidity([0x88, 0x13])!.value, closeTo(50.0, 1e-9)); // 5000
      expect(askodoxDecodeHumidity([0xFF, 0xFF]), isNull);
    });

    test('thermometer IEEE-11073 float, heart rate, battery', () {
      // 365 * 10^-1 = 36.5 °C: mantissa 0x00016D, exponent 0xFF (-1)
      final t = askodoxDecodeThermometer([0x00, 0x6D, 0x01, 0x00, 0xFF])!;
      expect(t.value, closeTo(36.5, 1e-9));
      expect(t.unit, '°C');
      expect(askodoxDecodeThermometer([0x01, 0x6D, 0x01, 0x00, 0xFF])!.unit, '°F');
      expect(askodoxDecodeThermometer([0x00, 0xFF, 0xFF, 0x7F, 0x00]), isNull, reason: 'NaN special value');
      expect(askodoxDecodeHeartRate([0x00, 72])!.value, 72);
      expect(askodoxDecodeHeartRate([0x01, 0x2C, 0x01])!.value, 300);
      expect(askodoxDecodeBattery([87])!.formatted(), '87 %');
      expect(askodoxDecodeBattery([150]), isNull);
    });

    test('UUID forms and profile matching', () {
      expect(askodoxShortUuid('0000181D-0000-1000-8000-00805F9B34FB'), '181d');
      expect(askodoxShortUuid('181a'), '181a');
      expect(askodoxShortUuid('6e400001-b5a3-f393-e0a9-e50e24dcca9e'), isNull);
      expect(askodoxProfilesFor(['181a']).map((p) => p.kind), ['temperature', 'humidity']);
      expect(askodoxDecode('2a19', [50])!.value, 50);
      expect(askodoxDecode('ffff', [1, 2]), isNull, reason: 'unknown characteristic -> no made-up reading');
    });
  });

  group('Pairing state machine', () {
    AskodoxPairingState run(List<AskodoxPairingEvent> events) {
      var s = const AskodoxPairingState(AskodoxPairingStep.idle);
      for (final e in events) {
        s = askodoxPairingNext(s, e);
      }
      return s;
    }

    test('happy path', () {
      expect(
          run([
            AskodoxPairingEvent.start, AskodoxPairingEvent.bleOn, AskodoxPairingEvent.scanDone,
            AskodoxPairingEvent.select, AskodoxPairingEvent.connected, AskodoxPairingEvent.discovered,
            AskodoxPairingEvent.saved,
          ]).step,
          AskodoxPairingStep.saved);
    });

    test('out-of-order events never jump forward', () {
      expect(run([AskodoxPairingEvent.saved]).step, AskodoxPairingStep.idle);
      expect(run([AskodoxPairingEvent.start, AskodoxPairingEvent.connected]).step, AskodoxPairingStep.checking);
      expect(run([AskodoxPairingEvent.start, AskodoxPairingEvent.bleUnsupported, AskodoxPairingEvent.bleOn]).step,
          AskodoxPairingStep.unsupported);
    });

    test('permission denial and errors land in failed with a reason; retry restarts', () {
      final denied = askodoxPairingNext(
          run([AskodoxPairingEvent.start, AskodoxPairingEvent.bleOn]), AskodoxPairingEvent.permissionDenied);
      expect(denied.step, AskodoxPairingStep.failed);
      expect(denied.reason, 'permission_denied');
      expect(askodoxPairingNext(denied, AskodoxPairingEvent.start).step, AskodoxPairingStep.checking);
    });
  });

  testWidgets('add device: scan -> choose -> standard profile detected -> save (NOT hardware verified)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ble = _FakeBle(devices: const [
      AskodoxBleDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'Scale X', rssi: -50, serviceUuids: ['181d']),
    ]);
    final client = _Client((path, body) => {
          'status': 'success',
          'device': {'id': 'dev_1', 'name': 'Scale X', 'category': 'weighing_scale', 'capabilities': ['read_weight'],
            'status': 'paired'},
        });
    await _pump(tester, const AskodoxAddDeviceScreen(), [
      askodoxBleGatewayProvider.overrideWithValue(ble),
      askodoxDeviceRepositoryProvider.overrideWithValue(AskodoxDeviceRepository(client, authToken: 't')),
    ]);
    await tester.tap(find.byKey(const Key('askodoxBleScan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxBleFound-AA:BB:CC:DD:EE:FF')));
    await tester.pumpAndSettle();
    expect(ble.connected, ['AA:BB:CC:DD:EE:FF']);
    expect(find.textContaining('Weight scale'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBleSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBleSaved')), findsOneWidget);
    final body = client.posts['/api/devices'] as Map;
    expect(body['identifier'], 'AA:BB:CC:DD:EE:FF', reason: 'the server hashes it; the phone keeps the raw id');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('askodox.devices.local.v1'), contains('dev_1'));
  });

  for (final (label, fake, key) in [
    ('no BLE', _FakeBle(supported: false), 'askodoxBleUnsupported'),
    ('Bluetooth off', _FakeBle(on: false), 'askodoxBleOff'),
    ('permission denied', _FakeBle(scanError: 'permission_denied'), 'askodoxPairingFailed'),
  ]) {
    testWidgets('$label is said plainly', (tester) async {
      await _pump(tester, const AskodoxAddDeviceScreen(), [askodoxBleGatewayProvider.overrideWithValue(fake)]);
      await tester.tap(find.byKey(const Key('askodoxBleScan')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(key)), findsOneWidget);
      if (key == 'askodoxPairingFailed') expect(find.textContaining('Nearby devices'), findsOneWidget);
    });
  }

  testWidgets('a non-standard device is not given made-up readings', (tester) async {
    final ble = _FakeBle(devices: const [AskodoxBleDevice(id: '11:22', name: 'Bulb', rssi: -60, serviceUuids: ['fff0'])]);
    final noStd = _NoStdBle(ble);
    await _pump(tester, const AskodoxAddDeviceScreen(), [askodoxBleGatewayProvider.overrideWithValue(noStd)]);
    await tester.tap(find.byKey(const Key('askodoxBleScan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxBleFound-11:22')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBleNoProfile')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBleLive')), findsNothing);
  });

  testWidgets('live screen shows readings as sent and disconnects on exit', (tester) async {
    final ble = _FakeBle(sends: const [AskodoxReading('weight', 70.0, 'kg')]);
    await _pump(tester, const AskodoxDeviceLiveScreen(localId: 'AA', name: 'Scale'), [
      askodoxBleGatewayProvider.overrideWithValue(ble),
      askodoxDeviceRepositoryProvider.overrideWithValue(AskodoxDeviceRepository(_Client((_, __) => {}))),
    ]);
    expect(find.text('70.00 kg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(ble.disconnected, ['AA']);
  });

  testWidgets('push-to-talk: hold records, release sends; others\' new clips auto-play', (tester) async {
    final audio = _FakeAudio();
    var clipsCall = 0;
    final client = _Client((path, body) {
      if (path.endsWith('/clips') && body != null) {
        return {'clip': {'id': 'c_me', 'sender_name': 'Me', 'mine': true, 'duration_ms': 1200, 'created_at': '2026-10-23T01:00:00'}};
      }
      clipsCall++;
      return {
        'clips': clipsCall == 1
            ? const []
            : [{'id': 'c_other', 'sender_name': 'Sita', 'mine': false, 'duration_ms': 900, 'created_at': '2026-10-23T01:00:05'}],
      };
    });
    final repo = _AudioRepo(client);
    await _pump(tester, const AskodoxPttChannelScreen(channelId: 'ptt_1', name: 'Farm', code: 'ABC234'), [
      askodoxPttRepositoryProvider.overrideWithValue(repo),
      askodoxPttAudioProvider.overrideWithValue(audio),
    ]);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('askodoxPttTalk'))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(audio.recording, isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(audio.recording, isFalse);
    final sent = client.posts['/api/ptt/channels/ptt_1/clips'] as Map;
    expect(sent['mime_type'], 'audio/mp4');
    expect(find.text('You'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // poll
    await tester.pumpAndSettle();
    expect(find.text('Sita'), findsOneWidget);
    expect(audio.played, 1, reason: 'a new clip from someone else auto-plays once');
    await tester.pumpWidget(const SizedBox());
  });
}

class _NoStdBle extends _FakeBle {
  _NoStdBle(_FakeBle base) : super(devices: base.devices);
  @override
  Future<List<String>> discoverServices(String id) async => ['0000fff0-0000-1000-8000-00805f9b34fb'];
}

class _FakeAudio implements AskodoxPttAudio {
  bool recording = false;
  int played = 0;
  @override
  Future<bool> start() async => recording = true;
  @override
  Future<Uint8List?> stop() async {
    recording = false;
    return Uint8List.fromList(List.filled(400, 1));
  }

  @override
  Future<bool> play(Uint8List bytes) async {
    played++;
    return true;
  }
}

class _AudioRepo extends AskodoxPttRepository {
  _AudioRepo(super.client) : super(authToken: 't');
  @override
  Future<Uint8List> audio(String clipId) async => Uint8List.fromList([1, 2, 3]);
}
