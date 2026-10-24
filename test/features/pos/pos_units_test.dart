import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';
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

void main() {
  final products = [
    {'id': 'soap', 'name': 'Soap', 'unit': 'pcs', 'price_paise': 4000, 'rate_bp': 1800, 'category': 'taxable',
      'price_includes_tax': true, 'packs': [{'name': 'box', 'factor_milli': 12000, 'price_paise': 45000, 'barcode': '8901111111111'}]},
    {'id': 'ph', 'name': 'Phone X', 'unit': 'pcs', 'price_paise': 1500000, 'rate_bp': 1800, 'category': 'taxable',
      'price_includes_tax': true, 'track_serials': true, 'serial_kind': 'imei', 'packs': <Object>[]},
  ];

  Future<_Api> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') {
        return {'id': 'b1', 'registration_type': 'regular', 'state_code': '36', 'permissions': ['view', 'sell'],
          'rules': <String, Object?>{}};
      }
      if (path.endsWith('/products')) return {'products': products};
      if (path.endsWith('/products/ph/serials')) return {'serials': ['490154203237518', '356938035643809']};
      if (path.endsWith('/device-series')) return {'prefix': 'SD1', 'fy': '2627', 'next_number': 1};
      if (path.endsWith('/invoices')) return {'id': 'inv1'};
      return <String, Object?>{};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
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

  Future<void> pay(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('askodoxPosPay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosIssue')));
    await tester.pumpAndSettle();
  }

  testWidgets('a box is sold at the box price and sent as pack=box', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxPosProduct-soap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosPack-box')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '2');
    await tester.tap(find.byKey(const Key('askodoxPosUnitOk')));
    await tester.pumpAndSettle();
    expect(find.text('₹900.00'), findsWidgets, reason: '2 boxes x Rs 450');
    await pay(tester);
    final line = ((api.bodies['POST /api/pos/businesses/b1/invoices'] as Map)['lines'] as List).single as Map;
    expect(line, {'product_id': 'soap', 'qty_milli': 2000, 'pack': 'box'});
  });

  testWidgets('an IMEI phone is sold only by picking its IMEI', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('askodoxPosProduct-ph')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosSerial-490154203237518')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosSerial-490154203237518')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosSerialsOk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('490154203237518'), findsOneWidget, reason: 'the cart shows which piece');
    await pay(tester);
    final line = ((api.bodies['POST /api/pos/businesses/b1/invoices'] as Map)['lines'] as List).single as Map;
    expect(line, {'product_id': 'ph', 'qty_milli': 1000, 'serials': ['490154203237518']});
  });

  testWidgets('a box barcode adds the box directly', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('askodoxPosSearch')), '8901111111111');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 box'), findsOneWidget);
  });
}
