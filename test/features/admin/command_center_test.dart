import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/route_guard.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/features/admin/command_center/command_center_api.dart';
import 'package:podx/features/admin/command_center/command_center_screen.dart';

const _staffToken = 'stf_test_token_123';

/// Minimal fake of the `/admin/cc` backend: enforces the credential and
/// records every call so tests can assert exactly what was sent.
class _FakeBackend implements ApiClient {
  final permissions = const ['overview:view', 'support:view', 'support:manage', 'config:view', 'config:manage'];
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final headersSeen = <Map<String, String>>[];

  Map<String, Object?>? _route(String method, String path) {
    switch ('$method $path') {
      case 'GET /admin/cc/me':
        return {'id': 'staff-1', 'name': 'Asha', 'role': 'support_agent', 'permissions': permissions};
      case 'GET /admin/cc/overview':
        return {
          'participants': {'buyers': 4, 'sellers': 2, 'service_providers': 1, 'job_seekers': 0, 'delivery_ride': 0},
          'requests': {'active': 3, 'total': 9},
          'orders': {'PLACED': 2},
          'listings': {'active': 5, 'disabled': 1},
          'support_open': 1,
          'no_match_open': 2,
          'unread_notifications': 1,
        };
      case 'GET /admin/cc/escalations':
        return {
          'items': [
            {'id': 7, 'category': 'PAYMENT', 'issue': 'Money deducted', 'critical': true, 'status': 'OPEN', 'created_at': '2026-09-26'},
          ],
        };
      case 'GET /admin/cc/escalations/7':
        return {
          'id': 7, 'category': 'PAYMENT', 'issue': 'Money deducted', 'critical': true, 'status': 'OPEN',
          'requester': 'app-phone-••••••••0001',
          'context': {'deal_id': '301', 'actions_tried': ['Checked UPI reference'], 'conversation': []},
        };
      case 'PATCH /admin/cc/escalations/7':
        return {'id': 7, 'status': 'RESOLVED'};
      case 'GET /admin/cc/config':
        return {
          'flags': [
            {'key': 'results.online', 'description': 'Online product results', 'enabled': true,
             'requires': 'brave_search', 'integration_configured': false},
          ],
        };
      case 'PUT /admin/cc/config/results.online':
        return {'key': 'results.online', 'enabled': false};
    }
    return null;
  }

  Future<ApiResult<T>> _handle<T>(String method, String path, Object? body, ApiRequestOptions options) async {
    calls.add('$method $path');
    bodies['$method $path'] = body;
    headersSeen.add(options.headers);
    if (options.headers['X-ASKODOX-Staff-Token'] != _staffToken) {
      return ApiError<T>(const ApiFailure(ApiFailureType.authentication, message: 'Command Center sign-in required', statusCode: 401));
    }
    final data = _route(method, path);
    if (data == null) {
      return ApiError<T>(const ApiFailure(ApiFailureType.notFound, message: 'not found', statusCode: 404));
    }
    return ApiSuccess<T>(data as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _handle('GET', path, null, options);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _handle('POST', path, body, options);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _handle('PUT', path, body, options);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _handle('PATCH', path, body, options);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _handle('DELETE', path, null, options);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      const ApiError<Uri>(ApiFailure(ApiFailureType.unknown));
}

Future<void> _pump(WidgetTester tester, _FakeBackend backend) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [commandCenterApiProvider.overrideWithValue(CommandCenterApi(backend))],
    child: const MaterialApp(home: CommandCenterScreen()),
  ));
}

Future<void> _signIn(WidgetTester tester, String secret) async {
  await tester.enterText(find.byKey(const Key('cc-secret')), secret);
  await tester.tap(find.byKey(const Key('cc-sign-in')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rejected token stays signed out with an honest message', (tester) async {
    final backend = _FakeBackend();
    await _pump(tester, backend);
    await _signIn(tester, 'stf_wrong');
    expect(find.text('That key or token was not accepted.'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('only sections the server granted are shown, with real overview numbers', (tester) async {
    final backend = _FakeBackend();
    await _pump(tester, backend);
    await _signIn(tester, _staffToken);

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Config'), findsOneWidget);
    expect(find.text('Staff'), findsNothing, reason: 'staff:manage was not granted');
    expect(find.text('Analytics'), findsNothing);
    expect(find.text('Open support cases'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(backend.headersSeen.every((h) => h['X-ASKODOX-Staff-Token'] == _staffToken), isTrue);
  });

  testWidgets('resolving an escalation needs a note and a confirmation', (tester) async {
    final backend = _FakeBackend();
    await _pump(tester, backend);
    await _signIn(tester, _staffToken);
    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Money deducted'));
    await tester.pumpAndSettle();

    expect(find.text('• Checked UPI reference'), findsOneWidget);
    expect(find.text('Deal / request id: 301'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cc-esc-RESOLVED')));
    await tester.pumpAndSettle();
    final confirm = tester.widget<FilledButton>(find.byKey(const Key('cc-confirm')));
    expect(confirm.onPressed, isNull, reason: 'a resolution note is required');
    await tester.enterText(find.byKey(const Key('cc-confirm-note')), 'Refunded via UPI');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cc-confirm')));
    await tester.pumpAndSettle();

    expect(backend.bodies['PATCH /admin/cc/escalations/7'],
        {'status': 'RESOLVED', 'resolution_note': 'Refunded via UPI', 'confirm': true});
  });

  testWidgets('turning a source off asks first and shows the integration state', (tester) async {
    final backend = _FakeBackend();
    await _pump(tester, backend);
    await _signIn(tester, _staffToken);
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();

    expect(find.textContaining('NOT configured'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cc-flag-results.online')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.calls.contains('PUT /admin/cc/config/results.online'), isFalse);

    await tester.tap(find.byKey(const Key('cc-flag-results.online')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cc-confirm')));
    await tester.pumpAndSettle();
    expect(backend.bodies['PUT /admin/cc/config/results.online'], {'enabled': false, 'confirm': true});
  });

  test('credential never prints its secret and CSV export matches backend columns', () {
    const credential = CommandCenterCredential(CommandCenterCredentialKind.ownerKey, 'super-secret');
    expect(credential.toString(), isNot(contains('super-secret')));
    expect(credential.headers, {'X-ASKODOX-Admin-Key': 'super-secret'});
    expect(
      commandCenterAnalyticsCsv({
        'daily': [
          {'date': '2026-09-26', 'requests': 3, 'matches': 1, 'no_match': 2, 'orders': 0, 'escalations': 1, 'seller_joins': 0},
        ],
      }),
      'date,requests,matches,no_match,orders,escalations,seller_joins\n2026-09-26,3,1,2,0,1,0',
    );
  });

  test('the command center route relies on its own server-checked sign-in', () {
    const guard = RouteGuard();
    const buyer = AuthSession(status: AuthStatus.loggedIn, user: AuthUser(id: 'b', role: UserRole.buyer));
    expect(guard.redirect(AuthSession.loggedOut, '/admin/command-center'), isNull);
    expect(guard.redirect(buyer, '/admin/command-center'), isNull);
    expect(guard.redirect(buyer, '/admin/dashboard'), '/forbidden');
  });
}
