import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/person_steps_screens.dart';

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
  testWidgets('staff month: salary on top, day rows, advance in 2 steps', (tester) async {
    final api = _Api((m, path, b) {
      if (m == 'POST') return {'ok': true};
      return {
        'name': 'Ravi',
        'counts': {'present': 20, 'absent': 2, 'ot_min': 60},
        'advance_paise': 50000,
        'salary': {'set': true, 'net_paise': 1000000},
        'days': [
          {'date': '2026-11-01', 'weekday': 6, 'att': {'status': 'P'}},
          {'date': '2026-11-02', 'weekday': 0, 'att': null},
        ],
      };
    });
    await _pump(tester, api, const AskodoxStaffPersonStepsScreen(businessId: 'b1', staffRef: 'r1'));
    expect(find.byKey(const Key('askodoxStaffPersonSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPersonStepsDay-2026-11-02')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPersonStepsDay-2026-11-02')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPersonStepsMark-2026-11-02-P')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('POST') && k.contains('attendance')), isTrue);
    await tester.tap(find.byKey(const Key('askodoxPersonStepsGive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPersonStepsAdvance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPersonSteps1')), findsOneWidget);
  });

  testWidgets('night report: yes, then pick the time', (tester) async {
    final api = _Api((m, path, b) => {'night_push': false, 'send_time': '23:00'});
    await _pump(tester, api, const AskodoxReportSettingsStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxNightSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxNightStepsOn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxNightSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxNightStepsTime-22:00')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxNightSteps3')), findsOneWidget);
    expect(api.calls.keys.any((k) => k.startsWith('PUT') || k.startsWith('POST')), isTrue);
  });
}
