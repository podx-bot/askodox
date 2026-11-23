import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/domain/pos_commands.dart';
import 'package:podx/features/pos/domain/pos_name_sound.dart';

// Every phrase an owner reported goes here FIRST (see .claude/rules/pos-spoken-orders.md), then the fix.
// Menu names are typed in English (as most shops do, no Telugu name): the order is said in Telugu / Hindi.
const _menu = [
  AskodoxPosItemRef(id: 'cb', name: 'Chicken Biryani', unit: 'plate'),
  AskodoxPosItemRef(id: 'fpb', name: 'Fry Piece Biryani', unit: 'plate'),
  AskodoxPosItemRef(id: 'fam', name: 'Family Pack Chicken Dum Biryani', unit: 'plate'),
  AskodoxPosItemRef(id: 'cdb', name: 'Chicken Dum Biryani', unit: 'plate'),
  AskodoxPosItemRef(id: 'mb', name: 'Mutton Biryani', unit: 'plate'),
  AskodoxPosItemRef(id: 'c65', name: 'Chicken 65', unit: 'plate'),
  AskodoxPosItemRef(id: 'veg', name: 'Veg Biryani', unit: 'pcs'),
];

(String?, int?) _line(String said, [List<AskodoxPosItemRef> menu = _menu]) {
  final c = askodoxParsePosCommand(said, menu);
  return (c.item?.id, c.qtyMilli);
}

void main() {
  test('a word sounds the same in Telugu, Hindi and English letters', () {
    expect(askodoxSoundWords('చికెన్ బిర్యానీ'), askodoxSoundWords('Chicken Biryani'));
    expect(askodoxSoundWords('बिरयानी'), askodoxSoundWords('biriyani'));
    expect(askodoxSoundWords('పీస్'), askodoxSoundWords('piece'));
    expect(askodoxSoundWords('ఫ్రై దమ్'), askodoxSoundWords('fry dum'));
    expect(askodoxSoundWords('చికెన్ ౬౫'), ['ckn', '65']);
  });

  test('owner 2026-11-24: a Telugu order finds English menu names, "parcel" and the full stop ignored', () {
    final order = askodoxParsePosOrder(
        'రెండు చికెన్ బిర్యానీ ఒక ఫ్రై పీస్ బిర్యానీ ఒక ఫ్యామిలీ ప్యాక్ చికెన్ దమ్ బిర్యానీ పార్సెల్.', _menu);
    expect([for (final o in order) (o.command.item?.id, o.command.qtyMilli)], [('cb', 2000), ('fpb', 1000), ('fam', 1000)]);
    expect(order.last.phrase.contains('.'), isFalse);
  });

  test('any script, any spelling, name before or after the quantity', () {
    expect(_line('दो चिकन बिरयानी'), ('cb', 2000));
    expect(_line('౨ చికెన్ బిర్యానీ'), ('cb', 2000));
    expect(_line('ఒక మటన్ బిర్యాని'), ('mb', 1000));
    expect(_line('chiken biriyani 3'), ('cb', 3000));
    expect(_line('చికెన్ దమ్ బిర్యానీ'), ('cdb', 1000), reason: 'the most specific name heard wins');
    expect(_line('ఫ్యామిలీ ప్యాక్ బిర్యానీ'), ('fam', 1000), reason: 'every word said is in one name only');
    final order = askodoxParsePosOrder('చికెన్ బిర్యానీ రెండు మటన్ బిర్యానీ ఒకటి', _menu);
    expect([for (final o in order) (o.command.item?.id, o.command.qtyMilli)], [('cb', 2000), ('mb', 1000)]);
  });

  test('a unit word that is part of the name, and counted units, never block the item', () {
    expect(_line('1 family pack chicken dum biryani'), ('fam', 1000));
    expect(_line('1 fry piece biryani'), ('fpb', 1000));
    expect(_line('రెండు ప్లేట్లు చికెన్ బిర్యానీ'), ('cb', 2000));
    expect(_line('2 plates veg biryani'), ('veg', 2000), reason: 'plates of a pieces item are pieces');
  });

  test('a number in the name is not the quantity ("Chicken 65")', () {
    expect(_line('రెండు చికెన్ 65'), ('c65', 2000));
    expect(_line('2 chicken 65'), ('c65', 2000));
    expect(_line('chicken 65 రెండు'), ('c65', 2000));
    final order = askodoxParsePosOrder('రెండు చికెన్ 65 ఒక మటన్ బిర్యానీ', _menu);
    expect([for (final o in order) (o.command.item?.id, o.command.qtyMilli)], [('c65', 2000), ('mb', 1000)]);
  });

  test('half a name is offered to pick, never added by itself; the cashier pick always works', () {
    final some = askodoxParsePosCommand('రెండు బిర్యానీ', _menu);
    expect(some.item, isNull);
    expect(some.needsChoice, isTrue);
    expect(some.candidates.map((c) => c.id), containsAll(['cb', 'mb', 'veg']));
    final partial = askodoxParsePosCommand('ఒక ఫ్రై పీస్ బిర్యానీ', [_menu.first]);
    expect(partial.item, isNull, reason: 'only "biryani" was heard');
    expect(partial.candidates.map((c) => c.id), ['cb']);
    final picked = askodoxParsePosCommand('రెండు ఏదో వస్తువు', _menu, pick: _menu[4]);
    expect((picked.item?.id, picked.qtyMilli), ('mb', 2000));
    expect(askodoxParsePosCommand('hello there', _menu).item, isNull);
  });
}
