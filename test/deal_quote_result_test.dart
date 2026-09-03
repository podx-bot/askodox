import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/domain/deal_quote.dart';
import 'package:podx/features/deal_brain/domain/deal_quote_collection.dart';
import 'package:podx/features/deal_brain/domain/deal_quote_result.dart';

void main() {
  DealQuote quote(String seller, double amount, double hours, double trust) => DealQuote(
        sellerId: seller,
        amount: amount,
        leadTimeHours: hours,
        trustScore: trust,
      );

  test('creates buyer-facing recommendation labels from collected quotes', () {
    final collection = DealQuoteCollection(const <DealQuote>[])
        .add(quote('seller-a', 1000, 48, 70))
        .add(quote('seller-b', 1200, 4, 75))
        .add(quote('seller-c', 1050, 24, 95));

    final result = DealQuoteResult.fromCollection(collection);

    expect(result.hasQuotes, isTrue);
    expect(result.labelFor(result.quotes.firstWhere((q) => q.sellerId == 'seller-a')), 'Cheapest');
    expect(result.labelFor(result.quotes.firstWhere((q) => q.sellerId == 'seller-b')), 'Fastest');
    expect(result.labelFor(result.quotes.firstWhere((q) => q.sellerId == 'seller-c')), 'Best Value');
  });

  test('combines labels when one seller wins multiple recommendations', () {
    final collection = DealQuoteCollection(const <DealQuote>[])
        .add(quote('seller-a', 900, 4, 99))
        .add(quote('seller-b', 1200, 24, 70));

    final result = DealQuoteResult.fromCollection(collection);
    final winner = result.quotes.firstWhere((q) => q.sellerId == 'seller-a');

    expect(result.labelFor(winner), contains('Cheapest'));
    expect(result.labelFor(winner), contains('Fastest'));
    expect(result.labelFor(winner), contains('Best Value'));
  });
}
