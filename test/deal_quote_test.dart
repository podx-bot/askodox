import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/deal_quote.dart';

void main() {
  test('quote normalized total includes tax and delivery', () {
    const quote = DealQuote(
      sellerId: 'seller-a',
      amount: 1000,
      tax: 50,
      deliveryFee: 100,
    );

    expect(quote.normalizedTotal, 1150);
  });

  test('cheapest compares normalized totals instead of base price only', () {
    const quotes = [
      DealQuote(sellerId: 'seller-a', amount: 900, deliveryFee: 300),
      DealQuote(sellerId: 'seller-b', amount: 1050, deliveryFee: 50),
    ];

    expect(DealQuoteComparison.cheapest(quotes)?.sellerId, 'seller-b');
  });

  test('fastest selects shortest available lead time', () {
    const quotes = [
      DealQuote(sellerId: 'seller-a', amount: 1000, leadTimeHours: 24),
      DealQuote(sellerId: 'seller-b', amount: 1100, leadTimeHours: 4),
    ];

    expect(DealQuoteComparison.fastest(quotes)?.sellerId, 'seller-b');
  });

  test('best value can prefer stronger trust and speed over tiny price gap', () {
    const quotes = [
      DealQuote(sellerId: 'seller-a', amount: 1000, trustScore: 50, leadTimeHours: 48),
      DealQuote(sellerId: 'seller-b', amount: 1050, trustScore: 95, leadTimeHours: 6),
    ];

    expect(DealQuoteComparison.bestValue(quotes)?.sellerId, 'seller-b');
  });
}
