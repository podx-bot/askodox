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

/// The shop's counter offer on an item, the same rule as the server (`PosStore.offer_discount`): "buy X get Y free"
/// gives Y pieces free in every full group of X + Y; "percent" takes that share off the line. 0 = no offer.
int askodoxOfferDiscount(Map product, int qtyMilli, int unitPricePaise) {
  final offer = product['offer'];
  if (offer is! Map || qtyMilli <= 0 || unitPricePaise <= 0) return 0;
  if (offer['kind'] == 'bxgy') {
    final buy = (offer['buy'] as num?)?.toInt() ?? 0;
    final free = (offer['free'] as num?)?.toInt() ?? 0;
    if (buy <= 0 || free <= 0) return 0;
    return (qtyMilli ~/ ((buy + free) * 1000)) * free * unitPricePaise;
  }
  if (offer['kind'] == 'percent') {
    final bp = (offer['bp'] as num?)?.toInt() ?? 0;
    final gross = qtyMilli * unitPricePaise ~/ 1000;
    return (gross * bp + 5000) ~/ 10000;
  }
  return 0;
}

/// "2 + 1 free" / "10% off" for a tile or a row; '' when the item has no offer.
String askodoxOfferLabel(Map product, bool te) {
  final offer = product['offer'];
  if (offer is! Map) return '';
  if (offer['kind'] == 'bxgy') return te ? '${offer['buy']} కొంటే ${offer['free']} ఉచితం' : '${offer['buy']} + ${offer['free']} free';
  if (offer['kind'] == 'percent') {
    final bp = (offer['bp'] as num?)?.toInt() ?? 0;
    return te ? '${bp / 100}% తగ్గింపు' : '${bp / 100}% off';
  }
  return '';
}
