import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide/screen_help.dart';
import 'package:podx/features/money_home/money_home_pages.dart';
import 'package:podx/features/pos/domain/shop_page_names.dart';
import 'package:podx/features/pos/presentation/pos_shop_tool_screen.dart';
import 'package:podx/shared/widgets/askodox_tile_grid.dart';
import 'package:podx/shared/widgets/chat_pins.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner 2026-11-24: "New bill" and "Counter bill" were two pins above the chat that opened the SAME counter page.
// One page = one name everywhere, and one pin.
void main() {
  test('a shop page is found the same way from every button', () {
    expect(askodoxShopPageName('/pos/s1/sale'), ('Counter bill', 'కౌంటర్ బిల్లు'));
    expect(askodoxShopPageName('/my-shop/sale'), ('Counter bill', 'కౌంటర్ బిల్లు'));
    expect(askodoxShopPageName('/my-shop/sale?say=2%20biryani'), ('Counter bill', 'కౌంటర్ బిల్లు'));
    expect(askodoxShopPageName('/desk/s1'), askodoxShopPageNames['/desk/<id>']);
    expect(askodoxShopPageName('/desk/s1/qr'), isNull, reason: 'another page');
    expect(askodoxShopPageName('/me/bills'), isNull);
    expect(askodoxSamePage('/my-shop/sale', '/pos/s1/sale'), isTrue);
    expect(askodoxSamePage('/pos/s1/sale', '/pos/s1/sale'), isTrue);
    expect(askodoxSamePage('/pos/s1/sale', '/pos/s2/sale'), isFalse, reason: 'two shops keep two counters');
    expect(askodoxSamePage('/pos/s1/sale', '/me/business/s1/bill'), isFalse, reason: 'the 3-step bill is another page');
    expect(askodoxSamePage('/me/dues', '/me/dues'), isTrue);
    expect(askodoxSamePage('/me/dues', '/me/bills'), isFalse);
  });

  test('chat / pin tools, Seller Money pages and the screen guide use the one name', () {
    for (final e in askodoxShopTools.entries) {
      expect((e.value.$2, e.value.$3), askodoxShopPageNames[e.value.$1], reason: 'tool ${e.key}');
    }
    for (final template in ['restaurant', 'kirana']) {
      for (final page in askodoxSellerPages('s1', {'role': 'owner', 'template': template})) {
        final name = page.route == null ? null : askodoxShopPageName(page.route!);
        if (name != null) expect((page.en, page.te), name, reason: '${page.id} on the Seller Money page');
      }
    }
    for (final e in askodoxShopPageNames.entries) {
      final help = askodoxScreenHelpFor(e.key.replaceAll('<id>', ':id'));
      if (help != null) expect((help.titleEn, help.titleTe), e.value, reason: 'guide title of ${e.key}');
    }
  });

  test('saved pins: one per page, each with the page name, first one keeps its place', () {
    final pins = askodoxOnePinPerPage(const [
      AskodoxChatPin(id: 'sale', route: '/pos/s1/sale', en: 'New bill', te: 'New bill'),
      AskodoxChatPin(id: 'desk', route: '/desk/s1', en: 'Orders desk', te: 'Orders desk'),
      AskodoxChatPin(id: 'money:s1:s.counter', route: '/pos/s1/sale', en: 'Counter billing', te: 'కౌంటర్ బిల్లింగ్'),
      AskodoxChatPin(id: 'b.bills', route: '/me/bills', en: 'My bills', te: 'నా బిల్లులు'),
    ]);
    expect(pins.map((p) => p.id), ['sale', 'desk', 'b.bills']);
    expect(pins.first.label(false), 'Counter bill');
    expect(pins.first.label(true), 'కౌంటర్ బిల్లు');
    expect(pins[1].label(false), askodoxShopPageNames['/desk/<id>']!.$1);
    expect(pins.last.label(false), 'My bills', reason: 'other pages keep the name they were pinned with');
  });

  testWidgets('pinning a page already pinned from another button never adds a second pin', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AskodoxTileGrid(tiles: [
              AskodoxTile(id: 'sale', icon: Icons.receipt_long, title: 'Counter bill', pinRoute: '/pos/1/sale', onTap: () {}),
              AskodoxTile(id: 'money:1:s.counter', icon: Icons.point_of_sale, title: 'Counter bill', pinRoute: '/pos/1/sale', onTap: () {}),
            ]),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('askodoxPin-sale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxChatPinAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('askodoxPin-money:1:s.counter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxChatPinAdd')), findsNothing, reason: 'already pinned: only move / remove');
    expect(find.byKey(const Key('askodoxChatPinRemove')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(AskodoxTileGrid)));
    expect(container.read(askodoxChatPinsProvider).pins.map((p) => p.id), ['sale']);
  });
}
