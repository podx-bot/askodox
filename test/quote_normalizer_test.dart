import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/deal_quote.dart';
import 'package:podx/features/deal_brain/domain/quote_normalizer.dart';

void main() {
  test('normalizes total quote with GST delivery and timeline', () {
    final quote = QuoteNormalizer.fromText(
      sellerId: 'seller-a',
      text: 'Total ₹10000, GST ₹500, delivery ₹250, delivery in 2 days',
      trustScore: 90,
    );
    expect(quote.amount, 10000);
    expect(quote.tax, 500);
    expect(quote.deliveryFee, 250);
    expect(quote.normalizedTotal, 10750);
    expect(quote.leadTimeHours, 48);
    expect(quote.kind, QuoteKind.totalPrice);
  });

  test('normalizes unit-price quote', () {
    final quote = QuoteNormalizer.fromText(
      sellerId: 'chicken-seller',
      text: '₹220 per kg, delivery ₹100, 4 hours',
    );
    expect(quote.amount, 220);
    expect(quote.kind, QuoteKind.unitPrice);
    expect(quote.priceBasis, 'per kg');
    expect(quote.deliveryFee, 100);
    expect(quote.leadTimeHours, 4);
  });

  test('normalized seller text can enter quote comparison', () {
    final a = QuoteNormalizer.fromText(sellerId: 'a', text: 'Total ₹1000, delivery ₹200');
    final b = QuoteNormalizer.fromText(sellerId: 'b', text: 'Total ₹1100, delivery ₹20');
    expect(DealQuoteComparison.cheapest(<DealQuote>[a, b])?.sellerId, 'b');
  });

  test('parses comma prices GST included free delivery and tomorrow', () {
    final quote = QuoteNormalizer.fromText(
      sellerId: 'seller-real',
      text: 'Total ₹25,000, GST included, free delivery tomorrow',
    );
    expect(quote.amount, 25000);
    expect(quote.tax, 0);
    expect(quote.deliveryFee, 0);
    expect(quote.leadTimeHours, 24);
    expect(quote.dynamicFields['gstIncluded'], true);
    expect(quote.dynamicFields['freeDelivery'], true);
  });

  test('parses GST extra validity payment terms and warranty', () {
    final now = DateTime(2026, 9, 3, 10);
    final quote = QuoteNormalizer.fromText(
      sellerId: 'seller-terms',
      text: 'Total ₹18,500, GST extra ₹925, validity 3 days, payment terms: 50% advance, 12 months warranty',
      now: now,
    );
    expect(quote.amount, 18500);
    expect(quote.tax, 925);
    expect(quote.validUntil, now.add(const Duration(days: 3)));
    expect(quote.paymentTerms, '50% advance');
    expect(quote.warrantyOrReturn, '12 months warranty');
  });
}
