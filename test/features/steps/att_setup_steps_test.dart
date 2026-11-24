import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/att_setup_steps_screens.dart';

/// Owner 2026-11-24: attendance setup in 3 pieces (made-up data only).
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
  testWidgets('attendance setup: rows, a switch sheet saves', (tester) async {
    final api = _Api((m, path, b) => {
          'own_phone': true,
          'kiosk': false,
          'shop_pin': false,
          'radius_m': 100,
          'start_time': '09:00',
          'end_time': '18:00',
          'grace_min': 10,
          'require_location': true,
          'require_live_face': true,
          'outside_needs_ok': true,
        });
    await _pump(tester, api, const AskodoxAttSetupStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxAttSetupSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAttSetupStepsPin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAttSetupStepsMethod')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAttSetupSteps-kiosk')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('PUT') || k.startsWith('POST') || k.startsWith('PATCH')), isTrue);
  });

  testWidgets('attendance setup: radius picker', (tester) async {
    final api = _Api((m, path, b) => {'own_phone': true, 'radius_m': 100, 'start_time': '09:00', 'end_time': '18:00', 'grace_min': 10, 'shop_pin': true});
    await _pump(tester, api, const AskodoxAttSetupStepsScreen(businessId: 'b1'));
    await tester.tap(find.byKey(const Key('askodoxAttSetupStepsRadius')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAttSetupStepsPick-radius_m-150')));
    await tester.pumpAndSettle();
    expect(api.calls.values.any((v) => v is Map && v['radius_m'] == 150), isTrue);
  });
}
