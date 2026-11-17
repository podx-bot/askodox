import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/domain/money_accounts.dart';

void main() {
  const hdfc = AskodoxMoneyPlace(key: 'bank:6911', type: 'bank', name: 'HDFC current', tail: '6911');
  const phonepeWallet = AskodoxMoneyPlace(key: 'place:w1', type: 'wallet', name: 'PhonePe wallet', apps: ['com.phonepe.app']);

  test('a row belongs to: hand move > bank digits > linked app > unknown (owner 2026-11-17)', () {
    final places = [hdfc, phonepeWallet];
    expect(askodoxAccountOf({'local_id': 'a', 'account': '6911'}, places, {}), 'bank:6911');
    expect(askodoxAccountOf({'local_id': 'b', 'account': '586'}, places, {}), 'bank:586', reason: 'unnamed digits = own bucket');
    expect(askodoxAccountOf({'local_id': 'c', 'source_app': 'com.phonepe.app'}, places, {}), 'place:w1');
    expect(
        askodoxAccountOf({'local_id': 'd', 'source_app': 'x.sms', 'also_from': 'PhonePe'}, places, {},
            labelToPackage: {'PhonePe': 'com.phonepe.app'}),
        'place:w1',
        reason: 'an app merged into the row counts too');
    expect(askodoxAccountOf({'local_id': 'e', 'source_app': 'net.one97.paytm'}, places, {}), askodoxUnknownAccount);
    expect(askodoxAccountOf({'local_id': 'a', 'account': '6911'}, places, {'a': 'place:w1'}), 'place:w1');
  });

  test('unnamed bank digits are offered for a name, newest first, once each', () {
    final events = [
      {'account': '586'},
      {'account': '6911'},
      {'account': '7571'},
      {'account': '586'},
    ];
    expect(askodoxUnnamedTails(events, [hdfc]), ['586', '7571']);
  });

  test('totals for today: in and out, tests never counted', () {
    final now = DateTime(2026, 11, 17, 14);
    final ms = now.millisecondsSinceEpoch;
    final t = askodoxMoneyTotals([
      {'amount_paise': 24000, 'at_ms': ms},
      {'amount_paise': 500, 'direction': 'out', 'at_ms': ms},
      {'amount_paise': 100000, 'at_ms': DateTime(2026, 11, 16).millisecondsSinceEpoch},
      {'amount_paise': 99, 'at_ms': ms, 'test': true},
    ], DateTime(2026, 11, 17));
    expect((t.inPaise, t.outPaise, t.count), (24000, 500, 2));
  });

  test('ways to get paid become accounts once; a deleted one never returns', () {
    final methods = [
      {'id': 'pm1', 'kind': 'bank', 'label': 'Shop current', 'account_last4': '6911', 'bank_name': 'HDFC'},
      {'id': 'pm2', 'kind': 'bank', 'label': '', 'account_last4': '7571', 'bank_name': 'SBI'},
      {'id': 'pm3', 'kind': 'upi', 'label': '', 'upi_id': 'shop@ybl'},
      {'id': 'pm4', 'kind': 'upi', 'label': 'Old', 'upi_id': 'old@ibl'},
    ];
    final out = askodoxPlacesFromMethods(methods, [hdfc], {'pm4'});
    expect(out.map((p) => p.name), ['SBI ••7571', 'shop@ybl'], reason: '6911 is already there; pm4 was deleted');
  });

  test('UPI ID from a QR', () {
    expect(askodoxUpiFromQr('upi://pay?pa=lakshmi.meat@okhdfcbank&pn=Lakshmi&cu=INR'), 'lakshmi.meat@okhdfcbank');
    expect(askodoxUpiFromQr('shop@ybl'), 'shop@ybl');
    expect(askodoxUpiFromQr('https://example.com'), isNull);
  });

  test('a place survives a save / load round trip', () {
    final back = AskodoxMoneyPlace.fromJson(phonepeWallet.toJson())!;
    expect((back.key, back.type, back.name, back.apps), ('place:w1', 'wallet', 'PhonePe wallet', ['com.phonepe.app']));
    expect(AskodoxMoneyPlace.fromJson({'key': 'x', 'type': 'nope'}), isNull);
  });
}
