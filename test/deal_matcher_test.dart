import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/deal_matcher.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const brain = UniversalDealBrain();
  const matcher = DealMatcher();

  UniversalDeal ready(String text, DealIntent intent, String subject, String category) {
    final captured = brain.capture(text).copyWith(
          intent: intent,
          subject: subject,
          category: category,
          quantity: 10,
          unit: 'kg',
          fulfilment: 'pickup',
          location: const DealLocation(label: 'Vijayawada'),
        );
    return captured;
  }

  test('matches only opposite-side exact relevant local product', () {
    final request = ready('Need 10 kg rice in Vijayawada', DealIntent.buy, 'rice', 'product');
    final riceSeller = ready('Sell rice in Vijayawada', DealIntent.sell, 'rice', 'product');
    final tvSeller = ready('Sell TV in Vijayawada', DealIntent.sell, 'TV', 'product');
    final riceBuyer = ready('Need rice in Vijayawada', DealIntent.buy, 'rice', 'product');

    final result = matcher.match(request, [
      DealMatchCandidate(id: 'rice-seller', deal: riceSeller, trustScore: 90),
      DealMatchCandidate(id: 'tv-seller', deal: tvSeller, trustScore: 99),
      DealMatchCandidate(id: 'rice-buyer', deal: riceBuyer, trustScore: 100),
    ]);

    expect(result.hasLocalMatch, isTrue);
    expect(result.matches.map((m) => m.candidate.id), ['rice-seller']);
  });

  test('returns explicit no-match recovery signal for irrelevant inventory', () {
    final request = ready('Need 10 kg rice in Vijayawada', DealIntent.buy, 'rice', 'product');
    final chickenSeller = ready('Sell chicken in Vijayawada', DealIntent.sell, 'chicken', 'product');

    final result = matcher.match(request, [
      DealMatchCandidate(id: 'chicken-seller', deal: chickenSeller),
    ]);

    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isTrue);
  });

  test('ranks relevant sellers by trust when relevance is otherwise equal', () {
    final request = ready('Need rice in Vijayawada', DealIntent.buy, 'rice', 'product');
    final sellerA = ready('Sell rice in Vijayawada', DealIntent.sell, 'rice', 'product');
    final sellerB = ready('Sell rice in Vijayawada', DealIntent.sell, 'rice', 'product');

    final result = matcher.match(request, [
      DealMatchCandidate(id: 'seller-a', deal: sellerA, trustScore: 70),
      DealMatchCandidate(id: 'seller-b', deal: sellerB, trustScore: 95),
    ]);

    expect(result.matches.first.candidate.id, 'seller-b');
  });
}
