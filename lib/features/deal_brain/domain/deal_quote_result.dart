import 'deal_quote.dart';
import 'deal_quote_collection.dart';

class DealQuoteResult {
  const DealQuoteResult({
    required this.quotes,
    required this.cheapest,
    required this.fastest,
    required this.bestValue,
  });

  final List<DealQuote> quotes;
  final DealQuote? cheapest;
  final DealQuote? fastest;
  final DealQuote? bestValue;

  factory DealQuoteResult.fromCollection(DealQuoteCollection collection) {
    return DealQuoteResult(
      quotes: List<DealQuote>.unmodifiable(collection.quotes),
      cheapest: collection.cheapest,
      fastest: collection.fastest,
      bestValue: collection.bestValue,
    );
  }

  bool get hasQuotes => quotes.isNotEmpty;

  String? labelFor(DealQuote quote) {
    final labels = <String>[];
    if (cheapest?.sellerId == quote.sellerId) labels.add('Cheapest');
    if (fastest?.sellerId == quote.sellerId) labels.add('Fastest');
    if (bestValue?.sellerId == quote.sellerId) labels.add('Best Value');
    return labels.isEmpty ? null : labels.join(' • ');
  }
}
