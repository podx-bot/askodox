import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/invoice_steps_screens.dart';

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
  testWidgets('bill: total on top, next bill right after billing, cancel in the menu', (tester) async {
    final api = _Api((m, path, b) {
      if (path.contains('/invoices/')) {
        return {
          'id': 'i1',
          'number': 'T/26/000001',
          'doc_kind': 'invoice',
          'status': 'issued',
          'lines': [
            {'line_no': 1, 'name': 'Tea', 'qty_milli': 2000, 'unit': 'pcs', 'rate_paise': 1000, 'line_total_paise': 2000}
          ],
          'totals': {'grand_total_paise': 2000},
          'payments': [],
        };
      }
      return {'name': 'Test Shop', 'permissions': ['return', 'cancel']};
    });
    await _pump(tester, api, const AskodoxInvoiceStepsScreen(businessId: 'b1', invoiceId: 'i1', fresh: true));
    expect(find.byKey(const Key('askodoxInvoiceSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxInvoiceStepsNext')), findsOneWidget);
    expect(find.byKey(const Key('askodoxInvoiceStepsReceipt')), findsOneWidget);
  });
}
