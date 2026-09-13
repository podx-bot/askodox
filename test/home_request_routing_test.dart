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

    test('routes explicit transactional requests to matching', () {
      expect(AskodoxHomeRequestRouting.isTransactional('చికెన్ కొనాలి'), isTrue);
      expect(AskodoxHomeRequestRouting.isTransactional('I need AC repair'), isTrue);
      expect(AskodoxHomeRequestRouting.isTransactional('నాకు ఉద్యోగం కావాలి'), isTrue);
      expect(AskodoxHomeRequestRouting.isTransactional('Send a parcel'), isTrue);
    });
  });
}
