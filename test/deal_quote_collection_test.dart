import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/deal_quote.dart';
import 'package:podx/features/deal_brain/domain/deal_quote_collection.dart';

void main() {
  DealQuote quote(String seller, double amount, double hours, double trust) => DealQuote(
        sellerId: seller,
        amount: amount,
        leadTimeHours: hours,
        trustScore: trust,
      );

  test('collects seller quotes and exposes cheapest fastest best value', () {
    final collection = DealQuoteCollection(const <DealQuote>[])
        .add(quote('seller-a', 1000, 48, 70))
        .add(quote('seller-b', 1200, 4, 75))
        .add(quote('seller-c', 1050, 24, 95));

    expect(collection.cheapest?.sellerId, 'seller-a');
    expect(collection.fastest?.sellerId, 'seller-b');
    expect(collection.bestValue?.sellerId, 'seller-c');
    expect(collection.recommendations[QuoteRecommendation.cheapest]?.sellerId, 'seller-a');
    expect(collection.recommendations[QuoteRecommendation.fastest]?.sellerId, 'seller-b');
    expect(collection.recommendations[QuoteRecommendation.bestValue]?.sellerId, 'seller-c');
  });

  test('new quote from same seller replaces older quote', () {
    final collection = DealQuoteCollection(const <DealQuote>[])
        .add(quote('seller-a', 1200, 24, 80))
        .add(quote('seller-a', 900, 12, 80));

    expect(collection.quotes, hasLength(1));
    expect(collection.cheapest?.amount, 900);
    expect(collection.fastest?.leadTimeHours, 12);
  });
}
