import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/order_steps_screens.dart';

/// Owner 2026-11-24: live orders, kitchen, tables and purchases in 3 pieces (made-up data only).
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path.split('?').first, null);
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
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('live orders: waiting number, new order first, tap = accept', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST') return {'ok': true};
      return {
        'counts': {'new': 1},
        'orders': [
          {'id': 'o2', 'stage': 'preparing', 'kind': 'takeaway', 'customer_name': 'Sita', 'estimate_paise': 20000, 'next_stage': 'ready', 'items': [{'name': 'Tea', 'qty': 2, 'product_id': 'p2'}]},
          {'id': 'o1', 'stage': 'placed', 'kind': 'dine_in', 'table_name': 'T1', 'estimate_paise': 15000, 'items': [{'name': 'Dosa', 'qty': 1, 'product_id': 'p1'}]},
        ],
      };
    });
    await _pump(tester, api, const AskodoxOrdersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxOrdersSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrdersStepsRow-o1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrdersStepsRow-o2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxOrdersStepsRow-o1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxOrdersStepsAccept-o1')));
    await tester.pumpAndSettle();
    final sent = api.calls['POST /api/pos/businesses/b1/desk/orders/o1/confirm'] as Map;
    expect((sent['decisions'] as Map)['p1'], true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kitchen: new tickets number, tap = ready', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST') return {'ok': true};
      return {
        'kots': [
          {'id': 'k1', 'number': 5, 'status': 'new', 'table_name': 'T2', 'items': [{'name': 'Biryani', 'qty_milli': 1000}]},
        ],
      };
    });
    await _pump(tester, api, const AskodoxKitchenStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxKitchenStepsRow-5')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxKitchenStepsRow-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxKitchenStepsReady-5')));
    await tester.pumpAndSettle();
    final sent = api.calls['POST /api/pos/businesses/b1/kitchen/k1'] as Map;
    expect(sent['status'], 'ready');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tables: busy count and takeaway button', (tester) async {
    final api = _Api((method, path, body) => {
          'tables': [
            {'id': 't1', 'name': 'T1', 'order': {'id': 'o1', 'estimate_paise': 10000}},
            {'id': 't2', 'name': 'T2', 'order': null},
          ],
        });
    await _pump(tester, api, const AskodoxTablesStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxTablesStepsTable-T1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxTablesStepsTable-T2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxTablesStepsTakeaway')), findsOneWidget);
  });

  testWidgets('purchases: what you owe and the supplier list', (tester) async {
    final api = _Api((method, path, body) => {
          'suppliers': [
            {'id': 's1', 'name': 'Ram Traders', 'owed_paise': 250000},
          ],
        });
    await _pump(tester, api, const AskodoxSuppliersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxSuppliersStepsRow-s1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSuppliersStepsNew')), findsOneWidget);
  });
}
