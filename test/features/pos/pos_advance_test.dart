import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_advance_screens.dart';

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

const _terms = {'en': 'ASKODOX only keeps a record of this advance. ASKODOX is not responsible for it.', 'te': 'తెలుగు'};

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner turns it on only after accepting the terms shown from the server', (tester) async {
    var enabled = false;
    final api = _Api((method, path, body) {
      if (method == 'PUT') enabled = true;
      return {'enabled': enabled, 'max_balance_paise': 200000, 'hard_max_paise': 1000000, 'terms_version': '2026-10-24',
        'terms': _terms};
    });
    await _pump(tester, api, const AskodoxPosAdvanceSettingsScreen(businessId: 'b1'));
    expect(find.textContaining('not responsible'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('askodoxAdvanceTurnOn'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('askodoxAdvanceAccept')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxAdvanceTurnOn')));
    await tester.pumpAndSettle();
    final sent = api.calls['PUT /api/pos/businesses/b1/advance/settings'] as Map;
    expect(sent['enabled'], isTrue);
    expect(sent['accept_terms_version'], '2026-10-24');
    expect(sent['max_balance_paise'], 200000);
    expect(find.byKey(const Key('askodoxAdvanceOn')), findsOneWidget);
  });

  testWidgets('shop: a deposit is only SENT for approval; the balance shown is the server\'s', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/advance/settings')) return {'enabled': true, 'terms': _terms};
      if (path.endsWith('/customers/c1/advance')) {
        return {'balance_paise': 0, 'due_paise': 0, 'entries': [
          {'id': 'adv1', 'kind': 'deposit', 'amount_paise': 50000, 'status': 'pending'},
        ]};
      }
      return {'id': 'adv2', 'status': 'pending'};
    });
    await _pump(tester, api, const AskodoxPosCustomerAdvanceCard(businessId: 'b1', customerId: 'c1'));
    expect(find.text('₹0.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPosAdvancePending-adv1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPosAdvanceRedeem')), findsNothing, reason: 'no balance, nothing due');
    await tester.tap(find.byKey(const Key('askodoxPosAdvanceDeposit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.byKey(const ValueKey('askodoxAdvanceMethod-upi')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxAdvanceSend')));
    await tester.pumpAndSettle();
    final body = api.calls['POST /api/pos/businesses/b1/customers/c1/advance/deposit'] as Map;
    expect(body['amount_paise'], 50000);
    expect(body['method'], 'upi');
    expect('${body['client_txn_id']}'.length, greaterThanOrEqualTo(8));
    expect(find.text('Sent to the customer for approval.'), findsOneWidget);
  });

  testWidgets('customer: first approval needs the terms ticked; reject never asks', (tester) async {
    final api = _Api((method, path, body) {
      if (path == '/api/pos/me/advances') {
        return {'terms': _terms, 'terms_version': '2026-10-24', 'shops': [
          {'business_id': 'b1', 'shop': 'Lakshmi Kirana', 'customer_id': 'c1', 'balance_paise': 0, 'accepted_terms': false,
            'pending': [
              {'id': 'adv1', 'kind': 'deposit', 'amount_paise': 50000, 'status': 'pending'},
              {'id': 'adv2', 'kind': 'deposit', 'amount_paise': 7000, 'status': 'pending'},
            ],
            'history': <Object>[]},
        ]};
      }
      return {'status': 'approved', 'balance_paise': 50000};
    });
    await _pump(tester, api, const AskodoxMyShopAdvancesScreen());
    expect(find.text('Did you give Lakshmi Kirana ₹500.00 as an advance?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxMyAdvanceReject-adv2')));
    await tester.pumpAndSettle();
    expect(api.calls['POST /api/pos/me/advances/adv2/decision'], {'approve': false});
    await tester.tap(find.byKey(const ValueKey('askodoxMyAdvanceApprove-adv1')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('askodoxMyAdvanceAcceptOk'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('askodoxMyAdvanceAccept')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxMyAdvanceAcceptOk')));
    await tester.pumpAndSettle();
    expect(api.calls['POST /api/pos/me/advances/adv1/decision'], {'approve': true, 'accept_terms_version': '2026-10-24'});
  });
}
