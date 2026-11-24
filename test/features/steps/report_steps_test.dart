import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/report_steps_screens.dart';

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
  testWidgets('GST: tax on top, a row per rate, change month', (tester) async {
    final api = _Api((m, path, b) => {
          'by_rate': [
            {'rate_bp': 500, 'category': 'regular', 'taxable_paise': 100000, 'cgst_paise': 2500, 'sgst_paise': 2500, 'igst_paise': 0, 'cess_paise': 0},
          ],
          'disclaimer': 'Not a return',
        });
    await _pump(tester, api, const AskodoxGstStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxGstSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxGstStepsRow-0')), findsOneWidget);
    expect(find.byKey(const Key('askodoxGstStepsDisclaimer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxGstStepsChange')));
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsWidgets);
  });

  testWidgets('purchase orders: waiting number and rows', (tester) async {
    final api = _Api((m, path, b) => {
          'orders': [
            {'id': 'o1', 'number': 'PO-1', 'supplier_name': 'Ravi Traders', 'status': 'sent'},
            {'id': 'o2', 'number': 'PO-2', 'supplier_name': 'Sita Stores', 'status': 'received'},
          ],
        });
    await _pump(tester, api, const AskodoxPurchaseOrdersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxPurchaseOrdersStepsRow-o1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPurchaseOrdersStepsRow-o2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPurchaseOrdersStepsNew')), findsOneWidget);
  });

  testWidgets('bill history: rows, search box and change day', (tester) async {
    final api = _Api((m, path, b) => {
          'bills': [
            {'id': 'v1', 'number': 'B1', 'customer_name': 'Ravi', 'local_date': '2026-11-24', 'total_paise': 20000, 'due_paise': 0, 'status': 'issued'},
            {'id': 'v2', 'number': 'B2', 'customer_name': '', 'local_date': '2026-11-24', 'total_paise': 30000, 'due_paise': 30000, 'status': 'issued'},
          ],
        });
    await _pump(tester, api, const AskodoxBillHistoryStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxBillHistoryStepsRow-v1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBillHistoryStepsRow-v2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxBillHistoryStepsSearch')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxBillHistoryStepsChange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxBillHistoryStepsRange-week')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxBillHistorySteps')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sales: total, how it was paid, best sellers', (tester) async {
    final api = _Api((m, path, b) => {
          'net_paise': 500000,
          'bills': 7,
          'dues_paise': 10000,
          'payments': [
            {'method': 'cash', 'amount_paise': 300000},
          ],
          'top_items': [
            {'name': 'Tea', 'total_paise': 100000},
          ],
        });
    await _pump(tester, api, const AskodoxSalesStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxSalesStepsSplit')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSalesStepsPay-cash')), findsOneWidget);
    expect(find.byKey(const Key('askodoxSalesStepsTop-Tea')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSalesStepsChange')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSalesStepsPeriod-week')), findsOneWidget);
  });
}
