import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/devices/data/ble_gateway.dart';
import 'package:podx/features/devices/data/device_repository.dart';
import 'package:podx/features/devices/domain/ble_standards.dart';
import 'package:podx/features/pos/data/pos_hardware.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/domain/pos_scale.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mocked hardware only: these tests prove the app's logic, NOT that any real
/// scale or camera works.
class _FakeBle implements AskodoxBleGateway {
  _FakeBle(this.sends, {this.failConnect = false});
  final List<AskodoxReading> sends;
  final bool failConnect;
  final connected = <String>[];
  final disconnected = <String>[];

  @override
  Future<bool> isSupported() async => true;
  @override
  Future<bool> isOn() async => true;
  @override
  Future<void> requestTurnOn() async {}
  @override
  Future<List<AskodoxBleDevice>> scan(Duration timeout) async => const [];
  @override
  Future<void> connect(String id) async {
    if (failConnect) throw const AskodoxBleException('connect_failed');
    connected.add(id);
  }

  @override
  Future<List<String>> discoverServices(String id) async => const [];
  @override
  Stream<AskodoxReading> readings(String id) => Stream.fromIterable(sends);
  @override
  Future<void> disconnect(String id) async => disconnected.add(id);
}

class _Scanner implements AskodoxBarcodeScanner {
  _Scanner(this.code);
  final String? code;
  @override
  Future<String?> scan(BuildContext context) async => code;
}

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    bodies['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}


/// Draws an EAN-13 barcode (standard L / G / R patterns) as ARGB pixels.
AskodoxScanImage _ean13(String digits, {int module = 3, int height = 80, bool rotate = false}) {
  const l = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011'];
  String r(String code) => code.split('').map((c) => c == '0' ? '1' : '0').join();
  String g(String code) => r(code).split('').reversed.join();
  const parity = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];
  final d = digits.split('').map(int.parse).toList();
  final p = parity[d[0]];
  var bits = '${'0' * 12}101';
  for (var i = 1; i <= 6; i++) {
    bits += p[i - 1] == 'L' ? l[d[i]] : g(l[d[i]]);
  }
  bits += '01010';
  for (var i = 7; i <= 12; i++) {
    bits += r(l[d[i]]);
  }
  bits += '101${'0' * 12}';
  final w = bits.length * module;
  final px = Int32List(w * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < w; x++) {
      px[y * w + x] = bits[x ~/ module] == '1' ? 0xFF000000 : 0xFFFFFFFF;
    }
  }
  if (!rotate) return AskodoxScanImage(w, height, px);
  // turn 90° counter-clockwise: the decoder must turn it back
  final t = Int32List(w * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < w; x++) {
      t[(w - 1 - x) * height + y] = px[y * w + x];
    }
  }
  return AskodoxScanImage(height, w, t);
}

String _withCheck(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(twelve[i]) * (i.isEven ? 1 : 3);
  }
  return '$twelve${(10 - sum % 10) % 10}';
}

