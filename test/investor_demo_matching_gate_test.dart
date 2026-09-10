import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/deal_matcher.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const brain = UniversalDealBrain();
  const matcher = DealMatcher();

  UniversalDeal deal({
    required DealIntent intent,
    required String subject,
    required String category,
    required double lat,
    required double lng,
    double radiusKm = 5,
  }) =>
      brain.capture(subject).copyWith(
            intent: intent,
            subject: subject,
            category: category,
            quantity: 10,
            unit: 'kg',
            fulfilment: 'pickup',
            dynamicFields: subject.toLowerCase() == 'chicken'
                ? const {
                    'freshness': 'fresh',
                    'cut': 'curry cut',
                    'chickenPreference': 'no preference',
                  }
                : const {},
            location: DealLocation(
              label: 'Vijayawada',
              latitude: lat,
              longitude: lng,
              radiusKm: radiusKm,
            ),
          );

  test('investor demo gate: only correct local opposite-side seller is returned', () {
    final request = deal(
      intent: DealIntent.buy,
      subject: 'chicken',
      category: 'product',
      lat: 16.5062,
      lng: 80.6480,
      radiusKm: 5,
    );

    final result = matcher.match(request, [
      DealMatchCandidate(
        id: 'near-chicken-seller',
        deal: deal(
          intent: DealIntent.sell,
          subject: 'chicken',
          category: 'product',
          lat: 16.5150,
          lng: 80.6550,
        ),
        trustScore: 95,
      ),
      DealMatchCandidate(
        id: 'wrong-category-tv-seller',
        deal: deal(
          intent: DealIntent.sell,
          subject: 'tv',
          category: 'product',
          lat: 16.5100,
          lng: 80.6500,
        ),
        trustScore: 100,
      ),
      DealMatchCandidate(
        id: 'far-chicken-seller',
        deal: deal(
          intent: DealIntent.sell,
          subject: 'chicken',
          category: 'product',
          lat: 16.6100,
          lng: 80.7200,
          radiusKm: 20,
        ),
        trustScore: 100,
      ),
      DealMatchCandidate(
        id: 'same-side-buyer',
        deal: deal(
          intent: DealIntent.buy,
          subject: 'chicken',
          category: 'product',
          lat: 16.5080,
          lng: 80.6490,
        ),
        trustScore: 100,
      ),
    ]);

    expect(result.hasLocalMatch, isTrue);
    expect(
      result.matches.map((match) => match.candidate.id),
      ['near-chicken-seller'],
    );
  });

  test('investor demo gate: no valid local seller triggers recovery', () {
    final request = deal(
      intent: DealIntent.buy,
      subject: 'chicken',
      category: 'product',
      lat: 16.5062,
      lng: 80.6480,
      radiusKm: 3,
    );

    final result = matcher.match(request, [
      DealMatchCandidate(
        id: 'wrong-product',
        deal: deal(
          intent: DealIntent.sell,
          subject: 'television',
          category: 'product',
          lat: 16.5100,
          lng: 80.6500,
        ),
      ),
      DealMatchCandidate(
        id: 'outside-radius',
        deal: deal(
          intent: DealIntent.sell,
          subject: 'chicken',
          category: 'product',
          lat: 16.6000,
          lng: 80.7000,
        ),
      ),
    ]);

    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isTrue);
  });
}
