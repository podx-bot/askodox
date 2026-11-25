import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/hire_steps_screen.dart';

/// Owner 2026-11-25: Hire a worker in 3 pieces (made-up data only).
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
  testWidgets('hire: no bookings -> what work -> where / when -> through whom -> booked', (tester) async {
    var booked = false;
    final api = _Api((m, path, b) {
      if (path == '/api/hire/work-types') {
        return {
          'work_types': [
            {'key': 'driver', 'en': 'Driver', 'te': 'డ్రైవర్'}
          ]
        };
      }
      if (m == 'POST' && path == '/api/hire/orders') {
        booked = true;
        return {'ok': true};
      }
      if (path == '/api/hire/orders') {
        return {
          'orders': booked
              ? [
                  {'id': 'h1', 'label': '#1', 'work_en': 'Driver', 'work_te': 'డ్రైవర్', 'authority': 'Test Agency', 'status': 'asked'}
                ]
              : <Object?>[]
        };
      }
      if (path == '/api/hire/options') {
        return {
          'options': [
            {'kind': 'business', 'business_id': 'b1', 'name': 'Test Agency', 'address': 'Main Road', 'team': 4, 'price_paise': 50000}
          ]
        };
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxHireStepsScreen());
    expect(find.byKey(const Key('askodoxHireSteps')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxHireStepsType-driver')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxHireStepsPlace')), 'Test Street');
    await tester.enterText(find.byKey(const Key('askodoxHireStepsWhen')), 'tomorrow 9');
    await tester.tap(find.byKey(const Key('askodoxHireStepsNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxHireStepsOption-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxHireStepsBookYes')));
    await tester.pumpAndSettle();
    final body = api.calls['POST /api/hire/orders'] as Map;
    expect(body['business_id'], 'b1');
    expect(body['work_type'], 'driver');
    expect(body['place'], 'Test Street');
    expect(find.byKey(const ValueKey('askodoxHireStepsOrder-h1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxHireStepsNew')), findsOneWidget);
  });

  testWidgets('hire: a done booking is rated from its sheet', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/hire/work-types') return {'work_types': <Object?>[]};
      if (path == '/api/hire/orders') {
        return {
          'orders': [
            {'id': 'h2', 'label': '#2', 'work_en': 'Cook', 'work_te': 'వంట', 'authority': 'Test Agency', 'status': 'done', 'worker_name': 'Test Worker'}
          ]
        };
      }
      return {'ok': true};
    });
    await _pump(tester, api, const AskodoxHireStepsScreen());
    await tester.tap(find.byKey(const ValueKey('askodoxHireStepsOrder-h2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxHireStepsRate-h2-5')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/hire/orders/h2/rating'] as Map)['stars'], 5);
  });
}
