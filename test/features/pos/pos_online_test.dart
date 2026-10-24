import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_common.dart';
import 'package:podx/features/pos/presentation/pos_records_screens.dart';

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


void main() {
  test('an item follows the shop default unless it has its own choice', () {
    expect(askodoxPosChannel({'channel': null}, 'both'), 'both');
    expect(askodoxPosChannel({'channel': 'pos'}, 'both'), 'pos');
    expect(askodoxPosChannel({}, null), 'pos');
    expect(askodoxPosChannel({'channel': 'odd'}, 'odd'), 'pos');
  });

  testWidgets('items: shop default segmented button + one item set to Online', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var online = <String, Object?>{'default': 'pos', 'items': [
      {'product_id': 'soap', 'state': 'not_published', 'reasons': <Object>[]},
    ]};
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') return {'id': 'b1', 'permissions': ['view', 'products', 'settings']};
      if (path.endsWith('/products')) {
        return {'products': [
          {'id': 'soap', 'name': 'Soap', 'unit': 'pcs', 'price_paise': 4000, 'rate_bp': 1800, 'channel': null},
        ]};
      }
      if (path.endsWith('/online') && method == 'PUT') {
        online = {'default': (body as Map)['channel'] ?? 'pos', 'items': [
          {'product_id': 'soap', 'state': 'live', 'reasons': <Object>[]},
        ]};
      }
      return online;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: const MaterialApp(home: AskodoxPosItemsScreen(businessId: 'b1')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosOnlineCard')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('askodoxPosItemChannel-soap')), matching: find.text('POS only')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosItemChannel-soap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosChannelPick-online')));
    await tester.pumpAndSettle();
    expect(api.calls['PUT /api/pos/businesses/b1/products/soap/online'], {'channel': 'online'});
    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();
    expect(api.calls['PUT /api/pos/businesses/b1/online'], {'channel': 'both'});
  });
}
