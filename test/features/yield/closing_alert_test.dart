import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/yield/closing_alert.dart';
import 'package:podx/features/yield/yield_math.dart';

void main() {
  const lot = AskodoxYieldBatch(id: 'a', item: 'chicken', day: '2026-11-27', liveGrams: 100000, ratePaise: 10000);
  const book = AskodoxYieldBook(batches: [lot]);

  test('clock times', () {
    expect(askodoxClosingParse('22:30')?.hour, 22);
    expect(askodoxClosingParse('9:05')?.minute, 5);
    expect(askodoxClosingParse('24:00'), isNull);
    expect(askodoxClosingParse('abc'), isNull);
    expect(askodoxClosingText(9, 5), '09:05');
  });

  test('due only after the closing time, for items traded lately, until the day end is saved', () {
    final before = DateTime(2026, 11, 28, 22, 0);
    final after = DateTime(2026, 11, 28, 22, 31);
    expect(askodoxClosingDue(book, before, '22:30'), isEmpty);
    expect(askodoxClosingDue(book, after, '22:30'), ['chicken']);
    expect(askodoxClosingDue(book, after, ''), isEmpty); // no closing time set: nothing nags
    final closed = book.copyWith(days: const [AskodoxYieldDay(item: 'chicken', day: '2026-11-28', actualGrams: 1000)]);
    expect(askodoxClosingDue(closed, after, '22:30'), isEmpty);
    // a lot older than three days is not an item in use
    expect(askodoxClosingDue(book, DateTime(2026, 12, 5, 23), '22:30'), isEmpty);
  });
}
