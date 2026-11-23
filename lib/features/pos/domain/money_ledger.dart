/// ONE money history (owner 2026-11-17): the phone's payments, the bills the person got (My bills), the shop's bills and
/// bank / Razorpay alerts, upcoming dues (EMI, current bill, rent ...) -- as one list, with "which bill did this pay",
/// "what was it for" and "what is coming". Pure rules only; the screens and storage live elsewhere.
///
/// Rules that never bend: the person's own money and a shop's money are never mixed (each view is built from one
/// side only); a payment is joined to a bill ONLY by the person's tap (suggestions are suggestions); ASKODOX never holds
/// money.
library;

import 'money_accounts.dart';

/// One row of the money history.
class AskodoxMoneyItem {
  const AskodoxMoneyItem({
    required this.id,
    required this.kind,
    required this.direction,
    required this.amountPaise,
    required this.at,
    required this.title,
    this.sub = '',
    this.how = '',
    this.account = '',
    this.confirmed = '',
    this.pending = false,
    this.category = '',
    this.linkedTo = '',
    this.raw = const {},
  });

  /// phone:LOCAL_ID | mybill:TOKEN | shopbill:INVOICE_ID | shopalert:EVENT_ID | due:ID
  final String id;

  /// payment | bill | due
  final String kind;

  /// in | out
  final String direction;
  final int amountPaise;
  final DateTime at;
  final String title;
  final String sub;

  /// How it moved: phonepe | gpay | paytm | upi | qr | wallet | card | bank | cash | razorpay | sms | ''
  final String how;
  final String account;

  /// Who confirmed it: bank_sms | provider | cashier | '' (= only an app notification / not paid yet)
  final String confirmed;

  /// A bill not paid yet / a due not paid yet.
  final bool pending;
  final String category;

  /// The other half of a join ("mybill:TOKEN" on a payment, "phone:ID" on a bill).
  final String linkedTo;
  final Map<String, Object?> raw;
}

// ------------------------------------------------------------------ how a payment moved

/// A payment app package / label -> a short "how" key. Covers the common Indian apps; any other bank / app -> bank / upi.
String askodoxHowOf(String package, String label, {String kind = ''}) {
  final s = '$package $label'.toLowerCase();
  if (s.contains('phonepe')) return 'phonepe';
  if (s.contains('paisa') || s.contains('google pay') || s.contains('gpay') || s.contains('nbu.paisa')) return 'gpay';
  if (s.contains('paytm')) return 'paytm';
  if (s.contains('amazon')) return 'wallet';
  if (s.contains('razorpay')) return 'razorpay';
  if (s.contains('bhim') || s.contains('upi')) return 'upi';
  // the bank's own app beats its SMS (owner 2026-11-17: show the app the money came through, not "Bank SMS")
  if (kind == 'bank' || s.contains('bank')) return 'bank';
  if (kind == 'sms' || s.contains('messag') || s.contains('sms')) return 'sms';
  return 'upi';
}

/// A shop bill's payment mode (server `pos_bills.MODE_KEYS`) as a "how" key. Owner 2026-11-23: a ₹580 UPI bill showed
/// "Other" -- UPI with no app named is `other_upi` on the server, which no label knew.
String askodoxBillModeHow(String mode) => switch (mode) {
      'other_upi' || 'upi' || 'bhim' => 'upi',
      'bank_transfer' || 'neft' || 'imps' || 'rtgs' => 'bank',
      _ => mode,
    };

/// (en, te) for a "how" key.
(String, String) askodoxHowLabel(String how) => switch (how) {
      'phonepe' => ('PhonePe', 'PhonePe'),
      'gpay' => ('Google Pay', 'Google Pay'),
      'paytm' => ('Paytm', 'Paytm'),
      'qr' => ('QR', 'QR'),
      'wallet' => ('Wallet', 'వాలెట్'),
      'card' => ('Card', 'కార్డ్'),
      'bank' => ('Bank', 'బ్యాంక్'),
      'cash' => ('Cash', 'క్యాష్'),
      'razorpay' => ('Razorpay', 'Razorpay'),
      'sms' => ('Bank SMS', 'బ్యాంక్ SMS'),
      'upi' || 'other_upi' => ('UPI', 'UPI'),
      'cheque' => ('Cheque', 'చెక్'),
      'credit' || 'due' => ('Due', 'బాకీ'),
      _ => ('Other', 'ఇతరాలు'),
    };

