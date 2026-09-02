import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';

const demand = DealPartyRequirement(
  side: DealSide.demand,
  role: 'user',
  action: 'need',
);
const supply = DealPartyRequirement(
  side: DealSide.supply,
  role: 'provider',
  action: 'offer',
);

UniversalDeal deal({
  required DealIntent intent,
  String? subject,
  String? timing,
  DealLocation location = const DealLocation(),
  Map<String, Object?> dynamicFields = const {},
}) => UniversalDeal(
      rawText: 'test request',
      intent: intent,
      partyA: demand,
      partyB: supply,
      subject: subject,
      timing: timing,
      location: location,
      dynamicFields: dynamicFields,
    );

void main() {
  group('UniversalDeal required fields stay aligned with backend policies', () {
    test('appointment requires timing after subject and location are known', () {
      final value = deal(
        intent: DealIntent.bookAppointment,
        subject: 'doctor',
        location: const DealLocation(label: 'Vijayawada'),
      );

      expect(value.missingForMatch, ['timing']);
      expect(value.readyToMatch, isFalse);
    });

    test('rental requires timing after subject and location are known', () {
      final value = deal(
        intent: DealIntent.rent,
        subject: 'house',
        location: const DealLocation(label: 'Vijayawada'),
      );

      expect(value.missingForMatch, ['timing']);
      expect(value.readyToMatch, isFalse);
    });

    test('parcel requires timing after route is known', () {
      final value = deal(
        intent: DealIntent.sendParcel,
        dynamicFields: const {
          'from': 'Vijayawada',
          'to': 'Hyderabad',
        },
      );

      expect(value.missingForMatch, ['timing']);
      expect(value.readyToMatch, isFalse);
    });

    test('appointment is ready when subject location and timing are present', () {
      final value = deal(
        intent: DealIntent.bookAppointment,
        subject: 'doctor',
        timing: 'Tomorrow morning',
        location: const DealLocation(label: 'Vijayawada'),
      );

      expect(value.missingForMatch, isEmpty);
      expect(value.readyToMatch, isTrue);
    });
  });
}
