/// Rate by quantity, the same rule as the server (`PosStore.tier_price`): the
/// price per base unit is that of the tier with the highest minimum quantity
/// not above what is bought; below every tier the item price applies.
library;

int? askodoxTierPrice(Map product, int baseQtyMilli) {
  final tiers = [
    for (final t in (product['tiers'] as List? ?? const []))
      if (t is Map) (min: (t['min_qty_milli'] as num?)?.toInt() ?? 0, price: (t['price_paise'] as num?)?.toInt() ?? 0),
  ]..sort((a, b) => a.min.compareTo(b.min));
  int? best;
  for (final t in tiers) {
    if (baseQtyMilli >= t.min) best = t.price;
  }
  return best;
}

/// The least a customer may buy (base milli-units), or null.
int? askodoxMinQty(Map product) {
  final v = (product['min_qty_milli'] as num?)?.toInt();
  return v == null || v <= 0 ? null : v;
}
