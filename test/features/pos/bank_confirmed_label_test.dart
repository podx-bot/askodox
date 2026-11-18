import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_payment_alerts.dart';

void main() {
  test('a row the bank SMS also reported says received, never confirmed (owner 2026-11-18)', () {
    final b = askodoxBankConfirmedLabel({'bank_confirmed': true, 'amount_paise': 24000})!;
    expect(b.$2, contains('అందింది'));
    expect('${b.$1} ${b.$2}', isNot(matches(RegExp('onfirm|నిర్ధార'))));
    expect(askodoxBankConfirmedLabel({'amount_paise': 24000})!.$1, contains('not seen yet'));
    expect(askodoxBankConfirmedLabel({'direction': 'out', 'bank_confirmed': true}), isNull);
    expect(askodoxBankConfirmedLabel(null), isNull);
  });
}
