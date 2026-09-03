import 'deal_quote.dart';
import 'deal_quote_collection.dart';
import 'deal_quote_result.dart';
import 'quote_normalizer.dart';
import 'rfq_request.dart';

class RfqQuotePipeline {
  const RfqQuotePipeline({
    required this.request,
    this.collection = const DealQuoteCollection(<DealQuote>[]),
  });

  final RfqRequest request;
  final DealQuoteCollection collection;

  RfqQuotePipeline ingestText({
    required String sellerId,
    required String text,
    String currency = 'INR',
    double? trustScore,
  }) {
    final quote = QuoteNormalizer.fromText(
      sellerId: sellerId,
      text: text,
      currency: currency,
      trustScore: trustScore,
    );
    return RfqQuotePipeline(
      request: request,
      collection: collection.add(quote),
    );
  }

  DealQuoteResult get result => DealQuoteResult.fromCollection(collection);

  bool get hasQuotes => collection.quotes.isNotEmpty;
}
