import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_hardware.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/selfshop_steps_screens.dart';
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


Future<void> _pump(WidgetTester tester, _Api api, Widget home,
    {AskodoxBarcodeScanner? scanner, AskodoxMultiBarcodeScanner? multi}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
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
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shop page: today\'s code on top, the lists, a list opened by its exit code', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/selfshop/exit/4821')) return {'id': 'ss1'};
      if (path.endsWith('/selfshop')) {
        return {'enabled': true, 'minutes': 90, 'code': '483920', 'qr': 'ASKODOX-SHOP:483920', 'sessions': [
          {'id': 'ss1', 'status': 'CHECKOUT', 'exit_code': '4821', 'items': 3, 'customer': '0503'},
        ]};
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxSelfShopOwnerStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxSelfShopOwnerSteps')), findsOneWidget);
    expect(find.text('483920'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxSelfShopOwnerStepsSession-ss1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSelfShopOwnerStepsOpen')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxSelfShopOwnerStepsExit')), '4821');
    await tester.tap(find.byKey(const Key('askodoxSelfShopOwnerStepsExitGo')));
    await tester.pumpAndSettle();
    expect(find.text('SESSION ss1'), findsOneWidget);
  });

  testWidgets('shop page: off shows ONE Turn on button', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'PUT') return {'enabled': true, 'minutes': 90, 'code': '111222', 'qr': 'ASKODOX-SHOP:111222', 'sessions': <Object>[]};
      return {'enabled': false, 'minutes': 90, 'sessions': <Object>[]};
    });
    await _pump(tester, api, const AskodoxSelfShopOwnerStepsScreen(businessId: 'b1'));
    await tester.tap(find.byKey(const Key('askodoxSelfShopOwnerStepsOn')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/selfshop'], {'enabled': true, 'minutes': 90});
    expect(find.text('111222'), findsOneWidget);
    expect(find.byKey(const Key('askodoxSelfShopOwnerStepsOpen')), findsOneWidget);
  });

  testWidgets('exit check: one photo is compared with the list, then the button becomes Bill', (tester) async {
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
    await _pump(tester, api, const AskodoxSelfShopCheckStepsScreen(businessId: 'b1', sessionId: 'ss1'),
        multi: _Multi(['8901000000011', '8901000000028']));
    expect(find.byKey(const Key('askodoxSelfShopCheckSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSelfShopCheckStepsBill')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxSelfShopCheckStepsPhoto')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/businesses/b1/selfshop/sessions/ss1/verify'], {
      'barcodes': ['8901000000011', '8901000000028'],
    });
    expect(find.byKey(const Key('askodoxSelfShopCheckStepsNotBilled')), findsOneWidget);
    expect(find.textContaining('Biscuit'), findsOneWidget);
    expect(find.byKey(const Key('askodoxSelfShopCheckStepsBill')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSelfShopCheckStepsPhoto')), findsNothing);
  });

  testWidgets('customer: QR at the entrance, scan items, checkout shows the exit code', (tester) async {
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
    await _pump(tester, api, const AskodoxShopScanStepsScreen(),
        scanner: _Scanner(['ASKODOX-SHOP:483920', '8901000000011', '2000000000015']));
    expect(find.byKey(const Key('askodoxShopScanSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxShopScanStepsEntry')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/selfshop/join'], {'code': 'ASKODOX-SHOP:483920'});
    expect(find.text('Sri Super Market'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxShopScanStepsScan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxShopScanStepsItem-soap-')), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('askodoxShopScanSteps')))).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxShopScanStepsScan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxShopScanStepsItemInfo')), findsOneWidget);
    expect(find.textContaining('sold by weight'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('askodoxShopScanStepsCheckout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxShopScanStepsCheckout')));
    await tester.pumpAndSettle();
    expect(find.text('4821'), findsOneWidget);
    expect(find.byKey(const Key('askodoxShopScanStepsReopen')), findsOneWidget);
  });
}
