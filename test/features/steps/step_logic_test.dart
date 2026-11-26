import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/steps/domain/step_logic.dart';

void main() {
  test('the number pad types whole rupees: no leading zero, 00, delete, a length cap', () {
    var v = '';
    for (final k in ['0', '2', '3', '5', '0']) {
      v = askodoxKeypadPress(v, k);
    }
    expect(v, '2350');
    expect(askodoxKeypadPress(v, 'del'), '235');
    expect(askodoxKeypadPress('5', '00'), '500');
    expect(askodoxKeypadPress('', 'del'), '');
    expect(askodoxKeypadPress('1234567', '8'), '1234567');
    expect(askodoxKeypadPaise('2350'), 235000);
    expect(askodoxKeypadPaise(''), 0);
  });

  test('a tap on an item tile: kg / litre go 1, 1½, 2; pieces and plates go one by one; grams 250 at a time', () {
    expect(askodoxBillTapQty(0, 'kg'), 1000);
    expect(askodoxBillTapQty(1000, 'kg'), 1500);
    expect(askodoxBillTapQty(1500, 'l'), 2000);
    expect(askodoxBillTapQty(0, 'pcs'), 1000);
    expect(askodoxBillTapQty(11000, 'plate'), 12000);
    expect(askodoxBillTapQty(0, 'g'), 250000);
    expect(askodoxLinePaise(24000, 1500), 36000);
    expect(askodoxLinePaise(600, 12000), 7200);
  });

  test('tile badges show halves and quarters the way a shop says them', () {
    expect(askodoxQtyShort(1000), '1');
    expect(askodoxQtyShort(1500), '1½');
    expect(askodoxQtyShort(250), '¼');
    expect(askodoxQtyShort(2750), '2¾');
    expect(askodoxQtyShort(12000), '12');
    expect(askodoxQtyShort(1200), '1.2');
    expect(askodoxQtyShort(0), '');
    expect(askodoxParseQtyMilli('1½'), 1500);
    expect(askodoxParseQtyMilli('.75'), 750);
    expect(askodoxParseQtyMilli('2'), 2000);
    expect(askodoxParseQtyMilli(''), isNull);
    expect(askodoxParseQtyMilli('abc'), isNull);
  });

  test('one payment against dues goes to the oldest bill first, never more than a bill owes', () {
    final bills = [('b1', 30000), ('b2', 0), ('b3', 50000), ('b4', 20000)];
    expect(askodoxSplitDuePayment(bills, 60000), [('b1', 30000), ('b3', 30000)]);
    expect(askodoxSplitDuePayment(bills, 100000), [('b1', 30000), ('b3', 50000), ('b4', 20000)]);
    expect(askodoxSplitDuePayment(bills, 10000), [('b1', 10000)]);
    expect(askodoxSplitDuePayment(bills, 0), isEmpty);
  });

  test('the way of paying said with the items (any phone language mix)', () {
    expect(askodoxSpokenPayMethod('12 నంబర్ 2, UPI'), 'online');
    expect(askodoxSpokenPayMethod('chicken 2 kg phonepe'), 'online');
    expect(askodoxSpokenPayMethod('గుడ్లు 12 క్యాష్'), 'cash');
    expect(askodoxSpokenPayMethod('రమేష్ బాకీ'), 'due');
    expect(askodoxSpokenPayMethod('3 నంబర్ 1'), isNull);
  });

  test('spoken amounts, step rupees and 10-digit numbers (made-up numbers only)', () {
    expect(askodoxSpokenRupees('2,350 ఇచ్చారు'), 235000);
    expect(askodoxSpokenRupees('ఏమీ లేదు'), isNull);
    expect(askodoxStepRupees(1845000), '₹18,450');
    expect(askodoxStepRupees(43250), '₹432.50');
    expect(askodoxTenDigits('+91 98765 43210'), '9876543210');
    expect(askodoxTenDigits('09876543210'), '9876543210');
    expect(askodoxTenDigits('12345'), '');
    expect(askodoxTenDigits('1234567890'), '', reason: 'an Indian mobile starts with 6-9');
  });

  test('calculator bill rows: qty x rate in paise (made-up numbers only)', () {
    expect(askodoxCalcRowPaise('2', '12.50'), 2500);
    expect(askodoxCalcRowPaise('1.5', '200'), 30000);
    expect(askodoxCalcRowPaise('1½', '1,200'), 180000);
    expect(askodoxCalcRowPaise('', '10'), 0);
    expect(askodoxCalcRowPaise('3', ''), 0);
    expect(askodoxCalcRowPaise('0', '10'), 0);
    expect(askodoxCalcRowPaise('abc', '10'), 0);
    expect(askodoxCalcRatePaise('7.25'), 725);
  });
}
