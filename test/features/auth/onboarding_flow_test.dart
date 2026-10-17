import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/auth_log.dart';
import 'package:podx/core/auth/phone_auth.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/auth/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_fakes.dart';

const _newUser = {
  'status': 'verified',
  'app_user_id': 'app-phone-919876543210',
  'token': 'tok-new',
  'returning': false,
  'profile': <String, Object?>{},
};

FakeAuthApi _api({bool firebase = false}) {
  final api = FakeAuthApi()
    ..on('GET /onboarding/methods',
        (_) => ApiSuccess<Object?>({'firebase_phone_auth': firebase, 'server_otp': true, 'resend_seconds': 45}))
    ..on('POST /onboarding/otp/send',
        (_) => const ApiSuccess<Object?>({'status': 'sent', 'channel': 'sms', 'resend_after_seconds': 45}))
    ..on('POST /onboarding/otp/verify', (body) {
      final otp = (body as Map)['otp'];
      if (otp == '000000') return httpError(400, 'Incorrect OTP.');
      if (otp == '111111') return httpError(400, 'OTP expired. Request a new OTP.');
      return const ApiSuccess<Object?>(_newUser);
    })
    ..on('POST /onboarding/firebase/verify', (_) => const ApiSuccess<Object?>(_newUser));
  return api;
}

Future<void> _pumpApp(WidgetTester tester, FakeAuthApi api, {FakePhoneAuth? phoneAuth}) async {
  SharedPreferences.setMockInitialValues({'askodox.locale': 'en'});
  final router = GoRouter(initialLocation: '/onboarding', routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
  ]);
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
      askodoxPhoneAuthProvider.overrideWithValue(phoneAuth ?? FakePhoneAuth(available: false)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _settle(tester);
}

/// Lets fake network answers arrive without running the resend countdown.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _sendCode(WidgetTester tester, String typed) async {
  await tester.enterText(find.byKey(const ValueKey('mobile-input')), typed);
  await tester.tap(find.byKey(const Key('askodoxSendOtp')));
  await _settle(tester);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const ValueKey('otp-input')), code);
  await _settle(tester);
}

String? _inlineError(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('askodoxSignInError'))).data;