void main() {
  test('a photographed EAN-13 decodes exactly (as taken and turned 90 degrees); a blank photo finds nothing', () {
    final code = _withCheck('890123456789');
    expect(askodoxDecodeBarcodePixels(_ean13(code)), code);
    expect(askodoxDecodeBarcodePixels(_ean13(code, rotate: true)), code);
    expect(askodoxDecodeBarcodePixels(AskodoxScanImage(50, 50, Int32List(2500)..fillRange(0, 2500, 0xFFFFFFFF))), isNull);
    expect(askodoxRgbaToArgb(Uint8List.fromList([1, 2, 3, 255]))[0] & 0xFFFFFFFF, 0xFF010203);
  });

  test('scale readings convert exactly into the item unit; only settled weights count', () {
    expect(askodoxScaleToItemMilli(1.235, 'kg', 'kg'), 1235);
    expect(askodoxScaleToItemMilli(1.235, 'kg', 'g'), 1235000);
    expect(askodoxScaleToItemMilli(2.0, 'lb', 'kg'), 907);
    expect(askodoxScaleToItemMilli(1.0, 'kg', 'pcs'), isNull);
    expect(askodoxScaleToItemMilli(-1, 'kg', 'kg'), isNull);
    expect(askodoxSettledWeight([0.4, 1.1, 1.2]), isNull, reason: 'still moving');
    expect(askodoxSettledWeight([0.4, 1.235, 1.235]), 1.235);
    expect(askodoxSettledWeight([1.235, 1.238]), 1.238, reason: 'within the 5 g tolerance');
    expect(askodoxProductsByBarcode(' 8901 0300 ', [
      {'id': 'a', 'barcode': '89010300'},
      {'id': 'b', 'barcode': '890103001'},
    ]).map((p) => p['id']), ['a'], reason: 'exact match only, never fuzzy');
  });

  test('scale reader waits for a settled weight, disconnects, and reports honest failures', () async {
    final ble = _FakeBle([
      const AskodoxReading('weight', 0.9, 'kg'),
      const AskodoxReading('weight', 1.235, 'kg'),
      const AskodoxReading('weight', 1.235, 'kg'),
    ]);
    expect(await AskodoxScaleReader(ble).readItemMilli('AA:BB', 'kg'), 1235);
    expect(ble.disconnected, ['AA:BB']);
    await expectLater(AskodoxScaleReader(_FakeBle([const AskodoxReading('weight', 1.0, 'kg')])).readItemMilli('x', 'kg'),
        throwsA(isA<AskodoxScaleException>().having((e) => e.code, 'code', 'no_reading')));
    await expectLater(AskodoxScaleReader(_FakeBle(const [], failConnect: true)).readItemMilli('x', 'kg'),
        throwsA(isA<AskodoxScaleException>().having((e) => e.code, 'code', 'connect_failed')));
  });

  group('counter with mocked scanner and scale', () {
    final products = [
      {'id': 'p1', 'name': 'Chicken curry cut', 'unit': 'kg', 'price_paise': 24000, 'rate_bp': 0, 'category': 'exempt',
        'price_includes_tax': true, 'barcode': ''},
      {'id': 'p2', 'name': 'Biscuits', 'unit': 'pcs', 'price_paise': 1000, 'rate_bp': 1800, 'category': 'taxable',
        'price_includes_tax': true, 'barcode': '8901234567890'},
    ];

    Future<_Api> pump(WidgetTester tester, {String? scanned, List<AskodoxReading> weights = const []}) async {
      SharedPreferences.setMockInitialValues({'askodox.devices.local.v1': '{"dev1":"AA:BB"}'});
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _Api((method, path, body) {
        if (path == '/api/pos/businesses/b1') {
          return {'id': 'b1', 'name': 'Shop', 'registration_type': 'regular', 'state_code': '36', 'template': 'meat_fish',
            'my_role': 'cashier', 'permissions': ['view', 'sell'], 'rules': <String, Object?>{}};
        }
        if (path.endsWith('/products')) return {'products': products};
        if (path.endsWith('/device-series')) return {'prefix': 'SD1', 'fy': '2627', 'next_number': 1};
        if (path == '/api/devices') {
          return {'devices': [{'id': 'dev1', 'name': 'Shop scale', 'category': 'weighing_scale', 'capabilities': ['read_weight'], 'status': 'paired'}]};
        }
        if (path.endsWith('/invoices')) return {'id': 'inv1'};
        return <String, Object?>{};
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
          askodoxDeviceRepositoryProvider.overrideWithValue(AskodoxDeviceRepository(api, authToken: 't')),
          askodoxBarcodeScannerProvider.overrideWithValue(_Scanner(scanned)),
          askodoxScaleReaderProvider.overrideWithValue(AskodoxScaleReader(_FakeBle(weights))),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, __) => const AskodoxPosSaleScreen(businessId: 'b1')),
            GoRoute(path: '/pos/b1/invoice/:iid', builder: (_, s) => Text('INVOICE ${s.pathParameters['iid']}')),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a scanned barcode adds exactly that item', (tester) async {
      await pump(tester, scanned: '8901234567890');
      await tester.tap(find.byKey(const Key('askodoxPosScan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsOneWidget);
      expect(find.textContaining('Biscuits'), findsWidgets);
    });

    testWidgets('an unknown barcode adds nothing and says so', (tester) async {
      await pump(tester, scanned: '0000000000000');
      await tester.tap(find.byKey(const Key('askodoxPosScan')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsNothing);
      expect(find.textContaining('No item has barcode 0000000000000'), findsOneWidget);
    });

    testWidgets('scale weight fills the dialog and is sent as source=scale', (tester) async {
      final api = await pump(tester, weights: const [
        AskodoxReading('weight', 1.235, 'kg'),
        AskodoxReading('weight', 1.235, 'kg'),
      ]);
      await tester.tap(find.byKey(const ValueKey('askodoxPosProduct-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosReadScale')));
      // The read waits on async device / stream work; let fake time run (well under the 15 s timeout).
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      final shown = [for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)))) t.data];
      final fieldText = [for (final f in tester.widgetList<TextField>(find.byType(TextField))) f.controller?.text];
      expect(find.textContaining('From Shop scale'), findsOneWidget, reason: 'dialog texts: $shown fields: $fieldText');
      await tester.tap(find.byKey(const Key('askodoxPosQtyOk')));
      await tester.pumpAndSettle();
      expect(find.textContaining('from scale'), findsOneWidget);
      expect(find.text('₹296.40'), findsWidgets);
      await tester.tap(find.byKey(const Key('askodoxPosPay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('askodoxPosIssue')));
      await tester.pumpAndSettle();
      final line = ((api.bodies['POST /api/pos/businesses/b1/invoices'] as Map)['lines'] as List).single as Map;
      expect(line['weight'], {'gross_milli': 1235, 'tare_milli': 0, 'source': 'scale'});
    });
  });
}
