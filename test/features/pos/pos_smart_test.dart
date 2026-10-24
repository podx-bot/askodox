import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/pos/domain/pos_commands.dart';
import 'package:podx/features/pos/domain/pos_pricing.dart';
import 'package:podx/features/pos/presentation/pos_catalogue_screens.dart';
import 'package:podx/features/pos/presentation/pos_sale_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final bodies = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    bodies['$method $path'] = body;
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


const _refs = [
  AskodoxPosItemRef(id: 'dal', name: 'Kandi pappu', nameTe: 'కంది పప్పు', unit: 'kg'),
  AskodoxPosItemRef(id: 'pappu', name: 'Pappu', unit: 'kg'),
  AskodoxPosItemRef(id: 'sam', name: 'Samosa', nameTe: 'సమోసా', unit: 'pcs'),
  AskodoxPosItemRef(id: 'cashew', name: 'Jeedipappu', unit: 'kg'),
  AskodoxPosItemRef(id: 'jag', name: 'Bellam', nameTe: 'బెల్లం', unit: 'kg'),
];

void main() {
  group('spoken order', () {
    test('one sentence becomes one line per item, either word order', () {
      expect(askodoxSplitPosOrder('10 kg kandi pappu, 60 samosas, jeedipappu 1 kilo, bellam 1 kilo'),
          ['10 kg kandi pappu', '60 samosas', 'jeedipappu 1 kilo', 'bellam 1 kilo']);
      expect(askodoxSplitPosOrder('10 kg kandi pappu 60 samosa pav kilo jeedipappu'),
          ['10 kg kandi pappu', '60 samosa', 'pav kilo jeedipappu']);
      expect(askodoxSplitPosOrder('add 2 kg chicken at 240 per kg'), ['add 2 kg chicken at 240 per kg'],
          reason: 'a price stays with its item');
      expect(askodoxSplitPosOrder('10 కిలోల కంది పప్పు మరియు 60 సమోసాలు'), ['10 కిలోల కంది పప్పు', '60 సమోసాలు']);
    });

    test('plurals, Telugu and the longest name match', () {
      final order = askodoxParsePosOrder('10 kg kandi pappu, 60 samosas, pav kilo jeedipappu, 1 kilo బెల్లం', _refs);
      expect([for (final o in order) (o.command.item?.id, o.command.qtyMilli)],
          [('dal', 10000), ('sam', 60000), ('cashew', 250), ('jag', 1000)]);
      expect(askodoxParsePosCommand('60 సమోసాలు', _refs).item?.id, 'sam');
      expect(askodoxParsePosCommand('10 కిలోల కంది పప్పు', _refs).item?.id, 'dal');
      expect(askodoxParsePosCommand('2 kg pappu', _refs).item?.id, 'pappu', reason: 'exact name');
    });

    test('rate by quantity follows the server rule', () {
      final p = {
        'price_paise': 18000,
        'tiers': [
          {'min_qty_milli': 250, 'price_paise': 17000},
          {'min_qty_milli': 10000, 'price_paise': 15000},
        ],
      };
      expect(askodoxTierPrice(p, 100), isNull);
      expect(askodoxTierPrice(p, 250), 17000);
      expect(askodoxTierPrice(p, 9999), 17000);
      expect(askodoxTierPrice(p, 10000), 15000);
      expect(askodoxMinQty({'min_qty_milli': 250}), 250);
      expect(askodoxMinQty({'min_qty_milli': null}), isNull);
    });
  });

  final products = [
    {'id': 'dal', 'name': 'Kandi pappu', 'unit': 'kg', 'price_paise': 18000, 'rate_bp': 0, 'category': 'exempt',
      'price_includes_tax': true, 'packs': <Object>[], 'min_qty_milli': 250,
      'tiers': [{'min_qty_milli': 10000, 'price_paise': 15000}]},
    {'id': 'sam', 'name': 'Samosa', 'unit': 'pcs', 'price_paise': 1500, 'rate_bp': 500, 'category': 'taxable',
      'price_includes_tax': true, 'packs': <Object>[], 'tiers': <Object>[]},
  ];

  Future<(_Api, List<String>)> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final spoken = <String>[];
    final api = _Api((method, path, body) {
      if (path == '/api/pos/businesses/b1') {
        return {'id': 'b1', 'registration_type': 'regular', 'state_code': '36', 'permissions': ['view', 'sell'],
          'rules': <String, Object?>{}};
      }
      if (path.endsWith('/products')) return {'products': products};
      if (path.endsWith('/device-series')) return {'prefix': 'SD1', 'fy': '2627', 'next_number': 1};
      if (path.endsWith('/invoices')) return {'id': 'inv1'};
      return <String, Object?>{};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't')),
        askodoxGuideSpeakerProvider.overrideWithValue((text, language) async => spoken.add(text)),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const AskodoxPosSaleScreen(businessId: 'b1')),
          GoRoute(path: '/pos/b1/invoice/:iid', builder: (_, s) => Text('INVOICE ${s.pathParameters['iid']}')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    return (api, spoken);
  }

  testWidgets('items show as picture tiles', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('askodoxPosProducts')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPosProduct-dal')), findsOneWidget);
    expect(find.text('K'), findsOneWidget, reason: 'no photo: the first letter');
    expect(find.textContaining('₹180.00/kg'), findsOneWidget);
  });

  testWidgets('a spoken order is reviewed, read back, and added with the 10 kg rate', (tester) async {
    final (api, spoken) = await pump(tester);
    await tester.enterText(find.byKey(const Key('askodoxPosCommand')), '10 kg kandi pappu, 60 samosas, 100 g kandi pappu, 2 kg sugar');
    await tester.tap(find.byKey(const Key('askodoxPosCommandGo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosMultiReview')), findsOneWidget);
    expect(find.textContaining('₹150.00/kg'), findsOneWidget, reason: '10 kg uses the 10 kg rate');
    expect(find.textContaining('quantity rate'), findsOneWidget);
    expect(find.textContaining('Least is'), findsOneWidget, reason: '100 g is below the least quantity');
    expect(find.text('Item not found'), findsOneWidget, reason: 'sugar is not an item');
    expect(find.textContaining('₹2,400.00'), findsOneWidget, reason: '10 x 150 + 60 x 15');
    await tester.tap(find.byKey(const Key('askodoxPosMultiRead')));
    await tester.pump();
    expect(spoken.single, contains('Total 2,400.00 rupees'));
    await tester.tap(find.byKey(const Key('askodoxPosMultiAdd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosCartLine-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPosCartLine-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxPosCartLine-2')), findsNothing);
    expect(find.textContaining('10 kg × ₹150.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPosPay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosAddPayment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxPosIssue')));
    await tester.pumpAndSettle();
    final lines = (api.bodies['POST /api/pos/businesses/b1/invoices'] as Map)['lines'] as List;
    expect(lines.first, {'product_id': 'dal', 'qty_milli': 10000},
        reason: 'no price sent: the server applies the same quantity rate');
  });

  testWidgets('item details ask "one rate or rates by quantity" and save them per unit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _Api((method, path, body) {
      if (path.endsWith('/products/dal')) {
        return {'id': 'dal', 'name': 'Kandi pappu', 'unit': 'kg', 'price_paise': 18000, 'tiers': <Object>[], 'attributes': <String, Object?>{}};
      }
      if (path.endsWith('/catalogue')) return {'attributes': <Object>[]};
      return <String, Object?>{};
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
      child: const MaterialApp(home: AskodoxPosItemDetailsScreen(businessId: 'b1', productId: 'dal')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPosRatesCard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPosTieredRate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxPosTierQty-0')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('askodoxPosTierTotal-0')), matching: find.byType(TextField)), '45');
    await tester.tap(find.byKey(const Key('askodoxPosTierAdd')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('askodoxPosTierQty-1')), matching: find.byType(TextField)), '10');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('askodoxPosTierTotal-1')), matching: find.byType(TextField)), '1500');
    await tester.enterText(find.descendant(of: find.byKey(const Key('askodoxPosMinQty')), matching: find.byType(TextField)), '0.25');
    await tester.tap(find.byKey(const Key('askodoxPosRatesSave')));
    await tester.pumpAndSettle();
    expect(api.bodies['PUT /api/pos/businesses/b1/products/dal/pricing'], {
      'tiers': [
        {'min_qty_milli': 250, 'price_paise': 18000},
        {'min_qty_milli': 10000, 'price_paise': 15000},
      ],
      'min_qty_milli': 250,
    }, reason: '¼ kg for ₹45 = ₹180/kg; 10 kg for ₹1500 = ₹150/kg');
  });
}