TextButton _resend(WidgetTester tester) => tester.widget<TextButton>(find.byKey(const Key('askodoxResendOtp')));

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('new user: number -> code (wrong, then right) -> name -> roles -> home', (tester) async {
    final api = _api();
    await _pumpApp(tester, api);
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget, reason: 'language already chosen');
    expect(find.byIcon(Icons.mic_rounded), findsNothing, reason: 'no microphone on sign-in screens');
    expect(find.byIcon(Icons.mic), findsNothing);
    await _sendCode(tester, '98765 43210');
    expect(api.to('POST', '/onboarding/otp/send').single.$3, {'mobile': '+919876543210'});
    expect(find.text('Enter the code sent to +91 98765 43210'), findsOneWidget);
    expect(_resend(tester).onPressed, isNull, reason: 'resend waits for the cooldown');
    expect(find.text('Resend OTP in 0:45'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Resend OTP in 0:42'), findsOneWidget);
    expect(find.text('Code sent by SMS.'), findsOneWidget, reason: 'the code step says how it was sent');
    await _enterCode(tester, '000000');
    expect(_inlineError(tester), 'Incorrect OTP.');
    expect(find.byKey(const Key('askodoxSignInErrorSnack')), findsOneWidget, reason: 'visible above the keyboard');
    await _enterCode(tester, '123456');
    expect(find.byKey(const ValueKey('name-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('name-input')), 'Asha K');
    await tester.tap(find.byKey(const Key('askodoxNameNext')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('askodoxSignUpRole-seller')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxSignUpRole-seller')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('askodoxFinishSignUp')));
    await _settle(tester);
    expect(find.text('HOME'), findsOneWidget);
    final put = api.to('PUT', '/api/me/profile').single;
    expect(put.$3, {'name': 'Asha K', 'language': 'en', 'roles': ['buyer', 'seller']});
    expect(put.$4, 'tok-new');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('askodox.auth.token'), 'tok-new');
    expect(prefs.getString('askodox.profile.mobile'), '919876543210');
    await _dispose(tester);
  });

  testWidgets('returning user: profile restored, nothing asked or overwritten', (tester) async {
    final api = _api()
      ..on('POST /onboarding/otp/verify', (_) => ApiSuccess<Object?>(<String, Object?>{
            ..._newUser,
            'returning': true,
            'profile': const {'name': 'Ravi', 'language': 'en', 'roles': ['buyer', 'seller']},
          }));
    await _pumpApp(tester, api);
    await _sendCode(tester, '+91 98765 43210');
    await _enterCode(tester, '123456');
    expect(find.text('HOME'), findsOneWidget);
    expect(api.to('PUT', '/api/me/profile'), isEmpty, reason: 'a saved profile is never overwritten at sign-in');
    expect((await SharedPreferences.getInstance()).getString('askodox.profile.name'), 'Ravi');
    await _dispose(tester);
  });

  testWidgets('expired code: resend becomes available at once', (tester) async {
    await _pumpApp(tester, _api());
    await _sendCode(tester, '9876543210');
    await _enterCode(tester, '111111');
    expect(_inlineError(tester), 'OTP expired. Request a new OTP.');
    expect(_resend(tester).onPressed, isNotNull);
    await _dispose(tester);
  });

  testWidgets('rate limited: goes to the code with the remaining wait', (tester) async {
    final api = _api()
      ..on('POST /onboarding/otp/send', (_) => httpError(429, 'Please wait 30 seconds before requesting another OTP.',
          headers: {'retry-after': '30'}));
    await _pumpApp(tester, api);
    await _sendCode(tester, '9876543210');
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    expect(find.text('Resend OTP in 0:30'), findsOneWidget);
    expect(find.textContaining('A code was sent a moment ago'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('network error: clear message + retry; change number cancels', (tester) async {
    final api = _api()..on('POST /onboarding/otp/send', (_) => networkError());
    await _pumpApp(tester, api);
    await _sendCode(tester, '9876543210');
    expect(_inlineError(tester), 'No connection. Check the internet and try again.');
    api.on('POST /onboarding/otp/send', (_) => const ApiSuccess<Object?>({'status': 'sent', 'resend_after_seconds': 45}));
    await tester.tap(find.byKey(const Key('askodoxSignInRetry')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxChangeNumber')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('invalid numbers are refused before anything is sent', (tester) async {
    final api = _api();
    await _pumpApp(tester, api);
    await _sendCode(tester, '12345');
    expect(_inlineError(tester), 'Enter a valid mobile number with country code.');
    expect(api.to('POST', '/onboarding/otp/send'), isEmpty);
    await _dispose(tester);
  });

  testWidgets('Firebase phone sign-in (when switched on): the server verifies the ID token', (tester) async {
    final api = _api(firebase: true);
    final phone = FakePhoneAuth();
    await _pumpApp(tester, api, phoneAuth: phone);
    await _sendCode(tester, '+1 415 555 0123');
    expect(phone.started, ['+14155550123']);
    expect(api.to('POST', '/onboarding/otp/send'), isEmpty);
    phone.confirmError = 'invalid-verification-code';
    await _enterCode(tester, '654321');
    expect(_inlineError(tester), 'Incorrect OTP. (Firebase: invalid-verification-code)');
    phone.confirmError = null;
    await _enterCode(tester, '123456');
    expect(phone.confirmed.last, ('vid-1', '123456'));
    expect(api.to('POST', '/onboarding/firebase/verify').single.$3, {'id_token': 'firebase-id-token'});
    expect(find.byKey(const ValueKey('name-input')), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('Firebase not set up for this app: falls back to the server code', (tester) async {
    final api = _api(firebase: true);
    final phone = FakePhoneAuth(startResult: const AskodoxPhoneAuthFailed('app-not-authorized'));
    await _pumpApp(tester, api, phoneAuth: phone);
    await _sendCode(tester, '9876543210');
    expect(phone.started, ['+919876543210']);
    expect(api.to('POST', '/onboarding/otp/send').single.$3, {'mobile': '+919876543210'});
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('Send OTP never fails silently: exception, undelivered WhatsApp, Firebase codes; logs stay clean',
      (tester) async {
    final lines = <String>[];
    final previous = askodoxAuthLogSink;
    askodoxAuthLogSink = lines.add;
    addTearDown(() => askodoxAuthLogSink = previous);

    // 1. The request itself throws: the button does not stay on "Sending...".
    final api = _api()..on('POST /onboarding/otp/send', (_) => throw StateError('boom'));
    await _pumpApp(tester, api);
    await _sendCode(tester, '98765 43210');
    expect(_inlineError(tester), contains('Something went wrong while sending the code'));
    expect(find.text('Send OTP'), findsOneWidget, reason: 'button usable again');
    expect(find.byKey(const Key('askodoxSignInRetry')), findsOneWidget);

    // 2. WhatsApp accepted but did not deliver (server 503 with the reason).
    api.on('POST /onboarding/otp/send', (_) => httpError(503,
        'The code could not be delivered: WhatsApp delivers this code only if you sent a message to the ASKODOX '
        'WhatsApp number in the last 24 hours (Meta error 131047).'));
    await tester.tap(find.byKey(const Key('askodoxSendOtp')));
    await _settle(tester);
    expect(_inlineError(tester), contains('Meta error 131047'));
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget, reason: 'stays on the number, no false OTP step');
    await _dispose(tester);

    // 3. A Firebase error that is not a setup problem is shown with its code.
    final phone = FakePhoneAuth(startResult: const AskodoxPhoneAuthFailed('too-many-requests'));
    await _pumpApp(tester, _api(firebase: true), phoneAuth: phone);
    await _sendCode(tester, '98765 43210');
    expect(_inlineError(tester), 'Too many attempts. Please wait and try again. (Firebase: too-many-requests)');
    await _dispose(tester);

    expect(lines.where((l) => l.startsWith('askodox.auth send_otp.tap')), isNotEmpty);
    expect(lines.any((l) => l.contains('send_otp.exception') && l.contains('StateError')), isTrue);
    expect(lines.any((l) => l.contains('send_otp.failed') && l.contains('http=503')), isTrue);
    expect(lines.any((l) => l.contains('firebase_failed') && l.contains('code=too-many-requests')), isTrue);
    for (final l in lines) {
      expect(l, isNot(contains('9876543210')), reason: 'no phone number in logs: $l');
      expect(l, isNot(contains('98765')), reason: l);
    }
  });

  test('log redaction removes numbers and codes even if passed by mistake', () {
    expect(askodoxRedactDigits('+91 98765 43210'), '[redacted]');
    expect(askodoxRedactDigits('otp 123456'), 'otp [redacted]');
    expect(askodoxRedactDigits('••••3210'), '••••3210');
    expect(askodoxRedactDigits('503'), '503');
  });

  testWidgets('Firebase SMS first; when it is not allowed AND the fallback fails, both reasons are shown',
      (tester) async {
    final api = _api(firebase: true)
      ..on('POST /onboarding/otp/send', (_) => httpError(503,
          'The code could not be delivered: WhatsApp delivers this code only if you sent a message to the ASKODOX '
          'WhatsApp number in the last 24 hours (Meta error 131047).'));
    final phone = FakePhoneAuth(startResult: const AskodoxPhoneAuthFailed('operation-not-allowed'));
    await _pumpApp(tester, api, phoneAuth: phone);
    await _sendCode(tester, '98765 43210');
    expect(phone.started, ['+919876543210'], reason: 'Firebase SMS is tried first');
    final error = _inlineError(tester)!;
    expect(error, contains('(Firebase: operation-not-allowed)'));
    expect(error, contains('Meta error 131047'));
    await _dispose(tester);
  });

  // APK 1336: "Firebase: network-request-failed" and "Firebase: unknown -- An
  // internal error has occurred. [ Software caused connection abort ]".
  testWidgets('Firebase connection failures: named as network problems, never a sent code; trail reaches the server',
      (tester) async {
    final lines = <String>[];
    final previous = askodoxAuthLogSink;
    askodoxAuthLogSink = lines.add;
    addTearDown(() => askodoxAuthLogSink = previous);

    // 1. Send step, 'unknown' carrying the socket error.
    final api = _api(firebase: true);
    final phone = FakePhoneAuth(
        startResult: const AskodoxPhoneAuthFailed('unknown', 'An internal error has occurred. [ Software caused connection abort ]'));
    await _pumpApp(tester, api, phoneAuth: phone);
    await _sendCode(tester, '9876543210');
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget, reason: 'no false code step');
    expect(find.byKey(const ValueKey('otp-input')), findsNothing);
    final error = _inlineError(tester)!;
    expect(error, startsWith('The connection to Google broke while sending the code.'));
    expect(error, contains('(Firebase: unknown – An internal error has occurred. [ Software caused connection abort ])'));
    expect(find.byKey(const Key('askodoxSignInRetry')), findsOneWidget);
    expect(api.to('POST', '/onboarding/otp/send'), isEmpty, reason: 'a network failure is not a setup problem');
    final trace = api.to('POST', '/onboarding/diagnostics/trace').single.$3! as Map;
    expect(trace['outcome'], 'failed');
    expect(trace['stage'], 'send_otp');
    expect(trace['code'], 'unknown');
    final trail = (trace['lines'] as List).cast<String>();
    expect(trail.first, matches(RegExp(r'^\+\d+ms send_otp\.tap ')));
    expect(trail.any((l) => l.contains('send_otp.firebase_failed code=unknown network=true')), isTrue);
    expect(trail.join(' '), isNot(contains('3210')), reason: 'not even the masked number');
    await _dispose(tester);

    // 2. Send step, network-request-failed.
    final api2 = _api(firebase: true);
    await _pumpApp(tester, api2, phoneAuth: FakePhoneAuth(startResult: const AskodoxPhoneAuthFailed('network-request-failed')));
    await _sendCode(tester, '9876543210');
    expect(_inlineError(tester), startsWith('The connection to Google broke'));
    expect(_inlineError(tester), endsWith('(Firebase: network-request-failed)'));
    expect(find.byKey(const ValueKey('otp-input')), findsNothing);
    await _dispose(tester);

    // 3. Code step: the SMS arrived, confirming it lost the connection.
    final api3 = _api(firebase: true);
    final phone3 = FakePhoneAuth()
      ..confirmError = 'unknown'
      ..confirmDetail = 'An internal error has occurred. [ Software caused connection abort ]';
    await _pumpApp(tester, api3, phoneAuth: phone3);
    await _sendCode(tester, '9876543210');
    expect(api3.to('POST', '/onboarding/diagnostics/trace').single.$3, containsPair('outcome', 'code_sent'));
    await _enterCode(tester, '123456');
    expect(_inlineError(tester), startsWith('The connection to Google broke'));
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget, reason: 'stays on the code; can retry');
    expect(api3.to('POST', '/onboarding/firebase/verify'), isEmpty);
    final verifyTrace = api3.to('POST', '/onboarding/diagnostics/trace').last.$3! as Map;
    expect(verifyTrace['stage'], 'verify_otp');
    expect((verifyTrace['lines'] as List).join(' '), isNot(contains('123456')));
    await _dispose(tester);

    expect(lines.join('\n'), isNot(contains('9876543210')));
    expect(lines.join('\n'), isNot(contains('123456')));
  });

  test('network failure classification', () {
    expect(askodoxPhoneAuthNetworkFailure('network-request-failed'), isTrue);
    expect(askodoxPhoneAuthNetworkFailure('unknown', 'An internal error has occurred. [ Software caused connection abort ]'), isTrue);
    expect(askodoxPhoneAuthNetworkFailure('unknown', 'An internal error has occurred. [ BILLING_NOT_ENABLED ]'), isFalse);
    expect(askodoxPhoneAuthNetworkFailure('unknown'), isFalse);
    expect(askodoxPhoneAuthNetworkFailure('invalid-verification-code', 'network'), isFalse);
  });
}
