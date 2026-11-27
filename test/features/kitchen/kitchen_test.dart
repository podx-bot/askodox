import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/kitchen/kitchen_logic.dart';
import 'package:podx/features/kitchen/kitchen_screen.dart';
import 'package:podx/features/kitchen/kitchen_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('kitchen rules', () {
    test('amounts and rupees', () {
      expect(askodoxKitchenParseAmount('12'), 12000);
      expect(askodoxKitchenParseAmount('0,5'), 500);
      expect(askodoxKitchenParseAmount('1.25'), 1250);
      expect(askodoxKitchenParseAmount('abc'), isNull);
      expect(askodoxKitchenShown(500), '0.5');
      expect(askodoxKitchenShown(12000), '12');
      expect(askodoxKitchenParsePaise('8,400'), 840000);
      expect(askodoxKitchenParsePaise('0'), isNull);
      expect(askodoxKitchenRupees(840000), '₹8,400');
      expect(askodoxKitchenRupees(12345600), '₹1,23,456');
    });

    test('low = finished or at / under the level the person set', () {
      const a = AskodoxKitchenItem(id: '1', name: 'Dal', milli: 500, lowMilli: 1000);
      const b = AskodoxKitchenItem(id: '2', name: 'Rice', milli: 12000, lowMilli: 2000);
      const c = AskodoxKitchenItem(id: '3', name: 'Salt', milli: 0, finished: true);
      const d = AskodoxKitchenItem(id: '4', name: 'Tea', milli: 100);
      expect(askodoxKitchenLow(a), isTrue);
      expect(askodoxKitchenLow(b), isFalse);
      expect(askodoxKitchenLow(c), isTrue);
      expect(askodoxKitchenLow(d), isFalse); // no level set: nothing is guessed
      expect(askodoxKitchenBuyList([b, a, c, d]).map((i) => i.name), ['Dal', 'Salt']);
    });

    test('month spend counts only that month; encode / decode', () {
      final spends = [
        const AskodoxKitchenSpend(day: '2026-11-03', paise: 100000),
        const AskodoxKitchenSpend(day: '2026-11-20', paise: 50000),
        const AskodoxKitchenSpend(day: '2026-10-30', paise: 999900),
      ];
      expect(askodoxKitchenMonthSpend(spends, DateTime(2026, 11, 28)), 150000);
      final book = AskodoxKitchenBook(items: const [AskodoxKitchenItem(id: '1', name: 'Dal', unit: 'kg', milli: 500)], spends: spends);
      final back = askodoxKitchenDecode(askodoxKitchenEncode(book));
      expect(back.items.single.name, 'Dal');
      expect(back.spends.length, 3);
      expect(askodoxKitchenDecode('nope').items, isEmpty);
    });
  });

  testWidgets('add an item, change it, it runs low, buy list and month spend', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxKitchenClockProvider.overrideWithValue(() => DateTime(2026, 11, 28, 9))],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxKitchenScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('askodoxKitchenEmpty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxKitchenAdd')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('askodoxKitchenName')), 'Toor dal');
    await tester.enterText(find.byKey(const Key('askodoxKitchenQty')), '1');
    await tester.enterText(find.byKey(const Key('askodoxKitchenLow')), '0.5');
    await tester.tap(find.byKey(const Key('askodoxKitchenSave')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Toor dal'), findsOneWidget);
    expect(find.byKey(const Key('askodoxKitchenBuyEmpty')), findsOneWidget);
    final id = (tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxKitchenMinus-'))).single.key as ValueKey).value.toString().split('-').last;

    await tester.tap(find.byKey(ValueKey('askodoxKitchenMinus-$id'))); // 1 kg -> 0.5 kg = at the level
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Text>(find.byKey(ValueKey('askodoxKitchenAmount-$id'))).data, '0.5 kg');
    expect(find.byKey(ValueKey('askodoxKitchenBuy-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('askodoxKitchenPlus-$id')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(ValueKey('askodoxKitchenBuy-$id')), findsNothing);
    await tester.tap(find.byKey(ValueKey('askodoxKitchenFinish-$id')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(ValueKey('askodoxKitchenBuy-$id')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('askodoxKitchenSpend')), '8400');
    await tester.tap(find.byKey(const Key('askodoxKitchenSpendAdd')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<Text>(find.byKey(const Key('askodoxKitchenMonth'))).data, '₹8,400');
  });
}
