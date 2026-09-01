import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/domain_brain_registry.dart';
import 'package:podx/features/deal_brain/application/natural_deal_brain.dart';

void main() {
  const brain = NaturalDealBrain();

  test('insurance request uses insurance behaviour, not commerce fields', () {
    final result = brain.understand('I need health insurance for my family with low premium');

    expect(result.domain, NaturalDomain.insurance);
    expect(result.goal.id, 'insurance_new_policy');
    expect(result.profile.requiredSignals, contains('policy_need'));
    expect(result.profile.actions, contains('compare_coverage'));
    expect(result.profile.requiredSignals, isNot(contains('item')));
    expect(result.profile.requiredSignals, isNot(contains('quantity')));
  });

  test('insurance renewal is a distinct goal inside insurance', () {
    final result = brain.understand('I want to renew my insurance policy');

    expect(result.domain, NaturalDomain.insurance);
    expect(result.goal.id, 'insurance_renewal');
    expect(result.goal.requiredSignals, contains('existing_policy'));
    expect(result.goal.actions, contains('compare_renewal'));
  });

  test('insurance claim is not treated as buying a policy', () {
    final result = brain.understand('I need help with an insurance claim');

    expect(result.domain, NaturalDomain.insurance);
    expect(result.goal.id, 'insurance_claim');
    expect(result.goal.actions, contains('check_documents'));
    expect(result.goal.actions, isNot(contains('compare_coverage')));
  });

  test('job request uses job behaviour, not product buying behaviour', () {
    final result = brain.understand('I need a night shift delivery job in Vijayawada');

    expect(result.domain, NaturalDomain.jobs);
    expect(result.goal.id, 'jobs_find_work');
    expect(result.profile.requiredSignals, contains('role_or_skill'));
    expect(result.profile.actions, contains('match_jobs'));
    expect(result.profile.actions, isNot(contains('order_or_connect')));
  });

  test('hiring is a distinct jobs goal from seeking work', () {
    final result = brain.understand('I want to hire a delivery driver in Vijayawada');

    expect(result.domain, NaturalDomain.jobs);
    expect(result.goal.id, 'jobs_hire');
    expect(result.goal.actions, contains('match_candidates'));
    expect(result.goal.actions, isNot(contains('match_jobs')));
  });

  test('ride request asks route signals rather than product specifications', () {
    final result = brain.understand('I need a ride from Vijayawada to Guntur tonight');

    expect(result.domain, NaturalDomain.rides);
    expect(result.goal.id, 'ride_arrange');
    expect(result.profile.requiredSignals, containsAll(['pickup', 'drop']));
    expect(result.profile.requiredSignals, isNot(contains('item')));
  });

  test('chicken stays in fresh-food behaviour only', () {
    final result = brain.understand('I want 2 kg fresh chicken curry cut delivered today');

    expect(result.domain, NaturalDomain.freshFood);
    expect(result.goal.id, 'commerce_transaction');
    expect(result.profile.requiredSignals, containsAll(['item', 'quantity']));
    expect(result.profile.optionalSignals, contains('cut_or_variant'));
  });

  test('unknown goal stays open-ended and can derive a new schema', () {
    final result = brain.understand('Help me organize something important for tomorrow');

    expect(result.domain, NaturalDomain.general);
    expect(result.goal.id, 'open_ended');
    expect(result.goal.actions, contains('derive_schema'));
    expect(result.goal.requiredSignals, ['goal']);
    expect(result.deal.category, isNull);
  });

  test('missing questions follow the resolved goal, not only broad domain', () {
    final result = brain.understand('I want to renew my insurance policy');
    final missing = brain.missingRequiredSignals(
      result,
      knownSignals: const ['existing_policy'],
    );

    expect(missing, isEmpty);
  });
}
