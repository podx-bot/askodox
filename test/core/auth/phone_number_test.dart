import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/phone_number.dart';

void main() {
  test('Indian numbers in every common spelling become +91 E.164', () {
    for (final typed in ['9876543210', '98765 43210', '+91 98765 43210', '+919876543210', '09876543210',
        '919876543210', '0091 98765 43210', '+91-98765-43210']) {
      expect(askodoxE164(typed), '+919876543210', reason: typed);
    }
  });

  test('international numbers keep their own country code', () {
    expect(askodoxE164('+1 415 555 0123'), '+14155550123');
    expect(askodoxE164('+44 7911 123456'), '+447911123456');
    expect(askodoxE164('+971 50 123 4567'), '+971501234567');
  });

  test('impossible numbers are refused', () {
    for (final typed in ['', '+91', '12345', '+91 12345 67890', '+91 98765 4321', '5876543210', '+0123456789',
        '+1234567890123456', 'abcdefghij']) {
      expect(askodoxE164(typed), isNull, reason: typed);
    }
  });

  test('display and mask never show more than intended', () {
    expect(askodoxDisplayPhone('+919876543210'), '+91 98765 43210');
    expect(askodoxDisplayPhone('+14155550123'), '+14155550123');
    expect(askodoxMaskedPhone('+919876543210'), '••••3210');
  });
}
