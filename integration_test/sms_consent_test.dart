import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:podx/core/auth/sms_code_listener.dart';

/// Real Android SMS User Consent on an emulator (CI workflow sms-consent-e2e):
/// the script sends an OTP SMS with `adb emu sms send` and taps "Allow" in
/// Google Play services' own prompt. Only the 6-digit code reaches Dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SMS User Consent: real SMS -> Allow -> code', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('SMS consent test'))));
    final source = AndroidSmsUserConsent.instance;
    final events = <AskodoxSmsEvent>[];
    final sub = source.events.listen(events.add);
    addTearDown(sub.cancel);

    expect(await source.start(), isTrue);
    await _waitFor(() => events.any((e) => e.event == 'listening' || e.event == 'error'), const Duration(seconds: 30));
    expect(events.map((e) => e.event), contains('listening'), reason: '${events.map((e) => e.event)}');
    // ignore: avoid_print
    print('ASKODOX_SMS_CONSENT_LISTENING');

    await _waitFor(() => events.any((e) => e.event == 'code' || e.event == 'denied' || e.event == 'timeout'),
        const Duration(seconds: 240));
    // ignore: avoid_print
    print('ASKODOX_SMS_CONSENT_EVENTS ${events.map((e) => e.event).join(',')}');
    expect(events.map((e) => e.event), containsAllInOrder(['listening', 'prompt', 'code']));
    final code = events.firstWhere((e) => e.event == 'code').code;
    expect(code, '482915');
    expect(askodoxValidOtp(code), isTrue);
    await source.stop();
  });
}

Future<void> _waitFor(bool Function() done, Duration limit) async {
  final end = DateTime.now().add(limit);
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
