/// Owner 2026-11-23 (ASKODOX Lite step 3): with NO net the chat still answers what the phone itself knows -- how much
/// came today / yesterday / this week / this month, the last payment, who paid -- from the phone's own payment records
/// (My phone payments). Any other question needs the net: it is KEPT (never lost, never guessed) and asked by itself
/// when the net is back.
///
/// Pure rules + one small store. No bank, app or shop names anywhere: the words are about money and time only.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../pos/domain/money_ledger.dart';

// ------------------------------------------------------------------ what was asked

enum AskodoxOfflineSpan { today, yesterday, week, month }

/// What the phone can answer by itself. [last] = "the last payment", [who] = "who paid how much".
class AskodoxOfflineAsk {
  const AskodoxOfflineAsk({required this.span, required this.out, this.last = false, this.who = false});
  final AskodoxOfflineSpan span;

  /// true = money that went out, false = money that came in.
  final bool out;
  final bool last;
  final bool who;

  @override
  bool operator ==(Object other) =>
      other is AskodoxOfflineAsk && other.span == span && other.out == out && other.last == last && other.who == who;

  @override
  int get hashCode => Object.hash(span, out, last, who);

  @override
  String toString() => 'AskodoxOfflineAsk(${span.name}, ${out ? 'out' : 'in'}${last ? ', last' : ''}${who ? ', who' : ''})';
}

final _today = RegExp(r'ఈ\s?రోజు|ఇవాళ|ఇవ్వాళ|నేడు|\btoday\b|आज', caseSensitive: false);
final _yesterday = RegExp(r'నిన్న|\byesterday\b|(^|\s)कल(\s|$)', caseSensitive: false);
final _week = RegExp(r'ఈ\s?వారం|వారంలో|\bweek\b|हफ्त|सप्ताह', caseSensitive: false);
final _month = RegExp(r'ఈ\s?నెల|నెలలో|\bmonth\b|महीन', caseSensitive: false);
final _lastWord = RegExp(r'ఆఖరి|చివరి|లాస్ట్|\blast\b|\blatest\b|आखिरी|आख़िरी|पिछल', caseSensitive: false);
final _whoWord = RegExp(r'ఎవరు|ఎవరెవరు|ఎవరి|\bwho\b|किसने|किस ने|कौन', caseSensitive: false);
final _howMuch = RegExp(r'ఎంత|మొత్తం|టోటల్|లెక్క|how much|how many|\btotal\b|कितन|कुल', caseSensitive: false);
final _money = RegExp(
  r'money|amount|payment|rupee|₹|collection|sales?|డబ్బు|పేమెంట్|అమౌంట్|రూపాయ|వసూలు|పైసల|पैस|भुगतान|रुपय|पेमेंट',
  caseSensitive: false,
);
final _inWord = RegExp(
  r'వచ్చ|అందిం|అందా|అందిన|జమ|కట్టారు|ఇచ్చారు|received|\bcame\b|\bcome\b|\bgot\b|credited|paid me|who paid|paid by|आया|आए|मिल|जमा|दिया|दिए',
  caseSensitive: false,
);
final _outWord = RegExp(
  r'ఖర్చు|వెళ్ళ|వెళ్లా|వెళ్లి|పంపా|పంపిన|కట్టాను|ఇచ్చాను|పోయ|spent|\bspend\b|\bsent\b|went out|debited|\bi paid\b|खर्च|भेज|गया|गए|निकल',
  caseSensitive: false,
);
// Money words that are NOT about the person's own payments: a price, a rate, how to do something, a loan, a bill to make.
final _notOwn = RegExp(
  r'ధర|రేటు|\bprice\b|\brate\b|कीमत|भाव|how (do|can|to)|ఎలా|कैसे|loan|లోన్|ऋण|offer|ఆఫర్|order|ఆర్డర్|బిల్ చేయ|make (a )?bill|'
  r'బాకీ|\bdues?\b|उधार|బంగారం|gold|సోనా|सोना',
  caseSensitive: false,
);

