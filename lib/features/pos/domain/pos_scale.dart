/// Weighing-scale helpers for the counter (pure, tested without hardware).
library;

const _lbToGrams = 453.59237;

/// A scale reading ([value] in kg or lb) -> milli-units of the item's unit, or
/// null when the item is not sold by weight. kg item: grams; g item: milli-grams.
int? askodoxScaleToItemMilli(double value, String readingUnit, String itemUnit) {
  if (value.isNaN || value < 0) return null;
  final grams = switch (readingUnit) {
    'kg' => value * 1000,
    'lb' => value * _lbToGrams,
    'g' => value,
    _ => double.nan,
  };
  if (grams.isNaN) return null;
  return switch (itemUnit) {
    'kg' => grams.round(),
    'g' => (grams * 1000).round(),
    _ => null,
  };
}

/// The first value repeated [needed] times in a row (within [tolerance]) -- a
/// settled weight; null while the pan is still moving.
double? askodoxSettledWeight(List<double> readings, {int needed = 2, double tolerance = 0.005}) {
  if (readings.isEmpty || needed < 1) return null;
  var run = 1;
  for (var i = 1; i < readings.length; i++) {
    if ((readings[i] - readings[i - 1]).abs() <= tolerance) {
      run += 1;
      if (run >= needed) return readings[i];
    } else {
      run = 1;
    }
  }
  return needed == 1 ? readings.first : null;
}

/// A barcode exactly as printed (digits / letters), never fuzzy-matched.
String askodoxCleanBarcode(String raw) => raw.trim().replaceAll(RegExp(r'\s'), '');

/// Products whose barcode equals [code] exactly.
List<Map<String, Object?>> askodoxProductsByBarcode(String code, List<Map<String, Object?>> products) {
  final c = askodoxCleanBarcode(code);
  if (c.isEmpty) return const [];
  return [for (final p in products) if (askodoxCleanBarcode('${p['barcode'] ?? ''}') == c) p];
}
