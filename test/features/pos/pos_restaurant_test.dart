import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/presentation/pos_restaurant_screens.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls.add('$method $path');
    bodies['$method $path'] = body;
    final out = reply(method, path, body);
    if (out is ApiFailure) return ApiError(out);
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

final _business = {
  'id': 'b1',
  'name': 'Hotel Annapurna',
  'registration_type': 'regular',
  'state_code': '36',
  'template': 'restaurant',
  'my_role': 'waiter',
  'permissions': ['view', 'tables'],
  'rules': <String, Object?>{},
};
final _menu = [
  {'id': 'p1', 'name': 'Chicken biryani', 'unit': 'plate', 'price_paise': 25200, 'rate_bp': 500, 'price_includes_tax': true,
    'category': 'taxable'},
];

Future<void> _pump(WidgetTester tester, _Api api, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => home),
        GoRoute(path: '/pos/b1/invoice/:iid', builder: (_, s) => Text('INVOICE ${s.pathParameters['iid']}')),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('waiter adds a dish with a note and sends the KOT; no Bill button for a waiter', (tester) async {
    var items = <Map<String, Object?>>[];
    Map<String, Object?> order() => {
          'id': 'o1', 'status': 'open', 'kind': 'dine_in', 'table_name': 'T1', 'items': items,
          'pending': items.where((i) => i['status'] == 'pending').length, 'item_count': items.length,
          'estimate_paise': 25200 * items.length, 'note': 'Estimate',
        };
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') return _business;
      if (path.endsWith('/products')) return {'products': _menu};
      if (path.endsWith('/orders/o1/items')) {
        final add = ((body as Map)['items'] as List).first as Map;
        items = [...items, {'id': 'i${items.length}', 'name': 'Chicken biryani', 'qty_milli': add['qty_milli'], 'note': add['note'],
          'status': 'pending', 'product_id': 'p1', 'price_paise': 25200}];
        return order();
      }
      if (path.endsWith('/orders/o1/kot')) {
        items = [for (final i in items) {...i, 'status': 'sent'}];
        return {...order(), 'kot': {'number': 1}};
      }
      if (path.endsWith('/orders/o1')) return order();
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxPosOrderScreen(businessId: 'b1', orderId: 'o1'));
    await tester.tap(find.byKey(const ValueKey('askodoxPosMenuItem-p1')));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '2');
    await tester.enterText(fields.at(1), 'less spicy');
    await tester.tap(find.byKey(const Key('askodoxPosOrderAddOk')));
    await tester.pumpAndSettle();
    final added = ((api.bodies['POST /api/pos/businesses/b1/orders/o1/items'] as Map)['items'] as List).single as Map;
    expect((added['qty_milli'], added['note']), (2000, 'less spicy'));
    expect('${added['client_txn_id']}', startsWith('pos-'), reason: 'resends never double an item');
    expect(find.textContaining('not sent'), findsOneWidget);
    expect(find.byKey(const Key('askodoxPosBillOrder')), findsNothing, reason: 'a waiter cannot bill');
    await tester.tap(find.byKey(const Key('askodoxPosSendKot')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('POST /api/pos/businesses/b1/orders/o1/kot'));
    expect(find.textContaining('in kitchen'), findsOneWidget);
  });

  testWidgets('kitchen screen marks a ticket ready', (tester) async {
    var status = 'new';
    final api = _Api((method, path, body) {
      if (path.endsWith('/kitchen')) {
        return {
          'kots': status == 'served'
              ? []
              : [
                  {'id': 'k1', 'number': 7, 'status': status, 'table_name': 'T3', 'kind': 'dine_in', 'items': [
                    {'name': 'Tea', 'qty_milli': 3000, 'note': '', 'status': 'sent'},
                  ]},
                ],
        };
      }
      if (path.endsWith('/kitchen/k1')) {
        status = '${(body as Map)['status']}';
        return <String, Object?>{};
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxPosKitchenScreen(businessId: 'b1', refreshEvery: Duration(hours: 1)));
    expect(find.textContaining('KOT 7 · T3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosKotReady-7')));
    await tester.pumpAndSettle();
    expect(status, 'ready');
    expect(find.textContaining('· ready'), findsOneWidget);
  });

  testWidgets('hold parks the cart as a draft (not an invoice) and resume brings it back', (tester) async {
    final drafts = <Map<String, Object?>>[];
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') return {..._business, 'my_role': 'cashier', 'permissions': ['view', 'sell', 'drafts']};
      if (path.endsWith('/products')) return {'products': _menu};
      if (path.endsWith('/device-series')) return {'prefix': 'HD1', 'fy': '2627', 'next_number': 1};
      if (method == 'POST' && path.endsWith('/drafts')) {
        drafts.add({'id': 'd1', ...(body as Map).cast<String, Object?>(), 'updated_at': '2026-10-24T10:00:00'});
        return {'id': 'd1'};
      }
      if (method == 'GET' && path.endsWith('/drafts')) return {'drafts': drafts};
      if (method == 'DELETE') {
        drafts.clear();
        return {'deleted': true};
      }
      return <String, Object?>{};
    });
    await _pump(tester, api, const AskodoxPosSaleScreen(businessId: 'b1'));
    await tester.enterText(find.byKey(const Key('askodoxPosCommand')), '2 biryani');
    await tester.tap(find.byKey(const Key('askodoxPosCommandGo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosConfirmYes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPosHold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsNothing);
    expect(api.calls.where((c) => c.endsWith('/invoices')), isEmpty, reason: 'a held bill is never issued');
    expect((drafts.single['payload'] as Map)['lines'], hasLength(1));
    await tester.tap(find.byKey(const Key('askodoxPosHeld')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosDraft-d1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsOneWidget);
    expect(find.text('₹504.00'), findsWidgets);
    expect(drafts, isEmpty, reason: 'a resumed hold is removed from the list');
  });
}
