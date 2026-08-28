import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

void main() {
  group('UniversalMatch totalValueScore', () {
    test('rewards trust, availability and proximity beyond backend score', () {
      const strongerOverall = UniversalMatch(
        id: 'near-trusted',
        title: 'Near trusted provider',
        score: 80,
        trustScore: 95,
        availabilityScore: 95,
        distanceKm: 2,
      );
      const weakerOverall = UniversalMatch(
        id: 'far-low-trust',
        title: 'Far lower-trust provider',
        score: 82,
        trustScore: 30,
        availabilityScore: 30,
        distanceKm: 40,
      );

      expect(strongerOverall.totalValueScore, greaterThan(weakerOverall.totalValueScore));
    });

    test('uses neutral fallback values when optional signals are missing', () {
      const match = UniversalMatch(
        id: 'fallback',
        title: 'Fallback provider',
        score: 50,
      );

      expect(match.totalValueScore, closeTo(50.0, 0.001));
    });

    test('clamps out-of-range signals before ranking', () {
      const match = UniversalMatch(
        id: 'clamped',
        title: 'Clamped provider',
        score: 200,
        trustScore: 150,
        availabilityScore: -20,
        distanceKm: 100,
      );

      expect(match.totalValueScore, closeTo(75.0, 0.001));
    });

    test('parses trust and availability aliases from backend payload', () {
      final match = UniversalMatch.fromJson({
        'id': 'provider-1',
        'name': 'Provider',
        'score': 70,
        'trust': 88,
        'availability_fit': 76,
        'distance_km': 5,
      });

      expect(match.trustScore, 88);
      expect(match.availabilityScore, 76);
      expect(match.distanceKm, 5);
    });
  });
}
