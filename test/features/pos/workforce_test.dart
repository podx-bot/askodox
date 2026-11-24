
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/workforce_screens.dart';

/// Owner plan 2026-11-24 steps 3-6: worker card (18+), authority finds + invites (no phone on cards), customer books.
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

const _types = [
  {'key': 'delivery', 'en': 'Delivery', 'te': 'డెలివరీ'},
  {'key': 'cook', 'en': 'Cook', 'te': 'వంటవాళ్ళు'},
];

void main() {
  testWidgets('worker: card needs 18+ and a work type, then the overview', (tester) async {
    var saved = false;
    final api = _Api((method, path, body) {
      if (path == '/api/me/work' && method == 'PUT') {
        saved = true;
        return {'ok': true};
      }
      if (path == '/api/me/work') {
        return saved
            ? {
                'worker': {'name': 'Laxmi', 'work_types': [_types.first], 'jobs': 0, 'free_when': ['day'], 'km': 10},
                'badge': {'has': false, 'steps': {'days': false, 'jobs': false}, 'need': {'days': 90, 'jobs': 50}},
                'links': [
                  {'business_id': 'b1', 'name': 'Sai Travels', 'status': 'invited', 'asks': 'licence'},
                ],
                'docs': [],
                'postings': [],
                'reject_note': 'note',
                'work_types': _types,
              }
            : {'worker': null, 'links': [], 'docs': [], 'postings': [], 'work_types': _types};
      }
      if (path == '/api/me/work/orders') return {'offers': [], 'mine': []};
      return {'ok': true};
    });
    await _pump(tester, api, const AskodoxMyWorkScreen());
    await tester.enterText(find.byKey(const Key('askodoxWorkName')), 'Laxmi');
    await tester.tap(find.byKey(const ValueKey('askodoxWorkType-delivery')));
    await tester.pump();
    final save = tester.widget<FilledButton>(find.byKey(const Key('askodoxWorkSave')));
    expect(save.onPressed, isNull, reason: '18+ is mandatory');
    await tester.ensureVisible(find.byKey(const Key('askodoxWorkAdult')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxWorkAdult')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('askodoxWorkSave')));
    await tester.tap(find.byKey(const Key('askodoxWorkSave')));
    await tester.pump(const Duration(milliseconds: 50));
    final sent = api.calls['PUT /api/me/work'] as Map;
    expect(sent['adult'], isTrue);
    expect(sent['work_types'], ['delivery']);
    expect(find.byKey(const Key('askodoxWorkCard')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('askodoxWorkJoin-b1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('askodoxWorkJoin-b1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/me/work/links/b1'], {'accept': true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('authority: cards without phone numbers, invite', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/workforce/cards')) {
        return {
          'cards': [
            {'user': 'u9', 'name': 'Raju', 'work_types': [_types.first], 'town': 'Vuyyuru', 'jobs': 3, 'rating': 4.6},
          ],
        };
      }
      if (path.endsWith('/workforce/orders')) return {'orders': []};
      if (path.endsWith('/workforce')) {
        return {
          'authority': {'kind': 'gst', 'gstin': '37AAAAA0000A1Z5', 'address': 'Vuyyuru', 'agency': 0, 'assigned_money': 'cash'},
          'can_browse': true,
          'work_types': _types,
          'team': [],
          'adding_note': 'note',
          'udyam_help': 'free',
        };
      }
      return {'invited': true};
    });
    await _pump(tester, api, const AskodoxAuthorityTeamScreen(businessId: 's1'));
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxWorkerCard-u9')), findsOneWidget);
    expect(find.textContaining('94000'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxWorkerInvite-u9')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.calls['POST /api/pos/businesses/s1/workforce/invite'], {'worker': 'u9', 'asks': ''});
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer: work type -> businesses with prices -> book', (tester) async {
    final api = _Api((method, path, body) {
      if (path == '/api/hire/work-types') return {'work_types': _types};
      if (path == '/api/hire/options') {
        return {
          'options': [
            {'kind': 'authority', 'business_id': 'b1', 'name': 'Sai Travels', 'address': 'Vuyyuru', 'price_paise': 5000, 'team': 4},
          ],
        };
      }
      if (path == '/api/hire/orders' && method == 'GET') return {'orders': []};
      return {'id': 'o1'};
    });
    await _pump(tester, api, const AskodoxHireScreen());
    await tester.tap(find.byKey(const ValueKey('askodoxHireType-delivery')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('₹50'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxHireBook-b1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect((api.calls['POST /api/hire/orders'] as Map)['business_id'], 'b1');
    expect(tester.takeException(), isNull);
  });
}
