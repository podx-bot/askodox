import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/deal_matcher.dart';
import 'package:podx/features/deal_brain/domain/no_match_recovery.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const brain = UniversalDealBrain();
  const matcher = DealMatcher();

  test('incomplete request does not trigger no-match recovery', () {
    final incomplete = brain.capture('buy nearby');

    expect(incomplete.readyToMatch, isFalse);
    final result = matcher.match(incomplete, const <DealMatchCandidate>[]);

    expect(result.hasLocalMatch, isFalse);
    expect(result.needsNoMatchRecovery, isFalse);
    expect(result.recovery, isNull);
  });

  test('ready product buy no-match attaches buying fallbacks', () {
    final request = brain.capture('I want to buy 10 kg rice in Vijayawada').copyWith(
          subject: 'rice',
          category: 'product',
          quantity: 10,
          unit: 'kg',
          fulfilment: 'pickup',
          location: const DealLocation(label: 'Vijayawada'),
        );

    final result = matcher.match(request, const <DealMatchCandidate>[]);
    final kinds = result.recovery!.actions.map((a) => a.kind);

    expect(result.needsNoMatchRecovery, isTrue);
    expect(kinds, contains(NoMatchFallbackKind.onlineSuggestion));
    expect(kinds, contains(NoMatchFallbackKind.affiliateSuggestion));
  });

  test('ready service no-match has no ecommerce fallback', () {
    final request = brain.capture('need service').copyWith(
          intent: DealIntent.needService,
          subject: 'plumber',
          category: 'service',
          fulfilment: 'onsite',
          location: const DealLocation(label: 'Vijayawada'),
        );

    final result = matcher.match(request, const <DealMatchCandidate>[]);
    final kinds = result.recovery!.actions.map((a) => a.kind);

    expect(result.needsNoMatchRecovery, isTrue);
    expect(kinds, isNot(contains(NoMatchFallbackKind.onlineSuggestion)));
    expect(kinds, isNot(contains(NoMatchFallbackKind.affiliateSuggestion)));
    expect(kinds, contains(NoMatchFallbackKind.adminReview));
  });
}
