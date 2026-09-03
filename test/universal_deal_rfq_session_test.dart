import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('completed conversation accepts seller quotes and compares them', () async {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone near Vijayawada');

    expect(controller.state.completed, isTrue);
    expect(controller.state.rfqRequest, isNotNull);

    controller.ingestSellerQuote(
      sellerId: 'seller-a',
      text: 'Total ₹25,000, delivery ₹300, delivery in 2 days',
      trustScore: 75,
    );
    controller.ingestSellerQuote(
      sellerId: 'seller-b',
      text: 'Total ₹26,000, free delivery, delivery in 4 hours',
      trustScore: 90,
    );

    expect(controller.state.quoteCollection.quotes, hasLength(2));
    expect(controller.state.quoteResult.cheapest?.sellerId, 'seller-a');
    expect(controller.state.quoteResult.fastest?.sellerId, 'seller-b');

    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('seller quotes restore with the active persistent deal', () async {
    final controller = UniversalDealController();
    controller.start('I want to buy a phone near Vijayawada');
    controller.ingestSellerQuote(
      sellerId: 'seller-a',
      text: 'Total ₹25,000, delivery in 1 day',
      trustScore: 88,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    final restored = UniversalDealController();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(restored.state.completed, isTrue);
    expect(restored.state.quoteCollection.quotes, hasLength(1));
    expect(restored.state.quoteCollection.quotes.single.sellerId, 'seller-a');
    expect(restored.state.quoteCollection.quotes.single.amount, 25000);
    expect(restored.state.quoteResult.cheapest?.sellerId, 'seller-a');
  });
}
