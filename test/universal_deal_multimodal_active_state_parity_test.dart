import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('text voice and image-equivalent inputs converge on one active deal state', () {
    final controller = UniversalDealController();

    // Text entry creates the authoritative active deal.
    controller.start('I want to buy a phone');
    controller.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );

    final textDeal = controller.state.deal;
    expect(textDeal, isNotNull);
    expect(controller.state.completed, isTrue);
    expect(textDeal!.subject?.toLowerCase(), contains('phone'));
    expect(textDeal.location.label, 'Vijayawada');

    // Voice recognition feeds UniversalDealController.start(). The same
    // semantic request must merge into the current deal rather than reset it.
    controller.start('I want to buy a phone');
    final voiceDeal = controller.state.deal;
    expect(voiceDeal, isNotNull);
    expect(controller.state.completed, isTrue);
    expect(voiceDeal!.subject?.toLowerCase(), contains('phone'));
    expect(voiceDeal.location.label, 'Vijayawada');
    expect(voiceDeal.location.latitude, 16.5062);
    expect(voiceDeal.location.longitude, 80.6480);

    // Vision/OCR extraction also feeds UniversalDealController.start(). A
    // same-context extracted request must preserve the same authoritative
    // state and previously known fields.
    controller.start('I want to buy a phone');
    final imageDeal = controller.state.deal;
    expect(imageDeal, isNotNull);
    expect(controller.state.completed, isTrue);
    expect(imageDeal!.subject?.toLowerCase(), contains('phone'));
    expect(imageDeal.location.label, 'Vijayawada');
    expect(imageDeal.location.latitude, 16.5062);
    expect(imageDeal.location.longitude, 80.6480);
  });

  test('a genuinely different multimodal request replaces the single active context', () {
    final controller = UniversalDealController();

    controller.start('I want to buy a phone');
    controller.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );
    expect(controller.state.completed, isTrue);

    // A different explicit subject is a new request, not a revision of phone.
    controller.start('I want to buy a laptop');

    final next = controller.state.deal;
    expect(next, isNotNull);
    expect(next!.subject?.toLowerCase(), contains('laptop'));
    expect(next.subject?.toLowerCase(), isNot(contains('phone')));
    expect(next.location.isKnown, isFalse);
    expect(controller.state.completed, isFalse);
  });
}
