import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart' show askodoxAppActionRoute;
import 'package:podx/features/pos/domain/pos_commands.dart';
import 'package:podx/features/pos/domain/pos_item_icons.dart';
import 'package:podx/features/pos/domain/pos_staff_tools.dart';
import 'package:podx/features/pos/presentation/pos_dues_screen.dart';

void main() {
  test('an item without a photo gets a picture that fits its name, in any language (owner 2026-11-20)', () {
    expect(askodoxItemIcon('Apollo Fish'), '🐟');
    expect(askodoxItemIcon('Apollo Chicken'), '🍗');
    expect(askodoxItemIcon('Apollo Panneer'), '🧀');
    expect(askodoxItemIcon('Chicken Biryani'), '🍛', reason: 'the dish before its main ingredient');
    expect(askodoxItemIcon('Boiled Egg'), '🥚');
    expect(askodoxItemIcon('టీ'), '🍵');
    expect(askodoxItemIcon('కంది పప్పు'), '🫘');
    expect(askodoxItemIcon('Penne pasta'), isNot('🖊️'), reason: 'short words match only whole words');
    expect(askodoxItemIcon('Xyz'), '🛍️');
  });

  test('a menu number picks the item, by typing or speaking ("20 నంబర్ 2")', () {
    const items = [
      AskodoxPosItemRef(id: 'a', name: 'Apollo Fish', unit: 'pcs', itemNo: 20),
      AskodoxPosItemRef(id: 'b', name: 'Apollo Chicken', unit: 'pcs', itemNo: 21),
    ];
    final te = askodoxParsePosCommand('20 నంబర్ 2', items);
    expect(te.item?.id, 'a');
    expect(te.qtyMilli, 2000);
    final en = askodoxParsePosCommand('number 21', items);
    expect(en.item?.id, 'b');
    expect(en.qtyMilli, 1000);
    final order = askodoxParsePosOrder('#20 2, number 21 3', items);
    expect(order.map((o) => o.command.item?.id), ['a', 'b']);
  });

  test('a new bill asked in chat opens straight away, with the spoken items when there are any', () {
    expect(askodoxAppActionRoute('/my-shop/sale', 'క్యాష్ బిల్ వేయి'), '/my-shop/sale');
    expect(askodoxAppActionRoute('/my-shop/sale', 'chicken biryani 2'), startsWith('/my-shop/sale?say='));
    expect(askodoxAppActionRoute('/my-shop/items', 'stock 2'), '/my-shop/items');
  });

  test('staff start with payment sound only; a tick never gives more than the role', () {
    expect(askodoxStaffStartTools('cashier'), ['payalerts']);
    expect(askodoxStaffStartTools('kitchen'), ['kitchen']);
    expect(askodoxStaffToolsFor('cashier'), containsAll(['sale', 'payalerts', 'bills']));
    expect(askodoxStaffToolsFor('cashier'), isNot(contains('gst')));
    expect(askodoxStaffToolsFor('attendant'), isNot(contains('sale')));
  });

  test('baaki pay dates are one tap: tomorrow, 3 days, 1 week, month end', () {
    final choices = askodoxDueDateChoices(DateTime(2026, 11, 20, 9));
    expect(choices.map((c) => askodoxIsoDay(c.$3)), ['2026-11-21', '2026-11-23', '2026-11-27', '2026-11-30']);
    expect(askodoxIsoDay(askodoxDueDateChoices(DateTime(2026, 11, 29)).last.$3), '2026-12-31',
        reason: 'month end too near -> next month end');
  });
}
