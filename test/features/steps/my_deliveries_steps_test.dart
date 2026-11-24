import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/my_deliveries_steps_screen.dart';

/// Owner 2026-11-24: My deliveries in 3 pieces (made-up data only).
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
  testWidgets('my deliveries: colour, a running job, an offer, the job sheet', (tester) async {
    final api = _Api((m, path, b) {
      if (path.contains('delivery-jobs') && m == 'GET') {
        return {
          'status': {'colour': 'free'},
          'cash_today': <Object?>[],
          'running': [
            {'id': 'j1', 'status': 'given', 'label': '#12', 'shop': 'Test Shop', 'from': 'Shop', 'to': 'Gandhi Road', 'collect_paise': 25000, 'maps_url': 'https://maps.example/x'}
          ],
          'offers': [
            {'id': 'j2', 'label': '#13', 'shop': 'Other Shop', 'from': 'Shop', 'to': 'Main Road', 'fee_paise': 3000, 'my_answer': 'waiting'}
          ],
        };
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxMyDeliveriesStepsScreen());
    expect(find.byKey(const Key('askodoxMyDeliveriesSteps')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyDeliveriesStepsJob-j1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyDeliveriesStepsOffer-j2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxMyDeliveriesStepsJob-j1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMyDeliveriesStepsPicked-j1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyDeliveriesStepsDone-j1-cash')), findsOneWidget);
  });

  testWidgets('my deliveries: no work says so', (tester) async {
    final api = _Api((m, path, b) => {'status': {'colour': 'busy'}, 'running': <Object?>[], 'offers': <Object?>[], 'cash_today': <Object?>[]});
    await _pump(tester, api, const AskodoxMyDeliveriesStepsScreen());
    expect(find.byKey(const Key('askodoxMyDeliveriesStepsOpen')), findsNothing);
  });
}
