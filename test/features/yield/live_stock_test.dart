import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/yield/live_stock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stock left = morning minus sales; low only under the level he set', () {
    const v = AskodoxLiveStockItem(day: 'd', morning: 20000, sales: [1500, 600, 1000], minGrams: 3000);
    expect(v.sold, 3100);
    expect(v.left, 16900);
    expect(v.low, isFalse);
    expect(v.copy(sales: [...v.sales, 14000]).low, isTrue);
    expect(v.copy(minGrams: 0, sales: [20000]).low, isFalse, reason: 'no level set = nothing flagged');
    expect(const AskodoxLiveStockItem(minGrams: 3000).low, isFalse, reason: 'no morning stock entered');
  });

  test('a new day starts empty and keeps only the level', () {
    const v = AskodoxLiveStockItem(day: '2026-11-27', morning: 20000, sales: [1000], minGrams: 3000);
    final t = v.on('2026-11-28');
    expect(t.morning, 0);
    expect(t.sales, isEmpty);
    expect(t.minGrams, 3000);
    expect(v.on('2026-11-27').morning, 20000);
  });

  test('spoken or typed amounts', () {
    expect(askodoxLiveStockGrams('1.5 kg'), 1500);
    expect(askodoxLiveStockGrams('2 కేజీలు'), 2000);
    expect(askodoxLiveStockGrams('అర కేజీ'), 500);
    expect(askodoxLiveStockGrams('half kilo'), 500);
    expect(askodoxLiveStockGrams('hello'), 0);
  });

  test('json round trip drops bad values', () {
    const v = AskodoxLiveStockItem(day: 'd', morning: 5000, sales: [100, 200], minGrams: 300);
    final back = AskodoxLiveStockItem.fromJson(v.toJson());
    expect(back.sales, [100, 200]);
    expect(back.minGrams, 300);
    expect(AskodoxLiveStockItem.fromJson({'s': [-5, 'x', 7]}).sales, [7]);
  });

  testWidgets('no lot yet says what fills the page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.light, home: const AskodoxLiveStockScreen(businessId: '1'))));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('askodoxLiveStock')), findsOneWidget);
    expect(find.byKey(const Key('askodoxLiveEmpty')), findsOneWidget);
  });

  test('a low-stock note shows only when a sale crosses the level', () {
    const a = AskodoxLiveStockItem(day: 'd', morning: 10000, sales: [3000], minGrams: 5000);
    final b = a.copy(sales: [3000, 3000]);
    final c2 = b.copy(sales: [3000, 3000, 1000]);
    expect(askodoxLowCrossed(a, b), isTrue);
    expect(askodoxLowCrossed(b, c2), isFalse, reason: 'already low');
    expect(askodoxLowCrossed(a.copy(minGrams: 0), b.copy(minGrams: 0)), isFalse, reason: 'no level = nothing');
    final n = askodoxLowStockNote('Chicken', 4000, 5000, false);
    expect(n.$2.contains('4'), isTrue);
    expect(askodoxLowStockNote('x', 4000, 5000, true).$1, isNotEmpty);
  });
}
