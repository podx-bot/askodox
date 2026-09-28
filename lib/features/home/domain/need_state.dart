/// Universal need-state helpers for Main Chat -- category-agnostic.
///
/// * "show me / results / options / చూపించు" means: search now with what
///   is already known (do not restart or extend the questionnaire).
/// * Budgets: "₹20,000–₹30,000", "₹30–40k", "₹10 lakh", "15 వేలు".
/// * Several needs in one message ("fridge ₹30–40k, TV ₹20–30k, car ₹10
///   lakh") become separate requirements that never share slots.
library;

final _showNow = RegExp(
  r'\b(show( me)?|results?|options?|find( it| them| me)?|search( now| it)?|what do you have|let me see'
  r'|go( ahead)?|proceed)\b'
  r'|చూపించు|చూపించండి|చూపు|చూపండి|ఆప్షన్స్|రిజల్ట్స్|వెతుకు|దిఖా|दिखा|ढूंढो|ढूँढो|खोजो',
  caseSensitive: false,
);

/// The customer is asking to see results now.
bool askodoxWantsResultsNow(String text) => _showNow.hasMatch(text);

const _units = <String, double>{
  'k': 1e3, 'thousand': 1e3, 'వేల': 1e3, 'వేలు': 1e3, 'हज़ार': 1e3, 'हजार': 1e3,
  'lakh': 1e5, 'lakhs': 1e5, 'lac': 1e5, 'lacs': 1e5, 'l': 1e5, 'లక్ష': 1e5, 'లక్షలు': 1e5, 'लाख': 1e5,
  'cr': 1e7, 'crore': 1e7, 'crores': 1e7, 'కోటి': 1e7, 'करोड़': 1e7,
};

final _amount = RegExp(
  r'(?:₹|rs\.?|inr)?\s*(\d+(?:,\d{2,3})*(?:\.\d+)?)\s*'
  r'(k(?![a-z])|thousand|lakhs?|lacs?|l(?![a-z])|cr(?:ores?)?(?![a-z])|crore|వేలు|వేల|లక్షలు|లక్ష|కోటి|हज़ार|हजार|लाख|करोड़)?',
  caseSensitive: false,
);
final _rangeSep = RegExp(r'^\s*(?:-|–|—|to|నుండి|నుంచి|se|से)\s*', caseSensitive: false);

class AskodoxBudget {
  const AskodoxBudget({this.min, this.max});
  final double? min;
  final double? max;
  bool get isEmpty => min == null && max == null;

  String label() {
    String fmt(double v) => v >= 1e5 && v % 1e5 == 0
        ? '₹${(v / 1e5).toStringAsFixed(0)} lakh'
        : '₹${v.toStringAsFixed(0)}';
    if (min != null && max != null && min != max) return '${fmt(min!)}–${fmt(max!)}';
    return fmt((max ?? min)!);
  }
}

double? _value(String digits, String? unit) {
  final n = double.tryParse(digits.replaceAll(',', ''));
  if (n == null) return null;
  final u = unit?.toLowerCase().trim();
  return u == null || u.isEmpty ? n : n * (_units[u] ?? _units[u.replaceAll(RegExp(r's$'), '')] ?? 1);
}

/// Budget in [text]: a range, "under X", or a single amount. Plain small
/// numbers that are clearly sizes/quantities (43 inch, 2 kg) are ignored.
AskodoxBudget askodoxBudgetRange(String text) {
  for (final first in _amount.allMatches(text)) {
    final raw = first.group(0)!;
    final hasCurrency = RegExp(r'₹|rs|inr', caseSensitive: false).hasMatch(raw);
    final after = text.substring(first.end);
    // Not a price: "43 inch", "2 kg", "1 bhk".
    if (!hasCurrency && first.group(2) == null &&
        RegExp(r'^\s*(-?\s*inch|"|ఇంచ్|kg|g\b|gm|litre|l\b|bhk|seater|seat|pcs|piece|ton)', caseSensitive: false)
            .hasMatch(after)) {
      continue;
    }
    final sep = _rangeSep.firstMatch(after);
    if (sep != null) {
      final second = _amount.matchAsPrefix(after, sep.end);
      if (second != null) {
        final unit2 = second.group(2);
        final a = _value(first.group(1)!, first.group(2) ?? unit2);
        final b = _value(second.group(1)!, unit2 ?? first.group(2));
        if (a != null && b != null && (hasCurrency || unit2 != null || b >= 100)) {
          return AskodoxBudget(min: a < b ? a : b, max: a < b ? b : a);
        }
      }
    }
    final v = _value(first.group(1)!, first.group(2));
    if (v == null) continue;
    if (!hasCurrency && first.group(2) == null && v < 100) continue;
    final before = text.substring(0, first.start).toLowerCase();
    final under = RegExp(r'(under|below|within|upto|up to|max|లోపు|లోపల)\s*$').hasMatch(before.trimRight()) ||
        RegExp(r'^\s*(లోపు|లోపల|లో|varaku|వరకు)').hasMatch(after);
    return under ? AskodoxBudget(max: v) : AskodoxBudget(min: v, max: v);
  }
  return const AskodoxBudget();
}

