import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/semantic_deal_input.dart';
import 'package:podx/services/in_app_assistant_service.dart';

void main() {
  test('canonicalizes Telugu chicken quantity and unit for deal capture', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'ok',
      'domain': 'FOOD',
      'transactional': true,
      'action': 'buy',
      'confidence': 0.99,
      'source': 'universal_ai',
      'entities': {
        'subject': 'chicken',
        'quantity': 5,
        'unit': 'కిలోల',
      },
    });

    expect(
      AskodoxSemanticDealInput.build('నాకు 5 కిలోల చికెన్ కావాలి', decision),
      'i want to buy 5 kg chicken',
    );
  });

  test('preserves semantic location when Universal AI supplied it', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'ok',
      'domain': 'PRODUCT',
      'transactional': true,
      'action': 'buy',
      'confidence': 0.99,
      'source': 'universal_ai',
      'entities': {
        'subject': 'TV',
        'quantity': 1,
        'unit': 'piece',
        'location': 'Vijayawada',
      },
    });

    expect(
      AskodoxSemanticDealInput.build('నాకు టీవీ కావాలి', decision),
      'i want to buy 1 pieces TV in Vijayawada',
    );
  });

  test('preserves seller intent for product listings', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'ok',
      'domain': 'PRODUCT',
      'transactional': true,
      'action': 'create_listing',
      'confidence': 0.99,
      'source': 'universal_ai',
      'entities': {'subject': 'Homemade Mango Pickle'},
    });

    expect(
      AskodoxSemanticDealInput.build('I want to sell homemade mango pickle', decision),
      'i want to sell Homemade Mango Pickle',
    );
  });

  test('uses offer phrasing for a service provider', () {
    final decision = InAppAssistantDecision.fromJson({
      'reply': 'ok',
      'domain': 'SERVICE',
      'transactional': true,
      'action': 'provide_service',
      'confidence': 0.99,
      'source': 'universal_ai',
      'entities': {'service': 'AC repair'},
    });

    expect(
      AskodoxSemanticDealInput.build('I provide AC repair', decision),
      'offer service AC repair',
    );
  });
}
