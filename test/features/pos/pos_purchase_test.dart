import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_purchase_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    bodies['$method $path'] = body;
    final out = reply(method, path, body);
    if (out is ApiFailure) return ApiError(out);
    return ApiSuccess(out as T);
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
  testWidgets('purchase bill: GST from a registered supplier, batch + expiry sent, typed total checked by the server',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') {
        return {'id': 'b1', 'registration_type': 'regular', 'state_code': '37', 'permissions': ['view', 'purchases'],
          'rules': <String, Object?>{}};
      }
      if (path.endsWith('/suppliers')) return {'suppliers': [{'id': 's1', 'name': 'Vijaya Pharma', 'gstin': '37AAGCB7383J1Z4', 'state_code': '37'}]};
      if (path.endsWith('/products')) {
        return {'products': [{'id': 'm1', 'name': 'Paracetamol strip', 'unit': 'pcs', 'rate_bp': 500, 'track_batches': true}]};
      }
      if (path.endsWith('/purchases')) return {'id': 'pur1'};
      return <String, Object?>{};
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/new', builder: (_, __) => const AskodoxPosPurchaseScreen(businessId: 'b1')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/new');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosPurchaseSupplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vijaya Pharma').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Supplier bill number'), 'VP/889');
    await tester.tap(find.byKey(const Key('askodoxPosPurchaseAddLine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paracetamol strip'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Qty'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Cost before GST'), '20');
    await tester.enterText(find.widgetWithText(TextField, 'Batch no.'), 'B1');
    await tester.enterText(find.widgetWithText(TextField, 'Expiry (YYYY-MM-DD)'), '2027-06-30');
    await tester.pumpAndSettle();
    expect(find.text('Computed: ₹2,100.00'), findsOneWidget, reason: '100 x Rs 20 + 5% GST');
    await tester.tap(find.byKey(const Key('askodoxPosPurchaseSave')));
    await tester.pumpAndSettle();
    final body = api.bodies['POST /api/pos/businesses/b1/purchases'] as Map;
    expect(body['supplier_bill_no'], 'VP/889');
    expect((body['lines'] as List).single,
        {'product_id': 'm1', 'qty_milli': 100000, 'cost_paise': 2000, 'rate_bp': 500, 'batch_no': 'B1', 'expiry_date': '2027-06-30'});
    expect('${body['client_txn_id']}', startsWith('pos-'));
    expect(find.text('HOME'), findsOneWidget, reason: 'the form closes after the server records the bill');
  });
}
