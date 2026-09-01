import 'package:flutter_test/flutter_test.dart';
import 'package:askodox/features/deal_brain/application/domain_brain_registry.dart';
import 'package:askodox/features/deal_brain/application/natural_deal_brain.dart';

void main() {
  const brain = NaturalDealBrain();

  test('insurance request uses insurance behaviour, not commerce fields', () {
    final result = brain.understand('I need health insurance for my family with low premium');

    expect(result.domain, NaturalDomain.insurance);
    expect(result.profile.requiredSignals, contains('policy_need'));
    expect(result.profile.actions, contains('compare_coverage'));
    expect(result.profile.requiredSignals, isNot(contains('item')));
    expect(result.profile.requiredSignals, isNot(contains('quantity')));
  });

  test('job request uses job behaviour, not product buying behaviour', () {
    final result = brain.understand('I need a night shift delivery job in Vijayawada');

    expect(result.domain, NaturalDomain.jobs);
    expect(result.profile.requiredSignals, contains('role_or_skill'));
    expect(result.profile.actions, contains('match_jobs'));
    expect(result.profile.actions, isNot(contains('order_or_connect')));
  });

  test('ride request asks route signals rather than product specifications', () {
    final result = brain.understand('I need a ride from Vijayawada to Guntur tonight');

    expect(result.domain, NaturalDomain.rides);
    expect(result.profile.requiredSignals, containsAll(['pickup', 'drop']));
    expect(result.profile.requiredSignals, isNot(contains('item')));
  });

  test('chicken stays in fresh-food behaviour only', () {
    final result = brain.understand('I want 2 kg fresh chicken curry cut delivered today');

    expect(result.domain, NaturalDomain.freshFood);
    expect(result.profile.requiredSignals, containsAll(['item', 'quantity']));
    expect(result.profile.optionalSignals, contains('cut_or_variant'));
  });

  test('unknown goal falls back to open-ended general brain', () {
    final result = brain.understand('Help me organize something important for tomorrow');

    expect(result.domain, NaturalDomain.general);
    expect(result.profile.requiredSignals, ['goal']);
    expect(result.profile.actions, contains('ask_missing_only'));
  });

  test('missing questions are limited to unresolved domain signals', () {
    final result = brain.understand('I need insurance');
    final missing = brain.missingRequiredSignals(
      result,
      knownSignals: const ['policy_need'],
    );

    expect(missing, isEmpty);
  });
}
