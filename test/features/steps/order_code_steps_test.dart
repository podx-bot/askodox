import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/order_code_steps_screen.dart';

/// Owner 2026-11-25: Order at a shop in 3 pieces (made-up data only).
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
  testWidgets('order at a shop: my orders, then a search result', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/pos/order-desk/mine') {
        return {
          'orders': [
            {'id': 'o1', 'business_id': 'b1', 'business_name': 'Test Hotel', 'kind': 'takeaway', 'stage': 'cooking', 'stage_text': {'en': 'Being cooked'}}
          ]
        };
      }
      if (path == '/api/pos/order-desk/shops') {
        return {
          'shops': [
            {'id': 'b2', 'name': 'Test Tiffins', 'open': true, 'code': 'ASKODOX-ORDER:b2'}
          ]
        };
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxOrderCodeStepsScreen());
    expect(find.byKey(const Key('askodoxOrderCodeSteps')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxOrderCodeStepsMine-o1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxOrderCodeStepsScan')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxOrderCodeStepsSearch')), 'tiff');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxOrderCodeStepsShop-b2')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxOrderCodeStepsMine-o1')), findsNothing);
  });
}
