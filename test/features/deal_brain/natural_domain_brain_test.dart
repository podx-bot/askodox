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

  test('service request stays in service behaviour', () {
    final result = brain.understand('I need an electrician today near me');

    expect(result.domain, NaturalDomain.services);
    expect(result.goal.id, 'service_solve');
    expect(result.profile.requiredSignals, containsAll(['problem_or_service', 'location']));
    expect(result.profile.requiredSignals, isNot(contains('item')));
    expect(result.profile.actions, contains('match_provider'));
  });

  test('doctor booking stays in appointment behaviour', () {
    final result = brain.understand('Book a doctor appointment tomorrow morning');

    expect(result.domain, NaturalDomain.appointments);
    expect(result.goal.id, 'appointment_book');
    expect(result.profile.requiredSignals, contains('professional_or_service'));
    expect(result.profile.actions, contains('find_slots'));
    expect(result.profile.actions, isNot(contains('match_seller')));
  });

  test('loan query stays in loan behaviour', () {
    final result = brain.understand('I need a personal loan of 5 lakh');

    expect(result.domain, NaturalDomain.loans);
    expect(result.goal.id, 'loans_goal');
    expect(result.profile.requiredSignals, containsAll(['loan_purpose', 'amount']));
    expect(result.profile.actions, contains('compare_eligibility'));
    expect(result.profile.requiredSignals, isNot(contains('item')));
  });

  test('property request stays in property behaviour', () {
    final result = brain.understand('I want to rent a 2 BHK house in Vijayawada');

    expect(result.domain, NaturalDomain.property);
    expect(result.goal.id, 'property_goal');
    expect(result.profile.requiredSignals, containsAll(['buy_rent_intent', 'location']));
    expect(result.profile.actions, contains('match_property'));
    expect(result.profile.actions, isNot(contains('order_or_connect')));
  });

  test('chicken stays in fresh-food behaviour only', () {
    final result = brain.understand('I want 2 kg fresh chicken curry cut delivered today');

    expect(result.domain, NaturalDomain.freshFood);
    expect(result.goal.id, 'commerce_transaction');
    expect(result.profile.requiredSignals, containsAll(['item', 'quantity']));
    expect(result.profile.optionalSignals, contains('cut_or_variant'));
    expect(result.deal.dynamicFields['productKind'], 'chicken');
  });

  test('chicken wording inside a job does not inject food fields', () {
    final result = brain.understand('I need a chicken delivery job in Vijayawada');

    expect(result.domain, NaturalDomain.jobs);
    expect(result.deal.dynamicFields, isNot(contains('productKind')));
    expect(result.deal.dynamicFields, isNot(contains('freshness')));
    expect(result.deal.dynamicFields, isNot(contains('cut')));
    expect(result.deal.dynamicFields, isNot(contains('chickenPreference')));
  });

  test('chicken wording inside insurance does not inject food fields', () {
    final result = brain.understand('I need insurance for my chicken farm');

    expect(result.domain, NaturalDomain.insurance);
    expect(result.deal.dynamicFields, isNot(contains('productKind')));
    expect(result.deal.dynamicFields, isNot(contains('freshness')));
    expect(result.deal.dynamicFields, isNot(contains('cut')));
    expect(result.deal.dynamicFields, isNot(contains('chickenPreference')));
  });

  test('unknown goal stays open-ended and can derive a new schema', () {
    final result = brain.understand('Help me organize something important for tomorrow');

    expect(result.domain, NaturalDomain.general);
    expect(result.goal.id, 'open_ended');
    expect(result.goal.actions, contains('derive_schema'));
    expect(result.goal.requiredSignals, ['goal']);
    expect(result.deal.category, isNull);
  });

  test('new event-planning goal does not fall back to commerce', () {
    final result = brain.understand('Help me plan a birthday event tomorrow');

    expect(result.domain, NaturalDomain.general);
    expect(result.goal.id, 'open_ended');
    expect(result.deal.category, isNull);
    expect(result.profile.requiredSignals, isNot(contains('item')));
    expect(result.goal.actions, contains('derive_schema'));
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
