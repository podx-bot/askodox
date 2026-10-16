import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_models.dart';
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
    await _enterCode(tester, '000000');
    expect(find.text('Incorrect OTP.'), findsOneWidget);
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
      ..on('POST /onboarding/otp/verify', (_) => const ApiSuccess<Object?>({
            ..._newUser,
            'returning': true,
            'profile': {'name': 'Ravi', 'language': 'en', 'roles': ['buyer', 'seller']},
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
    expect(find.text('OTP expired. Request a new OTP.'), findsOneWidget);
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
    expect(find.text('No connection. Check the internet and try again.'), findsOneWidget);
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
    expect(find.text('Enter a valid mobile number with country code.'), findsOneWidget);
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
    expect(find.text('Incorrect OTP.'), findsOneWidget);
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
}
