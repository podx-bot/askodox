import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_crm_screens.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path, null);
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
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('labels and dates read the way the shop talks', () {
    expect(askodoxCrmStageLabel('negotiation', false), 'Negotiation');
    expect(askodoxCrmStageLabel('quoted', true), 'Quotation ఇచ్చాం');
    expect(askodoxCrmSourceLabel('askodox', false), 'ASKODOX app');
    expect(askodoxCrmWhen('2026-10-28T10:00+05:30'), '2026-10-28 10:00');
    expect(askodoxCrmStages.last, 'lost');
  });

  testWidgets('a lost lead always sends the reason with the version it was read at', (tester) async {
    var stage = 'contacted';
    final api = _Api((method, path, body) {
      if (method == 'PATCH') stage = '${(body as Map)['stage']}';
      return {
        'id': 'lead1', 'name': 'Ravi', 'kind': 'lead', 'source': 'walk_in', 'need': 'Dining table', 'stage': stage,
        'version': 3, 'value_paise': 2500000, 'customer_id': null, 'lost_reason': stage == 'lost' ? 'Price' : '',
        'assigned_to': {'me': true, 'last4': '0001'}, 'followups': [], 'quotations': [],
        'timeline': [{'kind': 'created', 'text': 'lead · walk_in', 'at': '2026-10-27T06:00:00+00:00'}],
      };
    });
    await _pump(tester, api, const AskodoxPosCrmLeadScreen(businessId: 'b1', leadId: 'lead1'));
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.byKey(const Key('askodoxCrmQuote')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCrmToCustomer')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxCrmSetStage-lost')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Price too high');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final sent = api.calls['PATCH /api/pos/businesses/b1/crm/leads/lead1'] as Map;
    expect(sent['stage'], 'lost');
    expect(sent['lost_reason'], 'Price too high');
    expect(sent['version'], 3);
  });

  testWidgets('customer history shows the real bills, dues and open complaints', (tester) async {
    final api = _Api((method, path, body) => {
          'customer': {'id': 'c1', 'name': 'Suresh', 'phone': '9123456780'},
          'summary': {'bills': 2, 'billed_paise': 3000000, 'due_paise': 150000, 'open_leads': 1, 'open_complaints': 1},
          'invoices': [
            {'id': 'i1', 'doc_kind': 'invoice', 'number': 'LF/2627/000001', 'total_paise': 2500000, 'local_date': '2026-10-20',
              'status': 'issued'},
          ],
          'leads': [], 'complaints': [{'id': 'k1', 'subject': 'Leg loose', 'status': 'open'}], 'timeline': [],
        });
    await _pump(tester, api, const AskodoxPosCrmCustomerScreen(businessId: 'b1', customerId: 'c1'));
    expect(find.text('Suresh'), findsOneWidget);
    expect(find.textContaining('LF/2627/000001'), findsOneWidget);
    expect(find.text('Leg loose'), findsOneWidget);
    expect(find.byKey(const Key('askodoxCrmCustomerLead')), findsOneWidget);
    expect(api.calls.keys, contains('GET /api/pos/businesses/b1/crm/customers/c1/history'));
  });
}
