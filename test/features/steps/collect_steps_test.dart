import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/collect_steps_screens.dart';

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
  testWidgets('collect: amount, QR, confirm after the bank check', (tester) async {
    final api = _Api((m, path, b) {
      if (m == 'POST' && path.endsWith('/collect/requests')) {
        return {'id': 'r1', 'status': 'pending', 'amount_paise': 25000, 'payee': 'Test Shop', 'upi_id': 'shop@upi', 'upi_link': 'upi://pay?pa=shop@upi&am=250'};
      }
      if (m == 'POST') return {'id': 'r1', 'status': 'confirmed', 'amount_paise': 25000, 'payee': 'Test Shop', 'upi_id': 'shop@upi'};
      if (path.endsWith('/collect/requests')) return {'requests': []};
      return {'method': {'upi_id': 'shop@upi'}, 'options': [], 'can_edit': true};
    });
    await _pump(tester, api, const AskodoxCollectStepsScreen(businessId: 'b1', pollEvery: Duration.zero));
    expect(find.byKey(const Key('askodoxCollectSteps')), findsOneWidget);
    for (final k in ['2', '5', '0']) {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('askodoxCollectStepsShow')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCollectSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCollectStepsConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCollectStepsCheckBank')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCollectStepsCheckBankYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCollectSteps3')), findsOneWidget);
  });
}