// ------------------------------------------------------------------ categories

/// Spending / income categories: key, English, Telugu, words that name it (shop / payee / bill names).
const askodoxMoneyCategories = <(String, String, String, List<String>)>[
  ('meat', 'Meat & fish', 'మాంసం / చేపలు', ['chicken', 'mutton', 'meat', 'fish', 'prawn', 'egg', 'poultry', 'చికెన్', 'మటన్', 'మాంసం', 'చేప']),
  ('grocery', 'Grocery', 'కిరాణా', ['kirana', 'grocery', 'mart', 'stores', 'provision', 'supermarket', 'dmart', 'కిరాణా']),
  ('food', 'Food & hotel', 'భోజనం / హోటల్', ['hotel', 'restaurant', 'tiffin', 'cafe', 'bakery', 'swiggy', 'zomato', 'mess', 'హోటల్']),
  ('fuel', 'Petrol / fuel', 'పెట్రోల్', ['petrol', 'fuel', 'diesel', 'indian oil', 'iocl', 'bharat petroleum', 'bpcl', 'hpcl', 'hp petrol', 'పెట్రోల్']),
  ('power', 'Current / water / gas', 'కరెంట్ / నీళ్లు / గ్యాస్', ['power', 'electricity', 'electric', 'elec', 'ele', 'current bill', 'discom', 'vidyut', 'bijli', 'spdcl', 'npdcl', 'apspdcl', 'tsspdcl', 'bescom', 'tneb', 'tangedco', 'kseb', 'bses', 'water', 'gas', 'lpg', 'indane', 'కరెంట్']),
  ('phone', 'Phone / internet / DTH', 'ఫోన్ / ఇంటర్నెట్', ['jio', 'airtel', 'vodafone', 'vi ', 'bsnl', 'recharge', 'broadband', 'dth', 'tata play', 'రీఛార్జ్']),
  ('emi', 'EMI / loan', 'EMI / లోన్', ['emi', 'loan', 'nach', 'finance', 'bajaj', 'mandate', 'లోన్']),
  ('rent', 'Rent', 'అద్దె', ['rent', 'అద్దె']),
  ('insurance', 'Insurance', 'ఇన్సూరెన్స్', ['lic', 'insurance', 'premium', 'policy']),
  ('medical', 'Medical', 'మెడికల్', ['medical', 'pharma', 'hospital', 'clinic', 'apollo', 'medplus', 'మెడికల్']),
  ('education', 'Education', 'చదువు', ['school', 'college', 'tuition', 'fees', 'academy']),
  ('shopping', 'Shopping', 'షాపింగ్', ['amazon', 'flipkart', 'meesho', 'myntra', 'ajio', 'textile', 'fashion']),
  ('travel', 'Travel', 'ప్రయాణం', ['irctc', 'redbus', 'uber', 'ola', 'rapido', 'apsrtc', 'tsrtc', 'bus', 'train']),
  ('supplier', 'Suppliers / stock', 'సప్లయర్లు / సరుకు', ['supplier', 'wholesale', 'traders', 'agencies', 'distributor']),
  ('askodox', 'ASKODOX', 'ASKODOX', ['askodox']),
  ('salary', 'Salary', 'జీతం', ['salary', 'neft', 'payroll', 'జీతం']),
  ('other', 'Other', 'ఇతరాలు', []),
];

(String, String) askodoxCategoryLabel(String key) {
  for (final c in askodoxMoneyCategories) {
    if (c.$1 == key) return (c.$2, c.$3);
  }
  return ('Not set', 'వర్గం లేదు');
}

