import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/purchase_steps_screen.dart';

/// Owner 2026-11-25: Purchase bill in 3 steps (made-up data only).
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
  testWidgets('purchase bill: supplier -> bill number -> a line -> recorded', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/pos/businesses/b1/suppliers') {
        return {
          'suppliers': [
            {'id': 's1', 'name': 'Test Traders', 'gstin': null, 'state_code': '37'}
          ]
        };
      }
      if (path == '/api/pos/businesses/b1/products') {
        return {
          'products': [
            {'id': 'p1', 'name': 'Rice', 'unit': 'kg', 'rate_bp': 0}
          ]
        };
      }
      if (path == '/api/pos/businesses/b1/purchases') return {'id': 'pu1'};
      return {'id': 'b1', 'state_code': '37', 'permissions': ['purchase']};
    });
    await _pump(tester, api, const AskodoxPurchaseStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxPurchaseSteps')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPurchaseStepsSupplier-s1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxPurchaseStepsBillNo')), 'TB-12');
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxPurchaseStepsNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPurchaseStepsAddLine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPurchaseStepsProduct-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('askodoxPurchaseStepsQty-0')), '10');
    await tester.enterText(find.byKey(const ValueKey('askodoxPurchaseStepsCost-0')), '40');
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxPurchaseStepsLineOk-0')));
    await tester.tap(find.byKey(const ValueKey('askodoxPurchaseStepsLineOk-0')));
    await tester.pumpAndSettle();
    expect(find.text('₹400.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPurchaseStepsSave')));
    await tester.pumpAndSettle();
    final body = api.calls['POST /api/pos/businesses/b1/purchases'] as Map;
    expect(body['supplier_bill_no'], 'TB-12');
    expect(((body['lines'] as List).single as Map)['cost_paise'], 4000);
  });
}
