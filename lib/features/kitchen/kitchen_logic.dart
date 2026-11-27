/// Kitchen stock (owner 2026-11-27, phase 6, design "kitchen stock"): the person's OWN home pantry -- what is in the
/// kitchen, what is running low, a buy list, and what the groceries cost this month. Every item, unit and "low"
/// level is the person's own entry (no presets). The list stays on the person's own phone (account-scoped).
library;

import 'dart:convert';

/// Units the person can count in; the amount is kept as an integer in milli-units (1.5 kg = 1500).
const askodoxKitchenUnits = ['kg', 'g', 'L', 'ml', 'pcs'];
const askodoxKitchenMaxItems = 200;
const askodoxKitchenMaxSpends = 400;

class AskodoxKitchenItem {
  const AskodoxKitchenItem({required this.id, required this.name, this.unit = 'kg', this.milli = 0, this.lowMilli = 0, this.finished = false});

  final String id, name, unit;

  /// How much is in the kitchen, in milli-units.
  final int milli;

  /// The person's own "low" level in milli-units; 0 = none set (only "finished" counts).
  final int lowMilli;

  /// The person said it is finished.
  final bool finished;

  AskodoxKitchenItem copyWith({String? name, String? unit, int? milli, int? lowMilli, bool? finished}) => AskodoxKitchenItem(
      id: id, name: name ?? this.name, unit: unit ?? this.unit, milli: milli ?? this.milli, lowMilli: lowMilli ?? this.lowMilli,
      finished: finished ?? this.finished);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'unit': unit, 'milli': milli, 'low': lowMilli, 'done': finished};

  static AskodoxKitchenItem? from(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}', name = '${raw['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    int n(Object? v) => v is num && v >= 0 ? v.toInt() : 0;
    final unit = '${raw['unit'] ?? 'kg'}';
    return AskodoxKitchenItem(
        id: id, name: name, unit: askodoxKitchenUnits.contains(unit) ? unit : 'kg', milli: n(raw['milli']), lowMilli: n(raw['low']),
        finished: raw['done'] == true);
  }
}

/// One grocery spend the person noted: day `YYYY-MM-DD`, amount in paise.
class AskodoxKitchenSpend {
  const AskodoxKitchenSpend({required this.day, required this.paise, this.note = ''});
  final String day, note;
  final int paise;

  Map<String, Object?> toJson() => {'day': day, 'paise': paise, 'note': note};

  static AskodoxKitchenSpend? from(Object? raw) {
    if (raw is! Map) return null;
    final day = '${raw['day'] ?? ''}';
    final paise = raw['paise'];
    if (day.length != 10 || paise is! num || paise <= 0) return null;
    return AskodoxKitchenSpend(day: day, paise: paise.toInt(), note: '${raw['note'] ?? ''}');
  }
}

class AskodoxKitchenBook {
  const AskodoxKitchenBook({this.items = const [], this.spends = const []});
  final List<AskodoxKitchenItem> items;
  final List<AskodoxKitchenSpend> spends;
}

/// Running low = the person said finished, or what is left is at / under the level they set.
bool askodoxKitchenLow(AskodoxKitchenItem i) => i.finished || (i.lowMilli > 0 && i.milli <= i.lowMilli);

/// The buy list: everything running low, by name.
List<AskodoxKitchenItem> askodoxKitchenBuyList(List<AskodoxKitchenItem> items) =>
    [for (final i in items) if (askodoxKitchenLow(i)) i]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Milli-units from what the person typed ("1.5", "12", "0,5"); null when it is not a plain number.
int? askodoxKitchenParseAmount(String text) {
  final t = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final frac = parts.length == 2 ? int.parse(parts[1].padRight(3, '0')) : 0;
  return int.parse(parts[0]) * 1000 + frac;
}

/// "12", "0.5", "1.25" from milli-units.
String askodoxKitchenShown(int milli) {
  final whole = milli ~/ 1000, frac = milli % 1000;
  if (frac == 0) return '$whole';
  return '$whole.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}

/// The step a +/- button moves: 1 for pieces, 0.5 for kg / L, 100 for g / ml.
int askodoxKitchenStep(String unit) => switch (unit) { 'pcs' => 1000, 'g' || 'ml' => 100000, _ => 500 };

/// Paise from rupees typed by the person ("8400", "8,400.50"); null when it is not a plain amount.
int? askodoxKitchenParsePaise(String text) {
  final t = text.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final frac = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final v = int.parse(parts[0]) * 100 + frac;
  return v > 0 ? v : null;
}

/// What was noted this month (the day's `YYYY-MM`), in paise.
int askodoxKitchenMonthSpend(List<AskodoxKitchenSpend> spends, DateTime today) {
  final key = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}';
  return spends.where((s) => s.day.startsWith(key)).fold(0, (a, s) => a + s.paise);
}

/// The buy list as a message to the family.
String askodoxKitchenBuyText(List<AskodoxKitchenItem> items, bool te) {
  final list = askodoxKitchenBuyList(items);
  if (list.isEmpty) return '';
  return [
    te ? 'కొనాల్సిన సరుకులు' : 'To buy',
    for (final i in list) '- ${i.name}${i.finished || i.milli == 0 ? '' : ' (${te ? 'ఉంది' : 'left'} ${askodoxKitchenShown(i.milli)} ${i.unit})'}',
  ].join('\n');
}

/// "1,00,000"-style rupees from paise, whole rupees only.
String askodoxKitchenRupees(int paise) {
  final s = (paise ~/ 100).toString();
  if (s.length <= 3) return '₹$s';
  final head = s.substring(0, s.length - 3), tail = s.substring(s.length - 3);
  final groups = <String>[];
  var h = head;
  while (h.length > 2) {
    groups.insert(0, h.substring(h.length - 2));
    h = h.substring(0, h.length - 2);
  }
  if (h.isNotEmpty) groups.insert(0, h);
  return '₹${groups.join(',')},$tail';
}

AskodoxKitchenBook askodoxKitchenDecode(String? raw) {
  if (raw == null || raw.isEmpty) return const AskodoxKitchenBook();
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return const AskodoxKitchenBook();
    return AskodoxKitchenBook(
        items: [for (final r in (data['items'] as List? ?? const [])) AskodoxKitchenItem.from(r)].nonNulls.toList(),
        spends: [for (final r in (data['spends'] as List? ?? const [])) AskodoxKitchenSpend.from(r)].nonNulls.toList());
  } catch (_) {
    return const AskodoxKitchenBook();
  }
}

String askodoxKitchenEncode(AskodoxKitchenBook b) =>
    jsonEncode({'items': [for (final i in b.items) i.toJson()], 'spends': [for (final s in b.spends) s.toJson()]});
