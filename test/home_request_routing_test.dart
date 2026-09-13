import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/home_request_routing.dart';

void main() {
  group('AskodoxHomeRequestRouting', () {
    test('keeps general planning requests out of matching', () {
      expect(
        AskodoxHomeRequestRouting.isTransactional(
          'ఈ రోజు నా పనులు ప్లాన్ చేసుకోవడానికి సహాయం చేయి',
        ),
        isFalse,
      );
      expect(
        AskodoxHomeRequestRouting.isTransactional(
          'Help me plan my day and prioritise my tasks',
        ),
        isFalse,
      );
    });

    test('classifies explicit transactional requests', () {
      expect(AskodoxHomeRequestRouting.kindOf('చికెన్ కొనాలి'), AskodoxHomeRequestKind.food);
      expect(AskodoxHomeRequestRouting.kindOf('I need AC repair'), AskodoxHomeRequestKind.service);
      expect(AskodoxHomeRequestRouting.kindOf('నాకు ఉద్యోగం కావాలి'), AskodoxHomeRequestKind.job);
      expect(AskodoxHomeRequestRouting.kindOf('Send a parcel'), AskodoxHomeRequestKind.parcel);
      expect(AskodoxHomeRequestRouting.kindOf('delivery job kavali'), AskodoxHomeRequestKind.deliveryJob);
    });

    test('starts fresh when user switches category', () {
      expect(AskodoxHomeRequestRouting.shouldStartFresh('చికెన్ కొనాలి', 'AC repair కావాలి'), isTrue);
      expect(AskodoxHomeRequestRouting.shouldStartFresh('job kavali', 'delivery job kavali'), isTrue);
      expect(AskodoxHomeRequestRouting.shouldStartFresh('parcel పంపాలి', 'parcel today'), isFalse);
    });
  });
}
