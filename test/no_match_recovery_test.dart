import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/no_match_recovery.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const recovery = NoMatchRecovery();

  UniversalDeal request({String fulfilment = 'pickup'}) => UniversalDeal(
        rawText: 'Need rice in Vijayawada',
        intent: DealIntent.buy,
        partyA: const DealPartyRequirement(
          side: DealSide.demand,
          role: 'buyer',
          action: 'needs product',
        ),
        partyB: const DealPartyRequirement(
          side: DealSide.supply,
          role: 'seller',
          action: 'can supply product',
        ),
        subject: 'rice',
        category: 'product',
        quantity: 10,
        unit: 'kg',
        fulfilment: fulfilment,
        location: const DealLocation(label: 'Vijayawada'),
        status: DealStatus.readyToMatch,
      );

  test('creates admin signal with captured request context', () {
    final plan = recovery.build(request());

    expect(plan.adminSignal.reason, 'no_relevant_local_match');
    expect(plan.adminSignal.intent, DealIntent.buy);
    expect(plan.adminSignal.subject, 'rice');
    expect(plan.adminSignal.location, 'Vijayawada');
    expect(plan.adminSignal.category, 'product');
  });

  test('local no-match tries wider local search before external fallbacks', () {
    final plan = recovery.build(request());

    expect(plan.actions.first.kind, NoMatchFallbackKind.broadenLocalRadius);
    expect(plan.actions.map((a) => a.kind), contains(NoMatchFallbackKind.onlineSuggestion));
    expect(plan.actions.map((a) => a.kind), contains(NoMatchFallbackKind.adminReview));
  });

  test('online request does not add local-radius fallback', () {
    final plan = recovery.build(request(fulfilment: 'online'));

    expect(
      plan.actions.map((a) => a.kind),
      isNot(contains(NoMatchFallbackKind.broadenLocalRadius)),
    );
  });
}
