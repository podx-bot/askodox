import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_payment_alerts.dart';

void main() {
  test('a row the bank SMS also reported is shown as bank confirmed (owner 2026-11-17)', () {
    expect(askodoxBankConfirmedLabel({'bank_confirmed': true, 'amount_paise': 24000})!.$2, contains('నిర్ధారించింది'));
    expect(askodoxBankConfirmedLabel({'amount_paise': 24000})!.$1, contains('not seen yet'));
    expect(askodoxBankConfirmedLabel({'direction': 'out', 'bank_confirmed': true}), isNull);
    expect(askodoxBankConfirmedLabel(null), isNull);
  });
}
