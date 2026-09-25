import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/home/domain/home_request_routing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UniversalDealController> _controller() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final controller = UniversalDealController();
  await Future<void>.delayed(Duration.zero);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chicken short answers fill the detail they describe, in any order', () async {
    final c = await _controller();
    c.start('I want to buy chicken in Vijayawada');
    expect(c.state.lastQuestion, 'How much chicken do you need?');

    c.answer('curry cut');
    c.answer('1 kg');
    c.answer('skinless');
    c.answer('fresh');
    expect(c.state.deal!.readyToMatch, isFalse);
    c.answer('delivery');

    final deal = c.state.deal!;
    expect(deal.readyToMatch, isTrue);
    expect(deal.quantity, 1);
    expect(deal.unit, 'kg');
    expect(deal.dynamicFields['cut'], 'curry cut');
    expect(deal.dynamicFields['chickenPreference'], 'skinless');
    expect(deal.dynamicFields['freshness'], 'fresh');
    expect(deal.fulfilment, 'delivery');
    expect(c.state.completed, isTrue);
  });

  test('"delivery" is fulfilment, never freshness ("live" inside "delivery")', () async {
    final c = await _controller();
    c.start('I want to buy chicken in Vijayawada');
    c.answer('home delivery');
    expect(c.state.deal!.fulfilment, 'delivery');
    expect(c.state.deal!.dynamicFields.containsKey('freshness'), isFalse);
  });

  test('Telugu short answers are slotted too', () async {
    final c = await _controller();
    c.start('నాకు విజయవాడలో చికెన్ కావాలి');
    c.answer('కర్రీ కట్');
    c.answer('1 కిలో');
    c.answer('స్కిన్‌లెస్');
    c.answer('ఫ్రెష్');
    c.answer('డెలివరీ');
    final deal = c.state.deal!;
    expect(deal.quantity, 1);
    expect(deal.unit, 'kg');
    expect(deal.dynamicFields['cut'], 'కర్రీ కట్');
    expect(deal.dynamicFields['chickenPreference'], 'స్కిన్‌లెస్');
    expect(deal.fulfilment, 'delivery');
    expect(deal.missingForMatch, ['location']);
  });

  test('an answer describing no known detail still answers the pending question', () async {
    final c = await _controller();
    c.start('I want to buy chicken in Vijayawada');
    c.answer('two birds');
    expect(c.state.deal!.dynamicFields['quantityText'], 'two birds');
  });

  test('TV size stated up front is kept and not asked again', () async {
    final c = await _controller();
    c.start('I want to buy a 43 inch TV in Vijayawada');
    expect(c.state.deal!.size, '43 inch');
    expect(c.state.deal!.readyToMatch, isTrue);

    c.reset();
    c.start('I want to buy a TV');
    expect(c.state.lastQuestion, 'What TV screen size do you prefer?');
    c.answer('55-inch');
    expect(c.state.deal!.size, '55 inch');
  });

  test('screen size parser ignores plain counts', () {
    expect(UniversalDealBrain.screenSizeIn('43 inch tv'), '43 inch');
    expect(UniversalDealBrain.screenSizeIn('a 32" tv'), '32 inch');
    expect(UniversalDealBrain.screenSizeIn('buy 10 in vijayawada'), isNull);
  });

  test('short detail answers vs new requests and asides', () {
    for (final answer in ['curry cut', '1 kg', 'skinless', 'fresh', 'delivery',
        'home delivery', 'కర్రీ కట్', '1 కిలో', 'డెలివరీ', '43 inch', 'Samsung']) {
      expect(AskodoxHomeRequestRouting.isShortDetailAnswer(answer), isTrue, reason: answer);
    }
    for (final other in [
      'I want to sell my 2 bicycles',
      'I need AC repair',
      'send a parcel to Guntur',
      'what is the weather today?',
      'can you explain how compound interest works for a fixed deposit account',
    ]) {
      expect(AskodoxHomeRequestRouting.isShortDetailAnswer(other), isFalse, reason: other);
    }
  });
}
