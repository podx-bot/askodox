/// Buy in one form, sell in another (owner 2026-11-27, phase 6): live birds -> dressed meat, a goat -> mutton,
/// fish -> cleaned fish, paddy -> rice, a cloth roll -> pieces. Pure integer arithmetic: grams, paise, rates in paise
/// per kg, shares in basis points. Twin of `backend/app/services/yield_math.py`; both must pass
/// `test/fixtures/yield_vectors.json` -- change the two together. Every number comes from the owner's own entries;
/// nothing here is a preset.
library;

import 'dart:convert';

/// n / d to the nearest whole, halves away from zero. d > 0.
int askodoxYieldRoundDiv(int n, int d) {
  if (d <= 0) throw ArgumentError('divisor must be positive');
  final q = (n.abs() * 2 + d) ~/ (2 * d);
  return n >= 0 ? q : -q;
}

/// What the goods cost: weight x rate per kg.
int askodoxYieldGoods(int liveGrams, int ratePaise) => askodoxYieldRoundDiv(liveGrams * ratePaise, 1000);

/// Goods + the other costs of bringing them in (transport, unloading ...). A negative extra is not a discount.
int askodoxYieldTotal(int liveGrams, int ratePaise, Iterable<int> extrasPaise) =>
    askodoxYieldGoods(liveGrams, ratePaise) + extrasPaise.fold(0, (sum, e) => sum + (e > 0 ? e : 0));

/// What came out of what went in, in basis points (7000 = 70%). Null until both are weighed.
int? askodoxYieldBp(int liveGrams, int outGrams) =>
    liveGrams <= 0 || outGrams <= 0 ? null : askodoxYieldRoundDiv(outGrams * 10000, liveGrams);

/// The real cost of one sellable kg: (everything spent - what the by-products brought) / what came out.
int? askodoxYieldCostPerKg(int totalPaise, int byproductPaise, int outGrams) {
  if (outGrams <= 0) return null;
  final net = totalPaise - (byproductPaise > 0 ? byproductPaise : 0);
  return askodoxYieldRoundDiv((net > 0 ? net : 0) * 1000, outGrams);
}

/// A further form (skinless, boneless) cut from the sellable kg: its cost per kg by the owner's own yield.
int? askodoxYieldFormCost(int costPaise, int formYieldBp) =>
    formYieldBp <= 0 ? null : askodoxYieldRoundDiv(costPaise * 10000, formYieldBp);

/// Profit per kg and its share of the selling rate in basis points (null with no selling rate).
({int profit, int? marginBp}) askodoxYieldProfit(int sellPaise, int costPaise) {
  final gain = sellPaise - costPaise;
  return (profit: gain, marginBp: sellPaise > 0 ? askodoxYieldRoundDiv(gain * 10000, sellPaise) : null);
}

/// The buying rate moves by [deltaPaise]: the sellable kg's cost moves by this much.
int? askodoxYieldRiseEffect(int deltaPaise, int yieldBp) =>
    yieldBp <= 0 ? null : askodoxYieldRoundDiv(deltaPaise * 10000, yieldBp);

int askodoxYieldExpected(int openingGrams, int madeGrams, int soldGrams) => openingGrams + madeGrams - soldGrams;

/// What a stock difference is worth at cost (always a positive amount).
int askodoxYieldDiffValue(int diffGrams, int costPaise) => askodoxYieldRoundDiv(diffGrams.abs() * costPaise, 1000);

/// Sales, the cost of what was sold, and the day's profit.
({int sales, int spent, int profit}) askodoxYieldDayProfit(int soldGrams, int sellPaise, int costPaise, int otherPaise) {
  final sales = askodoxYieldRoundDiv(soldGrams * sellPaise, 1000);
  final spent = askodoxYieldRoundDiv(soldGrams * costPaise, 1000);
  return (sales: sales, spent: spent, profit: sales - spent - (otherPaise > 0 ? otherPaise : 0));
}

/// What one plate / piece costs in this item alone: the owner's own measure x the cost of a sellable kg.
int askodoxYieldPortionCost(int grams, int costPaise) => askodoxYieldRoundDiv((grams > 0 ? grams : 0) * costPaise, 1000);

/// The owner's own measure worked out from one batch: what went in / how many plates came out.
int? askodoxYieldMeasure(int batchGrams, int portions) =>
    batchGrams <= 0 || portions <= 0 ? null : askodoxYieldRoundDiv(batchGrams, portions);

// ------------------------------------------------------------------------------------------------ words
/// "66.2" / "29.85" / "70" from grams.
String askodoxYieldKg(int grams) {
  final sign = grams < 0 ? '-' : '';
  final g = grams.abs();
  final frac = (g % 1000).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$sign${g ~/ 1000}${frac.isEmpty ? '' : '.$frac'}';
}

