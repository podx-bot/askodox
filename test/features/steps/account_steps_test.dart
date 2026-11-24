import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/account_steps_screens.dart';

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
  testWidgets('supplier: what you owe, rows, and the 3 steps to record a payment', (tester) async {
    final api = _Api((m, path, b) {
      if (m == 'POST') return {'ok': true};
      return {
        'supplier': {'name': 'Ravi Traders'},
        'opening_paise': 0,
        'closing_paise': 150000,
        'entries': [
          {'local_date': '2026-11-20', 'note': 'Bill 1', 'owed_paise': 150000, 'paid_paise': 0},
        ],
      };
    });
    await _pump(tester, api, const AskodoxSupplierAccountStepsScreen(businessId: 'b1', supplierId: 's1'));
    expect(find.byKey(const Key('askodoxSupplierAccountSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAccountStepsRow-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAccountStepsPay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAccountSteps1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxStepQuick-1500')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxAccountStepsToMethod')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAccountSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxAccountStepsMethod-upi')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxAccountStepsSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxAccountSteps3')), findsOneWidget);
    expect(api.calls.keys.any((k) => k.startsWith('POST')), isTrue);
  });

  testWidgets('customer: baaki on top and the received button', (tester) async {
    final api = _Api((m, path, b) {
      if (path.contains('advance')) return {'balance_paise': 0, 'entries': [], 'pending': []};
      return {
        'customer': {'name': 'Sita'},
        'opening_paise': 0,
        'closing_paise': 50000,
        'entries': [
          {'local_date': '2026-11-21', 'kind': 'invoice', 'note': 'B1', 'debit_paise': 50000, 'credit_paise': 0, 'balance_paise': 50000},
        ],
      };
    });
    await _pump(tester, api, const AskodoxCustomerAccountStepsScreen(businessId: 'b1', customerId: 'c1'));
    expect(find.byKey(const Key('askodoxCustomerAccountSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAccountStepsRow-0')), findsOneWidget);
    expect(find.byKey(const Key('askodoxAccountStepsPay')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
