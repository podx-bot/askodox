import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/auth/presentation/onboarding_screen.dart';

void main() {
  test('the app takes its identity from the server account id (one account per number)', () {
    expect(askodoxAccountDigits('app-phone-919876543210'), '919876543210');
    expect(askodoxAccountDigits('app-phone-9876543210'), '9876543210');
    expect(askodoxAccountDigits(null), isNull, reason: 'older backend: fall back to the typed number');
    expect(askodoxAccountDigits('app-guest-1'), isNull);
  });
}
