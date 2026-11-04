import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

UniversalMatch _card(String id, double price) =>
    UniversalMatch(id: id, title: 'Phone $id', price: price, source: 'online');

void main() {
  group('rupee figures in a reply', () {
    test('symbols, words, Telugu units and ranges with one unit', () {
      expect(askodoxRupeeFigures('Price is ₹20,000 to ₹23,000.'), [20000, 23000]);
      expect(askodoxRupeeFigures('ధర సుమారు 20 నుంచి 23 వేలు ఉంటుంది.'), [20000, 23000]);
      expect(askodoxRupeeFigures('around 1.2 lakh'), [120000]);
      expect(askodoxRupeeFigures('Rs 39999 on Amazon'), [39999]);
      expect(askodoxRupeeFigures('20-23k range'), [20000, 23000]);
    });

    test('screens, batteries, years and counts are not prices', () {
      expect(askodoxRupeeFigures('4K display, 6000 mAh, 2024 model, 8 GB RAM, 2-3 years'), isEmpty);
    });
  });

  group('reply prices must agree with the cards (owner 2026-11-04)', () {
    final cards = [_card('a', 38999), _card('b', 40999), _card('c', 36499)];

    test('a memory price far from the cards is replaced by the cards\' real range', () {
      const reply = 'Vivo V50 is a good mid-range phone. Its price is about ₹20,000 – ₹23,000.\n\nCamera is strong.';
      final fixed = askodoxReconcileReplyPrices(reply, cards, telugu: false)!;
      expect(fixed, isNot(contains('20,000')));
      expect(fixed, contains('good mid-range phone'));
      expect(fixed, contains('Camera is strong'));
      expect(fixed, contains('₹36,499 – ₹40,999'));
    });

    test('Telugu reply gets the Telugu line', () {
      final fixed = askodoxReconcileReplyPrices('దీని ధర 20 నుంచి 23 వేలు.', cards, telugu: true)!;
      expect(fixed, contains('కింద చూపిన listings లో ఇప్పటి ధర'));
      expect(fixed, isNot(contains('20 నుంచి')));
    });

    test('a reply that already agrees, or no priced cards, is left alone', () {
      expect(askodoxReconcileReplyPrices('Expect around ₹37,000 – ₹41,000.', cards, telugu: false), isNull);
      expect(askodoxReconcileReplyPrices('About ₹20,000.', const [], telugu: false), isNull);
    });

    test('the customer\'s own budget is never treated as a wrong price', () {
      expect(
          askodoxReconcileReplyPrices('Within your ₹25,000 budget these are a stretch.', cards,
              telugu: false, userText: 'phone under 25000 rupees'),
          isNull);
    });
  });
}
