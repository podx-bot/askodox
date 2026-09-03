import 'deal_quote.dart';

class DealQuoteCollection {
  const DealQuoteCollection(this.quotes);

  final List<DealQuote> quotes;

  DealQuoteCollection add(DealQuote quote) {
    final next = <DealQuote>[
      ...quotes.where((existing) => existing.sellerId != quote.sellerId),
      quote,
    ];
    return DealQuoteCollection(List<DealQuote>.unmodifiable(next));
  }

  DealQuote? get cheapest => DealQuoteComparison.cheapest(quotes);
  DealQuote? get fastest => DealQuoteComparison.fastest(quotes);
  DealQuote? get bestValue => DealQuoteComparison.bestValue(quotes);

  Map<QuoteRecommendation, DealQuote> get recommendations {
    final result = <QuoteRecommendation, DealQuote>{};
    final cheap = cheapest;
    final fast = fastest;
    final value = bestValue;
    if (cheap != null) result[QuoteRecommendation.cheapest] = cheap;
    if (fast != null) result[QuoteRecommendation.fastest] = fast;
    if (value != null) result[QuoteRecommendation.bestValue] = value;
    return Map<QuoteRecommendation, DealQuote>.unmodifiable(result);
  }
}
