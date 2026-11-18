import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/domain/payment_alert_setup.dart';
import 'package:podx/features/pos/presentation/pay_alert_disclaimer.dart';
import 'package:podx/features/pos/presentation/pay_alert_phones_card.dart';
import 'package:podx/features/pos/presentation/payment_alert_banner.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path) reply;

  Future<ApiResult<T>> _go<T>(String method, String path) async => ApiSuccess(reply(method, path) as T);

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('DELETE', path);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

final _phones = {
  'problems': 2,
  'phones': [
    {'id': 'pad_1', 'mine': true, 'role': 'owner', 'name': '', 'state': 'working'},
    {'id': 'pad_2', 'mine': false, 'role': 'cashier', 'name': 'Ravi', 'state': 'permission_off', 'reason': 'needs_access'},
    {'id': 'pad_3', 'mine': false, 'role': 'waiter', 'name': 'Sita', 'state': 'not_answering', 'reason': 'no_answer',
      'missed_amount_paise': 35000},
  ],
};

Widget _app(Widget child) => ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(_Api((m, p) => _phones), authToken: 't')),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  testWidgets('owner sees every phone: working, permission off, sound missed (owner 2026-11-18)', (tester) async {
    await tester.pumpWidget(_app(const AskodoxPayAlertPhonesCard(businessId: 'b1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertPhones')), findsOneWidget);
    expect(find.textContaining('Working'), findsOneWidget);
    expect(find.textContaining('Permission off: notification access not given'), findsOneWidget);
    expect(find.textContaining('Sound missed (₹350)'), findsOneWidget);
    expect(find.textContaining('one step it needs'), findsOneWidget);
  });

  testWidgets('the warning on top lists only the phones with a problem', (tester) async {
    await tester.pumpWidget(_app(const AskodoxPayAlertPhonesCard(businessId: 'b1', warningOnly: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPayAlertPhonesWarning')), findsOneWidget);
    expect(find.textContaining('2 phone(s)'), findsOneWidget);
    expect(find.textContaining('Ravi'), findsOneWidget);
    expect(find.textContaining('Owner (this phone)'), findsNothing);
  });

  test('a hear-only phone is never asked for notification access', () {
    expect(askodoxHearOnlyHealth(AskodoxAlertHealth.needsAccess, hearOnly: true, mineEnabled: false), AskodoxAlertHealth.ok);
    expect(askodoxHearOnlyHealth(AskodoxAlertHealth.noVoice, hearOnly: true, mineEnabled: false), AskodoxAlertHealth.noVoice);
    expect(askodoxHearOnlyHealth(AskodoxAlertHealth.needsAccess, hearOnly: false, mineEnabled: false),
        AskodoxAlertHealth.needsAccess);
    expect(askodoxAlertHealthWire(AskodoxAlertHealth.needsAccess), 'needs_access');
    final steps = askodoxPayAlertSetupSteps(
        status: {'listenerAllowed': false, 'listenerDeclared': true},
        settings: {'enabled': true, 'can_edit': false, 'reports_payments': false},
        apps: const [
          {'package': 'com.phonepe.app.business', 'installed': true}
        ],
        confirmed: {});
    expect(steps.map((s) => s.kind), isNot(contains('access')));
    expect(steps.map((s) => s.kind), isNot(contains('app_notifications')));
  });

  test('the disclaimer says received, no guarantee, not linked to NPCI / RBI', () {
    final te = askodoxPayAlertDisclaimerLines(true).join(' ');
    expect(te, contains('అందింది'));
    expect(te, contains('హామీ లేదు'));
    expect(te, contains('NPCI'));
    expect(te, isNot(contains('నిర్ధార')));
    expect(askodoxPayAlertDisclaimerLines(false).join(' '), isNot(contains('confirm')));
  });
}
