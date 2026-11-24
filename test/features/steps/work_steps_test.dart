import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/work_steps_screens.dart';

/// Owner 2026-11-24: job cards, monthly and bookings in 3 pieces (made-up data only).
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
  testWidgets('job cards: one number + list, then a new job in 3 steps with a token', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST' && path.endsWith('/jobs')) {
        return {'id': 'j2', 'token': 8, 'item': 'Blouse'};
      }
      return {
        'jobs': [
          {'id': 'j1', 'token': 7, 'item': 'Phone screen', 'status': 'working', 'customer_name': 'Ravi', 'balance_paise': 50000, 'in_app': false},
        ],
        'counts': {},
      };
    });
    await _pump(tester, api, const AskodoxJobStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxJobSteps0')), findsOneWidget);
    expect(find.text('#7 Phone screen'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxJobStepsNew')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxJobSteps1')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('askodoxJobStepsNext1'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('askodoxJobStepsItem')), 'Blouse');
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxJobStepsNext1')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxJobSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxJobStepsSave')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxJobSteps3')), findsOneWidget);
    expect(find.textContaining('8'), findsWidgets);
    final sent = api.calls['POST /api/pos/businesses/b1/jobs'] as Map;
    expect(sent['item'], 'Blouse');
  });

  testWidgets('monthly: who paid -> how much -> done', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST') return {'month': '2026-12', 'members': [], 'owed_paise': 0};
      return {
        'month': '2026-12',
        'owed_paise': 50000,
        'members': [
          {'id': 'm1', 'name': 'Ravi', 'plan': 'Gym', 'status': 'active', 'left_paise': 50000, 'late': false},
        ],
      };
    });
    await _pump(tester, api, const AskodoxMonthlyStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxMonthlySteps1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMonthlyStepsRow-m1')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxMonthlySteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMonthlyStepsGot')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxMonthlySteps3')), findsOneWidget);
    final sent = api.calls['POST /api/pos/businesses/b1/monthly/members/m1/pay'] as Map;
    expect(sent['amount_paise'], 50000);
  });

  testWidgets('bookings: today\'s number and the list', (tester) async {
    final api = _Api((method, path, body) => {
          'bookings': [
            {'id': 'k1', 'item': 'Room 101', 'customer_name': 'Laxmi', 'status': 'booked', 'people': 2, 'mode': 'day'},
          ],
        });
    await _pump(tester, api, const AskodoxBookingStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxBookingSteps0')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBookingStepsRow-k1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBookingStepsRow-k1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('askodoxBookingStepsQr-k1')), findsOneWidget);
  });
}
