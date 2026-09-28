/// Universal brand / qualifier handling -- for ANY category, with NO
/// hard-coded brand list. A brand is recognised from:
///  1. how people say it: "Tata brand", "brand Tata", "only Tata",
///     "Tata only", "Tata instead", "prefer Tata", "show me Tata";
///  2. brands real ASKODOX listings carry (`GET /api/products/brands`,
///     learned from data, passed in as [known]);
///  3. a short refinement reply ("Tata") while a search is active that
///     answered no other question (see [askodoxQualifierReply]).
/// The chosen brand replaces the previous brand and that brand's model in
/// the searched subject; sizes/capacities ("43 inch", "250 l") are kept.
library;

// Words that are never a brand when said alone or in the patterns above.
const _notBrands = {
  'yes', 'no', 'ok', 'okay', 'sure', 'go', 'show', 'me', 'it', 'this', 'that', 'these', 'those', 'one', 'any',
  'new', 'used', 'old', 'second', 'hand', 'cheap', 'cheaper', 'cheapest', 'best', 'good', 'better', 'fine',
  'thanks', 'thank', 'please', 'more', 'other', 'another', 'next', 'same', 'nearby', 'near', 'online', 'local',
  'today', 'tomorrow', 'now', 'later', 'here', 'there', 'price', 'budget', 'size', 'colour', 'color', 'small',
  'big', 'large', 'medium', 'fresh', 'delivery', 'pickup', 'cash', 'upi', 'buy', 'sell', 'order', 'book',
  'search', 'find', 'results', 'options', 'option', 'first', 'third', 'all', 'none', 'brand',
  'company', 'make', 'model', 'what', 'which', 'why', 'how', 'where', 'when', 'hi', 'hello', 'the', 'a', 'an',
  'and', 'or', 'only', 'instead', 'prefer', 'want', 'need', 'like', 'car', 'tv', 'phone', 'fridge',
  'ac', 'bike', 'job', 'jobs', 'work', 'service', 'repair', 'chicken', 'mutton', 'fish', 'veg', 'nonveg',
};

const _units = {'inch', 'inches', 'in', 'kg', 'g', 'l', 'litre', 'liter', 'litres', 'ltr', 'ton', 'tons', 'cc',
  'gb', 'tb', 'mah', 'w', 'watt', 'hp', 'seater', 'door', 'lakh', 'lakhs', 'k'};

final _explicit = [
  RegExp(r"\b([A-Za-z][A-Za-z0-9&'.-]{1,24})\s+(?:brand|company|make)\b", caseSensitive: false),
  RegExp(r"\b(?:brand|company|make)\s*[:\-]?\s*([A-Za-z][A-Za-z0-9&'.-]{1,24})\b", caseSensitive: false),
  RegExp(r"\bonly\s+([A-Za-z][A-Za-z0-9&'.-]{1,24})\b", caseSensitive: false),
  RegExp(r"\b([A-Za-z][A-Za-z0-9&'.-]{1,24})\s+(?:only|instead)\b", caseSensitive: false),
  RegExp(r"\b(?:prefer|try)\s+([A-Z][A-Za-z0-9&'.-]{1,24})\b"),
];

String _display(String word) => word.length <= 3 && word == word.toUpperCase()
    ? word
    : word.length <= 2
        ? word.toUpperCase()
        : '${word[0].toUpperCase()}${word.substring(1)}';

bool _brandLike(String word) {
  final w = word.toLowerCase();
  return w.length >= 2 && !_notBrands.contains(w) && !_units.contains(w) && !RegExp(r'^\d').hasMatch(w);
}

/// The brand the customer named in [text] (display case), or null.
String? askodoxDetectBrand(String text, {Set<String> known = const {}}) {
  for (final brand in known) {
    if (brand.trim().length < 2) continue;
    if (RegExp('\\b${RegExp.escape(brand.trim())}\\b', caseSensitive: false).hasMatch(text)) return brand.trim();
  }
  for (final pattern in _explicit) {
    final match = pattern.firstMatch(text);
    final word = match?.group(1);
    if (word != null && _brandLike(word)) return _display(word);
  }
  return null;
}

/// A short reply ("Tata", "Blue Star") that refines the active search and
/// answered no other question: treated as the brand/maker the customer
/// wants. Commands, yes/no, numbers, sizes and common words never qualify.
String? askodoxQualifierReply(String text) {
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || words.length > 2) return null;
  if (!words.every((w) => RegExp(r"^[A-Za-z][A-Za-z&'.-]*$").hasMatch(w))) return null;
  if (!words.every(_brandLike)) return null;
  return words.map(_display).join(' ');
}

/// [subject] with [brand] as its brand. The [previous] brand (and any
/// [known] brand) plus that brand's model number are removed -- never
/// "Tata Maruti 800". Sizes/capacities are kept.
String askodoxSubjectWithBrand(String subject, String brand, {String? previous, Set<String> known = const {}}) {
  final remove = <String>{
    for (final b in [previous, ...known])
      if (b != null && b.trim().isNotEmpty && b.trim().toLowerCase() != brand.toLowerCase()) b.trim().toLowerCase(),
  };
  var words = subject.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  // Drop the new brand if already present (it is put in front below).
  final newWords = brand.toLowerCase().split(' ');
  for (var i = 0; i + newWords.length <= words.length; i++) {
    if (words.sublist(i, i + newWords.length).map((w) => w.toLowerCase()).join(' ') == newWords.join(' ')) {
      words = [...words.sublist(0, i), ...words.sublist(i + newWords.length)];
      break;
    }
  }
  final kept = <String>[];
  var i = 0;
  while (i < words.length) {
    String? hit;
    for (final old in remove) {
      final parts = old.split(' ');
      if (i + parts.length <= words.length &&
          words.sublist(i, i + parts.length).map((w) => w.toLowerCase()).join(' ') == old) {
        hit = old;
        break;
      }
    }
    if (hit == null) {
      kept.add(words[i]);
      i++;
      continue;
    }
    i += hit.split(' ').length;
    // The old brand's model number goes with it -- unless it is a size.
    if (i < words.length && RegExp(r'\d').hasMatch(words[i])) {
      final next = i + 1 < words.length ? words[i + 1].toLowerCase() : '';
      if (!_units.contains(next) && !RegExp(r'(inch|kg|l|gb|cc)$').hasMatch(words[i].toLowerCase())) i++;
    }
  }
  final rest = kept.join(' ').trim();
  return rest.isEmpty ? brand : '$brand $rest';
}
