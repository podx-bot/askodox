import 'package:podx/features/home/domain/need_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Telugu TV "show me" message: budget range, subject, no split', () {
    const text = 'నాకు 43-inch TV ₹20,000–₹30,000 లో కావాలి — show me';
    expect(askodoxWantsResultsNow(text), isTrue);
    final budget = askodoxBudgetRange(text);
    expect(budget.min, 20000);
    expect(budget.max, 30000);
    expect(askodoxNeedSubject(text), '43 inch TV');
    expect(askodoxSplitNeeds(text), isEmpty);
  });

  test('multi-category message splits into separate needs with their own budgets', () {
    final needs = askodoxSplitNeeds('నాకు fridge ₹30–40k, TV ₹20–30k, car ₹10 lakh లో కావాలి — show me');
    expect(needs.map((n) => n.subject), ['fridge', 'TV', 'car']);
    expect([needs[0].budget.min, needs[0].budget.max], [30000, 40000]);
    expect([needs[1].budget.min, needs[1].budget.max], [20000, 30000]);
    expect(needs[2].budget.max, 1000000);
  });

  test('sizes and quantities are never read as a budget', () {
    expect(askodoxBudgetRange('1 kg chicken').isEmpty, isTrue);
    expect(askodoxBudgetRange('43 inch TV').isEmpty, isTrue);
    expect(askodoxNeedSubject('1 kg chicken'), '1 kg chicken');
    expect(askodoxBudgetRange('car under 8 lakh').max, 800000);
    expect(askodoxBudgetRange('car under 8 lakh').min, isNull);
    expect(askodoxBudgetRange('phone 15 వేలు').max, 15000);
  });

  test('plain follow-up answers are not a show-me request', () {
    expect(askodoxWantsResultsNow('32 inch'), isFalse);
    expect(askodoxWantsResultsNow('Vijayawada'), isFalse);
    expect(askodoxWantsResultsNow('చూపించండి'), isTrue);
    expect(askodoxWantsResultsNow('find it'), isTrue);
  });

  test('same-need detection', () {
    expect(askodoxSameNeed('43 inch TV', 'TV'), isTrue);
    expect(askodoxSameNeed('43 inch TV', '32 inch fridge'), isFalse);
    expect(askodoxSameNeed('Samsung television', 'television'), isTrue);
    expect(askodoxSameNeed('fridge', 'car'), isFalse);
  });

  test('a stated need with a budget or "show me" is a request even without AI', () {
    expect(askodoxStatesANeed('I want a used car under ₹8 lakh'), isTrue);
    expect(askodoxStatesANeed('నాకు fridge ₹30,000 లో కావాలి'), isTrue);
    expect(askodoxStatesANeed('I need a plumber, show me'), isTrue);
    expect(askodoxStatesANeed('what is the weather today'), isFalse);
    expect(askodoxStatesANeed('I want to know about cars'), isFalse);
  });
}
