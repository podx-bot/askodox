import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/item_details_steps_screen.dart';

/// Owner 2026-11-25: Item details in 3 pieces (made-up data only).
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
  testWidgets('item details: missing count, pick a choice, save', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/pos/businesses/b1/products/p1') return {'id': 'p1', 'name': 'Test Shirt', 'attributes': <String, Object?>{}};
      if (path == '/api/pos/businesses/b1/catalogue') {
        return {
          'template_key': null,
          'attributes': [
            {'key': 'size', 'kind': 'choice', 'options': ['S', 'M', 'L'], 'required': true, 'label': {'en': 'Size', 'te': 'సైజు'}},
            {'key': 'colour', 'kind': 'text', 'label': {'en': 'Colour'}},
          ],
        };
      }
      if (path == '/api/pos/businesses/b1/products/p1/attributes') return {'missing': <Object?>[]};
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxItemDetailsStepsScreen(businessId: 'b1', productId: 'p1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxItemDetailsSteps')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxItemDetailsStepsRow-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxItemDetailsStepsOption-size-M')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('askodoxItemDetailsStepsOk-size')));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxItemDetailsStepsSave')));
    await tester.pumpAndSettle();
    expect((api.calls['PUT /api/pos/businesses/b1/products/p1/attributes'] as Map)['values'], {'size': 'M'});
  });
}
