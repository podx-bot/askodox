import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/no_match_recovery.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const recovery = NoMatchRecovery();

  UniversalDeal request({
    String fulfilment = 'pickup',
    DealIntent intent = DealIntent.buy,
    String subject = 'rice',
    String category = 'product',
  }) => UniversalDeal(
        rawText: 'Need $subject in Vijayawada',
        intent: intent,
        partyA: const DealPartyRequirement(
          side: DealSide.demand,
          role: 'requester',
          action: 'needs outcome',
        ),
        partyB: const DealPartyRequirement(
          side: DealSide.supply,
          role: 'provider',
          action: 'can fulfil outcome',
        ),
        subject: subject,
        category: category,
        quantity: intent == DealIntent.buy ? 10 : null,
        unit: intent == DealIntent.buy ? 'kg' : null,
        fulfilment: fulfilment,
        location: const DealLocation(label: 'Vijayawada'),
        dynamicFields: intent == DealIntent.needWorker
            ? const {'skill': 'electrician'}
            : const {},
        status: DealStatus.readyToMatch,
      );

  test('creates admin signal with captured request context', () {
    final plan = recovery.build(request())!;

    expect(plan.adminSignal.reason, 'no_relevant_local_match');
    expect(plan.adminSignal.intent, DealIntent.buy);
    expect(plan.adminSignal.subject, 'rice');
    expect(plan.adminSignal.location, 'Vijayawada');
    expect(plan.adminSignal.category, 'product');
  });

  test('product buyer gets local, online, affiliate, and admin recovery', () {
    final plan = recovery.build(request())!;
    final kinds = plan.actions.map((a) => a.kind);

    expect(plan.actions.first.kind, NoMatchFallbackKind.broadenLocalRadius);
    expect(kinds, contains(NoMatchFallbackKind.onlineSuggestion));
    expect(kinds, contains(NoMatchFallbackKind.affiliateSuggestion));
    expect(kinds, contains(NoMatchFallbackKind.adminReview));
  });

  test('online product buyer does not add local-radius fallback', () {
    final plan = recovery.build(request(fulfilment: 'online'))!;

    expect(
      plan.actions.map((a) => a.kind),
      isNot(contains(NoMatchFallbackKind.broadenLocalRadius)),
    );
  });

  test('service and job recovery never uses ecommerce fallbacks', () {
    final servicePlan = recovery.build(
      request(
        intent: DealIntent.needService,
        subject: 'plumber',
        category: 'service',
        fulfilment: 'onsite',
      ),
    )!;
    final jobPlan = recovery.build(
      request(
        intent: DealIntent.needWorker,
        subject: 'electrician',
        category: 'work',
        fulfilment: 'onsite',
      ),
    )!;

    for (final plan in [servicePlan, jobPlan]) {
      final kinds = plan.actions.map((a) => a.kind);
      expect(kinds, isNot(contains(NoMatchFallbackKind.onlineSuggestion)));
      expect(kinds, isNot(contains(NoMatchFallbackKind.affiliateSuggestion)));
      expect(kinds, contains(NoMatchFallbackKind.adminReview));
    }
  });

  test('incomplete request does not create no-match admin recovery', () {
    final incomplete = request().copyWith(subject: '');
    expect(incomplete.readyToMatch, isFalse);
    expect(recovery.build(incomplete), isNull);
  });
}
