import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/my_bills_steps_screen.dart';

/// Owner 2026-11-24: My bills in 3 pieces (made-up data only).
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
  testWidgets('my bills: total to pay, a row, the bill sheet', (tester) async {
    final api = _Api((m, path, b) => {
          'bills': [
            {
              'token': 't1',
              'shop': 'Test Shop',
              'number': 'A/1',
              'issued_at': '2026-11-20T10:00:00',
              'status': 'due',
              'due_paise': 25000,
              'total_paise': 25000,
              'lines': [
                {'name': 'Tea', 'qty_milli': 2000, 'amount_paise': 25000}
              ],
              'pay': [
                {'upi_link': 'upi://pay?pa=test@upi&am=250'}
              ],
            },
            {'token': 't2', 'shop': 'Old Shop', 'number': 'B/2', 'issued_at': '2026-11-01T10:00:00', 'status': 'paid', 'due_paise': 0, 'total_paise': 10000, 'lines': <Object?>[]},
          ]
        });
    await _pump(tester, api, const AskodoxMyBillsStepsScreen());
    expect(find.byKey(const Key('askodoxMyBillsSteps')), findsOneWidget);
    expect(find.text('₹250'), findsWidgets);
    expect(find.byKey(const ValueKey('askodoxMyBillStepsRow-t1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyBillStepsRow-t2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxMyBillStepsRow-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMyBillStepsQrBtn-t1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMyBillStepsPromise-t1')), findsOneWidget);
  });

  testWidgets('my bills: nothing to pay says so', (tester) async {
    final api = _Api((m, path, b) => {'bills': <Object?>[]});
    await _pump(tester, api, const AskodoxMyBillsStepsScreen());
    expect(find.byKey(const Key('askodoxMyBillsStepsPay')), findsNothing);
    expect(find.text('₹0'), findsOneWidget);
  });
}
