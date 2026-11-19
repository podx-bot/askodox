import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/own_money_records.dart';

void main() {
  test('money-moved questions in Telugu, English and Hindi are recognised', () {
    expect(askodoxAsksOwnMoney('సరే కానీ నా బ్యాంకులో నుంచి ఏమన్నా డబ్బులు కట్ అయినాయా ఇప్పుడు 1800 దాకా ఏమన్నా'), isTrue);
    expect(askodoxAsksOwnMoney('was 1800 debited from my bank just now'), isTrue);
    expect(askodoxAsksOwnMoney('did the payment come to my account'), isTrue);
    expect(askodoxAsksOwnMoney('मेरे बैंक से पैसे कट गए क्या'), isTrue);
  });

  test('shop, price and how-to questions are not own-money questions', () {
    expect(askodoxAsksOwnMoney('ఒక బిర్యానీ ఆర్డర్ పెట్టాలి.'), isFalse);
    expect(askodoxAsksOwnMoney('how to pay by UPI at the shop'), isFalse);
    expect(askodoxAsksOwnMoney('iPhone price in India'), isFalse);
    expect(askodoxAsksOwnMoney('hi'), isFalse);
  });

  test('guidance lists this phone\'s records and forbids guessing; empty list says none', () {
    final events = <Map<String, Object?>>[
      {
        'local_id': '1',
        'amount_paise': 180000,
        'direction': 'out',
        'detected_at': '2026-11-19T08:02:00Z',
        'source_app': 'com.phonepe.app',
        'source_label': 'PhonePe',
        'party': 'Gaurava Palli',
        'bank_confirmed': true,
      },
      {'local_id': '2', 'amount_paise': 5000, 'direction': 'in', 'detected_at': '2026-11-19T07:00:00Z', 'source_label': 'Google Pay'},
      {'local_id': '3', 'test': true, 'amount_paise': 999900},
    ];
    final g = askodoxMoneyFactsGuidance(events);
    expect(g, contains('₹1800'));
    expect(g, contains('MONEY OUT'));
    expect(g, contains('confirmed by a registered bank SMS'));
    expect(g, contains('₹50'));
    expect(g, isNot(contains('9999')));
    expect(g, contains('Never guess'));
    expect(askodoxMoneyFactsGuidance(const []), contains('none'));
  });
}
