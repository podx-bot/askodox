import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/payments_hub_screen.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls.add('$method $path');
    bodies['$method $path'] = body;
    final out = reply(method, path, body);
    if (out is ApiFailure) return ApiError<T>(out);
    return ApiSuccess(out as T);
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

Widget _app(_Api api, DateTime now) => ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: MaterialApp(home: AskodoxPaymentsHubScreen(now: now)),
    );

String _at(DateTime local) => local.toUtc().toIso8601String();

void main() {
  test('rupees use Indian digit grouping', () {
    expect(askodoxRupees(0), '₹0');
    expect(askodoxRupees(35000), '₹350');
    expect(askodoxRupees(245000), '₹2,450');
    expect(askodoxRupees(12345600), '₹1,23,456');
  });

  testWidgets('no shop yet: the hub offers to switch alerts on, with the QR / alerts / accounts doors', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = _Api((method, path, body) {
      if (method == 'GET' && path == '/api/pos/businesses') return {'businesses': <Object>[]};
      return const ApiFailure(ApiFailureType.notFound, statusCode: 404);
    });
    await tester.pumpWidget(_app(api, DateTime(2026, 11, 12, 18)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPaymentsHubStart')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPaymentsHubToday')), findsNothing);
    expect(find.byKey(const Key('askodoxPaymentsHubQr')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPaymentsHubAlerts')), findsOneWidget);
    expect(find.byKey(const Key('askodoxPaymentsHubAccounts')), findsOneWidget);
    expect(find.textContaining('Razorpay'), findsNothing);
  });

  testWidgets('today = real (non-test) alerts of today; spoken count from acks; latest three listed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 12, 18);
    final events = [
      {
        'id': 'e1', 'amount_paise': 35000, 'source_label': 'PhonePe', 'test': false,
        'received_at': _at(DateTime(2026, 11, 12, 10, 42)),
        'acks': [{'state': 'announced'}],
      },
      {
        'id': 'e2', 'amount_paise': 12000, 'source_label': 'Google Pay', 'test': false,
        'received_at': _at(DateTime(2026, 11, 12, 10, 15)),
        'acks': [{'state': 'muted'}],
      },
      {
        'id': 't1', 'amount_paise': 100, 'source_label': 'PhonePe', 'test': true,
        'received_at': _at(DateTime(2026, 11, 12, 9, 0)),
        'acks': <Object>[],
      },
      {
        'id': 'e3', 'amount_paise': 50000, 'source_label': 'Paytm', 'test': false,
        'received_at': _at(DateTime(2026, 11, 11, 20, 0)),
        'acks': <Object>[],
      },
    ];
    final api = _Api((method, path, body) {
      if (method == 'GET' && path == '/api/pos/businesses') {
        return {
          'businesses': [
            {'id': 'b1', 'name': 'Lakshmi Kirana', 'role': 'owner'}
          ]
        };
      }
      if (method == 'GET' && path.startsWith('/api/pos/businesses/b1/payment-alerts/events')) return {'events': events};
      return const ApiFailure(ApiFailureType.notFound, statusCode: 404);
    });
    await tester.pumpWidget(_app(api, now));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPaymentsHubToday')), findsOneWidget);
    expect(find.text('₹470'), findsOneWidget, reason: '350 + 120 today; the test payment and yesterday are left out');
    expect(find.text('2 payments · spoke 1 times'), findsOneWidget);
    expect(find.textContaining('not bank-confirmed'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPaymentsHubEvent-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPaymentsHubEvent-e2')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPaymentsHubEvent-e3')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPaymentsHubEvent-t1')), findsNothing);
    expect(find.text('✓ Spoke'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPaymentsHubAdvanced')), findsOneWidget);
    expect(find.textContaining('ASKODOX payment profile'), findsOneWidget);
    expect(find.textContaining('Razorpay'), findsNothing);
  });
}
