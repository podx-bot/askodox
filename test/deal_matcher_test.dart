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

  UniversalDeal service({
    required DealIntent intent,
    required String subject,
    required double lat,
    required double lng,
    double radiusKm = 10,
  }) {
    return brain.capture(subject).copyWith(
          intent: intent,
          subject: subject,
          category: 'service',
          fulfilment: 'onsite',
          location: DealLocation(
            label: 'Vijayawada',
            latitude: lat,
            longitude: lng,
            radiusKm: radiusKm,
          ),
        );
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

  test('matches correct service provider inside radius and rejects outside provider', () {
    final request = service(
      intent: DealIntent.needService,
      subject: 'electrician',
      lat: 16.5062,
      lng: 80.6480,
      radiusKm: 8,
    );
    final nearby = service(
      intent: DealIntent.offerService,
      subject: 'electrician',
      lat: 16.5150,
      lng: 80.6550,
      radiusKm: 10,
    );
    final farAway = service(
      intent: DealIntent.offerService,
      subject: 'electrician',
      lat: 16.6100,
      lng: 80.7200,
      radiusKm: 20,
    );
    final plumber = service(
      intent: DealIntent.offerService,
      subject: 'plumber',
      lat: 16.5100,
      lng: 80.6500,
      radiusKm: 10,
    );

    final result = matcher.match(request, [
      DealMatchCandidate(id: 'near-electrician', deal: nearby, trustScore: 80),
      DealMatchCandidate(id: 'far-electrician', deal: farAway, trustScore: 95),
      DealMatchCandidate(id: 'near-plumber', deal: plumber, trustScore: 100),
    ]);

    expect(result.matches.map((m) => m.candidate.id), ['near-electrician']);
    expect(result.matches.first.distanceKm, isNotNull);
    expect(result.matches.first.distanceKm!, lessThan(8));
  });

  test('nearer provider ranks first when trust is equal', () {
    final request = service(
      intent: DealIntent.needService,
      subject: 'electrician',
      lat: 16.5062,
      lng: 80.6480,
      radiusKm: 20,
    );
    final near = service(
      intent: DealIntent.offerService,
      subject: 'electrician',
      lat: 16.5100,
      lng: 80.6500,
      radiusKm: 20,
    );
    final farther = service(
      intent: DealIntent.offerService,
      subject: 'electrician',
      lat: 16.5600,
      lng: 80.6800,
      radiusKm: 20,
    );

    final result = matcher.match(request, [
      DealMatchCandidate(id: 'farther', deal: farther, trustScore: 90),
      DealMatchCandidate(id: 'near', deal: near, trustScore: 90),
    ]);

    expect(result.matches.first.candidate.id, 'near');
  });
}
