import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/table_watch/table_watch_logic.dart';
import 'package:podx/features/table_watch/table_watch_screen.dart';

/// Owner 2026-11-27: table watch from the table QR (made-up data only).
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String>[];

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls.add('$method $path');
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('GET', path.split('?').first, null);
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

void main() {
  test('state words, minutes and the order of the tables', () {
    expect(askodoxTableWatchText('empty', false), 'Free');
    expect(askodoxTableWatchText('unseen', true), 'వెళ్ళి పలకరించాలి');
    expect(askodoxTableWatchText('something new', false), 'Free');
    for (final state in askodoxTableWatchStates) {
      expect(askodoxTableWatchText(state, true).contains('లేదు'), isFalse, reason: state);
    }
    expect(askodoxTableWatchTime('empty', 30), '');
    expect(askodoxTableWatchTime('seated', 6), '06m');
    expect(askodoxTableWatchTime('eating', 65), '1h 05m');
    expect(askodoxTableWatchTime('waiting', -3), '00m');
    expect(askodoxTableWatchAlert('T5', 5, false), 'Table T5 · seated 5 min. Go and take the order.');
    final ordered = askodoxTableWatchOrder([
      {'id': 't1', 'state': 'empty', 'minutes': 0},
      {'id': 't2', 'state': 'seated', 'minutes': 2},
      {'id': 't3', 'state': 'waiting', 'minutes': 6},
      {'id': 't4', 'state': 'eating', 'minutes': 25},
      {'id': 't5', 'state': 'unseen', 'minutes': 5},
      {'id': 't6', 'state': 'empty', 'minutes': 0},
      {'id': 't7', 'state': 'waiting', 'minutes': 14},
    ]);
    expect([for (final t in ordered) t['id']], ['t5', 't7', 't3', 't2', 't4', 't1', 't6']);
  });

  testWidgets('the page: unseen on top with its alert; "I am going" and "They left" call the shop', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var seen = false;
    final api = _Api((method, path, body) {
      if (method == 'POST') {
        if (path.endsWith('/seen')) seen = true;
        return {'ok': true, 'changed': true};
      }
      return {
        'now': '2026-11-27T06:05:00+00:00',
        'unseen_minutes': 5,
        'counts': {'empty': 1, 'seated': seen ? 1 : 0, 'unseen': seen ? 0 : 1, 'waiting': 1, 'eating': 0},
        'tables': [
          {'id': 't1', 'name': 'T1', 'state': 'empty', 'minutes': 0},
          {'id': 't2', 'name': 'T2', 'state': 'waiting', 'minutes': 6, 'pos_order_id': 'ord1'},
          {'id': 't5', 'name': 'T5', 'state': seen ? 'seated' : 'unseen', 'minutes': 5, 'seen': seen},
        ],
        'alerts': seen
            ? <Object?>[]
            : [
                {'table_id': 't5', 'table_name': 'T5', 'minutes': 5},
              ],
      };
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxTableWatchScreen(businessId: 'b1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('askodoxTableWatch')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('askodoxTableWatchBusy'))).data, '2 / 3');
    expect(find.byKey(const ValueKey('askodoxTableWatchAlert-t5')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('askodoxTableWatchState-t5'))).data, 'Go to them');
    expect(tester.widget<Text>(find.byKey(const ValueKey('askodoxTableWatchTime-t2'))).data, '06m');
    expect(find.byKey(const ValueKey('askodoxTableWatchTime-t1')), findsNothing);
    // The unseen table is the first tile.
    final first = tester.getTopLeft(find.byKey(const ValueKey('askodoxTableWatchTable-t5')));
    final free = tester.getTopLeft(find.byKey(const ValueKey('askodoxTableWatchTable-t1')));
    expect(first.dy < free.dy || (first.dy == free.dy && first.dx < free.dx), isTrue);

    await tester.tap(find.byKey(const ValueKey('askodoxTableWatchTable-t5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxTableWatchTakeOrder')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxTableWatchSeen')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /api/pos/businesses/b1/desk/table-watch/t5/seen'));
    expect(find.byKey(const ValueKey('askodoxTableWatchAlert-t5')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('askodoxTableWatchState-t5'))).data, 'Seated');

    await tester.tap(find.byKey(const ValueKey('askodoxTableWatchTable-t5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxTableWatchSeen')), findsNothing); // already attended
    await tester.tap(find.byKey(const Key('askodoxTableWatchFree')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /api/pos/businesses/b1/desk/table-watch/t5/free'));

    // The open page reads the tables again by itself.
    final before = api.calls.where((c) => c.startsWith('GET')).length;
    await tester.pump(askodoxTableWatchRefresh);
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('GET')).length, before + 1);
  });
}