/// The question the phone can answer from its own payment records, or null (= it needs the net).
AskodoxOfflineAsk? askodoxOfflineAsk(String text) {
  final s = text.trim();
  if (s.length < 4 || s.length > 140) return null;
  if (_notOwn.hasMatch(s)) return null;
  final out = _outWord.hasMatch(s) && !_inWord.hasMatch(s);
  final moved = _inWord.hasMatch(s) || _outWord.hasMatch(s);
  final money = _money.hasMatch(s);
  if (!moved && !money) return null;
  final span = _yesterday.hasMatch(s)
      ? AskodoxOfflineSpan.yesterday
      : _week.hasMatch(s)
          ? AskodoxOfflineSpan.week
          : _month.hasMatch(s)
              ? AskodoxOfflineSpan.month
              : _today.hasMatch(s)
                  ? AskodoxOfflineSpan.today
                  : null;
  if (_lastWord.hasMatch(s) && span != AskodoxOfflineSpan.week && span != AskodoxOfflineSpan.month) {
    return AskodoxOfflineAsk(span: AskodoxOfflineSpan.today, out: out, last: true);
  }
  if (_whoWord.hasMatch(s) && moved) {
    return AskodoxOfflineAsk(span: span ?? AskodoxOfflineSpan.today, out: out, who: true);
  }
  // "How much came today?" needs a time AND a how-much; a bare "payment" is not a question the phone can answer.
  if (span == null || !(_howMuch.hasMatch(s) || moved)) return null;
  return AskodoxOfflineAsk(span: span, out: out);
}

// ------------------------------------------------------------------ the answer

String _two(int n) => n.toString().padLeft(2, '0');

