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

  test('ride live flow never falls into product questions', () {
    final controller = UniversalDealController();

    controller.start('I need a ride to Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.dynamicFields['_domain'], 'rides');
    expect(deal.missingForMatch, isNot(contains('quantity')));
    expect(deal.missingForMatch, isNot(contains('freshness')));
    expect(deal.missingForMatch, isNot(contains('cut')));
  });
}
