import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/yield/yield_math.dart';
import 'package:podx/features/yield/yield_screen.dart';
import 'package:podx/features/yield/yield_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  final vectors = jsonDecode(File('test/fixtures/yield_vectors.json').readAsStringSync()) as Map<String, dynamic>;

  group('yield maths (the vectors shared with the server)', () {
    for (final raw in vectors['cases'] as List) {
      final c = raw as Map<String, dynamic>;
      test('lot: ${c['name']}', () {
        final e = c['expect'] as Map<String, dynamic>;
        final live = c['live_g'] as int, out = c['out_g'] as int;
        final total = askodoxYieldTotal(live, c['rate_p'] as int, (c['extras_p'] as List).cast<int>());
        final y = askodoxYieldBp(live, out);
        final cost = askodoxYieldCostPerKg(total, c['byproduct_p'] as int, out);
        expect(askodoxYieldGoods(live, c['rate_p'] as int), e['goods_p']);
        expect(total, e['total_p']);
        expect(y, e['yield_bp']);
        expect(cost, e['cost_p']);
        final formBp = c['form_yield_bp'] as int?;
        final form = cost != null && formBp != null && formBp > 0 ? askodoxYieldFormCost(cost, formBp) : null;
        expect(form, e['form_cost_p']);
        final base = form ?? cost;
        if (base == null) {
          expect(e['profit_p'], isNull);
          expect(e['rise_p'], isNull);
        } else {
          final gain = askodoxYieldProfit(c['sell_p'] as int, base);
          expect(gain.profit, e['profit_p']);
          expect(gain.marginBp, e['margin_bp']);
          expect(askodoxYieldRiseEffect(c['delta_p'] as int, y!), e['rise_p']);
        }
      });
    }
    for (final raw in vectors['days'] as List) {
      final d = raw as Map<String, dynamic>;
      test('day: ${d['name']}', () {
        final e = d['expect'] as Map<String, dynamic>;
        final expected = askodoxYieldExpected(d['opening_g'] as int, d['made_g'] as int, d['sold_g'] as int);
        expect(expected, e['expected_g']);
        expect((d['actual_g'] as int) - expected, e['diff_g']);
        expect(askodoxYieldDiffValue((d['actual_g'] as int) - expected, d['cost_p'] as int), e['diff_value_p']);
        final money = askodoxYieldDayProfit(d['sold_g'] as int, d['sell_p'] as int, d['cost_p'] as int, d['other_p'] as int);
        expect([money.sales, money.spent, money.profit], [e['sales_p'], e['spent_p'], e['profit_p']]);
      });
    }

    test('rounding, words and typed numbers', () {
      expect(askodoxYieldRoundDiv(5, 2), 3);
      expect(askodoxYieldRoundDiv(-5, 2), -3);
      expect(askodoxYieldRoundDiv(4, 3), 1);
      expect(() => askodoxYieldRoundDiv(1, 0), throwsArgumentError);
      expect(askodoxYieldKg(66200), '66.2');
      expect(askodoxYieldKg(29850), '29.85');
      expect(askodoxYieldKg(70000), '70');
      expect(askodoxYieldKg(-700), '-0.7');
      expect(askodoxYieldRupees(1191600), '₹11,916');
      expect(askodoxYieldRupees(16667), '₹166.67');
      expect(askodoxYieldRupees(123456789), '₹12,34,567.89');
      expect(askodoxYieldRupees(-10500), '-₹105');
      expect(askodoxYieldRupees(0), '₹0');
      expect(askodoxYieldPercent(7000), '70%');
      expect(askodoxYieldPercent(1667), '16.7%');
      expect(askodoxYieldPercent(6910), '69.1%');
      expect(askodoxYieldParseGrams('43.2'), 43200);
      expect(askodoxYieldParseGrams('100'), 100000);
      expect(askodoxYieldParseGrams(' 0.75 '), 750);
      expect(askodoxYieldParsePaise('98.50'), 9850);
      expect(askodoxYieldParsePaise('1,050'), 105000);
      expect(askodoxYieldParsePaise('1.005'), 101);
      expect(askodoxYieldParsePaise('abc'), 0);
      expect(askodoxYieldParsePaise(''), 0);
    });

    test('a book: newest lot, own yields, tomorrow opens with tonight’s scale, saved text comes back', () {
      const lot1 = AskodoxYieldBatch(id: 'a', item: 'chicken', day: '2026-11-26', liveGrams: 100000, ratePaise: 9800, outGrams: 69000, sellPaise: 18000);
      const lot2 = AskodoxYieldBatch(
          id: 'b', item: 'chicken', day: '2026-11-27', liveGrams: 100000, ratePaise: 10000, transportPaise: 30000,
          labourPaise: 20000, outGrams: 70000, sellPaise: 18000);
      const goat = AskodoxYieldBatch(id: 'c', item: 'mutton', day: '2026-11-27', liveGrams: 22400, ratePaise: 42000);
      const book = AskodoxYieldBook(batches: [lot1, lot2, goat], days: [
        AskodoxYieldDay(item: 'chicken', day: '2026-11-26', actualGrams: 5000),
      ], minProfit: {'chicken': 2500});
      expect(book.latest('chicken')!.id, 'b');
      expect(book.latest('chicken')!.cost, 15000);
      expect(book.yields('chicken'), [6900, 7000]);
      expect(book.latest('mutton')!.cost, isNull);
      expect(book.openingFor('chicken', '2026-11-27'), 5000);
      expect(book.openingFor('mutton', '2026-11-27'), 0);
      expect(book.madeOn('chicken', '2026-11-27'), 70000);
      final back = askodoxYieldDecode(askodoxYieldEncode({'shop1': book}))['shop1']!;
      expect(back.batches.length, 3);
      expect(back.latest('chicken')!.total, 1050000);
      expect(back.minProfit['chicken'], 2500);
      expect(back.days.single.actualGrams, 5000);
      expect(askodoxYieldDecode('{broken'), isEmpty);
      expect(askodoxYieldDecode(null), isEmpty);
    });
  });

  testWidgets('a lot in three steps, the board, then day end -- the design sample numbers', (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxYieldClockProvider.overrideWithValue(() => DateTime(2026, 11, 27, 9))],
      child: MaterialApp(theme: AppTheme.light, home: const AskodoxYieldScreen(businessId: 'shop1')),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('askodoxYieldEmpty')), findsOneWidget);
    expect(find.byKey(const Key('askodoxEstimateNote')), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxYieldNew')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('askodoxYieldLive')), '100');
    await tester.enterText(find.byKey(const Key('askodoxYieldRate')), '100');
    await tester.enterText(find.byKey(const Key('askodoxYieldTransport')), '300');
    await tester.enterText(find.byKey(const Key('askodoxYieldLabour')), '200');
    await tester.pump();
    expect(_text(tester, 'askodoxYieldTotal'), '₹10,500');
    await tester.tap(find.byKey(const Key('askodoxYieldNext1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('askodoxYieldOut')), '70');
    await tester.pump();
    expect(_text(tester, 'askodoxYieldPercent'), '70%');
    expect(_text(tester, 'askodoxYieldLost'), '30 kg');
    expect(_text(tester, 'askodoxYieldCost'), '₹150');
    await tester.tap(find.byKey(const Key('askodoxYieldNext2')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('askodoxYieldSell')), '180');
    await tester.enterText(find.byKey(const Key('askodoxYieldMin')), '35');
    await tester.pump();
    expect(_text(tester, 'askodoxYieldProfit'), '₹30 · 16.7%');
    expect(find.byKey(const Key('askodoxYieldLow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxYieldSave')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('askodoxYieldBoard')), findsOneWidget);
    expect(_text(tester, 'askodoxYieldBoardTotal'), '₹10,500');
    expect(_text(tester, 'askodoxYieldBoardYield'), '70%');
    expect(_text(tester, 'askodoxYieldBoardCost'), '₹150');
    expect(_text(tester, 'askodoxYieldBoardProfit'), '₹30 · 16.7%');
    expect(find.byKey(const Key('askodoxYieldBoardLow')), findsOneWidget);
    expect(_text(tester, 'askodoxYieldBoardRise'), contains('₹2.86'));

    await tester.tap(find.byKey(const Key('askodoxYieldDayEnd')));
    await tester.pump();
    expect(_text(tester, 'askodoxYieldMade'), '70');
    await tester.enterText(find.byKey(const Key('askodoxYieldOpening')), '5');
    await tester.enterText(find.byKey(const Key('askodoxYieldSold')), '66.2');
    await tester.enterText(find.byKey(const Key('askodoxYieldActual')), '8.1');
    await tester.enterText(find.byKey(const Key('askodoxYieldOther')), '500');
    await tester.pump();
    expect(_text(tester, 'askodoxYieldExpected'), '8.8');
    expect(_text(tester, 'askodoxYieldDiff'), '-0.7 kg ≈ ₹105');
    expect(_text(tester, 'askodoxYieldSales'), '₹11,916');
    expect(_text(tester, 'askodoxYieldSpent'), '₹9,930');
    expect(_text(tester, 'askodoxYieldDayProfit'), '₹1,486');
    await tester.tap(find.byKey(const ValueKey('askodoxYieldReason-weight')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('askodoxYieldDaySave')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = askodoxYieldDecode(prefs.getString(askodoxYieldPrefsKey))['shop1']!;
    expect(saved.batches.single.cost, 15000);
    expect(saved.minProfit['chicken'], 3500);
    final day = saved.dayOf('chicken', '2026-11-27')!;
    expect([day.expected, day.diff, day.reason], [8800, -700, 'weight']);
  });
}
