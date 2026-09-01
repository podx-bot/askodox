import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('insurance request stays out of chicken flow', () {
    final controller = UniversalDealController();

    controller.start('I need insurance for my chicken farm');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'insurance');
    expect(deal.dynamicFields['productKind'], isNull);
    expect(deal.missingForMatch, isNot(contains('freshness')));
    expect(deal.missingForMatch, isNot(contains('cut')));
    expect(deal.missingForMatch, isNot(contains('chickenPreference')));
  });

  test('insurance claim keeps claim signals and never commerce fields', () {
    final controller = UniversalDealController();

    controller.start('I need help with an insurance claim');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'insurance');
    expect(deal.dynamicFields['_goal'], 'insurance_claim');
    expect(deal.missingForMatch, containsAll(['policy_or_provider', 'claim_need']));
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));

    controller.answer('Star Health');
    expect(controller.state.deal!.missingForMatch.first, 'claim_need');
  });

  test('insurance renewal stays a renewal flow', () {
    final controller = UniversalDealController();

    controller.start('I want to renew my insurance policy');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'insurance');
    expect(deal.dynamicFields['_goal'], 'insurance_renewal');
    expect(deal.missingForMatch, ['existing_policy']);
    expect(deal.missingForMatch, isNot(contains('policy_need')));
  });

  test('loan live flow asks for amount instead of commerce fields', () {
    final controller = UniversalDealController();

    controller.start('I need a personal loan');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'loans');
    expect(deal.missingForMatch, contains('amount'));
    expect(controller.state.lastQuestion, 'What amount do you need?');
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));
  });

  test('job live flow keeps role and location questions', () {
    final controller = UniversalDealController();

    controller.start('I need a job');

    expect(controller.state.deal!.dynamicFields['_domain'], 'jobs');
    expect(controller.state.deal!.missingForMatch.first, 'skill');
    expect(controller.state.lastQuestion, 'What skill or work is required?');

    controller.answer('computer operator');
    expect(controller.state.deal!.missingForMatch.first, 'location');
    expect(controller.state.lastQuestion, 'Where should ASKODOX find the match?');
  });

  test('specific job skips redundant skill question', () {
    final controller = UniversalDealController();

    controller.start('I need a computer operator job');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'jobs');
    expect(deal.dynamicFields['skill'], isNotNull);
    expect(deal.missingForMatch.first, 'location');
  });

  test('ride live flow never falls into product questions', () {
    final controller = UniversalDealController();

    controller.start('I need a ride to Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'rides');
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));
    expect(deal.missingForMatch, isNot(contains('cut')));
  });

  test('appointment request stays appointment-specific', () {
    final controller = UniversalDealController();

    controller.start('Book a doctor appointment tomorrow');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'appointments');
    expect(deal.dynamicFields['_goal'], 'appointment_book');
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));
  });

  test('property request stays out of commerce product questions', () {
    final controller = UniversalDealController();

    controller.start('I want a 2 BHK house in Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'property');
    expect(deal.missingForMatch, contains('buy_rent_intent'));
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));
  });
}
