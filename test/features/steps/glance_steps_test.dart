import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/glance_steps_screens.dart';

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
  testWidgets('baaki reminders: total on top, a row, the remind button', (tester) async {
    final api = _Api((m, path, b) => {
          'items': [
            {'invoice_id': 'i1', 'customer': 'Ravi', 'due_paise': 150000, 'state': 'remind', 'days_left': 1, 'number': 'A1', 'pay_date': '2026-11-25', 'whatsapp_to': '919999999999', 'text': 'hi'},
            {'invoice_id': 'i2', 'customer': 'Sita', 'due_paise': 50000, 'state': 'overdue', 'days_left': -2, 'number': 'A2', 'pay_date': '2026-11-22'},
          ],
        });
    await _pump(tester, api, const AskodoxDuesRemindersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxDuesRemindersSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDuesStepsRow-i1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDuesStepsRow-i2')), findsOneWidget);
    expect(find.byKey(const Key('askodoxDuesStepsNext')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDuesStepsRow-i2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxDuesStepsDate-i2-Tomorrow')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.contains('i2') || k.contains('due')), isTrue);
  });

  testWidgets('baaki reminders: the owner turns automatic WhatsApp on from the menu', (tester) async {
    var on = false;
    final api = _Api((m, path, b) {
      if (m == 'PUT' && path.endsWith('/dues/auto')) {
        on = true;
        return {'available': true, 'on': true};
      }
      return {
        'auto': {'available': true, 'on': on, 'owner': true},
        'items': [
          {'invoice_id': 'i1', 'customer': 'Ravi', 'due_paise': 150000, 'state': 'remind', 'days_left': 1, 'number': 'A1', 'pay_date': '2026-11-25', 'whatsapp_to': '919999999999', 'text': 'hi', 'sent_today': on, 'sent_auto': on},
        ],
      };
    });
    await _pump(tester, api, const AskodoxDuesRemindersStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxDuesStepsAutoOn')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxStepMore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxDuesStepsAuto')));
    await tester.pumpAndSettle();
    expect(api.calls['PUT /api/pos/businesses/b1/dues/auto'], {'on': true});
    expect(find.byKey(const Key('askodoxDuesStepsAutoOn')), findsOneWidget);
    expect(find.textContaining('sent by itself'), findsWidgets);
  });

  testWidgets('bills: total, rows and search', (tester) async {
    final api = _Api((m, path, b) => {
          'invoices': [
            {'id': 'v1', 'number': 'B1', 'customer_name': 'Ravi', 'local_date': '2026-11-24', 'grand_total_paise': 20000, 'status': 'issued'},
            {'id': 'v2', 'number': 'B2', 'customer_name': 'Sita', 'local_date': '2026-11-24', 'grand_total_paise': 30000, 'status': 'cancelled'},
          ],
        });
    await _pump(tester, api, const AskodoxInvoicesStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxInvoicesStepsRow-v1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxInvoicesStepsRow-v2')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxInvoicesStepsSearch')), 'Sita');
    await tester.pump();
    expect(find.byKey(const Key('askodoxInvoicesStepsRow-v1')), findsNothing);
    expect(find.byKey(const Key('askodoxInvoicesStepsNew')), findsOneWidget);
  });

  testWidgets('stock: value on top and the expiring batches', (tester) async {
    final api = _Api((m, path, b) => path.contains('valuation')
        ? {'total_value_paise': 500000, 'method': 'average'}
        : {
            'items': [
              {'batch_no': 'L1', 'name': 'Milk', 'expiry_date': '2026-12-01', 'expired': false, 'qty_milli': 2000, 'unit': 'pc'},
            ],
          });
    await _pump(tester, api, const AskodoxStockStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxStockSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStockStepsRow-L1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStockStepsCount')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStockStepsSerial')), findsOneWidget);
  });

  testWidgets('cashbook: left this month, rows, write an entry asks in or out', (tester) async {
    final api = _Api((m, path, b) => {
          'income_paise': 100000,
          'expense_paise': 40000,
          'balance_paise': 60000,
          'entries': [
            {'id': 'c1', 'kind': 'expense', 'amount_paise': 40000, 'category': 'gas', 'note': 'Gas', 'local_date': '2026-11-20'},
            {'id': 'c2', 'kind': 'income', 'amount_paise': 100000, 'category': 'sale', 'auto': true, 'local_date': '2026-11-21'},
          ],
        });
    await _pump(tester, api, const AskodoxCashbookStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxCashbookStepsRow-c1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCashbookStepsSplit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxCashbookStepsAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxCashbookStepsIn')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCashbookStepsOut')), findsOneWidget);
  });

  testWidgets('reports: sales on top, a problem, change day', (tester) async {
    final api = _Api((m, path, b) => path.contains('range')
        ? {'total_paise': 900000, 'bills': 30, 'items_top': [{'name': 'Tea', 'paise': 100000}]}
        : {
            'sales': {'paise': 250000, 'bills': 12},
            'problems': [
              {'key': 'p1', 'level': 'high', 'text_en': 'Dues are high', 'text_te': 'బాకీ ఎక్కువ', 'do_en': 'Remind', 'do_te': 'గుర్తు చేయండి'},
            ],
          });
    await _pump(tester, api, const AskodoxReportsStepsScreen(businessId: 'b1'));
    expect(find.byKey(const Key('askodoxReportsStepsProblem-p1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxReportsStepsChange')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxReportsStepsPeriod-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxReportsStepsTop-Tea')), findsOneWidget);
  });

  testWidgets('reports: one given day (night report link) shows that date', (tester) async {
    final api = _Api((m, path, b) => {
          'sales': {'paise': 120000, 'bills': 5},
          'problems': <Object?>[],
        });
    await _pump(tester, api, const AskodoxReportsStepsScreen(businessId: 'b1', date: '2026-11-20'));
    expect(find.text('2026-11-20'), findsOneWidget);
    expect(find.byKey(const Key('askodoxReportsStepsNone')), findsOneWidget);
  });
}
