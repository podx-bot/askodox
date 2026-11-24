import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/staff_steps_screens.dart';

/// Owner 2026-11-24: today's attendance and salary in 3 pieces (made-up data only).
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
  testWidgets('attendance: here today number, tap a person, mark present', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'POST') return {'ok': true};
      return {
        'counts': {'present': 1},
        'people': [
          {'ref': 'r1', 'name': 'Ravi', 'role': 'cashier', 'today': {'status': 'P', 'in_at': '2026-11-24T04:00:00Z'}},
          {'ref': 'r2', 'name': 'Sita', 'role': 'cook', 'today': null},
        ],
      };
    });
    await _pump(tester, api, const AskodoxAttendanceStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxAttendanceSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAttendanceStepsRow-r2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAttendanceStepsRow-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAttStepsMark-r2-P')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('POST') && k.contains('attendance')), isTrue);
  });

  testWidgets('salary: what is left to give and the give button', (tester) async {
    final api = _Api((method, path, body) => {
          'month': '2026-11',
          'people': [
            {'ref': 'r1', 'name': 'Ravi', 'paid': null, 'salary': {'set': true, 'net_paise': 1200000, 'days': 25}},
            {'ref': 'r2', 'name': 'Sita', 'paid': {'at': 'x'}, 'salary': {'set': true, 'net_paise': 900000, 'days': 26}},
          ],
        });
    await _pump(tester, api, const AskodoxSalaryStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxSalaryStepsRow-r1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSalaryStepsGive')), findsOneWidget);
  });
}
