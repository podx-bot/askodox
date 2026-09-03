import 'deal_quote.dart';

class QuoteNormalizer {
  const QuoteNormalizer._();

  static DealQuote fromText({
    required String sellerId,
    required String text,
    String currency = 'INR',
    double? trustScore,
    DateTime? now,
  }) {
    final lower = text.toLowerCase();
    final referenceNow = now ?? DateTime.now();
    final unitPrice = RegExp(
      r'(?:₹|rs\.?|inr)?\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*(?:/|per)\s*(kg|piece|pcs|unit|bag|pack|box)\b',
    ).firstMatch(lower);
    final amount = unitPrice == null
        ? (_money(lower, const <String>['total', 'price', 'quote', 'amount']) ?? _firstNumber(lower) ?? 0)
        : _parseNumber(unitPrice.group(1)!) ?? 0;

    final gstIncluded = RegExp(r'\b(?:gst|tax)\s+(?:is\s+)?included\b|\binclusive\s+of\s+(?:gst|tax)\b').hasMatch(lower);
    final freeDelivery = RegExp(r'\bfree\s+(?:delivery|freight|transport)\b|\b(?:delivery|freight|transport)\s+(?:is\s+)?free\b').hasMatch(lower);
    final tax = gstIncluded ? 0.0 : _money(lower, const <String>['tax', 'gst']);
    final delivery = freeDelivery ? 0.0 : _money(lower, const <String>['delivery', 'freight', 'transport']);
    final leadTimeHours = _durationHours(lower);
    final validUntil = _validUntil(lower, referenceNow);

    return DealQuote(
      sellerId: sellerId,
      amount: amount,
      currency: currency,
      kind: unitPrice == null ? QuoteKind.totalPrice : QuoteKind.unitPrice,
      priceBasis: unitPrice == null ? null : 'per ${unitPrice.group(2)}',
      tax: tax,
      deliveryFee: delivery,
      leadTimeHours: leadTimeHours,
      validUntil: validUntil,
      paymentTerms: _paymentTerms(text),
      warrantyOrReturn: _warrantyOrReturn(text),
      trustScore: trustScore,
      notes: text,
      dynamicFields: <String, Object?>{
        if (gstIncluded) 'gstIncluded': true,
        if (freeDelivery) 'freeDelivery': true,
      },
    );
  }

  static double? _money(String text, List<String> labels) {
    for (final label in labels) {
      final after = RegExp(
        '$label\\s*(?:is|:|=|extra|additional)?\\s*(?:₹|rs\\.?|inr)?\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)',
      ).firstMatch(text);
      if (after != null) return _parseNumber(after.group(1)!);
      final before = RegExp(
        '(?:₹|rs\\.?|inr)\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)\\s*$label',
      ).firstMatch(text);
      if (before != null) return _parseNumber(before.group(1)!);
    }
    return null;
  }

  static double? _firstNumber(String text) {
    final match = RegExp(r'(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]+)?)').firstMatch(text);
    return match == null ? null : _parseNumber(match.group(1)!);
  }

  static double? _parseNumber(String value) => double.tryParse(value.replaceAll(',', ''));

  static double? _durationHours(String text) {
    if (RegExp(r'\b(?:delivery\s+)?tomorrow\b').hasMatch(text)) return 24;
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*(hour|hours|hr|hrs|day|days)\b').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    return match.group(2)!.startsWith('d') ? value * 24 : value;
  }

  static DateTime? _validUntil(String text, DateTime now) {
    final match = RegExp(r'\bvalid(?:ity)?(?:\s+for|\s*:|\s*=)?\s*([0-9]+(?:\.[0-9]+)?)\s*(hour|hours|hr|hrs|day|days)\b').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    final hours = match.group(2)!.startsWith('d') ? value * 24 : value;
    return now.add(Duration(minutes: (hours * 60).round()));
  }

  static String? _paymentTerms(String text) {
    final patterns = <RegExp>[
      RegExp(r'\bpayment\s+terms?\s*[:=-]\s*([^,;.]+)', caseSensitive: false),
      RegExp(r'\b(advance\s+payment|cash\s+on\s+delivery|cod|pay\s+on\s+delivery|net\s+[0-9]+\s+days?)\b', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  static String? _warrantyOrReturn(String text) {
    final match = RegExp(
      r'\b([0-9]+\s*(?:day|days|month|months|year|years)\s+(?:warranty|return)|no\s+warranty|no\s+return)\b',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }
}
