import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/growth/data/growth_repository.dart';
import 'package:podx/features/guide/in_app_guide.dart';
import 'package:podx/features/selling/presentation/sell_sheet.dart';
import 'package:podx/shared/smart_guide/smart_guide_corrections.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Growth implements GrowthRepository {
  final drafts = <String>[];
  final published = <Map<String, Object?>>[];

  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async => const [];
  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async => null;
  @override
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId}) async => null;
  @override
  Future<AskodoxCatalogDraft?> draftListing(
      {String text = '', Map<String, Object?>? imageAnalysis, Map<String, Object?>? videoAnalysis}) async {
    drafts.add(text);
    return const AskodoxCatalogDraft(
        id: 7, draft: {'subject': 'Cotton saree', 'price': 1200, 'category_tag': 'FASHION'}, missing: ['stock']);
  }

  @override
  Future<int?> publishDraft(int draftId, Map<String, Object?> reviewed) async {
    published.add(reviewed);
    return 99;
  }

  @override
  Future<List<AskodoxLead>> leads() async => const [];
  @override
  Future<bool> expressInterest(String requestId) async => true;
}

Future<_Growth> _pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final growth = _Growth();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      growthRepositoryProvider.overrideWithValue(growth),
      askodoxGuideSpeakerProvider.overrideWithValue((text, language) async {}),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => showAskodoxSellSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return growth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Smart Guide corrections', () {
    const all = {
      AskodoxGuideFieldId.name,
      AskodoxGuideFieldId.price,
      AskodoxGuideFieldId.stock,
      AskodoxGuideFieldId.variant,
      AskodoxGuideFieldId.category,
      AskodoxGuideFieldId.unit,
    };

    test('English typed / spoken phrases map to the right fields', () {
      expect(askodoxParseCorrections('change the price to 300 and size 8, 9', all),
          {'price': '300', 'variant': '8, 9'});
      expect(askodoxParseCorrections('stock is 12; name Silk saree', all), {'stock': '12', 'name': 'Silk saree'});
      expect(askodoxParseCorrections('out of stock', all), isEmpty, reason: 'no field named -> no change');
      expect(askodoxParseCorrections('stock sold out', all), {'stock': '0'});
      expect(askodoxParseCorrections('₹1,250', all), {'price': '1250'});
    });

    test('Telugu phrases map to the right fields', () {
      expect(askodoxParseCorrections('ధర 450 చేయండి, స్టాక్ 5', all), {'price': '450', 'stock': '5'});
      expect(askodoxParseCorrections('సైజు 8 మరియు రంగు ఎరుపు', all)['variant'], isNotNull);
    });

    test('fields the form does not have are never touched', () {
      expect(askodoxParseCorrections('price 300 and terms none', {AskodoxGuideFieldId.price}), {'price': '300'});
    });

    test('diff keeps only real changes', () {
      final d = askodoxDiff({'price': '300', 'name': 'Saree'}, {'price': '300', 'name': 'Silk saree'});
      expect(d.single.field, 'name');
      expect(d.single.before, 'Saree');
    });
  });

  testWidgets('Sell something: draft only, corrections need a Yes, publish needs a Yes', (tester) async {
    final growth = await _pumpSheet(tester);
    expect(find.byKey(const Key('askodoxSellSheet')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('askodoxSellDescribe')), 'Cotton saree 6 m');
    await tester.tap(find.byKey(const Key('askodoxSellMakeDraft')));
    await tester.pumpAndSettle();
    expect(growth.drafts, ['Cotton saree 6 m']);
    expect(growth.published, isEmpty, reason: 'a draft is not a listing');
    TextField field(String id) => tester.widget<TextField>(find.byKey(ValueKey('askodoxSell-$id')));
    expect(field('price').controller!.text, '1200');
    expect(field('stock').controller!.text, isEmpty, reason: 'stock is never invented');

    // A correction shows old -> new; "No" keeps the draft exactly as it was.
    await tester.enterText(find.byKey(const Key('askodoxSmartGuideInput')), 'price 1100 and size free size');
    await tester.tap(find.byKey(const Key('askodoxSmartGuideSend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxGuideChange-price')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxGuideChange-variant')), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(field('price').controller!.text, '1200');
    expect(field('name').controller!.text, 'Cotton saree');

    await tester.tap(find.byKey(const Key('askodoxSmartGuideSend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxGuideApply')));
    await tester.pumpAndSettle();
    expect(field('price').controller!.text, '1100');
    expect(field('variant').controller!.text, 'free size');
    expect(field('name').controller!.text, 'Cotton saree', reason: 'other fields untouched');
    expect(field('category').controller!.text, 'FASHION');

    // Publish asks first; "Not yet" publishes nothing.
    await tester.ensureVisible(find.byKey(const Key('askodoxSellPublish')));
    await tester.tap(find.byKey(const Key('askodoxSellPublish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSellConfirm')), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(growth.published, isEmpty);

    await tester.tap(find.byKey(const Key('askodoxSellPublish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxSellConfirmYes')));
    await tester.pumpAndSettle();
    expect(growth.published.single['price'], 1100.0);
    expect(growth.published.single['variant'], 'free size');
    expect(growth.published.single['stock_status'], 'UNKNOWN');
    expect(find.byKey(const Key('askodoxSellSheet')), findsNothing, reason: 'closes after the confirmed publish');
  });

  test('stock typed -> stored status', () {
    expect(askodoxStockStatus(''), 'UNKNOWN');
    expect(askodoxStockStatus('0'), 'OUT_OF_STOCK');
    expect(askodoxStockStatus('12'), 'IN_STOCK');
  });
}
