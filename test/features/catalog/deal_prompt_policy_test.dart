import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/presentation/deal_prompt_policy.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

void main() {
  const demand = DealPartyRequirement(side: DealSide.demand, role: 'buyer', action: 'find');
  const supply = DealPartyRequirement(side: DealSide.supply, role: 'seller', action: 'offer');

  UniversalDeal deal({
    required String rawText,
    required DealIntent intent,
    String? subject,
  }) => UniversalDeal(
        rawText: rawText,
        intent: intent,
        partyA: demand,
        partyB: supply,
        subject: subject,
      );

  test('keeps chicken-specific quantity prompts only for chicken flow', () {
    final chicken = deal(rawText: 'I want chicken nearby', intent: DealIntent.buy, subject: 'chicken');
    final generic = deal(rawText: 'I want a laptop nearby', intent: DealIntent.buy, subject: 'laptop');

    expect(
      DealPromptPolicy.questionFor(deal: chicken, field: 'quantity', telugu: false),
      contains('chicken'),
    );
    expect(
      DealPromptPolicy.suggestionsFor(deal: chicken, field: 'quantity', telugu: false),
      ['1 kg', '2 kg', '3 kg'],
    );

    expect(
      DealPromptPolicy.questionFor(deal: generic, field: 'quantity', telugu: false),
      isNot(contains('chicken')),
    );
    expect(
      DealPromptPolicy.suggestionsFor(deal: generic, field: 'quantity', telugu: false),
      isEmpty,
    );
  });

  test('generic Telugu quantity prompt never says chicken', () {
    final generic = deal(rawText: 'నాకు ల్యాప్‌టాప్ కావాలి', intent: DealIntent.buy, subject: 'ల్యాప్‌టాప్');
    final prompt = DealPromptPolicy.questionFor(deal: generic, field: 'quantity', telugu: true);

    expect(prompt, isNot(contains('చికెన్')));
    expect(prompt, contains('quantity'));
  });

  test('job seeker and hiring prompts use the correct perspective', () {
    final seeker = deal(rawText: 'I need a job', intent: DealIntent.seekWork);
    final hiring = deal(rawText: 'I need a worker', intent: DealIntent.needWorker);

    expect(
      DealPromptPolicy.questionFor(deal: seeker, field: 'skill', telugu: false),
      'What job or skill are you looking for?',
    );
    expect(
      DealPromptPolicy.questionFor(deal: hiring, field: 'skill', telugu: false),
      'What work or skill should the person have?',
    );
  });

  test('service and ride flows do not expose chicken or kg suggestions', () {
    final service = deal(rawText: 'I need an electrician', intent: DealIntent.needService);
    final ride = deal(rawText: 'I need a ride to Vijayawada', intent: DealIntent.needRide);

    expect(
      DealPromptPolicy.questionFor(deal: service, field: 'subject', telugu: false),
      'What service do you need?',
    );
    expect(
      DealPromptPolicy.suggestionsFor(deal: ride, field: 'timing', telugu: false),
      ['Now', 'Today', 'Tomorrow'],
    );
    expect(
      DealPromptPolicy.suggestionsFor(deal: ride, field: 'quantity', telugu: false),
      isEmpty,
    );
  });
}