String askodoxNormPayee(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ఀ-౿]+'), ' ').trim();

/// The category of a row: the person's choice for this row > their choice for this payee > an EMI debit > the words
/// in the payee / bill name > none ("").
String askodoxCategoryOf(AskodoxMoneyItem item, {Map<String, String> rowCategory = const {}, Map<String, String> payeeCategory = const {}}) {
  final mine = rowCategory[item.id];
  if (mine != null && mine.isNotEmpty) return mine;
  final payee = askodoxNormPayee(item.title);
  final byPayee = payeeCategory[payee];
  if (byPayee != null && byPayee.isNotEmpty) return byPayee;
  if (item.raw['emi'] == true) return 'emi';
  if (item.category.isNotEmpty) return item.category;
  // Owner 2026-11-20: a transfer to a person showed "Food & hotel" because the SMS app's name "Messages" contains
  // "mess". Only the payee / bill name decides (never the app or SMS label), and a word must match as a WHOLE word.
  final words = ' ${askodoxNormPayee(item.title)} ';
  for (final c in askodoxMoneyCategories) {
    if (c.$4.any((w) => askodoxNameHasWord(words, w))) return c.$1;
  }
  // Owner 2026-11-22 ("APCPDC Ele Bill"): electricity boards are named by their initials in every state (APCPDCL,
  // TSNPDCL, MSEDCL, JVVNL, DHBVN, HESCOM ...) -- the ending says it, never a list of every board.
  if (_powerBoard.hasMatch(words)) return 'power';
  return '';
}

final _powerBoard = RegExp(r' [a-z]{1,6}(?:pdcl|pdc|vvnl|bvn|sedcl|escom) ');

/// True when [word] appears in the padded, normalised [padded] name as whole word(s). Indian-script words match
/// anywhere (they join to the word before them: "చికెన్‌సెంటర్").
bool askodoxNameHasWord(String padded, String word) {
  final w = askodoxNormPayee(word);
  if (w.isEmpty) return false;
  if (RegExp(r'[ఀ-౿]').hasMatch(w)) return padded.contains(w);
  return padded.contains(' $w ');
}

// ------------------------------------------------------------------ building rows

