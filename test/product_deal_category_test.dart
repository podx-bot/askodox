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

  test('general product does not force irrelevant quantity question', () {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone near Vijayawada');

    final deal = controller.state.deal!;
    expect(deal.productProfile, 'general');
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
}
