import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/crm_more_steps_screens.dart';

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
  testWidgets('complaint: next status is the one big button', (tester) async {
    final api = _Api((m, path, b) {
      if (m == 'PATCH' || m == 'PUT') return {'ok': true};
      return {'id': 'k1', 'subject': 'Wrong item', 'name': 'Test Buyer', 'priority': 'normal', 'status': 'open', 'timeline': []};
    });
    await _pump(tester, api, const AskodoxCrmComplaintStepsScreen(businessId: 'b1', complaintId: 'k1'));
    expect(find.byKey(const Key('askodoxComplaintSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxComplaintStepsNext')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('PATCH') || k.startsWith('PUT')), isTrue);
  });

  testWidgets('customer history: bought total, bill row, account button', (tester) async {
    final api = _Api((m, path, b) => {
          'customer': {'name': 'Test Buyer', 'phone': '9000000000'},
          'summary': {'bills': 1, 'billed_paise': 150000, 'due_paise': 0, 'open_leads': 0, 'open_complaints': 0},
          'invoices': [
            {'id': 'i1', 'number': 'T/26/000001', 'doc_kind': 'invoice', 'status': 'issued', 'total_paise': 150000, 'local_date': '2026-11-20'}
          ],
          'leads': [],
          'complaints': [],
        });
    await _pump(tester, api, const AskodoxCrmCustomerStepsScreen(businessId: 'b1', customerId: 'c1'));
    expect(find.byKey(const Key('askodoxCrmCustomerSteps')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCrmCustomerStepsBill-i1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxCrmCustomerStepsAccount')), findsOneWidget);
  });
}
