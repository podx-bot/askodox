import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_payment_alerts.dart';

// Owner 2026-11-25: the bank's alert e-mail is a third way to hear a payment (with the app notification and the SMS).
void main() {
  test('mail apps are kind email', () {
    expect(askodoxMoneyAppKind('com.google.android.gm'), 'email');
    expect(askodoxMoneyAppKind('com.microsoft.office.outlook'), 'email');
    expect(askodoxMoneyAppKind('com.example.somemail', 'Some Mail'), 'email');
    expect(askodoxMoneyAppKind('com.google.android.apps.messaging'), 'sms');
    expect(askodoxMoneyAppKind('com.phonepe.app'), 'upi');
  });

  test('mail apps are suggested on the phone', () {
    expect(askodoxLooksLikeMoneyApp('com.google.android.gm', 'Gmail'), isTrue);
  });

  test('the Gmail hint says how to get the notification, in both languages', () {
    expect(askodoxBankMailHint('com.google.android.gm', false), contains('Notifications'));
    expect(askodoxBankMailHint('com.google.android.gm', true), contains('Gmail'));
    expect(askodoxBankMailHint('com.zoho.mail', false), contains('bank'));
  });
}
