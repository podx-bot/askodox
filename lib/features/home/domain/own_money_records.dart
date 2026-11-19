/// "Was money cut from my bank?" / "did the payment come?" -- answered in the chat from the person's OWN payment
/// records on this phone (owner 2026-11-19), never from a guess and never from anyone else's data.
///
/// The phone keeps what its payment-app notifications and bank SMS showed (My phone payments). When the person asks a
/// money question, the app hands the assistant those records as grounded context (the same pattern as the Customer
/// Care help text); the assistant may only say what is in the records, or that there is no record on this phone.
library;

import '../../pos/domain/money_ledger.dart';

final _moneyWord = RegExp(
  r'money|amount|payment|paid|rupee|₹|rs\.?\s*\d|bank|account|transaction|upi|'
  r'డబ్బు|పేమెంట్|అమౌంట్|బ్యాంక్|బ్యాంకు|ఖాతా|రూపాయ|'
  r'पैसे|पैसा|भुगतान|बैंक|खाता',
  caseSensitive: false,
);
final _moveWord = RegExp(
  r'debit|credit|deduct|\bcut\b|cut off|received|\bcame\b|\bcome\b|\bgot\b|sent|spent|'
  r'కట్|డెబిట్|క్రెడిట్|పడ్డ|పడింది|వచ్చ|అంద|జమ|కొట్టే|తీసు|వెళ్ళ|వెళ్లా|పోయ|'
  r'कट|जमा|आए|आया|गए|गया|निकल',
  caseSensitive: false,
);
// A "how to" / shop / price question is not a question about the person's own money moving.
final _notOwnMoney = RegExp(r'how (do|can|to)|ఎలా|कैसे|price|ధర|कीमत|offer|ఆఫర్|loan|లోన్|order|ఆర్డర్|refund|రిఫండ్|not confirmed|failed', caseSensitive: false);

/// True when the person asks whether money moved (cut, came, debited, credited ...).
bool askodoxAsksOwnMoney(String text) {
  final s = text.trim();
  if (s.length < 6) return false;
  if (_notOwnMoney.hasMatch(s)) return false;
  return _moneyWord.hasMatch(s) && _moveWord.hasMatch(s);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _when(DateTime d) => '${_two(d.day)}-${_two(d.month)} ${_two(d.hour)}:${_two(d.minute)}';

String _rupees(int paise) {
  final r = paise ~/ 100;
  final p = paise % 100;
  return p == 0 ? '₹$r' : '₹$r.${_two(p)}';
}

/// The facts + rules for ONE money turn. [events] are the phone's own records (My phone payments).
String askodoxMoneyFactsGuidance(Iterable<Map<String, Object?>> events, {int limit = 15}) {
  final items = askodoxItemsFromPhone(events, const [], const {}, const {})
    ..sort((a, b) => b.at.compareTo(a.at));
  final recent = items.take(limit).toList();
  final lines = StringBuffer();
  for (final i in recent) {
    final how = askodoxHowLabel(i.how).$1;
    lines.writeln('- ${_when(i.at)} · ${i.direction == 'out' ? 'MONEY OUT (debit)' : 'MONEY IN (credit)'} '
        '${_rupees(i.amountPaise)} · ${i.title} · via $how · '
        '${i.confirmed.isNotEmpty ? 'confirmed by a registered bank SMS' : 'seen only in an app notification / SMS, not bank-confirmed'}');
  }
  return 'The person asks whether money was cut from their bank or came in. ASKODOX cannot see any bank account. '
      'The ONLY facts available are this phone\'s own payment records below (what this phone\'s payment-app '
      'notifications and bank SMS showed, newest first). Answer ONLY from them, in the language of the conversation, '
      'in two or three short sentences: say the matching record (amount, in or out, time, app or bank) if there is '
      'one; if there is no matching record say plainly "ASKODOX has no record of that on this phone" and that the '
      'phone may not have shown the notification (payment alerts may be off) so they should check the bank SMS or the '
      'bank app. A record that is not bank-confirmed is only what a notification said. Never guess, never invent a '
      'record, never say money was or was not cut from the bank account itself. If they say money left that they do '
      'not recognise, tell them to call their bank at once and the cyber helpline 1930.\n'
      '${recent.isEmpty ? 'Payment records on this phone: none.' : 'Payment records on this phone:\n$lines'}';
}
