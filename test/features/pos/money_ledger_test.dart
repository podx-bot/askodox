import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/domain/money_ledger.dart';

AskodoxMoneyItem pay(String id, int paise, DateTime at, {String dir = 'out', String title = 'Raju Chicken Center', Map<String, Object?> raw = const {}}) =>
    AskodoxMoneyItem(id: id, kind: 'payment', direction: dir, amountPaise: paise, at: at, title: title, raw: raw);
AskodoxMoneyItem bill(String id, int paise, DateTime at, {bool pending = true, String dir = 'out'}) =>
    AskodoxMoneyItem(id: id, kind: 'bill', direction: dir, amountPaise: paise, at: at, title: 'Raju Chicken Center', sub: '#R-214', pending: pending);

void main() {
  final t0 = DateTime(2026, 11, 17, 13, 2);

  test('a payment is offered for the bill of the same amount -- once, closest first, never a "no" again', () {
    final p1 = pay('phone:a', 35000, t0.add(const Duration(minutes: 3)));
    final p2 = pay('phone:b', 35000, t0.add(const Duration(days: 2)));
    final b = bill('mybill:t1', 35000, t0);
    final s = askodoxPairSuggestions([p1, p2], [b]);
    expect(s.map((x) => x.payment.id), ['phone:a']);
    expect(askodoxPairSuggestions([p1, p2], [b], dismissed: {'phone:a|mybill:t1'}).map((x) => x.payment.id), ['phone:b']);
    expect(askodoxPairSuggestions([pay('phone:c', 34999, t0)], [b]), isEmpty, reason: 'a different amount is never offered');
    expect(askodoxPairSuggestions([pay('phone:d', 35000, t0, dir: 'in')], [b]), isEmpty, reason: 'money in never pays my bill');
    expect(askodoxPairSuggestions([p1], [bill('mybill:t2', 35000, t0, pending: false)]), isEmpty, reason: 'a paid bill is done');
    expect(askodoxPairSuggestions([pay('phone:e', 35000, t0.add(const Duration(days: 5)))], [b]), isEmpty, reason: 'too late');
  });

  test('categories: my row choice > my payee choice > EMI > words in the name > none', () {
    final p = pay('phone:a', 100, t0);
    expect(askodoxCategoryOf(p), 'meat');
    expect(askodoxCategoryOf(pay('phone:x', 100, t0, title: 'APSPDCL Vijayawada')), 'power');
    expect(askodoxCategoryOf(pay('phone:y', 100, t0, title: 'VAKADOTHU PRASAD')), '');
    // Owner 2026-11-20: a person paid through a bank SMS read by "Messages" is NOT "Food & hotel" ("mess").
    expect(askodoxCategoryOf(AskodoxMoneyItem(id: 'phone:m', kind: 'payment', direction: 'out', amountPaise: 700000, at: t0,
        title: 'BHAGYA SRI KOVELAKAR', sub: 'Messages (Google)')), '');
    expect(askodoxCategoryOf(pay('phone:w', 100, t0, title: 'Parent Teacher Fund')), '', reason: 'rent only as a whole word');
    expect(askodoxCategoryOf(pay('phone:v', 100, t0, title: 'Sri Lakshmi Mess')), 'food');
    expect(askodoxCategoryOf(pay('phone:u', 100, t0, title: 'రాజు చికెన్ సెంటర్')), 'meat');
    expect(askodoxCategoryOf(pay('phone:z', 100, t0, title: 'Bajaj', raw: {'emi': true})), 'emi');
    expect(askodoxCategoryOf(p, payeeCategory: {askodoxNormPayee('Raju Chicken Center'): 'food'}), 'food');
    expect(askodoxCategoryOf(p, rowCategory: {'phone:a': 'other'}, payeeCategory: {askodoxNormPayee('Raju Chicken Center'): 'food'}), 'other');
  });

  test('totals: a bill joined to a payment counts once; an unpaid bill is not money that moved', () {
    final from = DateTime(2026, 11, 1), to = DateTime(2026, 12, 1);
    final items = [
      pay('phone:a', 35000, t0),
      AskodoxMoneyItem(id: 'mybill:t1', kind: 'bill', direction: 'out', amountPaise: 35000, at: t0, title: 'x', linkedTo: 'phone:a'),
      bill('mybill:t2', 42000, t0),
      pay('phone:in', 130000, t0, dir: 'in', title: 'Salary'),
    ];
    final t = askodoxTotals(items, from, to);
    expect((t.inPaise, t.outPaise), (130000, 35000));
    expect(t.byCategory['meat'], 35000);
  });

  test('dues: next date, monthly / days repeat, paid dates skip, overdue stays', () {
    final emi = AskodoxDue(id: 'e', name: 'Bike EMI', amountPaise: 194100, date: DateTime(2026, 10, 21));
    expect(askodoxDay(askodoxNextDue(emi, DateTime(2026, 11, 17))!), '2026-10-21', reason: 'October not marked paid = overdue');
    final paid = emi.copyWith(paidDates: ['2026-10-21']);
    expect(askodoxDay(askodoxNextDue(paid, DateTime(2026, 11, 17))!), '2026-11-21');
    final recharge = AskodoxDue(id: 'r', name: 'Jio', amountPaise: 79900, date: DateTime(2026, 11, 1), repeat: 'days:84');
    expect(askodoxDueDates(recharge).take(2).map(askodoxDay), ['2026-11-01', '2027-01-24']);
    final jan31 = AskodoxDue(id: 'j', name: 'Rent', amountPaise: 1, date: DateTime(2026, 1, 31));
    expect(askodoxDueDates(jan31).take(3).map(askodoxDay), ['2026-01-31', '2026-02-28', '2026-03-31']);
    final once = AskodoxDue(id: 'o', name: 'Fee', amountPaise: 1, date: DateTime(2026, 11, 20), repeat: 'once', paidDates: ['2026-11-20']);
    expect(askodoxNextDue(once, DateTime(2026, 11, 17)), isNull);
    expect(AskodoxDue.fromJson(paid.toJson())!.paidDates, ['2026-10-21']);
  });

  test('a due reminder the phone saw is offered once; one already in the list is not', () {
    final events = [
      {'local_id': 'due-1', 'direction': 'due', 'amount_paise': 194100, 'due_date': '2026-11-21', 'party': 'Andhra Pradesh Southern'},
      {'local_id': 'due-2', 'direction': 'due', 'amount_paise': 194100, 'due_date': '2026-11-21', 'party': 'Andhra Pradesh Southern'},
      {'local_id': 'due-3', 'direction': 'due', 'amount_paise': 82100, 'due_date': '2026-11-21', 'party': 'Andhra Pradesh Southern'},
      {'local_id': 'p', 'direction': 'in', 'amount_paise': 100},
    ];
    final today = DateTime(2026, 11, 17);
    expect(askodoxDueSuggestions(events, [], {}, today).map((e) => e['local_id']), ['due-1', 'due-3']);
    final have = [AskodoxDue(id: 'x', name: 'Current', amountPaise: 82100, date: DateTime(2026, 10, 21))];
    expect(askodoxDueSuggestions(events, have, {'due-1'}, today).map((e) => e['local_id']), isEmpty);
  });

  test('a bill reminder that is already paid is not offered as an upcoming due', () {
    final today = DateTime(2026, 11, 22);
    final reminder = {'local_id': 'due-1', 'direction': 'due', 'amount_paise': 96200, 'due_date': '2026-12-05', 'party': 'APCPDC', 'at_ms': 1000};
    final other = {'local_id': 'due-2', 'direction': 'due', 'amount_paise': 194100, 'due_date': '2026-12-05', 'party': 'APCPDC', 'at_ms': 1000};
    Map<String, Object?> out(int amount, int at, {bool excluded = false}) =>
        {'local_id': 'p$at', 'direction': 'out', 'amount_paise': amount, 'at_ms': at, 'kind': 'billpay', if (excluded) 'excluded': true};
    // paid after the reminder came -> gone; the other bill stays
    expect(askodoxDueSuggestions([reminder, other, out(96200, 2000)], [], {}, today).map((e) => e['local_id']), ['due-2']);
    // a payment of the same amount BEFORE the reminder is last month's bill; a row set aside is not money
    expect(askodoxDueSuggestions([reminder, out(96200, 500)], [], {}, today).map((e) => e['local_id']), ['due-1']);
    expect(askodoxDueSuggestions([reminder, out(96200, 2000, excluded: true)], [], {}, today).map((e) => e['local_id']), ['due-1']);
    // money that came IN of the same amount never pays a bill
    expect(askodoxDueSuggestions([reminder, {'local_id': 'i', 'direction': 'in', 'amount_paise': 96200, 'at_ms': 2000}], [], {}, today), hasLength(1));
  });

  test('a paid bill row: the "Bill Paid" SMS of the bank is the bank word, and an electricity board is Current', () {
    final rows = askodoxItemsFromPhone([
      {'local_id': 'b1', 'direction': 'out', 'amount_paise': 96200, 'at_ms': 1000, 'kind': 'billpay', 'party': 'APCPDC Ele Bill',
        'source_app': 'com.google.android.apps.messaging', 'source_label': 'Messages (Google)', 'bill': true},
    ], const [], const {}, const {});
    expect(rows.single.direction, 'out');
    expect(rows.single.confirmed, 'bank_sms');
    expect(rows.single.title, 'APCPDC Ele Bill');
    expect(askodoxCategoryOf(rows.single), 'power');
    AskodoxMoneyItem named(String title) => AskodoxMoneyItem(
        id: title, kind: 'payment', direction: 'out', amountPaise: 1, at: DateTime(2026, 11, 22), title: title, sub: '', how: 'sms', account: '');
    for (final board in ['APCPDCL', 'TSNPDCL', 'MSEDCL', 'JVVNL', 'DHBVN', 'HESCOM', 'APEPDCL']) {
      expect(askodoxCategoryOf(named(board)), 'power', reason: board);
    }
    expect(askodoxCategoryOf(named('Ramesh Kumar')), '');
    expect(askodoxCategoryOf(named('HDFC current')), '');
  });

  test('a payment of a due amount near its date is offered as "did you pay it?"', () {
    final d = AskodoxDue(id: 'c', name: 'Current bill', amountPaise: 82100, date: DateTime(2026, 11, 21));
    expect(askodoxDuePaidBy(pay('phone:a', 82100, DateTime(2026, 11, 19)), [d])?.$1.id, 'c');
    expect(askodoxDuePaidBy(pay('phone:b', 82100, DateTime(2026, 11, 1)), [d]), isNull);
    expect(askodoxDuePaidBy(pay('phone:c', 82000, DateTime(2026, 11, 20)), [d]), isNull);
  });

  test('EMI debits not yet a due are offered once per amount', () {
    final items = [
      pay('phone:1', 194100, t0, title: 'BAJAJFIN', raw: {'emi': true}),
      pay('phone:2', 194100, t0, title: 'BAJAJFIN', raw: {'emi': true}),
      pay('phone:3', 5000, t0),
    ];
    expect(askodoxEmiSuggestions(items, [], {}).map((i) => i.id), ['phone:1']);
  });

  test('phone rows: due reminders and tests stay out; the bank SMS proof and the join come through', () {
    final rows = askodoxItemsFromPhone([
      {'local_id': 'a', 'direction': 'out', 'amount_paise': 35000, 'party': 'Raju', 'source_label': 'PhonePe', 'source_app': 'com.phonepe.app', 'bank_confirmed': true, 'account': '7571'},
      {'local_id': 'b', 'direction': 'due', 'amount_paise': 1},
      {'local_id': 'c', 'amount_paise': 1, 'test': true},
    ], const [], const {}, {'phone:a': 'mybill:t1'});
    expect(rows.length, 1);
    expect((rows.first.how, rows.first.confirmed, rows.first.account, rows.first.linkedTo), ('phonepe', 'bank_sms', 'bank:7571', 'mybill:t1'));
  });

  test('the app the money came through is shown, never "Messages" or "Bank SMS" when an app saw it too', () {
    expect(askodoxHowOf('com.google.android.apps.messaging', 'Messages (Google) HDFC Bank App', kind: 'sms'), 'bank');
    expect(askodoxHowOf('com.google.android.apps.messaging', 'Messages (Google) PhonePe', kind: 'sms'), 'phonepe');
    expect(askodoxHowOf('com.google.android.apps.messaging', 'Messages (Google)', kind: 'sms'), 'sms');
    final rows = askodoxItemsFromPhone([
      {'local_id': 'a', 'amount_paise': 24000, 'direction': 'in', 'source_label': 'Messages (Google)', 'kind': 'sms',
       'account_tail': '6911', 'at_ms': 1}
    ], const [], const {}, const {});
    expect(rows.single.title.toLowerCase().contains('messag'), isFalse);
    expect(askodoxNoNameTitle('Messages (Google)', 'HDFC Bank', '', const []), 'HDFC Bank');
    expect(askodoxNoNameTitle('Messages (Google)', '', 'bank:6911', const []), 'A/c ••6911');
  });

  test('a debit read from the bank SMS carries no ⏳ (it is the bank\'s own word)', () {
    final rows = askodoxItemsFromPhone([
      {'local_id': 'a', 'direction': 'out', 'kind': 'sms', 'amount_paise': 1200, 'party': 'AYSHA', 'at_ms': 1},
      {'local_id': 'b', 'direction': 'out', 'kind': 'notification', 'amount_paise': 1200, 'party': 'AYSHA', 'at_ms': 1},
      {'local_id': 'c', 'direction': 'in', 'kind': 'sms', 'amount_paise': 1200, 'party': 'AYSHA', 'at_ms': 1},
    ], const [], const {}, const {});
    expect(rows.map((r) => r.confirmed), ['bank_sms', '', '']);
  });

  test('a shop bill paid by UPI with no app named says UPI, never "Other" (owner 2026-11-23, Rs 580)', () {
    final rows = askodoxItemsFromShopBills([
      {'id': 'i7', 'status': 'issued', 'number': 'INV/2627/000007', 'total_paise': 58000, 'due_paise': 0,
       'modes': ['other_upi'], 'issued_at': '2026-11-22T18:36:00+05:30'},
      {'id': 'i8', 'status': 'issued', 'number': 'INV/2627/000008', 'total_paise': 54000, 'due_paise': 0,
       'modes': ['cash'], 'issued_at': '2026-11-23T16:32:00+05:30'},
      {'id': 'i9', 'status': 'issued', 'number': 'INV/2627/000009', 'total_paise': 10000, 'due_paise': 0,
       'modes': ['bank_transfer'], 'issued_at': '2026-11-23T17:00:00+05:30'},
    ]);
    expect(rows.map((r) => askodoxHowLabel(r.how).$1), ['UPI', 'Cash', 'Bank']);
    for (final mode in ['phonepe', 'gpay', 'paytm', 'bhim', 'other_upi', 'card', 'cheque', 'cash', 'bank_transfer']) {
      expect(askodoxHowLabel(askodoxBillModeHow(mode)).$1, isNot('Other'), reason: mode);
    }
  });
}
