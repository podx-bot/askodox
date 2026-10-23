import 'pos_money.dart';

/// Typed / spoken counter commands in English and Telugu, e.g.
/// "add 2 kg chicken at 240 per kg", "అర కిలో చికెన్", "remove chicken",
/// "discount 10%". The parser only PROPOSES an action; the cart changes only
/// after the cashier confirms it (AI never edits a cart, price or invoice
/// silently), and a changed price is still checked by the server's roles.
enum AskodoxPosCommandKind { add, remove, discount, clear, checkout, unknown }

class AskodoxPosItemRef {
  const AskodoxPosItemRef({required this.id, required this.name, this.nameTe = '', required this.unit});
  final String id;
  final String name;
  final String nameTe;
  final String unit;
}

class AskodoxPosCommand {
  const AskodoxPosCommand(this.kind,
      {this.item, this.query = '', this.qtyMilli, this.pricePaise, this.discountPaise, this.discountBp, this.candidates = const []});
  final AskodoxPosCommandKind kind;
  final AskodoxPosItemRef? item;
  final String query;

  /// In the ITEM's own unit (milli-kg for a kg item, milli-pieces for pcs).
  final int? qtyMilli;
  final int? pricePaise;
  final int? discountPaise;
  final int? discountBp;

  /// More than one item matched: the cashier picks.
  final List<AskodoxPosItemRef> candidates;

  bool get needsChoice => item == null && candidates.length > 1;

  String describe(bool te) {
    final name = item == null ? query : (te && item!.nameTe.isNotEmpty ? item!.nameTe : item!.name);
    return switch (kind) {
      AskodoxPosCommandKind.add => [
          te ? 'జోడించాలా:' : 'Add:',
          if (qtyMilli != null) askodoxQty(qtyMilli!, item?.unit ?? ''),
          name,
          if (pricePaise != null) '@ ${askodoxPaise(pricePaise!)}${te ? ' (ధర మార్పు)' : ' (price change)'}',
        ].join(' '),
      AskodoxPosCommandKind.remove => '${te ? 'తీసేయాలా:' : 'Remove:'} $name',
      AskodoxPosCommandKind.discount => discountBp != null
          ? '${te ? 'డిస్కౌంట్:' : 'Discount:'} ${askodoxRate(discountBp!)}'
          : '${te ? 'డిస్కౌంట్:' : 'Discount:'} ${askodoxPaise(discountPaise ?? 0)}',
      AskodoxPosCommandKind.clear => te ? 'బిల్లు మొత్తం ఖాళీ చేయాలా?' : 'Clear the whole bill?',
      AskodoxPosCommandKind.checkout => te ? 'బిల్లు చేయాలా?' : 'Go to payment?',
      AskodoxPosCommandKind.unknown => te ? 'అర్థం కాలేదు' : 'Not understood',
    };
  }
}

const _fractionWords = {
  'అర': 500, 'అరకిలో': 500, 'half': 500, 'పావు': 250, 'quarter': 250, 'ముప్పావు': 750, 'ఒకటిన్నర': 1500,
  'ఒక': 1000, 'ఒకటి': 1000, 'రెండు': 2000, 'మూడు': 3000, 'నాలుగు': 4000, 'ఐదు': 5000, 'one': 1000, 'two': 2000,
  'three': 3000, 'four': 4000, 'five': 5000,
};

const _unitWords = {
  'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogram': 'kg', 'కిలో': 'kg', 'కిలోలు': 'kg', 'కేజీ': 'kg',
  'g': 'g', 'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g', 'గ్రాములు': 'g', 'గ్రాము': 'g',
  'l': 'l', 'litre': 'l', 'liter': 'l', 'litres': 'l', 'లీటర్': 'l', 'లీటరు': 'l',
  'ml': 'ml',
  'pcs': 'pcs', 'pc': 'pcs', 'piece': 'pcs', 'pieces': 'pcs', 'nos': 'pcs', 'ముక్కలు': 'pcs',
  'dozen': 'dozen', 'డజను': 'dozen', 'plate': 'plate', 'plates': 'plate', 'ప్లేట్': 'plate',
  'packet': 'pack', 'packets': 'pack', 'pack': 'pack',
};

const _removeWords = {'remove', 'delete', 'cancel', 'తీసేయ్', 'తీసేయి', 'తీసేయండి', 'వద్దు', 'తొలగించు'};
const _addWords = {'add', 'put', 'give', 'జోడించు', 'వేయి', 'వెయ్', 'ఇవ్వు', 'కావాలి', 'plus'};
const _fillerWords = {'and', 'of', 'the', 'a', 'an', 'please', 'ఇంకా', 'కూడా', 'per', 'each', 'rs', 'rupees', 'రూపాయలు', 'రూ'};

/// Converts a spoken quantity in [spokenUnit] to milli-units of [itemUnit];
/// null when the two units cannot be converted (e.g. "kg" for a pieces item).
int? askodoxConvertQty(int milli, String? spokenUnit, String itemUnit) {
  if (spokenUnit == null || spokenUnit == itemUnit) return milli;
  return switch ((spokenUnit, itemUnit)) {
    ('g', 'kg') || ('ml', 'l') => askodoxRoundDiv(milli, 1000),
    ('kg', 'g') || ('l', 'ml') => milli * 1000,
    ('dozen', 'pcs') => milli * 12,
    _ => null,
  };
}

