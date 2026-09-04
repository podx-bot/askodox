import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/deal_lifecycle.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/deal_brain/domain/universal_negotiation.dart';

void main() {
  const brain = UniversalDealBrain();
  const lifecycle = DealLifecycleEngine();
  const negotiation = UniversalNegotiationEngine();

  UniversalDeal readyDeal() => brain.capture('Need rice').copyWith(
        intent: DealIntent.buy,
        subject: 'rice',
        category: 'product',
        quantity: 10,
        unit: 'kg',
        fulfilment: 'pickup',
        location: const DealLocation(label: 'Vijayawada'),
        status: DealStatus.readyToMatch,
      );

  test('match to negotiation to accepted price to completion', () {
    var state = lifecycle.initial(readyDeal());
    state = lifecycle.apply(state, DealLifecycleEvent.matchFound);
    expect(state.status, DealStatus.matched);

    state = lifecycle.apply(state, DealLifecycleEvent.negotiationStarted);
    expect(state.status, DealStatus.negotiating);

    final accepted = negotiation.evaluate(
      buyerOffer: 950,
      policy: const NegotiationPolicy(askingPrice: 1000, autoAcceptFloor: 900),
    );
    state = lifecycle.apply(
      state,
      DealLifecycleEvent.negotiationAccepted,
      negotiation: accepted,
    );
    expect(state.status, DealStatus.matched);
    expect(state.agreedPrice, 950);

    state = lifecycle.apply(state, DealLifecycleEvent.completed);
    expect(state.status, DealStatus.closed);
    expect(state.isTerminal, isTrue);
  });

  test('unresolved negotiation cannot silently set agreed price', () {
    var state = lifecycle.apply(
      lifecycle.initial(readyDeal()),
      DealLifecycleEvent.matchFound,
    );
    final unresolved = negotiation.evaluate(
      buyerOffer: 500,
      policy: const NegotiationPolicy(askingPrice: 1000, autoAcceptFloor: 900),
    );
    state = lifecycle.apply(
      state,
      DealLifecycleEvent.negotiationAccepted,
      negotiation: unresolved,
    );
    expect(state.agreedPrice, isNull);
    expect(state.status, DealStatus.matched);
  });

  test('open dispute blocks completion and requires admin review', () {
    var state = lifecycle.apply(
      lifecycle.initial(readyDeal()),
      DealLifecycleEvent.matchFound,
    );
    state = lifecycle.apply(
      state,
      DealLifecycleEvent.disputeRaised,
      disputeReason: 'Seller did not provide agreed item',
    );
    expect(state.hasOpenDispute, isTrue);
    expect(state.adminReviewRequired, isTrue);

    final blocked = lifecycle.apply(state, DealLifecycleEvent.completed);
    expect(blocked.status, DealStatus.matched);

    state = lifecycle.apply(state, DealLifecycleEvent.disputeResolved);
    expect(state.hasOpenDispute, isFalse);
    expect(state.adminReviewRequired, isFalse);

    state = lifecycle.apply(state, DealLifecycleEvent.completed);
    expect(state.status, DealStatus.closed);
  });

  test('closed deal cannot be cancelled', () {
    var state = lifecycle.apply(
      lifecycle.initial(readyDeal()),
      DealLifecycleEvent.matchFound,
    );
    state = lifecycle.apply(state, DealLifecycleEvent.completed);
    expect(state.status, DealStatus.closed);
    state = lifecycle.apply(state, DealLifecycleEvent.cancelled);
    expect(state.status, DealStatus.closed);
  });

  test('blank dispute reason is ignored', () {
    var state = lifecycle.apply(
      lifecycle.initial(readyDeal()),
      DealLifecycleEvent.matchFound,
    );
    state = lifecycle.apply(
      state,
      DealLifecycleEvent.disputeRaised,
      disputeReason: '   ',
    );
    expect(state.disputeState, DealDisputeState.none);
    expect(state.adminReviewRequired, isFalse);
  });
}
