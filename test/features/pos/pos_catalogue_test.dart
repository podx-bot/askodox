import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/features/pos/presentation/pos_catalogue_screens.dart';
import 'package:podx/features/selling/data/catalogue_repository.dart';

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


final _attrs = [
  {'key': 'fabric', 'label': {'en': 'Fabric', 'te': 'బట్ట'}, 'kind': 'choice', 'options': ['Cotton', 'Silk'], 'required': true,
    'group': 'Details', 'multi': false},
  {'key': 'mrp', 'label': {'en': 'MRP', 'te': 'MRP'}, 'kind': 'number', 'unit': '₹', 'options': <String>[], 'required': false,
    'group': 'Pricing'},
];

Future<void> _pump(WidgetTester tester, _Api api, String location, {bool smartFill = false}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/start', routes: [
    GoRoute(path: '/start', builder: (context, _) => Scaffold(
        body: TextButton(onPressed: () => context.push(location), child: const Text('GO')))),
    GoRoute(path: '/pos/:id/catalogue', builder: (_, s) => AskodoxPosCatalogueScreen(businessId: s.pathParameters['id']!)),
    GoRoute(path: '/pos/:id/item/:pid',
        builder: (_, s) => AskodoxPosItemDetailsScreen(businessId: s.pathParameters['id']!, productId: s.pathParameters['pid']!)),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
      askodoxCatalogueRepositoryProvider.overrideWithValue(AskodoxCatalogueRepository(api, authToken: smartFill ? 't' : null)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('GO'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ready list: tick, size, OWN price (+ GST % when registered) -> import', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/catalogue/import')) return {'added': [{'id': 'p1', 'name': 'Toor dal 1 kg'}], 'skipped': <Object>[]};
      if (path == '/api/pos/businesses/b1') return {'id': 'b1', 'permissions': ['view', 'products', 'settings']};
      return {
        'template_key': 'grocery', 'registration_type': 'regular',
        'choices': [{'key': 'grocery', 'name': {'en': 'Grocery'}}],
        'attributes': _attrs,
        'categories': [
          {'key': 'dals', 'name': {'en': 'Dals'}, 'items': [
            {'key': 'dals.toor', 'name': {'en': 'Toor dal', 'te': 'కంది పప్పు'}, 'sizes': ['500 g', '1 kg'], 'pos_unit': 'kg'},
          ]},
        ],
      };
    });
    await _pump(tester, api, '/pos/b1/catalogue');
    await tester.tap(find.text('Dals'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosCataloguePick-dals.toor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosCatalogueSize-dals.toor-1 kg')));
    await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('askodoxPosCataloguePrice-dals.toor')), matching: find.byType(TextField)), '160');
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxPosCatalogueAdd')));
    await tester.pumpAndSettle();
    expect(api.calls['POST /api/pos/businesses/b1/catalogue/import'], isNull, reason: 'registered: GST % is the owner\'s choice');
    expect(find.text('Choose the GST % for every ticked item.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosCatalogueRate-dals.toor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5%').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosCatalogueAdd')));
    await tester.pumpAndSettle();
    expect(api.calls['POST /api/pos/businesses/b1/catalogue/import'], {
      'items': [{'item_key': 'dals.toor', 'size': '1 kg', 'price_paise': 16000, 'rate_bp': 500}],
    });
  });

  testWidgets('item details: missing required marked, guide explains, save sends details + online price', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/products/p1')) {
        return {'id': 'p1', 'name': 'Cotton shirt', 'unit': 'pcs', 'price_paise': 49900, 'attributes': <String, Object?>{},
          'online_price_paise': null};
      }
      if (path.endsWith('/attributes')) return {'attributes': {'fabric': 'Cotton'}, 'missing': <Object>[]};
      if (path.endsWith('/online-price')) return {'id': 'p1'};
      return {'template_key': 'fashion', 'attributes': _attrs, 'categories': <Object>[]};
    });
    await _pump(tester, api, '/pos/b1/item/p1');
    expect(find.byKey(const Key('askodoxPosItemMissing')), findsOneWidget);
    expect(find.text('Needed'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPosAttrGuide-fabric')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxFieldGuideSheet')), findsOneWidget);
    expect(find.textContaining('Pick the one that is true'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPosAttrOption-fabric-Cotton')));
    await tester.tap(find.byKey(const Key('askodoxPosSamePrice')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byKey(const Key('askodoxPosOnlinePrice')), matching: find.byType(TextField)), '529');
    await tester.tap(find.byKey(const Key('askodoxPosItemDetailsSave')));
    await tester.pumpAndSettle();
    expect(api.calls['PUT /api/pos/businesses/b1/products/p1/attributes'], {'values': {'fabric': 'Cotton'}});
    expect(api.calls['PUT /api/pos/businesses/b1/products/p1/online-price'], {'online_price_paise': 52900});
    expect(find.byKey(const Key('askodoxPosItemMissing')), findsNothing);
  });

  testWidgets('item details pre-fill empty boxes from the item name and show examples inside boxes', (tester) async {
    final api = _Api((method, path, body) {
      if (path.endsWith('/products/p1')) {
        return {'id': 'p1', 'name': 'Silk saree', 'unit': 'pcs', 'price_paise': 99900, 'attributes': <String, Object?>{},
          'online_price_paise': null};
      }
      if (path.endsWith('/smart-fill')) {
        final text = '${(body as Map)['text']}';
        return {'values': text.contains('1200') ? {'mrp': 1200} : {'fabric': 'Silk'}, 'price': null};
      }
      return {'template_key': 'fashion', 'attributes': _attrs, 'categories': <Object>[]};
    });
    await _pump(tester, api, '/pos/b1/item/p1', smartFill: true);
    expect(api.calls['POST /api/catalog/templates/fashion/smart-fill'], {'text': 'Silk saree'});
    expect(find.byKey(const ValueKey('askodoxPosAttrPrefilled-fabric')), findsOneWidget, reason: 'filled from the name');
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('askodoxPosAttrOption-fabric-Silk'))).selected, isTrue);
    expect(find.textContaining('e.g.'), findsWidgets, reason: 'examples sit inside the boxes');
    await tester.enterText(find.descendant(of: find.byKey(const Key('askodoxPosDescribe')), matching: find.byType(TextField)),
        'MRP 1200');
    await tester.tap(find.byKey(const Key('askodoxPosSmartFill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosAttrPrefilled-mrp')), findsOneWidget);
    expect(find.text('1200'), findsOneWidget);
  });
}
