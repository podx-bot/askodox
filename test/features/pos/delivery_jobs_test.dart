import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/delivery_jobs_screens.dart';

/// Owner plan 2026-11-24 step 1: one line -> job card -> who goes (free first) -> answers -> give; the person's page.
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

const _job = {
  'id': 'dlv_1', 'label': '#12', 'order_no': 12, 'from': 'Uyyuru', 'to': 'Param', 'item': 'cake',
  'fee_paise': 4000, 'collect_paise': 25000, 'status': 'asking', 'assignee_label': '',
  'asks': [
    {'user': 'u1', 'label': 'Suresh', 'answer': 'now', 'phone': '9400000001'},
    {'user': 'u2', 'label': 'Kiran', 'answer': 'no', 'phone': ''},
  ],
};

void main() {
  testWidgets('owner: one line -> card -> free people -> answers -> give', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/delivery-jobs/draft')) {
        return {'from': 'Uyyuru', 'to': 'Param', 'item': 'cake', 'fee_paise': 0, 'collect_paise': 25000, 'km': 7.4, 'minutes': 18};
      }
      if (path.endsWith('/delivery-jobs/people')) {
        return {
          'people': [
            {'id': 'u1', 'label': 'Suresh', 'role': 'delivery', 'colour': 'free'},
            {'id': 'u2', 'label': 'Kiran', 'role': 'delivery', 'colour': 'off'},
          ],
        };
      }
      if (path.endsWith('/give')) return {..._job, 'status': 'given', 'assignee_label': 'Suresh'};
      if (method == 'POST' && path.endsWith('/delivery-jobs')) return _job;
      return {'jobs': []};
    });
    await _pump(tester, api, const AskodoxDeliveryJobsScreen(businessId: 's1'));
    await tester.enterText(find.byKey(const Key('askodoxDeliveryLine')), 'Uyyuru to Param cake, collect 250');
    await tester.tap(find.byKey(const Key('askodoxDeliveryRead')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('askodoxDeliveryRoute')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeliveryNext')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('askodoxDeliveryPerson-u1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxDeliverySend')));
    await tester.pump(const Duration(milliseconds: 50));
    final sent = api.calls['POST /api/pos/businesses/s1/delivery-jobs'] as Map;
    expect(sent['ask'], ['u1'], reason: 'free people are chosen first');
    expect(sent['collect_paise'], 25000);
    expect(find.byKey(const Key('askodoxDeliveryCard')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxDeliveryGive-u1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('askodoxDeliveryGiven')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxDeliveryGive-u2')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('person: colour, answer an offer, money buttons', (tester) async {
    final api = _Api((method, path, body) {
      if (path == '/api/me/delivery-jobs') {
        return {
          'status': {'colour': 'free'},
          'offers': [
            {'id': 'dlv_2', 'label': '#13', 'shop': 'Sai Bakery', 'from': 'Shop', 'to': 'Gudivada', 'fee_paise': 5000, 'km': 3.2},
          ],
          'running': [
            {'id': 'dlv_1', 'label': '#12', 'shop': 'Sai Bakery', 'from': 'Uyyuru', 'to': 'Param', 'collect_paise': 25000,
             'status': 'given', 'maps_url': 'https://www.google.com/maps/dir/?api=1&destination=Param'},
          ],
          'cash_today': [
            {'business_id': 's1', 'paise': 50000, 'jobs': 2},
          ],
        };
      }
      return {'ok': true};
    });
    await _pump(tester, api, const AskodoxMyDeliveriesScreen());
    expect(find.byKey(const Key('askodoxMyCashToday')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxWorkStatus-off')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['PUT /api/me/work-status'], {'colour': 'off'});
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxOfferAnswer-dlv_2-now')), 200);
    await tester.tap(find.byKey(const ValueKey('askodoxOfferAnswer-dlv_2-now')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/me/delivery-jobs/dlv_2/answer'], {'answer': 'now'});
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxMyJobDone-dlv_1-cash')), -200);
    await tester.tap(find.byKey(const ValueKey('askodoxMyJobDone-dlv_1-cash')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/me/delivery-jobs/dlv_1/step'], {'step': 'done', 'money': 'cash'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(Future<void>.value());
  });
}