/// ₹ with Indian grouping: 425000 paise -> "₹4,250", 12345678 paise -> "₹1,23,456.78".
String askodoxRupeesIn(int paise) {
  final r = (paise ~/ 100).toString();
  final p = paise % 100;
  String grouped;
  if (r.length <= 3) {
    grouped = r;
  } else {
    final tail = r.substring(r.length - 3);
    var head = r.substring(0, r.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$tail';
  }
  return p == 0 ? '₹$grouped' : '₹$grouped.${_two(p)}';
}

({DateTime from, DateTime to}) _range(AskodoxOfflineSpan span, DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return switch (span) {
    AskodoxOfflineSpan.today => (from: day, to: day.add(const Duration(days: 1))),
    AskodoxOfflineSpan.yesterday => (from: day.subtract(const Duration(days: 1)), to: day),
    // the week starts on Monday
    AskodoxOfflineSpan.week => (from: day.subtract(Duration(days: now.weekday - 1)), to: day.add(const Duration(days: 1))),
    AskodoxOfflineSpan.month => (from: DateTime(now.year, now.month), to: day.add(const Duration(days: 1))),
  };
}

String _spanWord(AskodoxOfflineSpan span, String lang) => switch (lang) {
      'te' => const {
          AskodoxOfflineSpan.today: 'ఈరోజు',
          AskodoxOfflineSpan.yesterday: 'నిన్న',
          AskodoxOfflineSpan.week: 'ఈ వారం',
          AskodoxOfflineSpan.month: 'ఈ నెల',
        }[span]!,
      'hi' => const {
          AskodoxOfflineSpan.today: 'आज',
          AskodoxOfflineSpan.yesterday: 'कल',
          AskodoxOfflineSpan.week: 'इस हफ्ते',
          AskodoxOfflineSpan.month: 'इस महीने',
        }[span]!,
      _ => const {
          AskodoxOfflineSpan.today: 'Today',
          AskodoxOfflineSpan.yesterday: 'Yesterday',
          AskodoxOfflineSpan.week: 'This week',
          AskodoxOfflineSpan.month: 'This month',
        }[span]!,
    };

String _clock(DateTime d, DateTime now, String lang) {
  final t = '${_two(d.hour)}:${_two(d.minute)}';
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? t : '${_two(d.day)}-${_two(d.month)} $t';
}

String _l(String lang, String te, String hi, String en) => lang == 'te' ? te : (lang == 'hi' ? hi : en);

/// Where the answer comes from -- said every time, so nobody takes it for the bank's own balance.
String askodoxOfflineSourceNote(String lang) => _l(
      lang,
      'ఇది ఈ phone చూసిన payment messages లెక్క మాత్రమే (bank balance కాదు).',
      'यह सिर्फ़ इस phone ने देखे payment messages का हिसाब है (bank balance नहीं).',
      'This is only what this phone\'s payment messages showed (not the bank balance).',
    );

/// The answer to [ask] from the phone's own payment [events]. Never a guess: no rows -> it says there are none.
String askodoxOfflineAnswer(AskodoxOfflineAsk ask, Iterable<Map<String, Object?>> events, DateTime now, String lang) {
  final dir = ask.out ? 'out' : 'in';
  final all = askodoxItemsFromPhone(events, const [], const {}, const {}).where((i) => i.direction == dir).toList()
    ..sort((a, b) => b.at.compareTo(a.at));
  final note = askodoxOfflineSourceNote(lang);

  if (ask.last) {
    if (all.isEmpty) {
      return '${_l(lang, 'ఈ phone లో ఇంకా ఏ payment record లేదు.', 'इस phone में अभी कोई payment record नहीं है.', 'This phone has no payment record yet.')} $note';
    }
    final i = all.first;
    final how = askodoxHowLabel(i.how).$1;
    final sure = i.confirmed.isNotEmpty
        ? ''
        : _l(lang, ' Bank SMS ఇంకా నిర్ధారించలేదు.', ' Bank SMS ने अभी पक्का नहीं किया.', ' Not confirmed by a bank SMS yet.');
    final head = ask.out
        ? _l(lang, 'ఆఖరిగా వెళ్ళింది', 'आख़िरी बार गया', 'Last money out')
        : _l(lang, 'ఆఖరి payment', 'आख़िरी payment', 'Last payment');
    return '$head: ${askodoxRupeesIn(i.amountPaise)} · ${i.title} · ${_clock(i.at, now, lang)} · $how.$sure $note';
  }

  final r = _range(ask.span, now);
  final rows = all.where((i) => !i.at.isBefore(r.from) && i.at.isBefore(r.to)).toList();
  final span = _spanWord(ask.span, lang);
  if (rows.isEmpty) {
    final none = ask.out
        ? _l(lang, '$span వెళ్ళిన payment record ఈ phone లో లేదు.', '$span गए payment का record इस phone में नहीं है.',
            '$span: no money-out record on this phone.')
        : _l(lang, '$span వచ్చిన payment record ఈ phone లో లేదు.', '$span आए payment का record इस phone में नहीं है.',
            '$span: no payment-received record on this phone.');
    return '$none $note';
  }
  final total = rows.fold<int>(0, (s, i) => s + i.amountPaise);
  final n = rows.length;
  final unsure = rows.where((i) => i.confirmed.isEmpty).length;

  if (ask.who) {
    final by = <String, int>{};
    for (final i in rows) {
      by[i.title] = (by[i.title] ?? 0) + i.amountPaise;
    }
    final top = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final list = top.take(5).map((e) => '${e.key} ${askodoxRupeesIn(e.value)}').join(', ');
    final more = top.length > 5 ? _l(lang, ', ఇంకా ${top.length - 5} మంది', ', और ${top.length - 5} लोग', ', and ${top.length - 5} more') : '';
    final head = ask.out
        ? _l(lang, '$span ఎవరికి వెళ్ళింది', '$span किसे गया', '$span, paid to')
        : _l(lang, '$span ఎవరు కట్టారు', '$span किसने दिया', '$span, paid by');
    return '$head: $list$more. ${_l(lang, 'మొత్తం', 'कुल', 'Total')} ${askodoxRupeesIn(total)}. $note';
  }

  final top = rows.reduce((a, b) => b.amountPaise > a.amountPaise ? b : a);
  final head = ask.out
      ? _l(lang, '$span వెళ్ళింది', '$span गया', '$span, money out')
      : _l(lang, '$span వచ్చింది', '$span आया', '$span, received');
  final count = _l(lang, '$n payments', '$n payments', n == 1 ? '1 payment' : '$n payments');
  final big = n > 1
      ? ' ${_l(lang, 'ఎక్కువ', 'सबसे बड़ा', 'Biggest')}: ${top.title} ${askodoxRupeesIn(top.amountPaise)}, ${_clock(top.at, now, lang)}.'
      : '';
  final wait = unsure > 0
      ? ' ${_l(lang, 'వీటిలో $unsure bank SMS ఇంకా నిర్ధారించలేదు.', 'इनमें $unsure को bank SMS ने अभी पक्का नहीं किया.', '$unsure of them not confirmed by a bank SMS yet.')}'
      : '';
  return '$head: ${askodoxRupeesIn(total)} ($count).$big$wait $note';
}

/// The ready questions shown while there is no net (tap = asked).
List<String> askodoxOfflineReadyQuestions(String lang) => switch (lang) {
      'te' => const ['ఈరోజు ఎంత వచ్చింది?', 'నిన్న ఎంత వచ్చింది?', 'ఈరోజు ఎవరు ఎంత కట్టారు?', 'ఈ వారం ఎంత వచ్చింది?', 'ఆఖరి payment'],
      'hi' => const ['आज कितना आया?', 'कल कितना आया?', 'आज किसने कितना दिया?', 'इस हफ्ते कितना आया?', 'आख़िरी payment'],
      _ => const ['How much came today?', 'How much came yesterday?', 'Who paid today?', 'How much came this week?', 'Last payment'],
    };

/// What the chat says when a question has to wait for the net.
String askodoxOfflineKeptText(String lang, int waiting) => _l(
      lang,
      'ఈ ప్రశ్నకు internet కావాలి. మర్చిపోకుండా దాచాను — net రాగానే నేనే అడిగి జవాబు చెప్తాను ✓'
          '${waiting > 1 ? ' ($waiting ప్రశ్నలు ఆగి ఉన్నాయి)' : ''}',
      'इस सवाल के लिए internet चाहिए. मैंने इसे रख लिया है — net आते ही जवाब दूँगा ✓'
          '${waiting > 1 ? ' ($waiting सवाल रुके हैं)' : ''}',
      'This question needs the internet. I have kept it — the answer comes by itself when the net is back ✓'
          '${waiting > 1 ? ' ($waiting questions waiting)' : ''}',
    );

// ------------------------------------------------------------------ questions that wait for the net

class AskodoxHeldQuestion {
  const AskodoxHeldQuestion(this.text, this.atMs);
  final String text;
  final int atMs;
}

/// At most this many wait (the oldest goes first when one more is added).
const askodoxHeldMax = 10;

/// A kept question older than this is dropped, not asked (yesterday's "will it rain today?" is no use).
const askodoxHeldKeepMs = 24 * 60 * 60 * 1000;

/// [list] with [text] added: the same words twice wait once; the oldest drops past [askodoxHeldMax]. Pure.
List<AskodoxHeldQuestion> askodoxHeldAdd(List<AskodoxHeldQuestion> list, String text, int nowMs) {
  final t = text.trim();
  if (t.isEmpty) return list;
  final out = list.where((q) => q.text.trim().toLowerCase() != t.toLowerCase()).toList()..add(AskodoxHeldQuestion(t, nowMs));
  return out.length > askodoxHeldMax ? out.sublist(out.length - askodoxHeldMax) : out;
}

/// The questions still worth asking at [nowMs], oldest first. Pure.
List<AskodoxHeldQuestion> askodoxHeldFresh(List<AskodoxHeldQuestion> list, int nowMs) =>
    list.where((q) => nowMs - q.atMs <= askodoxHeldKeepMs && nowMs >= q.atMs - 60000).toList();

String askodoxHeldEncode(List<AskodoxHeldQuestion> list) =>
    jsonEncode([for (final q in list) {'t': q.text, 'at': q.atMs}]);

List<AskodoxHeldQuestion> askodoxHeldDecode(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return [
      for (final e in data)
        if (e is Map && e['t'] is String && e['at'] is num) AskodoxHeldQuestion(e['t'] as String, (e['at'] as num).toInt()),
    ];
  } catch (_) {
    return const [];
  }
}

