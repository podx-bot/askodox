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

void main() {
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
      await tester.pumpAndSettle();
      expect(find.textContaining('From Shop scale'), findsOneWidget);
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
