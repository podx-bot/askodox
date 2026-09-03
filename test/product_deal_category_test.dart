import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('grocery product asks quantity before matching', () {
    final controller = UniversalDealController();
    controller.start('I want to buy rice near Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.productProfile, 'grocery');
    expect(deal.missingForMatch.first, 'quantity');
    expect(controller.state.lastQuestion, 'How much do you need?');

    controller.answer('5 kg');

    expect(controller.state.deal?.quantity, 5);
    expect(controller.state.deal?.unit, 'kg');
    expect(controller.state.completed, isTrue);
    controller.dispose();
  });

  test('mobile phone category does not force irrelevant quantity question', () {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone near Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.productProfile, 'mobile_phone');
    expect(deal.missingForMatch, isEmpty);
    expect(controller.state.completed, isTrue);
    controller.dispose();
  });

  test('material product also captures quantity progressively', () {
    final controller = UniversalDealController();
    controller.start('I want to buy cement near Guntur');

    expect(controller.state.deal?.productProfile, 'material');
    expect(controller.state.deal?.missingForMatch.first, 'quantity');

    controller.answer('20 bags');

    expect(controller.state.deal?.quantity, 20);
    expect(controller.state.completed, isTrue);
    controller.dispose();
  });

  test('television uses category-specific size question and stores size', () {
    final controller = UniversalDealController();
    controller.start('I want to buy a TV near Vijayawada');

    expect(controller.state.deal?.productProfile, 'television');
    expect(controller.state.deal?.missingForMatch.first, 'size');
    expect(controller.state.lastQuestion, 'What TV screen size do you prefer?');

    controller.answer('55 inch');

    expect(controller.state.deal?.size, '55 inch');
    expect(controller.state.completed, isTrue);
    controller.dispose();
  });

  test('wholesale packaged goods asks quantity then pack size', () {
    final controller = UniversalDealController();
    controller.start('I want to buy masala wholesale near Guntur');

    expect(controller.state.deal?.productProfile, 'wholesale_packaged_goods');
    expect(controller.state.lastQuestion, 'How many packs, bags, cartons or units do you need?');

    controller.answer('10 bags');
    expect(controller.state.lastQuestion, 'What pack or bag size do you need?');

    controller.answer('25 kg');
    expect(controller.state.deal?.dynamicFields['packSize'], '25 kg');
    expect(controller.state.completed, isTrue);
    controller.dispose();
  });
}
