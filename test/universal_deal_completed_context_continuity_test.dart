import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('same completed request preserves known location instead of replacing active deal', () {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone');

    expect(controller.state.deal, isNotNull);
    expect(controller.state.deal!.subject?.toLowerCase(), contains('phone'));
    expect(controller.state.completed, isFalse);

    controller.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );

    expect(controller.state.completed, isTrue);
    expect(controller.state.deal!.location.label, 'Vijayawada');

    controller.start('I want to buy a phone');

    expect(controller.state.completed, isTrue);
    expect(controller.state.deal!.subject?.toLowerCase(), contains('phone'));
    expect(controller.state.deal!.location.label, 'Vijayawada');
    expect(controller.state.deal!.location.latitude, 16.5062);
    expect(controller.state.deal!.location.longitude, 80.6480);
  });

  test('different completed request becomes the single new active deal', () {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone');
    controller.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );
    expect(controller.state.completed, isTrue);

    controller.start('I want to buy a laptop');

    expect(controller.state.deal!.subject?.toLowerCase(), contains('laptop'));
    expect(controller.state.deal!.subject?.toLowerCase(), isNot(contains('phone')));
    expect(controller.state.deal!.location.isKnown, isFalse);
    expect(controller.state.completed, isFalse);
  });
}