AskodoxPosCommand askodoxParsePosCommand(String text, List<AskodoxPosItemRef> items) {
  var s = text.toLowerCase().replaceAll('₹', ' rs ').replaceAll(RegExp(r'[,!?]'), ' ').trim();
  if (s.isEmpty) return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  final words = s.split(RegExp(r'\s+'));
  bool has(Set<String> set) => words.any(set.contains);
  if (RegExp(r'^(clear|new bill|reset)\b').hasMatch(s) || s.contains('బిల్లు ఖాళీ')) {
    return const AskodoxPosCommand(AskodoxPosCommandKind.clear);
  }
  if (RegExp(r'^(checkout|pay|payment|total|bill it|finish)\b').hasMatch(s) || s.contains('బిల్లు చేయి') ||
      s.contains('బిల్ చేయి')) {
    return const AskodoxPosCommand(AskodoxPosCommandKind.checkout);
  }
  final discount = RegExp(r'(?:discount|డిస్కౌంట్|తగ్గింపు)\s*(?:of\s*)?(?:rs\s*)?(\d+(?:\.\d+)?)\s*(%|percent|శాతం)?').firstMatch(s);
  if (discount != null) {
    final percent = discount.group(2) != null;
    if (percent) {
      final bp = askodoxParsePaise(discount.group(1)!); // 10 -> 1000 bp, 12.5 -> 1250 bp
      if (bp != null && bp > 0 && bp <= 10000) return AskodoxPosCommand(AskodoxPosCommandKind.discount, discountBp: bp);
    } else {
      final paise = askodoxParsePaise(discount.group(1)!);
      if (paise != null && paise > 0) return AskodoxPosCommand(AskodoxPosCommandKind.discount, discountPaise: paise);
    }
    return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  }

  // price: "at 240", "@240", "240 per kg", "కిలో 240"
  int? price;
  final priceMatch = RegExp(r'(?:@|\bat\b|\brate\b|ధర)\s*(?:rs\s*)?(\d+(?:\.\d{1,2})?)').firstMatch(s) ??
      RegExp(r'(?:rs\s*)?(\d+(?:\.\d{1,2})?)\s*(?:rs\s*)?(?:per|/)\s*\w+').firstMatch(s);
  if (priceMatch != null) {
    price = askodoxParsePaise(priceMatch.group(1)!);
    s = s.replaceRange(priceMatch.start, priceMatch.end, ' ');
  }

  int? qty;
  String? unit;
  final numberUnit = RegExp(r'(\d+(?:\.\d{1,3})?)\s*([a-zఀ-౿]+)?').firstMatch(s);
  final rest = <String>[];
  var tokens = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (numberUnit != null) {
    qty = askodoxParseMilli(numberUnit.group(1)!);
    final maybeUnit = numberUnit.group(2);
    if (maybeUnit != null && _unitWords.containsKey(maybeUnit)) unit = _unitWords[maybeUnit];
    s = s.replaceRange(numberUnit.start, numberUnit.end, maybeUnit != null && unit == null ? ' $maybeUnit ' : ' ');
    tokens = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }
  for (final w in tokens) {
    if (qty == null && _fractionWords.containsKey(w)) {
      qty = _fractionWords[w];
      continue;
    }
    if (w.startsWith('అరకిలో')) {
      qty ??= 500;
      unit ??= 'kg';
      continue;
    }
    if (_unitWords.containsKey(w)) {
      unit ??= _unitWords[w];
      continue;
    }
    if (_removeWords.contains(w) || _addWords.contains(w) || _fillerWords.contains(w)) continue;
    rest.add(w);
  }
  final query = rest.join(' ').trim();
  final remove = has(_removeWords);
  if (query.isEmpty) return const AskodoxPosCommand(AskodoxPosCommandKind.unknown);
  final matches = askodoxMatchItems(query, items);
  final kind = remove ? AskodoxPosCommandKind.remove : AskodoxPosCommandKind.add;
  if (matches.length != 1) {
    return AskodoxPosCommand(kind, query: query, candidates: matches, qtyMilli: null, pricePaise: price);
  }
  final item = matches.single;
  int? itemQty;
  if (!remove) {
    itemQty = askodoxConvertQty(qty ?? 1000, unit, item.unit);
    if (itemQty == null || itemQty <= 0) {
      return AskodoxPosCommand(AskodoxPosCommandKind.unknown, query: query);
    }
  }
  return AskodoxPosCommand(kind, item: item, query: query, qtyMilli: itemQty, pricePaise: remove ? null : price);
}

/// Items whose English or Telugu name contains every word of [query] (or the
/// query contains the whole name). Exact name matches win.
List<AskodoxPosItemRef> askodoxMatchItems(String query, List<AskodoxPosItemRef> items) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return const [];
  final exact = items.where((i) => i.name.toLowerCase() == q || i.nameTe == q).toList();
  if (exact.isNotEmpty) return exact;
  final parts = q.split(RegExp(r'\s+'));
  bool fits(String name) {
    final n = name.toLowerCase();
    if (n.isEmpty) return false;
    return parts.every(n.contains) || q.contains(n);
  }

  return items.where((i) => fits(i.name) || fits(i.nameTe)).toList();
}