/// "₹11,916" / "₹166.67" (Indian grouping; paise only when there are some).
String askodoxYieldRupees(int paise) {
  final sign = paise < 0 ? '-' : '';
  final p = paise.abs();
  var whole = '${p ~/ 100}';
  if (whole.length > 3) {
    final last = whole.substring(whole.length - 3);
    var head = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    whole = '${parts.join(',')},$last';
  }
  return '$sign₹$whole${p % 100 == 0 ? '' : '.${(p % 100).toString().padLeft(2, '0')}'}';
}

/// "70%" / "16.7%" from basis points.
String askodoxYieldPercent(int bp) =>
    bp % 100 == 0 ? '${bp ~/ 100}%' : '${(askodoxYieldRoundDiv(bp, 10) / 10).toStringAsFixed(1)}%';

/// "350 g" / "1.2 kg" for a measure.
String askodoxYieldGrams(int grams) => grams < 1000 ? '$grams g' : '${askodoxYieldKg(grams)} kg';

int _decimal(String text, int scale) {
  final clean = text.replaceAll(',', '').replaceAll('₹', '').trim();
  final match = RegExp(r'^(\d{0,7})(?:\.(\d{0,6}))?$').firstMatch(clean);
  if (match == null || clean.isEmpty || clean == '.') return 0;
  final whole = int.tryParse(match[1] ?? '') ?? 0;
  final digits = scale.toString().length - 1;
  final frac = (match[2] ?? '').padRight(digits + 1, '0');
  final kept = int.parse(frac.substring(0, digits));
  final next = int.parse(frac.substring(digits, digits + 1));
  return whole * scale + kept + (next >= 5 ? 1 : 0);
}

/// "43.2" (kg) -> 43200 grams. Anything unreadable is 0.
int askodoxYieldParseGrams(String text) => _decimal(text, 1000);

/// "98.50" (rupees) -> 9850 paise. Anything unreadable is 0.
int askodoxYieldParsePaise(String text) => _decimal(text, 100);

/// "90" / "62.5" (percent) -> 9000 / 6250 basis points. Anything unreadable is 0.
int askodoxYieldParsePercent(String text) => _decimal(text, 100);

/// The rate board a shop sends its customers: SELLING rates only -- never a cost, a yield or a profit.
String askodoxYieldBoardText(String shop, String item, int sellPaise, List<AskodoxYieldForm> forms, bool te) {
  final name = askodoxYieldItemName(item, te);
  final lines = <String>[
    if (shop.trim().isNotEmpty) shop.trim(),
    te ? '$name · ఈ రోజు రేట్లు' : '$name · today\'s rates',
    if (sellPaise > 0) '$name: ${askodoxYieldRupees(sellPaise)} / kg',
    for (final f in forms)
      if (f.sellPaise > 0) '${f.name}: ${askodoxYieldRupees(f.sellPaise)} / kg',
    'ASKODOX',
  ];
  return lines.join('\n');
}

String askodoxYieldDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------------------------------------------ records
/// The starter items; a person types any other name.
const askodoxYieldItems = <(String, String, String)>[
  ('chicken', 'Chicken', 'చికెన్'),
  ('mutton', 'Mutton', 'మటన్'),
  ('fish', 'Fish', 'చేప'),
];

String askodoxYieldItemName(String item, bool te) {
  for (final row in askodoxYieldItems) {
    if (row.$1 == item) return te ? row.$3 : row.$2;
  }
  return item;
}

/// One lot bought: what went in, what it cost, what came out, what it sells for.
class AskodoxYieldBatch {
  const AskodoxYieldBatch({
    required this.id,
    required this.item,
    required this.day,
    required this.liveGrams,
    required this.ratePaise,
    this.count = 0,
    this.transportPaise = 0,
    this.labourPaise = 0,
    this.outGrams = 0,
    this.byproductPaise = 0,
    this.sellPaise = 0,
  });

  final String id, item, day;
  final int liveGrams, ratePaise, count, transportPaise, labourPaise, outGrams, byproductPaise, sellPaise;

  int get total => askodoxYieldTotal(liveGrams, ratePaise, [transportPaise, labourPaise]);
  int? get yieldBp => askodoxYieldBp(liveGrams, outGrams);
  int? get cost => askodoxYieldCostPerKg(total, byproductPaise, outGrams);

