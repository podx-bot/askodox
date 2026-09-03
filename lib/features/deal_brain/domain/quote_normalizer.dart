import 'deal_quote.dart';

class QuoteNormalizer {
  const QuoteNormalizer._();

  static DealQuote fromText({
    required String sellerId,
    required String text,
    String currency = 'INR',
    double? trustScore,
  }) {
    final lower = text.toLowerCase();
    final amount = _money(lower, const <String>['total', 'price', 'quote', 'amount']) ??
        _firstNumber(lower) ??
        0;
    final tax = _money(lower, const <String>['tax', 'gst']);
    final delivery = _money(lower, const <String>['delivery', 'freight', 'transport']);
    final leadTimeHours = _durationHours(lower);
    final unitPrice = RegExp(r'(?:₹|rs\.?|inr)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:/|per)\s*(kg|piece|pcs|unit|bag|pack|box)\b')
        .firstMatch(lower);

    return DealQuote(
      sellerId: sellerId,
      amount: unitPrice == null ? amount : double.parse(unitPrice.group(1)!),
      currency: currency,
      kind: unitPrice == null ? QuoteKind.totalPrice : QuoteKind.unitPrice,
      priceBasis: unitPrice == null ? null : 'per ${unitPrice.group(2)}',
      tax: tax,
      deliveryFee: delivery,
      leadTimeHours: leadTimeHours,
      trustScore: trustScore,
      notes: text,
    );
  }

  static double? _money(String text, List<String> labels) {
    for (final label in labels) {
      final after = RegExp('$label\\s*(?:is|:|=)?\\s*(?:₹|rs\\.?|inr)?\\s*([0-9]+(?:\\.[0-9]+)?)').firstMatch(text);
      if (after != null) return double.tryParse(after.group(1)!);
      final before = RegExp('(?:₹|rs\\.?|inr)\\s*([0-9]+(?:\\.[0-9]+)?)\\s*$label').firstMatch(text);
      if (before != null) return double.tryParse(before.group(1)!);
    }
    return null;
  }

  static double? _firstNumber(String text) {
    final match = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static double? _durationHours(String text) {
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(hour|hours|hr|hrs|day|days)\b').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    return match.group(2)!.startsWith('d') ? value * 24 : value;
  }
}
