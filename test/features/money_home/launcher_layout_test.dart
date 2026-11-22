import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/money_home/launcher_layout.dart';
import 'package:podx/features/money_home/money_home_pages.dart';
import 'package:podx/features/money_home/payment_voice_sheet.dart';

List<String> ids(AskodoxLaunchLayout l) => [for (final e in l.entries) e.id];

void main() {
  const base = AskodoxLaunchLayout([
    AskodoxLaunchEntry.page('a'),
    AskodoxLaunchEntry.page('b'),
    AskodoxLaunchEntry.folder('f1', 'Mine', ['c', 'd']),
    AskodoxLaunchEntry.page('e'),
  ]);

  group('the person\'s own screen (phone style)', () {
    test('drop a page on a page = a new folder where the target was; on a folder = into it', () {
      final made = base.combine('e', 'a', newFolderId: 'n1', name: 'New');
      expect(ids(made), ['f:n1', 'b', 'f:f1']);
      expect(made.entry('f:n1')!.children, ['a', 'e']);
      final into = base.combine('b', 'f:f1', newFolderId: 'x', name: 'x');
      expect(into.entry('f:f1')!.children, ['c', 'd', 'b']);
      expect(ids(into), ['a', 'f:f1', 'e']);
    });

    test('a folder is never put inside a folder (it moves next to it)', () {
      final l = base.combine('f:f1', 'a', newFolderId: 'x', name: 'x');
      expect(ids(l), ['f:f1', 'a', 'b', 'e']);
      expect(l.entries.where((e) => e.isFolder).length, 1);
    });

    test('move, take out (a one-page folder dissolves), add to folder, new folder, rename', () {
      expect(ids(base.move('e', 0)), ['e', 'a', 'b', 'f:f1']);
      final out = base.takeOut('c');
      expect(out.entry('f:f1'), isNull, reason: 'one page left = no folder');
      expect(ids(out), ['a', 'b', 'd', 'c', 'e']);
      final added = base.addToFolder('f1', 'a');
      expect(added.entry('f:f1')!.children, ['c', 'd', 'a']);
      expect(ids(added), ['b', 'f:f1', 'e']);
      final grouped = base.newFolder(['b', 'e'], folderId: 'g', name: 'Two');
      expect(ids(grouped), ['a', 'f:g', 'f:f1']);
      expect(grouped.rename('g', '  Shop  ').entry('f:g')!.name, 'Shop');
      expect(grouped.rename('g', '   ').entry('f:g')!.name, 'Two', reason: 'an empty name keeps the old one');
    });

    test('hide never deletes: hidden pages come back; reset = the shipped screen', () {
      final hid = base.hide('d');
      expect(hid.hidden, {'d'});
      expect(hid.placed.contains('d'), isFalse);
      expect(hid.entry('f:f1'), isNull, reason: 'c is left alone, so the folder becomes c');
      final back = hid.restore('d');
      expect(back.hidden, isEmpty);
      expect(back.placed, containsAll(['a', 'b', 'c', 'd', 'e']));
    });

    test('fitTo: unknown pages skipped, new pages added at the end, hidden stay hidden, each page once', () {
      const messy = AskodoxLaunchLayout([
        AskodoxLaunchEntry.page('a'),
        AskodoxLaunchEntry.page('gone'),
        AskodoxLaunchEntry.folder('f', 'F', ['b', 'gone2', 'a']),
      ], hidden: {'c', 'gone3'});
      final fit = messy.fitTo(['a', 'b', 'c', 'new']);
      expect(ids(fit), ['a', 'b', 'new'], reason: 'folder f lost a duplicate and an unknown page -> one page -> dissolved');
      expect(fit.hidden, {'c'});
    });

    test('saved and read back the same; a broken saved text is ignored', () {
      final l = base.hide('e').rename('f1', 'Bills');
      final again = AskodoxLaunchLayout.decode(l.encode())!;
      expect(ids(again), ids(l));
      expect(again.hidden, l.hidden);
      expect(again.entry('f:f1')!.name, 'Bills');
      expect(AskodoxLaunchLayout.decode('not json'), isNull);
      expect(AskodoxLaunchLayout.decode(null), isNull);
    });

    test('screens: the first holds fewer (the card), the rest the full grid, never an empty screen', () {
      final entries = [for (var i = 0; i < 23; i++) AskodoxLaunchEntry.page('p$i')];
      final screens = askodoxLaunchScreens(entries, 8, 12);
      expect([for (final s in screens) s.length], [8, 12, 3]);
      expect(askodoxLaunchScreenStart(2, 8, 12), 20);
      expect(askodoxLaunchScreens(const [], 8, 12).length, 1);
    });
  });

  group('the shipped screens', () {
    test('Buyer: every shipped page exists, ids unique, keys kept for the registry', () {
      final known = {for (final p in askodoxBuyerPages) p.id};
      expect(known.length, askodoxBuyerPages.length);
      expect(askodoxBuyerShippedLayout().placed, known, reason: 'every Buyer page is on the shipped screen');
      expect(askodoxBuyerPages.map((p) => p.keyName), containsAll(['askodoxShoppingOrderCode', 'askodoxShoppingFollowing']));
      // Buyer pages never open a shop's tools.
      expect(askodoxBuyerPages.where((p) => (p.route ?? '').contains('/biz/') || (p.route ?? '').startsWith('/pos/')), isEmpty);
    });

    test('Seller: a hotel gets tables + kitchen, a kirana does not; staff see only what their role allows', () {
      final hotel = askodoxSellerPages('h1', {'role': 'owner', 'template': 'restaurant'}).map((p) => p.id).toSet();
      final kirana = askodoxSellerPages('k1', {'role': 'owner', 'template': 'kirana'}).map((p) => p.id).toSet();
      expect(hotel, containsAll(['s.tables', 's.kitchen', 's.voice', 's.bill']));
      expect(kirana.contains('s.tables'), isFalse);
      expect(kirana.contains('s.kitchen'), isFalse);
      final staff = askodoxSellerPages('k1', {'my_role': 'cashier', 'template': 'kirana', 'permissions': ['sell']})
          .map((p) => p.id)
          .toSet();
      expect(staff, contains('s.bill'));
      expect(staff.contains('s.reports'), isFalse);
      expect(staff.contains('s.details'), isFalse);
      // Every Seller page opens THIS shop's own screen.
      for (final p in askodoxSellerPages('k1', {'role': 'owner', 'template': 'kirana'})) {
        if (p.route != null && p.route!.contains('/k1')) continue;
        expect(p.route == null || p.route == '/me/payment-methods' || p.route!.startsWith('/me/business/k1'), isTrue,
            reason: '${p.id} -> ${p.route}');
      }
      final shipped = askodoxSellerShippedLayout().placed;
      final all = askodoxSellerPages('h1', {'role': 'owner', 'template': 'restaurant'}).map((p) => p.id).toSet();
      expect(all.difference(shipped), isEmpty, reason: 'every Seller page has a place on the shipped screen');
    });
  });

  group('Payment voice kinds', () {
    test('defaults: all on except money sent (follows the older switch); fake warning always on', () {
      final d = askodoxVoiceKindsWithDefaults(const {}, askodoxPersonalVoiceKinds);
      expect(d['out'], isFalse);
      expect(d['bill'], isTrue);
      expect(d['fake'], isTrue);
      expect(askodoxVoiceKindsWithDefaults(const {}, askodoxPersonalVoiceKinds, announceDebits: true)['out'], isTrue);
      final saved = askodoxVoiceKindsWithDefaults(const {'bill': false, 'fake': false}, askodoxPersonalVoiceKinds);
      expect(saved['bill'], isFalse);
      expect(saved['fake'], isTrue, reason: 'never switched off');
      expect(askodoxPersonalVoiceKinds.length, 11);
      expect(askodoxShopVoiceKinds.map((k) => k.id), ['in', 'refund', 'request', 'fake']);
    });

    test('words for money that did NOT come never say "received"', () {
      for (final k in askodoxPersonalVoiceKinds.where((k) => k.id != 'in')) {
        expect(k.sampleTe.contains('అందింది'), isFalse, reason: k.id);
        expect(k.sampleEn.toLowerCase().contains('received'), isFalse, reason: k.id);
      }
    });
  });
}
