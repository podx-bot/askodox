/// POS money and quantity helpers. Money is integer paise and quantities are
/// integer milli-units everywhere; text is parsed digit by digit (never
/// through a double) so ₹0.10 + ₹0.20 is exactly ₹0.30.
library;

/// Half-up integer division for non-negative numerators (matches Python's
/// Decimal ROUND_HALF_UP used by the server).
int askodoxRoundDiv(int numerator, int denominator) {
  if (denominator <= 0) throw ArgumentError('denominator');
  if (numerator < 0) return -askodoxRoundDiv(-numerator, denominator);
  return (2 * numerator + denominator) ~/ (2 * denominator);
}

/// "1234.5" / "1,234.50" / "₹ 12" -> paise; null when not a valid amount
/// (more than 2 decimals, letters, negative).
int? askodoxParsePaise(String text) => _parseScaled(text, 2);

/// "1.235" kg -> 1235 milli; null when invalid (more than 3 decimals).
int? askodoxParseMilli(String text) => _parseScaled(text, 3);

int? _parseScaled(String text, int decimals) {
  final cleaned = text.replaceAll(RegExp(r'[₹,\s]|rs\.?', caseSensitive: false), '');
  final match = RegExp(r'^(\d{1,12})(?:\.(\d*))?$').firstMatch(cleaned);
  if (match == null) return null;
  final fraction = match.group(2) ?? '';
  if (fraction.length > decimals) return null;
  final scale = [1, 10, 100, 1000][decimals];
  return int.parse(match.group(1)!) * scale + (fraction.isEmpty ? 0 : int.parse(fraction.padRight(decimals, '0')));
}

/// Indian digit grouping: 1234567 paise -> "₹12,345.67".
String askodoxPaise(int paise, {bool symbol = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = '${abs ~/ 100}';
  final paisePart = (abs % 100).toString().padLeft(2, '0');
  String grouped;
  if (rupees.length <= 3) {
    grouped = rupees;
  } else {
    final last3 = rupees.substring(rupees.length - 3);
    var head = rupees.substring(0, rupees.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped.$paisePart';
}

/// 1235 milli + "kg" -> "1.235 kg"; whole numbers drop the decimals.
String askodoxQty(int milli, String unit) {
  final whole = milli ~/ 1000;
  final rest = (milli % 1000).abs();
  final text = rest == 0 ? '$whole' : '$whole.${rest.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return unit.isEmpty ? text : '$text $unit';
}

/// Rate in basis points -> "18%" / "0.25%".
String askodoxRate(int bp) {
  final whole = bp ~/ 100;
  final rest = bp % 100;
  return rest == 0 ? '$whole%' : '$whole.${rest.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
}
