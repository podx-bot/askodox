import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/items_steps_screens.dart';

/// Owner 2026-11-24: baaki reminders, bills, stock, cashbook and reports in 3 pieces (made-up data only).
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
  testWidgets('items: count on top, list, search, add button', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/products')) {
        return {
          'products': [
            {'id': 'p1', 'name': 'Tea', 'item_no': 1, 'unit': 'pcs', 'price_paise': 1000, 'rate_bp': 0},
            {'id': 'p2', 'name': 'Coffee', 'item_no': 2, 'unit': 'pcs', 'price_paise': 2000, 'rate_bp': 0, 'low_stock': true},
          ]
        };
      }
      return {'default': 'pos', 'items': []};
    });
    await _pump(tester, api, const AskodoxItemsStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxItemsSteps')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxItemsStepsItem-p2')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxItemsStepsSearch')), 'tea');
    await tester.pump();
    expect(find.byKey(const ValueKey('askodoxItemsStepsItem-p2')), findsNothing);
    expect(find.byKey(const Key('askodoxItemsStepsAdd')), findsOneWidget);
  });
}
