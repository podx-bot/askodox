enum QuoteKind { unitPrice, totalPrice, serviceEstimate, custom }

enum QuoteRecommendation { cheapest, fastest, bestValue, none }

class DealQuote {
  const DealQuote({
    required this.sellerId,
    required this.amount,
    this.currency = 'INR',
    this.kind = QuoteKind.totalPrice,
    this.priceBasis,
    this.tax,
    this.deliveryFee,
    this.leadTimeHours,
    this.validUntil,
    this.paymentTerms,
    this.warrantyOrReturn,
    this.trustScore,
    this.notes,
    this.dynamicFields = const <String, Object?>{},
  });

  final String sellerId;
  final double amount;
  final String currency;
  final QuoteKind kind;
  final String? priceBasis;
  final double? tax;
  final double? deliveryFee;
  final double? leadTimeHours;
  final DateTime? validUntil;
  final String? paymentTerms;
  final String? warrantyOrReturn;
  final double? trustScore;
  final String? notes;
  final Map<String, Object?> dynamicFields;

  double get normalizedTotal => amount + (tax ?? 0) + (deliveryFee ?? 0);

  bool get isValidNow => validUntil == null || validUntil!.isAfter(DateTime.now());
}

class DealQuoteComparison {
  const DealQuoteComparison._();

  static DealQuote? cheapest(Iterable<DealQuote> quotes) {
    final valid = quotes.where((q) => q.isValidNow).toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) => a.normalizedTotal.compareTo(b.normalizedTotal));
    return valid.first;
  }

  static DealQuote? fastest(Iterable<DealQuote> quotes) {
    final valid = quotes.where((q) => q.isValidNow && q.leadTimeHours != null).toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) => a.leadTimeHours!.compareTo(b.leadTimeHours!));
    return valid.first;
  }

  static DealQuote? bestValue(Iterable<DealQuote> quotes) {
    final valid = quotes.where((q) => q.isValidNow).toList();
    if (valid.isEmpty) return null;
    final cheapestQuote = cheapest(valid)!;
    valid.sort((a, b) => _score(b, cheapestQuote).compareTo(_score(a, cheapestQuote)));
    return valid.first;
  }

  static double _score(DealQuote quote, DealQuote cheapestQuote) {
    final priceScore = cheapestQuote.normalizedTotal <= 0
        ? 1.0
        : (cheapestQuote.normalizedTotal / quote.normalizedTotal).clamp(0.0, 1.0).toDouble();
    final trustScore = ((quote.trustScore ?? 50) / 100).clamp(0.0, 1.0).toDouble();
    final speedScore = quote.leadTimeHours == null
        ? 0.5
        : (1 / (1 + quote.leadTimeHours! / 24)).clamp(0.0, 1.0).toDouble();
    return priceScore * 0.5 + trustScore * 0.3 + speedScore * 0.2;
  }
}