DateTime _when(Object? iso, [Object? ms]) {
  if (ms is num && ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  return DateTime.tryParse('${iso ?? ''}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// The phone's own payment rows (My phone). Due reminders and tests are left out.
List<AskodoxMoneyItem> askodoxItemsFromPhone(Iterable<Map<String, Object?>> events, List<AskodoxMoneyPlace> places,
    Map<String, String> assigned, Map<String, String> links, {Map<String, String> labelToPackage = const {}}) {
  final out = <AskodoxMoneyItem>[];
  for (final e in events) {
    if (e['test'] == true || e['direction'] == 'due' || e['amount_paise'] is! num) continue;
    // Owner 2026-11-19: a 'received' SMS from a person's number is a likely fake -- never counted as money.
    if (e['status'] == 'suspect_sender') continue;
    // Owner 2026-11-21: a row set aside (bank SMS said the opposite / "not a payment") is never money.
    if (e['excluded'] == true) continue;
    final id = 'phone:${e['local_id']}';
    final party = '${e['party'] ?? ''}'.trim();
    final label = '${e['source_label'] ?? ''}';
    final also = '${e['also_from'] ?? ''}';
    final how = askodoxHowOf('${e['source_app'] ?? ''}', '$label $also', kind: '${e['kind'] ?? ''}');
    final account = askodoxAccountOf(e, places, assigned, labelToPackage: labelToPackage);
    out.add(AskodoxMoneyItem(
      id: id,
      kind: 'payment',
      direction: e['direction'] == 'out' ? 'out' : 'in',
      amountPaise: (e['amount_paise'] as num).toInt(),
      at: _when(e['detected_at'], e['at_ms']),
      title: party.isNotEmpty ? party : askodoxNoNameTitle(label, also, account, places),
      sub: also.isEmpty ? label : '$label + $also',
      how: how,
      account: account,
      // A debit read from the bank's own SMS IS the bank's word: no ⏳ (owner 2026-11-20).
      // 'billpay' (owner 2026-11-22) = the bank's own "Bill Paid ... from your account" SMS.
      confirmed: e['bank_confirmed'] == true || (e['direction'] == 'out' && (e['kind'] == 'sms' || e['kind'] == 'billpay')) ? 'bank_sms' : '',
      linkedTo: links[id] ?? '',
      raw: e,
    ));
  }
  return out;
}

/// A payment with no person's name: never the messages app's name ("Messages (Google)") -- the app it came through,
/// else the account it moved in ("HDFC ••6911"), else the bank.
String askodoxNoNameTitle(String label, String also, String account, List<AskodoxMoneyPlace> places) {
  bool messages(String x) => x.toLowerCase().contains('messag') || x.toLowerCase().contains('sms');
  if (label.trim().isNotEmpty && !messages(label)) return label.trim();
  if (also.trim().isNotEmpty && !messages(also)) return also.trim();
  for (final p in places) {
    if (p.key == account && p.name.trim().isNotEmpty) return p.name.trim();
  }
  if (account.startsWith('bank:')) return 'A/c ••${account.substring(5)}';
  return 'Bank';
}

/// Bills the person RECEIVED from shops (My bills): money they owe / paid.
List<AskodoxMoneyItem> askodoxItemsFromMyBills(Iterable<Map<String, Object?>> bills, Map<String, String> links) {
  final out = <AskodoxMoneyItem>[];
  for (final b in bills) {
    final token = '${b['token'] ?? ''}';
    if (token.isEmpty) continue;
    final id = 'mybill:$token';
    final due = (b['due_paise'] as num?)?.toInt() ?? 0;
    final total = (b['total_paise'] as num?)?.toInt() ?? 0;
    final shop = '${b['shop'] ?? b['name'] ?? ''}';
    final lines = b['lines'] is List ? (b['lines'] as List).whereType<Map>().map((l) => '${l['name'] ?? ''}').where((x) => x.isNotEmpty) : const <String>[];
    final linked = links.entries.where((e) => e.value == id).map((e) => e.key).firstOrNull ?? '';
    out.add(AskodoxMoneyItem(
      id: id,
      kind: 'bill',
      direction: 'out',
      amountPaise: due > 0 ? due : total,
      at: _when(b['issued_at']),
      title: shop.isEmpty ? 'Bill ${b['number'] ?? ''}' : shop,
      sub: ['#${b['number'] ?? ''}', ...lines.take(2)].join(' · '),
      how: '${b['paid_with'] ?? ''}',
      confirmed: due <= 0 && total > 0 ? 'cashier' : '',
      pending: due > 0 && linked.isEmpty,
      linkedTo: linked,
      raw: b,
    ));
  }
  return out;
}

/// The shop's own bills (Bill history): money customers paid / still owe the shop.
List<AskodoxMoneyItem> askodoxItemsFromShopBills(Iterable<Map<String, Object?>> bills) => [
      for (final b in bills)
        if ('${b['status']}' == 'issued')
          AskodoxMoneyItem(
            id: 'shopbill:${b['id']}',
            kind: 'bill',
            direction: 'in',
            amountPaise: (b['total_paise'] as num?)?.toInt() ?? 0,
            at: _when(b['issued_at']),
            title: '${b['customer_name'] ?? ''}'.isEmpty ? 'Bill ${b['number']}' : '${b['customer_name']}',
            sub: '#${b['number']}',
            how: (b['modes'] is List && (b['modes'] as List).isNotEmpty) ? askodoxBillModeHow('${(b['modes'] as List).first}') : '',
            confirmed: ((b['due_paise'] as num?)?.toInt() ?? 0) <= 0 ? 'cashier' : '',
            pending: ((b['due_paise'] as num?)?.toInt() ?? 0) > 0,
            raw: b,
          ),
    ];

/// The shop's payment alerts (Razorpay verified / shop phones).
List<AskodoxMoneyItem> askodoxItemsFromShopAlerts(Iterable<Map<String, Object?>> events) => [
      for (final e in events)
        if (e['test'] != true && e['amount_paise'] is num && e['status'] != 'duplicate')
          AskodoxMoneyItem(
            id: 'shopalert:${e['id']}',
            kind: 'payment',
            direction: 'in',
            amountPaise: (e['amount_paise'] as num).toInt(),
            at: _when(e['detected_at']),
            title: '${e['source_label'] ?? ''}',
            sub: '${e['reference_tail'] ?? ''}'.isEmpty ? '' : 'Ref ••${e['reference_tail']}',
            how: askodoxHowOf('${e['source_app'] ?? ''}', '${e['source_label'] ?? ''}'),
            confirmed: e['verified'] == true ? 'provider' : '',
            raw: e,
          ),
    ];

// ------------------------------------------------------------------ "which bill did this pay?"

/// A suggestion: this payment may be for that bill.
class AskodoxPairSuggestion {
  const AskodoxPairSuggestion(this.payment, this.bill);
  final AskodoxMoneyItem payment;
  final AskodoxMoneyItem bill;
}

/// Payments not joined yet whose amount equals a pending bill's amount, in the right direction, within [window] after
/// the bill (or a little before: the bill may be made after a counter payment). Each payment and each bill is offered
/// once (closest in time first). [dismissed] = "paymentId|billId" pairs the person said no to.
List<AskodoxPairSuggestion> askodoxPairSuggestions(List<AskodoxMoneyItem> payments, List<AskodoxMoneyItem> bills,
    {Set<String> dismissed = const {}, Duration window = const Duration(days: 3)}) {
  final cands = <(int, AskodoxMoneyItem, AskodoxMoneyItem)>[];
  for (final p in payments) {
    if (p.kind != 'payment' || p.linkedTo.isNotEmpty) continue;
    for (final b in bills) {
      if (b.kind != 'bill' || !b.pending || b.linkedTo.isNotEmpty) continue;
      if (b.direction != p.direction || b.amountPaise != p.amountPaise) continue;
      final gap = p.at.difference(b.at);
      if (gap > window || gap < const Duration(hours: -2)) continue;
      if (dismissed.contains('${p.id}|${b.id}')) continue;
      cands.add((gap.inMinutes.abs(), p, b));
    }
  }
  cands.sort((a, b) => a.$1.compareTo(b.$1));
  final usedP = <String>{}, usedB = <String>{};
  final out = <AskodoxPairSuggestion>[];
  for (final c in cands) {
    if (usedP.contains(c.$2.id) || usedB.contains(c.$3.id)) continue;
    usedP.add(c.$2.id);
    usedB.add(c.$3.id);
    out.add(AskodoxPairSuggestion(c.$2, c.$3));
  }
  return out;
}

// ------------------------------------------------------------------ totals

class AskodoxMoneyTotals {
  const AskodoxMoneyTotals(this.inPaise, this.outPaise, this.byCategory, this.inByHow);
  final int inPaise;
  final int outPaise;
  final Map<String, int> byCategory;
  final Map<String, int> inByHow;
}

/// Money in / out from [from] (inclusive) to [to] (exclusive). Bills already paid by a joined payment are counted once
/// (the payment); unpaid bills are not money that moved.
AskodoxMoneyTotals askodoxTotals(Iterable<AskodoxMoneyItem> items, DateTime from, DateTime to,
    {Map<String, String> rowCategory = const {}, Map<String, String> payeeCategory = const {}}) {
  var inP = 0, outP = 0;
  final cat = <String, int>{};
  final how = <String, int>{};
  for (final i in items) {
    if (i.kind == 'due' || i.at.isBefore(from) || !i.at.isBefore(to)) continue;
    if (i.kind == 'bill' && (i.pending || i.linkedTo.isNotEmpty)) continue;
    if (i.direction == 'in') {
      inP += i.amountPaise;
      how[i.how.isEmpty ? 'other' : i.how] = (how[i.how.isEmpty ? 'other' : i.how] ?? 0) + i.amountPaise;
    } else {
      outP += i.amountPaise;
      final c = askodoxCategoryOf(i, rowCategory: rowCategory, payeeCategory: payeeCategory);
      cat[c] = (cat[c] ?? 0) + i.amountPaise;
    }
  }
  return AskodoxMoneyTotals(inP, outP, cat, how);
}

/// The latest balance a bank SMS told, per account key: (paise, when).
Map<String, (int, DateTime)> askodoxLatestBalances(Iterable<AskodoxMoneyItem> items) {
  final out = <String, (int, DateTime)>{};
  for (final i in items) {
    final b = i.raw['balance_paise'];
    if (b is! num || i.account.isEmpty) continue;
    final have = out[i.account];
    if (have == null || i.at.isAfter(have.$2)) out[i.account] = (b.toInt(), i.at);
  }
  return out;
}

// ------------------------------------------------------------------ upcoming dues (EMI, current bill, rent ...)

class AskodoxDue {
  const AskodoxDue({
    required this.id,
    required this.name,
    required this.amountPaise,
    required this.date,
    this.repeat = 'monthly',
    this.category = '',
    this.paidDates = const [],
    this.match = '',
  });

  final String id;
  final String name;
  final int amountPaise;

  /// The FIRST / reference due date.
  final DateTime date;

  /// once | monthly | quarterly | yearly | days:N (e.g. days:84 for a phone recharge)
  final String repeat;
  final String category;

  /// Due dates (yyyy-MM-dd) the person marked paid.
  final List<String> paidDates;

  /// Words that name its payee in a payment (to offer "was this the current bill?").
  final String match;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'amount_paise': amountPaise,
        'date': askodoxDay(date),
        'repeat': repeat,
        if (category.isNotEmpty) 'category': category,
        if (paidDates.isNotEmpty) 'paid': paidDates,
        if (match.isNotEmpty) 'match': match,
      };

  static AskodoxDue? fromJson(Object? j) {
    if (j is! Map) return null;
    final date = DateTime.tryParse('${j['date'] ?? ''}');
    final amount = j['amount_paise'];
    if (date == null || amount is! num || '${j['id'] ?? ''}'.isEmpty) return null;
    return AskodoxDue(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      amountPaise: amount.toInt(),
      date: date,
      repeat: '${j['repeat'] ?? 'monthly'}',
      category: '${j['category'] ?? ''}',
      paidDates: j['paid'] is List ? [for (final x in j['paid'] as List) '$x'] : const [],
      match: '${j['match'] ?? ''}',
    );
  }

  AskodoxDue copyWith({String? name, int? amountPaise, DateTime? date, String? repeat, String? category, List<String>? paidDates}) =>
      AskodoxDue(
          id: id,
          name: name ?? this.name,
          amountPaise: amountPaise ?? this.amountPaise,
          date: date ?? this.date,
          repeat: repeat ?? this.repeat,
          category: category ?? this.category,
          paidDates: paidDates ?? this.paidDates,
          match: match);
}

String askodoxDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _addMonths(DateTime d, int months) {
  final m = d.month - 1 + months;
  final y = d.year + m ~/ 12;
  final month = m % 12 + 1;
  final last = DateTime(y, month + 1, 0).day;
  return DateTime(y, month, d.day > last ? last : d.day);
}

/// The due's dates from its reference date on (at most [limit]).
Iterable<DateTime> askodoxDueDates(AskodoxDue d, {int limit = 400}) sync* {
  var cur = DateTime(d.date.year, d.date.month, d.date.day);
  for (var i = 0; i < limit; i++) {
    yield cur;
    if (d.repeat == 'once') return;
    if (d.repeat.startsWith('days:')) {
      final n = int.tryParse(d.repeat.substring(5)) ?? 30;
      cur = cur.add(Duration(days: n < 1 ? 1 : n));
    } else {
      cur = _addMonths(d.date, switch (d.repeat) { 'quarterly' => 3 * (i + 1), 'yearly' => 12 * (i + 1), _ => i + 1 });
    }
  }
}

/// The next date still to pay (the earliest unpaid date on or after the earliest unpaid one), or null (all paid / once
/// and paid). An unpaid date in the past stays the next one (it is overdue).
DateTime? askodoxNextDue(AskodoxDue d, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  for (final date in askodoxDueDates(d)) {
    if (d.paidDates.contains(askodoxDay(date))) continue;
    // a date more than 40 days in the past that nobody marked is forgotten history, not a due
    if (day.difference(date).inDays > 40) continue;
    return date;
  }
  return null;
}

/// Due reminders the phone saw ("₹1,941 due on Nov 21") that are not in the list yet: offered with one tap.
List<Map<String, Object?>> askodoxDueSuggestions(Iterable<Map<String, Object?>> phoneEvents, List<AskodoxDue> dues,
    Set<String> dismissed, DateTime today) {
  final out = <Map<String, Object?>>[];
  final seen = <String>{};
  // Owner 2026-11-22: a bill that is already PAID is not offered as an upcoming due -- the phone saw the same amount
  // go out after the reminder came ("Bill Paid!" SMS, the bank's debit SMS, the app's message).
  final paid = <(int, int)>[
    for (final e in phoneEvents)
      if (e['direction'] == 'out' && e['test'] != true && e['excluded'] != true && e['amount_paise'] is num && e['at_ms'] is num)
        ((e['amount_paise'] as num).toInt(), (e['at_ms'] as num).toInt()),
  ];
  for (final e in phoneEvents) {
    if (e['direction'] != 'due') continue;
    final date = DateTime.tryParse('${e['due_date'] ?? ''}');
    final amount = e['amount_paise'];
    if (date == null || amount is! num) continue;
    final cameAt = e['at_ms'];
    if (cameAt is num && cameAt > 0 && paid.any((p) => p.$1 == amount.toInt() && p.$2 >= cameAt)) continue;
    if (date.isBefore(DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1)))) continue;
    final key = '${amount.toInt()}|${askodoxDay(date)}';
    if (!seen.add(key) || dismissed.contains('${e['local_id']}')) continue;
    final have = dues.any((d) =>
        d.amountPaise == amount.toInt() &&
        askodoxDueDates(d, limit: 24).any((x) => askodoxDay(x) == askodoxDay(date)));
    if (have) continue;
    out.add(e);
  }
  return out;
}