final _filler = RegExp(
  r'\b(i want( to buy)?|i need|want|need|looking for|buy|get me|please|budget|under|below|around|within|show( me)?|'
  r'results?|options?|find( it| me)?|a|an|the|for|in|at|lo|kavali|kaavali)\b'
  r'|నాకు|మాకు|కావాలి|కొనాలి|లోపు|లోపల|లో|కి|చూపించండి|చూపించు|చూపండి|చూపు|బడ్జెట్',
  caseSensitive: false,
);

const _moneyUnit = r'(?:k(?![a-z])|thousand|lakhs?|lacs?|l(?![a-z])|crores?|cr(?![a-z])|వేలు|వేల|లక్షలు|లక్ష|కోటి|हज़ार|हजार|लाख|करोड़)';
final _money = RegExp(
  '(?:(?:₹|rs\\.?|inr)\\s*\\d[\\d,.]*\\s*$_moneyUnit?|\\d[\\d,.]*\\s*$_moneyUnit|\\b\\d{4,}(?:,\\d{3})*\\b)'
  '(?:\\s*(?:-|–|—|to|నుండి|నుంచి)\\s*(?:₹|rs\\.?|inr)?\\s*\\d[\\d,.]*\\s*$_moneyUnit?)?',
  caseSensitive: false,
);

/// The thing asked for, without budget, filler or "show me". Sizes and
/// quantities ("43 inch", "1 kg") are part of the need and are kept.
String askodoxNeedSubject(String segment) {
  var s = segment.replaceAll(_money, ' ');
  s = s.replaceAllMapped(RegExp(r'(\d{2,3})\s*-\s*(inch)', caseSensitive: false), (m) => '${m[1]} ${m[2]}');
  s = s.replaceAll(RegExp(r'[₹—–:,.!?]+'), ' ').replaceAll(_filler, ' ');
  s = s.replaceAll(RegExp(r'\b(rs|inr|to|and|or)\b', caseSensitive: false), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class AskodoxNeedSegment {
  const AskodoxNeedSegment({required this.subject, required this.budget, required this.raw});
  final String subject;
  final AskodoxBudget budget;
  final String raw;
}

final _needSplit = RegExp(r'(?<!\d),|,(?!\d)|;|\s+and\s+|\s+&\s+|\s+మరియు\s+|\s+ఇంకా\s+|\s+और\s+', caseSensitive: false);

/// Two or more distinct needs, each with its own budget, in one message.
/// Returns an empty list for a single need (the normal flow handles it).
List<AskodoxNeedSegment> askodoxSplitNeeds(String text) {
  final parts = text.split(_needSplit).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return const [];
  final needs = <AskodoxNeedSegment>[];
  for (final part in parts) {
    final budget = askodoxBudgetRange(part);
    final subject = askodoxNeedSubject(part);
    if (budget.isEmpty || subject.isEmpty) return const [];
    needs.add(AskodoxNeedSegment(subject: subject, budget: budget, raw: part));
  }
  final distinct = {for (final n in needs) n.subject.toLowerCase()};
  return distinct.length == needs.length ? needs : const [];
}

Set<String> _tokens(String? value) => {
      for (final t in (value ?? '').toLowerCase().split(RegExp(r'[^a-z0-9ఀ-౿]+')))
        if (t.length > 1 && !RegExp(r'^\d+$').hasMatch(t) &&
            !{'inch', 'kg', 'want', 'need', 'buy', 'the', 'and', 'for', 'to', 'in', 'of', 'me', 'my'}.contains(t))
          t,
    };

/// Whether two subjects describe the same need ("43 inch TV" vs "TV").
bool askodoxSameNeed(String? a, String? b) {
  final x = _tokens(a), y = _tokens(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x.intersection(y).isNotEmpty;
}

final _wants = RegExp(
  r'\b(i want|i need|need|want|looking for|searching for|get me)\b|కావాలి|కొనాలి|चाहिए',
  caseSensitive: false,
);

/// A concrete need without any AI help: the customer says they want/need
/// something AND gives a budget or asks to see results ("I want a used car
/// under ₹8 lakh -- show me"). Category-agnostic by design.
bool askodoxStatesANeed(String text) =>
    _wants.hasMatch(text) &&
    (askodoxWantsResultsNow(text) || !askodoxBudgetRange(text).isEmpty) &&
    askodoxNeedSubject(text).isNotEmpty;
