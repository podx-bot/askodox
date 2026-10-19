/// Smart Guide corrections: typed or spoken "price 300, size 8 and 9" /
/// "ధర 300, స్టాక్ 12" -> which form field gets which new value. Pure and
/// rule-based (no network); the form shows old -> new and applies ONLY after
/// the person confirms. Unknown words never change a field.
library;

/// The fields a form can offer to corrections, by stable id.
abstract final class AskodoxGuideFieldId {
  static const name = 'name';
  static const price = 'price';
  static const unit = 'unit';
  static const stock = 'stock';
  static const variant = 'variant';
  static const category = 'category';
  static const description = 'description';
  static const terms = 'terms';
  static const address = 'address';
}

/// Words that name a field (English + Telugu, lower case).
const Map<String, List<String>> askodoxGuideFieldWords = {
  AskodoxGuideFieldId.price: ['price', 'rate', 'cost', 'amount', 'mrp', 'ధర', 'రేటు', 'రేట్', 'ఖరీదు'],
  AskodoxGuideFieldId.stock: ['stock', 'quantity', 'qty', 'pieces', 'స్టాక్', 'సంఖ్య', 'పరిమాణం'],
  AskodoxGuideFieldId.unit: ['unit', 'యూనిట్'],
  AskodoxGuideFieldId.variant: ['size', 'sizes', 'variant', 'variants', 'colour', 'color', 'సైజు', 'సైజ్', 'రంగు', 'వేరియంట్'],
  AskodoxGuideFieldId.category: ['category', 'type', 'విభాగం', 'కేటగిరీ', 'రకం'],
  AskodoxGuideFieldId.description: ['description', 'details', 'వివరణ', 'వివరాలు'],
  AskodoxGuideFieldId.terms: ['terms', 'conditions', 'condition', 'షరతులు', 'నిబంధనలు'],
  AskodoxGuideFieldId.address: ['address', 'location', 'place', 'చిరునామా', 'అడ్రస్', 'ప్రాంతం'],
  AskodoxGuideFieldId.name: ['name', 'title', 'product', 'item', 'పేరు', 'వస్తువు'],
};

final _splitter = RegExp(r',(?!\d)|[;\n]|\s+and\s+|\s+also\s+|\s+మరియు\s+|\s+ఇంకా\s+', caseSensitive: false);
final _lead = RegExp(r'^(?:please\s+|pls\s+)?(?:change|set|make|update|correct|put)?\s*(?:the\s+|my\s+)?',
    caseSensitive: false);
final _joiners = RegExp(r'^(?:\s*(?:to|is|as|should be|=|:|-|ని|ను|గా|కి)(?=\s|\d|$))+\s*', caseSensitive: false);
final _teluguVerbs =
    RegExp(r'\s*(?:అని|గా|కి)?\s*(?:చేయండి|చెయ్యి|చేయి|పెట్టండి|పెట్టు|మార్చండి|మార్చు|ఉంచండి|ఉంచు|రాయండి)\s*$');
final _number = RegExp(r'\d+(?:[.,]\d+)*');

/// A proposed change: field, value now, value proposed.
class AskodoxFieldChange {
  const AskodoxFieldChange(this.field, this.before, this.after);
  final String field;
  final String before;
  final String after;
}

/// Parses [text] into field -> new value, only for [fields] the form has.
/// "price 300 and size 8, 9" -> {price: 300, variant: 8, 9}.
Map<String, String> askodoxParseCorrections(String text, Set<String> fields) {
  final out = <String, String>{};
  String? last;
  for (final raw in text.split(_splitter)) {
    var segment = raw.trim();
    if (segment.isEmpty) continue;
    segment = segment.replaceFirst(_lead, '').trim();
    final lower = segment.toLowerCase();
    String? field;
    var rest = segment;
    var bestAt = -1;
    for (final entry in askodoxGuideFieldWords.entries) {
      if (!fields.contains(entry.key)) continue;
      for (final word in entry.value) {
        // The field word must start the segment (after "change the ...").
        if (lower.startsWith(word) && (lower.length == word.length || !_isLetter(lower[word.length]))) {
          if (word.length > bestAt) {
            bestAt = word.length;
            field = entry.key;
            rest = segment.substring(word.length);
          }
        }
      }
    }
    if (field == null) {
      // "size 8 and 9": a bare continuation joins the previous variant field.
      if (last == AskodoxGuideFieldId.variant && out[last] != null) {
        out[last!] = '${out[last]}, $segment';
        continue;
      }
      // A bare amount ("₹300") is a price when the form has one.
      if (fields.contains(AskodoxGuideFieldId.price) && RegExp(r'^(?:₹|rs\.?\s*)\s*\d').hasMatch(lower)) {
        field = AskodoxGuideFieldId.price;
      } else {
        continue;
      }
    }
    var value = rest.replaceFirst(_joiners, '').replaceFirst(_teluguVerbs, '').trim();
    if (field == AskodoxGuideFieldId.price || field == AskodoxGuideFieldId.stock) {
      if (field == AskodoxGuideFieldId.stock && RegExp(r'out of stock|sold out|అయిపోయ|లేదు').hasMatch(value.toLowerCase())) {
        value = '0';
      } else {
        final n = _number.firstMatch(value)?.group(0);
        if (n == null) continue;
        value = n.replaceAll(',', '');
      }
    }
    if (value.isEmpty) continue;
    // "size 8 and colour red": options add up in the one variant field.
    out[field] = field == AskodoxGuideFieldId.variant && out[field] != null ? '${out[field]}, $value' : value;
    last = field;
  }
  return out;
}

bool _isLetter(String ch) => RegExp(r'\p{L}', unicode: true).hasMatch(ch);

/// Old -> new for the fields that would actually change.
List<AskodoxFieldChange> askodoxDiff(Map<String, String> current, Map<String, String> proposed) => [
      for (final e in proposed.entries)
        if ((current[e.key] ?? '').trim() != e.value.trim()) AskodoxFieldChange(e.key, current[e.key] ?? '', e.value),
    ];
