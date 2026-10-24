import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_hardware.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_selfshop_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

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


class _Scanner implements AskodoxBarcodeScanner {
  _Scanner(this.codes);
  final List<String> codes;
  @override
  Future<String?> scan(BuildContext context) async => codes.isEmpty ? null : codes.removeAt(0);
}

class _Multi implements AskodoxMultiBarcodeScanner {
  _Multi(this.codes);
  final List<String> codes;
  @override
  Future<List<String>?> scanAll(BuildContext context) async => codes;
}

Widget _app(_Api api, Widget home, {AskodoxBarcodeScanner? scanner, AskodoxMultiBarcodeScanner? multi}) => ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
        if (scanner != null) askodoxBarcodeScannerProvider.overrideWithValue(scanner),
        if (multi != null) askodoxMultiBarcodeScannerProvider.overrideWithValue(multi),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => home),
          GoRoute(path: '/pos/b1/invoice/:iid', builder: (_, s) => Text('INVOICE ${s.pathParameters['iid']}')),
          GoRoute(path: '/pos/b1/selfshop/:sid', builder: (_, s) => Text('SESSION ${s.pathParameters['sid']}')),
        ]),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('staff see today\'s code + QR and open a list by its exit code', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/selfshop/exit/4821')) return {'id': 'ss1'};
      if (path.endsWith('/selfshop')) {
        return {'enabled': true, 'minutes': 90, 'code': '483920', 'qr': 'ASKODOX-SHOP:483920', 'sessions': [
          {'id': 'ss1', 'status': 'CHECKOUT', 'exit_code': '4821', 'items': 3, 'customer': '0503'},
        ]};
      }
      return <String, Object?>{};
    });
    await tester.pumpWidget(_app(api, const AskodoxPosSelfShopScreen(businessId: 'b1')));
    await tester.pumpAndSettle();
    expect(find.text('483920'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPosSelfShopQr')), findsOneWidget);
    expect(find.textContaining('exit code 4821'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const Key('askodoxPosSelfShopExit')), matching: find.byType(TextField)), '4821');
    await tester.tap(find.byKey(const Key('askodoxPosSelfShopExitGo')));
    await tester.pumpAndSettle();
    expect(find.text('SESSION ss1'), findsOneWidget);
  });

  testWidgets('one exit photo is compared with the list, then billed at the counter', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = {
      'id': 'ss1', 'status': 'CHECKOUT', 'customer': '0503', 'total_paise': 8000, 'exit_code': '4821',
      'items': [{'product_id': 'soap', 'name': 'Soap', 'pack': '', 'unit': 'pcs', 'qty_milli': 2000,
        'unit_price_paise': 4000, 'total_paise': 8000}],
    };
    final api = _Api((method, path, body) {
      if (path.endsWith('/verify')) {
        return {'all_clear': false, 'matched': [{'name': 'Soap', 'pack': '', 'qty_milli': 2000}], 'not_seen': <Object>[],
          'not_billed': [{'name': 'Biscuit', 'pack': '', 'barcode': '8901000000028'}],
          'count_by_hand': [{'name': 'Soap', 'pack': '', 'qty_milli': 2000}]};
      }
      if (path.endsWith('/bill')) return {'invoice': {'id': 'inv9'}};
      return session;
    });
    await tester.pumpWidget(_app(api, const AskodoxPosSelfShopCheckScreen(businessId: 'b1', sessionId: 'ss1'),
        multi: _Multi(['8901000000011', '8901000000028'])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosSelfShopPhoto')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/businesses/b1/selfshop/sessions/ss1/verify'], {
      'barcodes': ['8901000000011', '8901000000028'],
    });
    expect(find.byKey(const Key('askodoxPosSelfShopNotBilled')), findsOneWidget);
    expect(find.textContaining('Biscuit'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPosSelfShopCount')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPosSelfShopBill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosIssue')));
    await tester.pumpAndSettle();
    expect((api.bodies['POST /api/pos/businesses/b1/selfshop/sessions/ss1/bill'] as Map)['payments'], isNotEmpty);
    expect(find.text('INVOICE inv9'), findsOneWidget);
  });

  testWidgets('a customer joins with the code, scans, and gets an exit code', (tester) async {
    var status = 'OPEN';
    final items = <Map<String, Object?>>[];
    Map<String, Object?> view() => {'id': 'ss1', 'shop': 'Sri Super Market', 'status': status, 'total_paise': 4000 * items.length,
          'items': items, if (status == 'CHECKOUT') 'exit_code': '4821'};
    final api = _Api((method, path, body) {
      if (path.endsWith('/selfshop/mine')) return {'sessions': <Object>[]};
      if (path.endsWith('/selfshop/join')) return view();
      if (path.endsWith('/scan')) {
        if ((body as Map)['barcode'] == '2000000000015') {
          return {'added': false, 'reason': 'weigh_at_counter', 'item': {'name': 'Rice loose', 'price_paise': 6000, 'unit': 'kg',
            'attributes': <String, Object?>{}}, 'session': view()};
        }
        items.add({'product_id': 'soap', 'name': 'Soap', 'pack': '', 'unit': 'pcs', 'qty_milli': 1000, 'unit_price_paise': 4000,
          'total_paise': 4000, 'attributes': {'brand_free': 'yes'}});
        return {'added': true, 'item': {'name': 'Soap', 'price_paise': 4000}, 'session': view()};
      }
      if (path.endsWith('/checkout')) {
        status = 'CHECKOUT';
        return view();
      }
      return view();
    });
    await tester.pumpWidget(_app(api, const AskodoxSelfShopScreen(), scanner: _Scanner(['8901000000011', '2000000000015'])));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSelfShopJoin')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const Key('askodoxSelfShopCode')), matching: find.byType(TextField)), '483920');
    await tester.tap(find.byKey(const Key('askodoxSelfShopJoinGo')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/selfshop/join'], {'code': '483920'});
    expect(find.text('Sri Super Market'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSelfShopScanItem')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxSelfShopItem-soap-')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSelfShopScanItem')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSelfShopItemInfo')), findsOneWidget);
    expect(find.textContaining('sold by weight'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxSelfShopCheckout')));
    await tester.pumpAndSettle();
    expect(find.text('4821'), findsOneWidget);
    expect(find.byKey(const Key('askodoxSelfShopReopen')), findsOneWidget);
  });
}
