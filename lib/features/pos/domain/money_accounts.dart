/// "My money accounts" on a person's own phone (owner 2026-11-17): bank accounts (last digits), UPI IDs, wallets and QR
/// codes the person adds, and the history shown account by account (in / out, today / this month).
///
/// Pure rules only (no storage, no widgets) so they are tested without a phone.
library;

/// One place money comes in to / goes out of. Bank accounts are keyed by their last digits (`bank:6911`); UPI IDs,
/// wallets and QR codes by their own id (`place:ID`).
class AskodoxMoneyPlace {
  const AskodoxMoneyPlace({
    required this.key,
    required this.type,
    required this.name,
    this.tail = '',
    this.upi = '',
    this.apps = const [],
    this.fromMethod = '',
  });

  /// `bank:DIGITS` or `place:ID`
  final String key;

  /// bank | upi | wallet | qr
  final String type;
  final String name;

  /// Bank account: the last digits a bank SMS shows (3-4).
  final String tail;

  /// UPI ID / QR: the VPA.
  final String upi;

  /// Packages whose notifications are this account's money ("PhonePe = HDFC current").
  final List<String> apps;

  /// Imported from the person's "ways to get paid" (server payment method id), so a deleted one is never re-added.
  final String fromMethod;

  Map<String, Object?> toJson() => {
        'key': key,
        'type': type,
        'name': name,
        if (tail.isNotEmpty) 'tail': tail,
        if (upi.isNotEmpty) 'upi': upi,
        if (apps.isNotEmpty) 'apps': apps,
        if (fromMethod.isNotEmpty) 'from_method': fromMethod,
      };

  static AskodoxMoneyPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final key = '${j['key'] ?? ''}';
    final type = '${j['type'] ?? ''}';
    if (key.isEmpty || !askodoxMoneyPlaceTypes.contains(type)) return null;
    return AskodoxMoneyPlace(
      key: key,
      type: type,
      name: '${j['name'] ?? ''}',
      tail: '${j['tail'] ?? ''}',
      upi: '${j['upi'] ?? ''}',
      apps: j['apps'] is List ? [for (final a in j['apps'] as List) '$a'] : const [],
      fromMethod: '${j['from_method'] ?? ''}',
    );
  }

  AskodoxMoneyPlace copyWith({String? name, List<String>? apps}) => AskodoxMoneyPlace(
      key: key, type: type, name: name ?? this.name, tail: tail, upi: upi, apps: apps ?? this.apps, fromMethod: fromMethod);
}

const askodoxMoneyPlaceTypes = ['bank', 'upi', 'wallet', 'qr'];

/// (en, te) name of a place type.
(String, String) askodoxMoneyPlaceTypeLabel(String type) => switch (type) {
      'bank' => ('Bank account', 'బ్యాంక్ ఖాతా'),
      'upi' => ('UPI ID', 'UPI ID'),
      'wallet' => ('Wallet', 'వాలెట్'),
      'qr' => ('QR code', 'QR కోడ్'),
      _ => ('Account', 'ఖాతా'),
    };

String askodoxBankKey(String tail) => 'bank:$tail';

/// Key used for money whose account is not known (an app notification with no bank SMS, no linked app).
const askodoxUnknownAccount = '';

/// The UPI ID inside a scanned QR ("upi://pay?pa=shop@okhdfcbank&pn=..."), or null.
String? askodoxUpiFromQr(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.scheme.toLowerCase() == 'upi') {
    final pa = uri.queryParameters['pa'];
    if (pa != null && pa.contains('@')) return pa.trim();
  }
  final m = RegExp(r'pa=([A-Za-z0-9._\-]+@[A-Za-z0-9.\-]+)').firstMatch(text);
  if (m != null) return m.group(1);
  return RegExp(r'^[A-Za-z0-9._\-]{2,}@[A-Za-z][A-Za-z0-9.\-]{1,}$').hasMatch(text) ? text : null;
}