/// On-phone store of the questions that wait for the net (belongs to the signed-in account: `askodoxAccountScopedKeys`).
class AskodoxHeldQuestions {
  AskodoxHeldQuestions._();
  static final AskodoxHeldQuestions instance = AskodoxHeldQuestions._();
  static const prefsKey = 'askodox.offline_questions.v1';

  /// How many wait now (the chip above the chat follows this).
  final ValueNotifier<int> count = ValueNotifier(0);

  Future<List<AskodoxHeldQuestion>> load({int? nowMs}) async {
    final prefs = await SharedPreferences.getInstance();
    final all = askodoxHeldDecode(prefs.getString(prefsKey));
    final fresh = askodoxHeldFresh(all, nowMs ?? DateTime.now().millisecondsSinceEpoch);
    if (fresh.length != all.length) await _save(prefs, fresh);
    count.value = fresh.length;
    return fresh;
  }

  Future<int> add(String text, {int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    final next = askodoxHeldAdd(askodoxHeldFresh(askodoxHeldDecode(prefs.getString(prefsKey)), now), text, now);
    await _save(prefs, next);
    count.value = next.length;
    return next.length;
  }

  /// Takes [q] off the list (it was asked).
  Future<void> remove(AskodoxHeldQuestion q) async {
    final prefs = await SharedPreferences.getInstance();
    final next = askodoxHeldDecode(prefs.getString(prefsKey)).where((x) => !(x.text == q.text && x.atMs == q.atMs)).toList();
    await _save(prefs, next);
    count.value = next.length;
  }

  Future<void> _save(SharedPreferences prefs, List<AskodoxHeldQuestion> list) async {
    if (list.isEmpty) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setString(prefsKey, askodoxHeldEncode(list));
    }
  }
}
