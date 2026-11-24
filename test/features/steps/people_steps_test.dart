import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/people_steps_screens.dart';

/// Owner 2026-11-24: customers, enquiries and team in 3 pieces (made-up data only).
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
  testWidgets('customers: what they owe, then a new customer in 3 steps', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST' && path.endsWith('/customers')) return {'id': 'c2'};
      if (path.endsWith('/customers/suggestions')) return {'suggestions': []};
      return {
        'customers': [
          {'id': 'c1', 'name': 'Ravi', 'gstin': null, 'balance_paise': 120000},
        ],
      };
    });
    await _pump(tester, api, const AskodoxCustomersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCustomersSteps0')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCustomersStepsRow-c1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCustomersStepsNew')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxCustomersSteps1')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('askodoxCustomersStepsNext1'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('askodoxCustomersStepsName')), 'Sita');
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxCustomersStepsNext1')));
    await tester.pump();
    expect(find.byKey(const Key('askodoxCustomersSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCustomersStepsSave')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxCustomersSteps3')), findsOneWidget);
    final sent = api.calls['POST /api/pos/businesses/b1/customers'] as Map;
    expect(sent['name'], 'Sita');
  });

  testWidgets('enquiries: open number and list', (tester) async {
    final api = _Api((method, path, body) => {
          'leads': [
            {'id': 'l1', 'name': 'Anil', 'stage': 'new', 'need': 'AC repair', 'value_paise': 0},
            {'id': 'l2', 'name': 'Old', 'stage': 'won', 'value_paise': 0},
          ],
        });
    await _pump(tester, api, const AskodoxEnquiriesStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxEnquiriesStepsRow-l1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxEnquiriesStepsRow-l2')), findsNothing);
    expect(find.byKey(const Key('askodoxEnquiriesStepsNew')), findsOneWidget);
  });

  testWidgets('team: number and people', (tester) async {
    final api = _Api((method, path, body) => {
          'team': [
            {'user': 'u1', 'name': 'Kiran', 'status': 'joined', 'jobs': 4, 'phone': '9000000000'},
          ],
        });
    await _pump(tester, api, const AskodoxTeamStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxTeamStepsRow-u1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxTeamStepsFind')), findsOneWidget);
  });
}