  AskodoxYieldBatch copyWith({int? outGrams, int? byproductPaise, int? sellPaise}) => AskodoxYieldBatch(
      id: id,
      item: item,
      day: day,
      liveGrams: liveGrams,
      ratePaise: ratePaise,
      count: count,
      transportPaise: transportPaise,
      labourPaise: labourPaise,
      outGrams: outGrams ?? this.outGrams,
      byproductPaise: byproductPaise ?? this.byproductPaise,
      sellPaise: sellPaise ?? this.sellPaise);

  Map<String, Object?> toJson() => {
        'id': id, 'item': item, 'day': day, 'live': liveGrams, 'rate': ratePaise, 'count': count,
        'transport': transportPaise, 'labour': labourPaise, 'out': outGrams, 'by': byproductPaise, 'sell': sellPaise,
      };

  static AskodoxYieldBatch? from(Object? raw) {
    if (raw is! Map) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    final id = '${raw['id'] ?? ''}', item = '${raw['item'] ?? ''}', day = '${raw['day'] ?? ''}';
    if (id.isEmpty || item.isEmpty || day.length != 10 || n('live') <= 0) return null;
    return AskodoxYieldBatch(
        id: id, item: item, day: day, liveGrams: n('live'), ratePaise: n('rate'), count: n('count'),
        transportPaise: n('transport'), labourPaise: n('labour'), outGrams: n('out'), byproductPaise: n('by'),
        sellPaise: n('sell'));
  }
}

/// A further form of an item the owner sells (skinless, boneless ...): the owner's own yield from the sellable kg and
/// its own selling rate. No number here is a preset.
class AskodoxYieldForm {
  const AskodoxYieldForm({required this.name, this.yieldBp = 0, this.sellPaise = 0});
  final String name;
  final int yieldBp, sellPaise;

  Map<String, Object?> toJson() => {'n': name, 'y': yieldBp, 's': sellPaise};

  static AskodoxYieldForm? from(Object? raw) {
    if (raw is! Map || '${raw['n'] ?? ''}'.isEmpty) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    return AskodoxYieldForm(name: '${raw['n']}', yieldBp: n('y'), sellPaise: n('s'));
  }
}

/// One line of the owner's measure card: a plate / piece, how much of the item goes into it, what it sells for.
class AskodoxYieldPortion {
  const AskodoxYieldPortion({required this.name, this.grams = 0, this.sellPaise = 0});
  final String name;
  final int grams, sellPaise;

  Map<String, Object?> toJson() => {'n': name, 'g': grams, 's': sellPaise};

  static AskodoxYieldPortion? from(Object? raw) {
    if (raw is! Map || '${raw['n'] ?? ''}'.isEmpty) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    return AskodoxYieldPortion(name: '${raw['n']}', grams: n('g'), sellPaise: n('s'));
  }
}

/// One day's close for an item: the books against the scale.
class AskodoxYieldDay {
  const AskodoxYieldDay({
    required this.item,
    required this.day,
    this.openingGrams = 0,
    this.madeGrams = 0,
    this.soldGrams = 0,
    this.actualGrams = 0,
    this.otherPaise = 0,
    this.costPaise = 0,
    this.sellPaise = 0,
    this.reason = '',
  });

  final String item, day, reason;
  final int openingGrams, madeGrams, soldGrams, actualGrams, otherPaise, costPaise, sellPaise;

  int get expected => askodoxYieldExpected(openingGrams, madeGrams, soldGrams);
  int get diff => actualGrams - expected;

  Map<String, Object?> toJson() => {
        'item': item, 'day': day, 'opening': openingGrams, 'made': madeGrams, 'sold': soldGrams, 'actual': actualGrams,
        'other': otherPaise, 'cost': costPaise, 'sell': sellPaise, 'reason': reason,
      };

  static AskodoxYieldDay? from(Object? raw) {
    if (raw is! Map) return null;
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    final item = '${raw['item'] ?? ''}', day = '${raw['day'] ?? ''}';
    if (item.isEmpty || day.length != 10) return null;
    return AskodoxYieldDay(
        item: item, day: day, openingGrams: n('opening'), madeGrams: n('made'), soldGrams: n('sold'),
        actualGrams: n('actual'), otherPaise: n('other'), costPaise: n('cost'), sellPaise: n('sell'),
        reason: '${raw['reason'] ?? ''}');
  }
}

/// One shop's book: lots (oldest first), day closes, and the least profit per kg the owner set for each item.
class AskodoxYieldBook {
  const AskodoxYieldBook({
    this.batches = const [],
    this.days = const [],
    this.minProfit = const {},
    this.forms = const {},
    this.portions = const {},
  });
  final List<AskodoxYieldBatch> batches;
  final List<AskodoxYieldDay> days;
  final Map<String, int> minProfit;