/// EMI debits the phone saw (bank SMS "EMI / NACH / auto debit") whose amount is not a due yet: "add as a monthly EMI?"
List<AskodoxMoneyItem> askodoxEmiSuggestions(Iterable<AskodoxMoneyItem> items, List<AskodoxDue> dues, Set<String> dismissed) {
  final out = <AskodoxMoneyItem>[];
  final amounts = <int>{};
  for (final i in items) {
    if (i.raw['emi'] != true || i.direction != 'out' || dismissed.contains(i.id)) continue;
    if (dues.any((d) => d.amountPaise == i.amountPaise) || amounts.contains(i.amountPaise)) continue;
    amounts.add(i.amountPaise);
    out.add(i);
  }
  return out;
}

/// A payment that looks like a due being paid: same amount, out, from 7 days before to 10 days after the due date,
/// that date not marked paid yet.
(AskodoxDue, DateTime)? askodoxDuePaidBy(AskodoxMoneyItem payment, List<AskodoxDue> dues) {
  if (payment.direction != 'out' || payment.kind != 'payment') return null;
  for (final d in dues) {
    if (d.amountPaise != payment.amountPaise) continue;
    for (final date in askodoxDueDates(d, limit: 60)) {
      final gap = payment.at.difference(date).inDays;
      if (gap > 10) continue;
      if (gap < -7) break;
      if (!d.paidDates.contains(askodoxDay(date))) return (d, date);
    }
  }
  return null;
}