/// Which account a history row belongs to:
/// 1. the person moved it by hand ([assigned] localId -> key),
/// 2. the bank SMS's last digits (a named bank account, or the plain `bank:DIGITS` bucket),
/// 3. an app linked to an account (its own app, or an app merged into the row),
/// 4. otherwise unknown ("").
String askodoxAccountOf(Map<String, Object?> event, List<AskodoxMoneyPlace> places, Map<String, String> assigned,
    {Map<String, String> labelToPackage = const {}}) {
  final id = '${event['local_id'] ?? ''}';
  final moved = assigned[id];
  if (moved != null && moved.isNotEmpty) return moved;
  final tail = '${event['account'] ?? ''}';
  if (tail.isNotEmpty) return askodoxBankKey(tail);
  final packages = <String>{
    '${event['source_app'] ?? ''}',
    for (final label in '${event['also_from'] ?? ''}'.split(',').map((x) => x.trim()))
      if (labelToPackage[label] != null) labelToPackage[label]!,
  };
  for (final p in places) {
    if (p.apps.any(packages.contains)) return p.key;
  }
  return askodoxUnknownAccount;
}

/// Bank account digits seen in the history that the person has not named yet (newest first, no repeats).
List<String> askodoxUnnamedTails(Iterable<Map<String, Object?>> events, List<AskodoxMoneyPlace> places) {
  final named = {for (final p in places) if (p.type == 'bank') p.tail};
  final out = <String>[];
  for (final e in events) {
    final tail = '${e['account'] ?? ''}';
    if (tail.isNotEmpty && !named.contains(tail) && !out.contains(tail)) out.add(tail);
  }
  return out;
}

/// Money in / out (paise) of the rows that happened at or after [from]. Test rows are never counted.
({int inPaise, int outPaise, int count}) askodoxMoneyTotals(Iterable<Map<String, Object?>> events, DateTime from) {
  var inP = 0, outP = 0, n = 0;
  for (final e in events) {
    if (e['test'] == true) continue;
    final amount = e['amount_paise'];
    if (amount is! num) continue;
    final at = askodoxEventTime(e);
    if (at == null || at.isBefore(from)) continue;
    n++;
    if (e['direction'] == 'out') {
      outP += amount.toInt();
    } else {
      inP += amount.toInt();
    }
  }
  return (inPaise: inP, outPaise: outP, count: n);
}

/// The payment's own time (at_ms), else when the phone saw it (detected_at).
DateTime? askodoxEventTime(Map<String, Object?> e) {
  final ms = e['at_ms'];
  if (ms is num && ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return DateTime.tryParse('${e['detected_at'] ?? ''}')?.toLocal();
}

/// The person's "ways to get paid" (server payment methods) turned into accounts they do not have yet. A method
/// imported once and later deleted by the person ([dismissed]) never comes back.
List<AskodoxMoneyPlace> askodoxPlacesFromMethods(
    List<Map<String, Object?>> methods, List<AskodoxMoneyPlace> have, Set<String> dismissed) {
  final out = <AskodoxMoneyPlace>[];
  final tails = {for (final p in have) if (p.type == 'bank') p.tail};
  final upis = {for (final p in have) if (p.upi.isNotEmpty) p.upi.toLowerCase()};
  final fromIds = {for (final p in have) if (p.fromMethod.isNotEmpty) p.fromMethod};
  for (final m in methods) {
    final id = '${m['id'] ?? ''}';
    if (id.isEmpty || dismissed.contains(id) || fromIds.contains(id)) continue;
    final label = '${m['label'] ?? ''}'.trim();
    if (m['kind'] == 'bank') {
      final last4 = '${m['account_last4'] ?? ''}';
      if (last4.length < 3 || tails.contains(last4)) continue;
      final bank = '${m['bank_name'] ?? m['app'] ?? ''}'.trim();
      out.add(AskodoxMoneyPlace(
          key: askodoxBankKey(last4),
          type: 'bank',
          name: label.isNotEmpty ? label : (bank.isNotEmpty ? '$bank ••$last4' : 'A/c ••$last4'),
          tail: last4,
          fromMethod: id));
      tails.add(last4);
    } else if (m['kind'] == 'upi') {
      final upi = '${m['upi_id'] ?? ''}'.trim();
      if (upi.isEmpty || upis.contains(upi.toLowerCase())) continue;
      out.add(AskodoxMoneyPlace(
          key: 'place:m_$id', type: 'upi', name: label.isNotEmpty ? label : upi, upi: upi, fromMethod: id));
      upis.add(upi.toLowerCase());
    }
  }
  return out;
}
