import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/yield/weekly_report.dart';
import 'package:podx/features/yield/yield_math.dart';

AskodoxYieldDay _day(String day, {int opening = 10000, int made = 0, int sold = 6000, int actual = 3000, int cost = 20000, int sell = 30000}) =>
    AskodoxYieldDay(
        item: 'chicken', day: day, openingGrams: opening, madeGrams: made, soldGrams: sold, actualGrams: actual, costPaise: cost, sellPaise: sell);

void main() {
  test('seven days ending today, oldest first', () {
    final days = askodoxWeekDays(DateTime(2026, 11, 28));
    expect(days.first, '2026-11-22');
    expect(days.last, '2026-11-28');
    expect(days.length, 7);
    expect(askodoxWeekdayName('2026-11-28', false), 'Sat');
    expect(askodoxWeekdayName('2026-11-28', true), 'శని');
  });

  test('only a shortage is a leak, valued at that day\'s cost of a kg', () {
    // expected 10000 + 0 - 6000 = 4000 g, weighed 3000 g: 1000 g short = 1 kg at Rs 200 = Rs 200
    final book = AskodoxYieldBook(days: [_day('2026-11-27'), _day('2026-11-28', actual: 5000)]);
    expect(askodoxMissingGrams([book], 'chicken', '2026-11-27'), 1000);
    expect(askodoxMissingGrams([book], 'chicken', '2026-11-28'), 0, reason: 'more stock than the books is not a leak');
    expect(askodoxMissingPaise([book], 'chicken', ['2026-11-27', '2026-11-28']), 20000);
  });

  test('cost share = what the sold kg cost against what they sold for', () {
    final book = AskodoxYieldBook(days: [_day('2026-11-27'), _day('2026-11-28')]);
    expect(askodoxCostShareBp(book, 'chicken', ['2026-11-27', '2026-11-28']), 6667);
    expect(askodoxCostShareBp(const AskodoxYieldBook(), 'chicken', ['2026-11-28']), isNull);
  });

  test('supplier rate: the last lot against the lot before', () {
    const a = AskodoxYieldBatch(id: 'a', item: 'chicken', day: '2026-11-20', liveGrams: 1000, ratePaise: 21000);
    const b = AskodoxYieldBatch(id: 'b', item: 'chicken', day: '2026-11-27', liveGrams: 1000, ratePaise: 22500);
    expect(askodoxSupplierRates([const AskodoxYieldBook(batches: [b, a])], 'chicken'), (21000, 22500));
    expect(askodoxSupplierRates([const AskodoxYieldBook(batches: [a])], 'chicken'), isNull);
  });
}
