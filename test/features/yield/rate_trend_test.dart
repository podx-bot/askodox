import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/yield/rate_trend.dart';
import 'package:podx/features/yield/yield_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

AskodoxYieldDay _day(String day, int cost, int sell) =>
    AskodoxYieldDay(item: 'chicken', day: day, soldGrams: 1000, costPaise: cost, sellPaise: sell);

void main() {
  test('days with both a cost and a selling rate; two shops average; nothing guessed', () {
    final a = AskodoxYieldBook(days: [_day('2026-11-27', 15000, 18000), _day('2026-11-28', 0, 18000)]);
    final b = AskodoxYieldBook(days: [_day('2026-11-27', 15100, 18400)]);
    final days = askodoxTrendDays([a, b], 'chicken', ['2026-11-26', '2026-11-27', '2026-11-28']);
    expect(days.map((d) => d.day), ['2026-11-27']);
    expect(days.first.costPaise, 15050);
    expect(days.first.sellPaise, 18200);
    expect(days.first.profitPaise, 3150);
    expect(askodoxTrendDays(const [], 'chicken', ['2026-11-27']), isEmpty);
  });

  test('minimum profit: smallest positive one set; days under it; none set = none flagged', () {
    final a = AskodoxYieldBook(minProfit: {'chicken': 3000});
    final b = AskodoxYieldBook(minProfit: {'chicken': 2500});
    expect(askodoxTrendMin([a, b], 'chicken'), 2500);
    expect(askodoxTrendMin(const [AskodoxYieldBook()], 'chicken'), 0);
    const days = [AskodoxTrendDay('d1', 15000, 18000), AskodoxTrendDay('d2', 15500, 18000)];
    expect(askodoxTrendBelow(days, 3000).map((d) => d.day), ['d2']);
    expect(askodoxTrendBelow(days, 0), isEmpty);
  });

  testWidgets('empty book says what fills the page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.light, home: const AskodoxRateTrendScreen())));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('askodoxRateTrend')), findsOneWidget);
    expect(find.byKey(const Key('askodoxTrendEmpty')), findsOneWidget);
  });
}
