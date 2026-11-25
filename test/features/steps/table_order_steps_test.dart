import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/table_order_steps_screen.dart';

/// Owner 2026-11-25: Table order in 3 steps (made-up data only).
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
  testWidgets('table order: add from the menu -> send to kitchen -> bill button', (tester) async {
    var stage = 0; // 0 empty, 1 one pending item, 2 sent
    AskodoxJson order() => {
          'id': 'o1',
          'status': 'open',
          'table_name': 'T1',
          'kind': 'dine_in',
          'estimate_paise': stage == 0 ? 0 : 6000,
          'pending': stage == 1 ? 1 : 0,
          'item_count': stage == 0 ? 0 : 1,
          'items': [
            if (stage > 0) {'id': 'i1', 'product_id': 'p1', 'name': 'Idli', 'qty_milli': 2000, 'status': stage == 1 ? 'pending' : 'sent'}
          ],
        };
    final api = _Api((m, path, b) {
      if (path == '/api/pos/businesses/b1/products') {
        return {
          'products': [
            {'id': 'p1', 'name': 'Idli', 'price_paise': 3000, 'rate_bp': 0}
          ]
        };
      }
      if (path == '/api/pos/businesses/b1/orders/o1/items') stage = 1;
      if (path == '/api/pos/businesses/b1/orders/o1/kot') stage = 2;
      if (path.startsWith('/api/pos/businesses/b1/orders/o1')) return order();
      return {'id': 'b1', 'role': 'owner', 'permissions': ['sell', 'cancel'], 'registration_type': 'unregistered', 'state_code': '37'};
    });
    await _pump(tester, api, const AskodoxTableOrderStepsScreen(businessId: 'b1', orderId: 'o1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxTableOrderSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxTableOrderStepsAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxTableOrderStepsMenu-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxTableOrderStepsQty')), '2');
    await tester.tap(find.byKey(const Key('askodoxTableOrderStepsAddOk')));
    await tester.pumpAndSettle();
    expect(((api.calls['POST /api/pos/businesses/b1/orders/o1/items'] as Map)['items'] as List).single, containsPair('qty_milli', 2000));
    expect(find.byKey(const ValueKey('askodoxTableOrderStepsItem-i1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxTableOrderStepsKot')));
    await tester.pumpAndSettle();
    expect(api.calls.containsKey('POST /api/pos/businesses/b1/orders/o1/kot'), isTrue);
    expect(find.byKey(const Key('askodoxTableOrderStepsBill')), findsOneWidget);
  });
}
