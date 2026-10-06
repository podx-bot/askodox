import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/follow_up_router.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

const _rows = [
  UniversalMatch(id: '1', title: 'Voltas 1.5T Inverter', source: 'online', price: 38990, priceVerified: true,
      sourceName: 'Amazon.in', offerTitle: '₹2,000 off on HDFC cards'),
  UniversalMatch(id: '2', title: 'Reliance Digital Benz Circle', source: 'external', distanceKm: 2.4,
      latitude: 16.5, longitude: 80.6),
  UniversalMatch(id: '3', title: 'LG 1.5T Dual Inverter', source: 'online', price: 42990, priceVerified: true,
      ratingAverage: 4.3, reviewCount: 120),
  UniversalMatch(id: 'v', title: 'AC review video', source: 'video', videoId: 'abc'),
];

void main() {
  test('intents: follow-ups about shown results, new requests are not', () {
    expect(askodoxFollowUpIntent('Compare the best 3'), AskodoxFollowUp.compare);
    expect(askodoxFollowUpIntent('వీటిని పోల్చండి'), AskodoxFollowUp.compare);
    expect(askodoxFollowUpIntent('which is the cheapest?'), AskodoxFollowUp.cheapest);
    expect(askodoxFollowUpIntent('show only the ones under 40000'), AskodoxFollowUp.underBudget);
    expect(askodoxFollowUpIntent('any deals on these?'), AskodoxFollowUp.deals);
    expect(askodoxFollowUpIntent('reviews of these'), AskodoxFollowUp.reviews);
    expect(askodoxFollowUpIntent('directions to the nearest one'), AskodoxFollowUp.nearest);
    expect(askodoxFollowUpIntent('give me directions to that shop'), AskodoxFollowUp.directions);
    expect(askodoxFollowUpIntent('I want to buy an AC'), isNull);
    expect(askodoxFollowUpIntent('Samsung TV review videos'), isNull, reason: 'a new request, not about shown results');
    expect(askodoxFollowUpBudget('under 40k'), 40000);
    expect(askodoxFollowUpBudget('below ₹38,000'), 38000);
  });

  test('compare uses the current set, says Not verified, never videos', () {
    final out = askodoxAnswerFollowUp(AskodoxFollowUp.compare, _rows, te: false)!;
    expect(out, contains('Comparing the 3 options shown'));
    expect(out, contains('Voltas 1.5T Inverter'));
    expect(out, contains('Rating: Not verified'));
    expect(out, contains('Nearby shop (Google listing)'));
    expect(out, contains('Lowest stated price: Voltas'));
    expect(out, isNot(contains('AC review video')));
    expect(out, isNot(contains('videos and reviews')));
  });

  test('budget filter keeps only stated prices within budget; deals and reviews fall back when unknown', () {
    final under = askodoxAnswerFollowUp(AskodoxFollowUp.underBudget, _rows, te: false, budget: 40000)!;
    expect(under, contains('Voltas'));
    expect(under, isNot(contains('LG 1.5T')));
    expect(under, contains('no verified price and are not included'));
    expect(askodoxAnswerFollowUp(AskodoxFollowUp.deals, _rows, te: false), contains('HDFC'));
    expect(askodoxAnswerFollowUp(AskodoxFollowUp.reviews, _rows, te: false), contains('4.3'));
    expect(askodoxAnswerFollowUp(AskodoxFollowUp.reviews, [_rows[0], _rows[1]], te: false), isNull,
        reason: 'no rating on screen -> search real reviews instead');
    expect(askodoxAnswerFollowUp(AskodoxFollowUp.compare, [_rows[3]], te: false), isNull);
  });
}
