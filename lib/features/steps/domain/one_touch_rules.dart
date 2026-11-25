/// Pure rules for the last two "ఒక్క టచ్" jobs (owner 2026-11-25): the family shopping list and the shop's bulk price
/// change. Kept equal to the server (`family_lists.py`, `pos_bulk_price.new_price`) -- change both together.
library;

/// Ways to change many prices at once (server `pos_bulk_price.MODES`).
const askodoxBulkPriceModes = ['up_percent', 'down_percent', 'up_rupees', 'down_rupees', 'set'];

/// The new price (paise) the server will write -- shown before the owner taps ✓. Never below ₹1.
int askodoxBulkNewPrice(int oldPaise, String mode, num value, int roundPaise) {
  final raw = switch (mode) {
    'up_percent' => oldPaise * (100 + value) / 100,
    'down_percent' => oldPaise * (100 - value) / 100,
    'up_rupees' => oldPaise + value * 100,
    'down_rupees' => oldPaise - value * 100,
    _ => value * 100,
  };
  var price = _roundHalfEven(raw.toDouble());
  if (roundPaise > 0) price = _roundHalfEven(price / roundPaise) * roundPaise;
  return price < 100 ? 100 : price;
}

/// Python's round() (banker's rounding) so the app shows exactly what the server writes.
int _roundHalfEven(double x) {
  final f = x.floorToDouble();
  final diff = x - f;
  if ((diff - 0.5).abs() < 1e-9) return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
  return x.round();
}

/// Is [value] allowed for [mode] (server `_check`)?
bool askodoxBulkValueOk(String mode, num value) {
  if (value <= 0) return false;
  if (mode == 'down_percent') return value <= 90;
  if (mode == 'up_percent') return value <= 500;
  return value <= 1000000;
}

/// One typed / spoken line -> the list items: "sugar, milk and 2 kg rice" -> [sugar, milk, 2 kg rice].
/// Splits on commas, new lines, " and ", " మరియు ", " ఇంకా ", " aur "; drops empty bits; max 30 (server limit).
List<String> askodoxFamilyItemsFrom(String text) {
  final parts = text
      .split(RegExp(r'[,\n;،]|\s+(?:and|మరియు|ఇంకా|aur|और)\s+', caseSensitive: false))
      .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.length > 30 ? parts.sublist(0, 30) : parts;
}

/// The chat question for "find these nearby" (only the items still needed).
String askodoxFamilyNearbyAsk(List<String> open, bool te) => te
    ? 'ఈ వస్తువులు దగ్గర్లో ఎక్కడ దొరుకుతాయి, ధరలతో చూపించు: ${open.join(', ')}'
    : 'Where nearby can I buy these, with prices: ${open.join(', ')}';
