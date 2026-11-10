import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/my_payment_alerts_screen.dart';

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

Widget _app(_Api api) => ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: const MaterialApp(home: AskodoxMyPaymentAlertsScreen()),
    );

void main() {
  testWidgets('first time: name + State create the shop; then staff are added with a role (attendant too)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    var shops = <Map<String, Object?>>[];
    final members = <Map<String, Object?>>[];
    final api = _Api((method, path, body) {
      if (method == 'GET' && path == '/api/pos/businesses') return {'businesses': shops};
      if (method == 'GET' && path == '/api/pos/meta') {
        return {
          'states': {'37': 'Andhra Pradesh', '36': 'Telangana'}
        };
      }
      if (method == 'POST' && path == '/api/pos/businesses') {
        shops = [
          {'id': 'b1', 'name': (body as Map)['name'], 'role': 'owner'}
        ];
        return {'id': 'b1'};
      }
      if (method == 'GET' && path == '/api/pos/businesses/b1/members') return {'members': members};
      if (method == 'POST' && path == '/api/pos/businesses/b1/members') {
        final b = body as Map;
        members.add({'phone_last4': '${b['phone']}'.substring(6), 'role': b['role'], 'active': true});
        return {'phone_last4': '${b['phone']}'.substring(6), 'role': b['role']};
      }
      return const ApiFailure(ApiFailureType.notFound, statusCode: 404);
    });
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxMyPaymentAlertsSetup')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('askodoxMyPaymentAlertsName')), 'Lakshmi Kirana');
    await tester.tap(find.byKey(const Key('askodoxMyPaymentAlertsState')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andhra Pradesh').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxMyPaymentAlertsCreate')));
    await tester.pumpAndSettle();
    final created = api.bodies['POST /api/pos/businesses'] as Map;
    expect(created['name'], 'Lakshmi Kirana');
    expect(created['state_code'], '37');
    expect(created['registration_type'], 'unregistered');
    expect(find.byKey(const ValueKey('askodoxMyPaymentAlertsShop-b1')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('askodoxMyPaymentAlertsPhone-b1')), '9400000304');
    await tester.tap(find.byKey(const ValueKey('askodoxMyPaymentAlertsRole-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attendant').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxMyPaymentAlertsAdd-b1')));
    await tester.tap(find.byKey(const ValueKey('askodoxMyPaymentAlertsAdd-b1')));
    await tester.pumpAndSettle();
    expect(api.bodies['POST /api/pos/businesses/b1/members'], {'phone': '9400000304', 'role': 'attendant'});
    expect(find.byKey(const ValueKey('askodoxMyPaymentAlertsStaff-b1-0304')), findsOneWidget);
    expect(find.text('••••••0304'), findsOneWidget, reason: 'only the last four digits are shown');
    expect(find.byKey(const Key('askodoxMyPaymentAlertsMessage')), findsOneWidget);
  });

  testWidgets('a staff member sees the shop with their role and only the sound switch (no staff list)', (tester) async {
    final api = _Api((method, path, body) {
      if (method == 'GET' && path == '/api/pos/businesses') {
        return {
          'businesses': [
            {'id': 'b9', 'name': 'Sri Fuels', 'role': 'attendant'}
          ]
        };
      }
      return const ApiFailure(ApiFailureType.notFound, statusCode: 404);
    });
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Sri Fuels'), findsOneWidget);
    expect(find.textContaining('Attendant'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyPaymentAlertsOpen-b9')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyPaymentAlertsAdd-b9')), findsNothing);
    expect(api.calls.where((c) => c.contains('/members')), isEmpty, reason: 'staff never ask for the staff list');
  });
}
