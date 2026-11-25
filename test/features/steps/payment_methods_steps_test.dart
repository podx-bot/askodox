import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/payment_methods_steps_screen.dart';

/// Owner 2026-11-25: My accounts in 3 pieces (made-up data only).
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
  testWidgets('my accounts: no QR -> type a UPI ID -> saved -> QR shows; remove asks once', (tester) async {
    var methods = <Object?>[];
    final api = _Api((m, path, b) {
      if (m == 'POST' && path == '/api/me/payment-methods') {
        methods = [
          {'id': 'p1', 'kind': 'upi', 'upi_id': 'test@okbank', 'payee_name': 'Test Shop', 'app': 'PhonePe', 'is_default': true}
        ];
      }
      if (m == 'DELETE' && path == '/api/me/payment-methods/p1') methods = <Object?>[];
      return {'methods': methods};
    });
    await _pump(tester, api, const AskodoxPaymentMethodsStepsScreen());
    expect(find.byKey(const Key('askodoxPayMethodsSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPayMethodsStepsQr')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxPayMethodsStepsAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPayMethodsStepsWay-typed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxPayMethodsStepsUpi')), 'test@okbank');
    await tester.tap(find.byKey(const Key('askodoxPayMethodsStepsUpiNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayMethodsStepsConfirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPayMethodsStepsSave')));
    await tester.pumpAndSettle();
    expect((api.calls['POST /api/me/payment-methods'] as Map)['upi_id'], 'test@okbank');
    expect(find.byKey(const Key('askodoxPayMethodsStepsQr')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPayMethodsStepsRow-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPayMethodsStepsRemove-p1')));
    await tester.pumpAndSettle();
    expect(api.calls.containsKey('DELETE /api/me/payment-methods/p1'), isFalse);
    await tester.tap(find.byKey(const Key('askodoxPayMethodsStepsRemoveYes')));
    await tester.pumpAndSettle();
    expect(api.calls.containsKey('DELETE /api/me/payment-methods/p1'), isTrue);
    expect(find.byKey(const Key('askodoxPayMethodsStepsQr')), findsNothing);
  });
}
