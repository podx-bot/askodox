import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/my_work_steps_screen.dart';

/// Owner 2026-11-25: I want work in 3 pieces (made-up data only).
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

void main() {
  testWidgets('my work, no card: pick work -> name + 18+ -> card saved', (tester) async {
    var saved = false;
    final api = _Api((m, path, b) {
      if (m == 'PUT' && path == '/api/me/work') {
        saved = true;
        return {'ok': true};
      }
      if (path == '/api/me/work/orders') return {'offers': <Object?>[], 'mine': <Object?>[]};
      if (path == '/api/me/work') {
        return saved
            ? {
                'worker': {'name': 'Test Worker', 'work_types': <Object?>[]},
                'links': <Object?>[],
                'docs': <Object?>[],
                'postings': <Object?>[],
                'badge': <String, Object?>{},
              }
            : {
                'worker': null,
                'work_types': [
                  {'key': 'driver', 'en': 'Driver', 'te': 'డ్రైవర్'},
                  {'key': 'cook', 'en': 'Cook', 'te': 'వంట'},
                ],
              };
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxMyWorkStepsScreen());
    expect(find.byKey(const Key('askodoxMyWorkSteps')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxMyWorkStepsType-driver')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxMyWorkStepsNext')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askodoxMyWorkStepsName')), 'Test Worker');
    await tester.tap(find.byKey(const Key('askodoxMyWorkStepsAdult')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxMyWorkStepsSave')));
    await tester.pumpAndSettle();
    final body = api.calls['PUT /api/me/work'] as Map;
    expect(body['work_types'], ['driver']);
    expect(body['adult'], true);
    expect(find.byKey(const Key('askodoxMyWorkStepsWaiting')), findsOneWidget);
  });

  testWidgets('my work with a card: waiting count, offer answered from the big button', (tester) async {
    final api = _Api((m, path, b) {
      if (path == '/api/me/work/orders') {
        return {
          'offers': [
            {'id': 'o1', 'label': '#7', 'work_en': 'Driver', 'work_te': 'డ్రైవర్', 'authority': 'Test Agency', 'place': 'Town'}
          ],
          'mine': [
            {'id': 'j1', 'label': '#5', 'work_en': 'Cook', 'work_te': 'వంట', 'place': 'Hall', 'status': 'given'}
          ],
        };
      }
      if (path == '/api/me/work') {
        return {
          'worker': {
            'name': 'Test Worker',
            'work_types': [
              {'key': 'driver', 'en': 'Driver'}
            ],
            'jobs': 3,
          },
          'links': [
            {'business_id': 'b1', 'name': 'Test Shop', 'status': 'invited'},
            {'business_id': 'b2', 'name': 'Other Shop', 'status': 'joined'},
          ],
          'docs': <Object?>[],
          'postings': <Object?>[],
          'badge': {'has': false, 'steps': {'jobs': false}, 'need': {'jobs': 10}},
        };
      }
      return {'ok': true};
    });
    await _pump(tester, api, const AskodoxMyWorkStepsScreen());
    expect(find.byKey(const Key('askodoxMyWorkSteps')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyWorkStepsOfferRow-o1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyWorkStepsJob-j1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxMyWorkStepsLinkRow-b1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxMyWorkStepsOpen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxMyWorkStepsOffer-o1-take')));
    await tester.pumpAndSettle();
    expect(api.calls.keys.any((k) => k.startsWith('POST /api/me/work/orders/o1')), isTrue);
  });
}