  /// Per item: the further forms the owner sells, and the lines of the measure card.
  final Map<String, List<AskodoxYieldForm>> forms;
  final Map<String, List<AskodoxYieldPortion>> portions;

  AskodoxYieldBook copyWith({
    List<AskodoxYieldBatch>? batches,
    List<AskodoxYieldDay>? days,
    Map<String, int>? minProfit,
    Map<String, List<AskodoxYieldForm>>? forms,
    Map<String, List<AskodoxYieldPortion>>? portions,
  }) =>
      AskodoxYieldBook(
          batches: batches ?? this.batches,
          days: days ?? this.days,
          minProfit: minProfit ?? this.minProfit,
          forms: forms ?? this.forms,
          portions: portions ?? this.portions);

  List<AskodoxYieldForm> formsOf(String item) => forms[item] ?? const [];
  List<AskodoxYieldPortion> portionsOf(String item) => portions[item] ?? const [];

  List<AskodoxYieldBatch> of(String item) => [for (final b in batches) if (b.item == item) b];

  /// The newest lot of an item (the one the rate board shows).
  AskodoxYieldBatch? latest(String item) {
    final mine = of(item);
    return mine.isEmpty ? null : mine.last;
  }

  /// The owner's own last yields, newest last (at most [count]).
  List<int> yields(String item, {int count = 5}) {
    final all = [for (final b in of(item)) if (b.yieldBp != null) b.yieldBp!];
    return all.length > count ? all.sublist(all.length - count) : all;
  }

  AskodoxYieldDay? dayOf(String item, String day) {
    for (final d in days) {
      if (d.item == item && d.day == day) return d;
    }
    return null;
  }

  /// What was on the scale at the last close before [day] (tomorrow's opening stock); 0 with no close yet.
  int openingFor(String item, String day) {
    AskodoxYieldDay? last;
    for (final d in days) {
      if (d.item == item && d.day.compareTo(day) < 0 && (last == null || d.day.compareTo(last.day) > 0)) last = d;
    }
    return last?.actualGrams ?? 0;
  }

  /// What came out of the lots of [day].
  int madeOn(String item, String day) => of(item).where((b) => b.day == day).fold(0, (sum, b) => sum + b.outGrams);

  Map<String, Object?> toJson() => {
        'batches': [for (final b in batches) b.toJson()],
        'days': [for (final d in days) d.toJson()],
        'min': minProfit,
        'forms': {for (final e in forms.entries) e.key: [for (final f in e.value) f.toJson()]},
        'portions': {for (final e in portions.entries) e.key: [for (final p in e.value) p.toJson()]},
      };

  static AskodoxYieldBook from(Object? raw) {
    if (raw is! Map) return const AskodoxYieldBook();
    final batches = <AskodoxYieldBatch>[];
    final days = <AskodoxYieldDay>[];
    final min = <String, int>{};
    if (raw['batches'] is List) {
      for (final row in raw['batches'] as List) {
        final b = AskodoxYieldBatch.from(row);
        if (b != null) batches.add(b);
      }
    }
    if (raw['days'] is List) {
      for (final row in raw['days'] as List) {
        final d = AskodoxYieldDay.from(row);
        if (d != null) days.add(d);
      }
    }
    if (raw['min'] is Map) {
      (raw['min'] as Map).forEach((k, v) {
        if (v is num) min['$k'] = v.toInt();
      });
    }
    final forms = <String, List<AskodoxYieldForm>>{};
    if (raw['forms'] is Map) {
      (raw['forms'] as Map).forEach((k, v) {
        if (v is List) forms['$k'] = [for (final row in v) AskodoxYieldForm.from(row)].nonNulls.toList();
      });
    }
    final portions = <String, List<AskodoxYieldPortion>>{};
    if (raw['portions'] is Map) {
      (raw['portions'] as Map).forEach((k, v) {
        if (v is List) portions['$k'] = [for (final row in v) AskodoxYieldPortion.from(row)].nonNulls.toList();
      });
    }
    return AskodoxYieldBook(batches: batches, days: days, minProfit: min, forms: forms, portions: portions);
  }
}

/// Every shop's book on this phone, as saved text. Anything unreadable is an empty start, never a crash.
Map<String, AskodoxYieldBook> askodoxYieldDecode(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return {};
    return {for (final e in data.entries) '${e.key}': AskodoxYieldBook.from(e.value)};
  } catch (_) {
    return {};
  }
}

String askodoxYieldEncode(Map<String, AskodoxYieldBook> books) =>
    jsonEncode({for (final e in books.entries) e.key: e.value.toJson()});
