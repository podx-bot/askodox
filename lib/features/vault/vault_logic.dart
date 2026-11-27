/// Bills & warranty (owner 2026-11-27, phase 6): the papers a person wants to find again -- what was bought, where,
/// when, the warranty's last day, the serial number, the service number. The records and the photos stay on the
/// person's own phone (account-scoped). Dates are what the paper says, checked by the person.
library;

import 'dart:convert';

/// A warranty with this many days left (or fewer) is "ending".
const askodoxVaultEndingDays = 30;
const askodoxVaultKeep = 500;

class AskodoxVaultPaper {
  const AskodoxVaultPaper({
    required this.id,
    required this.item,
    this.shop = '',
    this.boughtOn = '',
    this.warrantyUntil = '',
    this.serial = '',
    this.servicePhone = '',
    this.amountPaise = 0,
    this.photo = '',
    this.remind = true,
    this.addedAt = '',
  });

  final String id, item, shop, serial, servicePhone, addedAt;

  /// `YYYY-MM-DD`, or empty when the paper does not say.
  final String boughtOn, warrantyUntil;
  final int amountPaise;

  /// The photo's file on this phone ('' = typed, no photo).
  final String photo;
  final bool remind;

  Map<String, Object?> toJson() => {
        'id': id, 'item': item, 'shop': shop, 'bought': boughtOn, 'until': warrantyUntil, 'serial': serial,
        'service': servicePhone, 'amount': amountPaise, 'photo': photo, 'remind': remind, 'at': addedAt,
      };

  static AskodoxVaultPaper? from(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => '${raw[k] ?? ''}';
    if (s('id').isEmpty || s('item').isEmpty) return null;
    return AskodoxVaultPaper(
        id: s('id'), item: s('item'), shop: s('shop'), boughtOn: askodoxVaultDay(s('bought')),
        warrantyUntil: askodoxVaultDay(s('until')), serial: s('serial'), servicePhone: s('service'),
        amountPaise: raw['amount'] is num ? (raw['amount'] as num).toInt() : 0, photo: s('photo'),
        remind: raw['remind'] != false, addedAt: s('at'));
  }
}

/// A real `YYYY-MM-DD` day, else ''.
String askodoxVaultDay(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (match == null) return '';
  final y = int.parse(match[1]!), m = int.parse(match[2]!), d = int.parse(match[3]!);
  final day = DateTime(y, m, d);
  return day.year == y && day.month == m && day.day == d ? text.trim() : '';
}

String askodoxVaultIso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// "27-11-2026" for the eye; '' stays ''.
String askodoxVaultShown(String iso) => iso.length == 10 ? '${iso.substring(8)}-${iso.substring(5, 7)}-${iso.substring(0, 4)}' : '';

/// Days from today to the warranty's last day (negative = over); null with no end day.
int? askodoxVaultDaysLeft(String until, DateTime today) {
  if (askodoxVaultDay(until).isEmpty) return null;
  final end = DateTime.utc(int.parse(until.substring(0, 4)), int.parse(until.substring(5, 7)), int.parse(until.substring(8)));
  return end.difference(DateTime.utc(today.year, today.month, today.day)).inDays;
}

/// none (no end day) / over / ending (30 days or fewer) / on.
String askodoxVaultState(AskodoxVaultPaper paper, DateTime today) {
  final left = askodoxVaultDaysLeft(paper.warrantyUntil, today);
  if (left == null) return 'none';
  if (left < 0) return 'over';
  return left <= askodoxVaultEndingDays ? 'ending' : 'on';
}

/// The line under an item's name.
String askodoxVaultStateText(AskodoxVaultPaper paper, DateTime today, bool te) {
  final left = askodoxVaultDaysLeft(paper.warrantyUntil, today);
  return switch (askodoxVaultState(paper, today)) {
    'over' => te ? 'వారంటీ ముగిసింది' : 'Warranty is over',
    'ending' => left == 0
        ? (te ? 'వారంటీ ఈ రోజే ముగుస్తోంది' : 'Warranty ends today')
        : (te ? 'ముగుస్తోంది · $left రోజులు' : 'Ending · $left days'),
    'on' => left! >= 60
        ? (te ? 'వారంటీ ఉంది · ${left ~/ 30} నెలలు' : 'In warranty · ${left ~/ 30} months')
        : (te ? 'వారంటీ ఉంది · $left రోజులు' : 'In warranty · $left days'),
    _ => te ? 'బిల్ మాత్రమే' : 'Bill only',
  };
}

/// What the list shows: the search words (item or shop) and one filter (all / warranty / ending); ending first, then
/// the newest.
List<AskodoxVaultPaper> askodoxVaultShow(List<AskodoxVaultPaper> papers, DateTime today, {String query = '', String filter = 'all'}) {
  final q = query.trim().toLowerCase();
  int rank(AskodoxVaultPaper p) => switch (askodoxVaultState(p, today)) { 'ending' => 0, 'on' => 1, 'none' => 2, _ => 3 };
  final out = [
    for (final p in papers)
      if ((q.isEmpty || p.item.toLowerCase().contains(q) || p.shop.toLowerCase().contains(q)) &&
          (filter == 'all' ||
              (filter == 'warranty' && askodoxVaultState(p, today) != 'none') ||
              (filter == 'ending' && askodoxVaultState(p, today) == 'ending')))
        p,
  ];
  out.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    if (rank(a) == 0) return a.warrantyUntil.compareTo(b.warrantyUntil);
    return b.addedAt.compareTo(a.addedAt);
  });
  return out;
}

/// The papers to remind about now: ending, and the person left the reminder on. Soonest first.
List<AskodoxVaultPaper> askodoxVaultEnding(List<AskodoxVaultPaper> papers, DateTime today) => [
      for (final p in askodoxVaultShow(papers, today, filter: 'ending'))
        if (p.remind) p,
    ];

/// The message a person sends a service centre: what, when bought, serial -- nothing else of theirs.
String askodoxVaultServiceText(AskodoxVaultPaper p, bool te) => [
      te ? 'సర్వీస్ కోసం వివరాలు' : 'Details for service',
      '${te ? 'వస్తువు' : 'Item'}: ${p.item}',
      if (p.shop.isNotEmpty) '${te ? 'కొన్న షాప్' : 'Bought at'}: ${p.shop}',
      if (p.boughtOn.isNotEmpty) '${te ? 'కొన్న తేదీ' : 'Bought on'}: ${askodoxVaultShown(p.boughtOn)}',
      if (p.warrantyUntil.isNotEmpty) '${te ? 'వారంటీ ముగింపు' : 'Warranty till'}: ${askodoxVaultShown(p.warrantyUntil)}',
      if (p.serial.isNotEmpty) '${te ? 'సీరియల్ నంబర్' : 'Serial number'}: ${p.serial}',
    ].join('\n');

List<AskodoxVaultPaper> askodoxVaultDecode(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [for (final row in data) AskodoxVaultPaper.from(row)].nonNulls.toList();
  } catch (_) {
    return const [];
  }
}

String askodoxVaultEncode(List<AskodoxVaultPaper> papers) => jsonEncode([for (final p in papers) p.toJson()]);
