import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/app_restart.dart';
import 'package:podx/core/auth/phone_auth.dart';
import 'package:podx/core/auth/sign_out.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/auth/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_fakes.dart';

/// APK 1334 regression: first Firebase login -> logout -> second login where
/// Firebase reports "unknown" around the reCAPTCHA step and then sends the SMS
/// (codeSent). The code step must open, keep Firebase's verification id and
/// sign the same account in.
class _App extends StatefulWidget {
  const _App();
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  late final GoRouter router = GoRouter(initialLocation: '/onboarding', routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Column(children: [
            Text('HOME ${ref.watch(authSessionProvider).user?.displayName ?? ''}'),
            TextButton(
              key: const Key('testSignOut'),
              onPressed: () => askodoxSignOut(ref, restartFrom: context),
              child: const Text('Sign out'),
            ),
          ]),
        ),
      ),
    ),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
  ]);

  @override
  Widget build(BuildContext context) => MaterialApp.router(routerConfig: router);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String? _inlineError(WidgetTester tester) {
  final f = find.byKey(const Key('askodoxSignInError'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  testWidgets('first login, logout, second login with reCAPTCHA ("unknown" then codeSent), OTP entry',
      (tester) async {
    SharedPreferences.setMockInitialValues({'askodox.locale': 'en'});
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var returning = false;
    final api = FakeAuthApi()
      ..on('GET /onboarding/methods', (_) => const ApiSuccess<Object?>(
          {'firebase_phone_auth': true, 'server_otp': true, 'resend_seconds': 45}))
      ..on('POST /onboarding/firebase/verify', (_) => ApiSuccess<Object?>(<String, Object?>{
            'status': 'verified',
            'app_user_id': 'app-phone-919876543210',
            'token': returning ? 'tok-2' : 'tok-1',
            'returning': returning,
            'profile': returning ? const {'name': 'Asha', 'language': 'en', 'roles': ['buyer']} : const {},
          }))
      ..on('POST /api/me/logout', (_) => const ApiSuccess<Object?>({'signed_out': true, 'server_session': 'revoked'}));
    final phone = FakePhoneAuth()..script = (s) => s.codeSent('vid-1', 7);
    await tester.pumpWidget(AskodoxAppRestart(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        askodoxPhoneAuthProvider.overrideWithValue(phone),
      ],
      child: const _App(),
    ));
    await _settle(tester);

    // 1. First login (Firebase codeSent straight away).
    await tester.enterText(find.byKey(const ValueKey('mobile-input')), '98765 43210');
    await tester.tap(find.byKey(const Key('askodoxSendOtp')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '123456');
    await _settle(tester);
    expect(phone.confirmed.last, ('vid-1', '123456'));
    await tester.enterText(find.byKey(const ValueKey('name-input')), 'Asha');
    await tester.tap(find.byKey(const Key('askodoxNameNext')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('askodoxFinishSignUp')));
    await _settle(tester);
    expect(find.text('HOME Asha'), findsOneWidget);

    // 2. Logout -> fresh app on the sign-in screen.
    await tester.tap(find.byKey(const Key('testSignOut')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget);
    expect(phone.signOuts, 1);

    // 3. Second login, same number: "unknown" first (reCAPTCHA), the SMS is sent afterwards.
    returning = true;
    phone.script = (s) {
      s.failed('unknown', 'An internal error has occurred.');
      Future<void>.delayed(const Duration(milliseconds: 120), () => s.codeSent('vid-2', 8));
    };
    await tester.enterText(find.byKey(const ValueKey('mobile-input')), '98765 43210');
    await tester.tap(find.byKey(const Key('askodoxSendOtp')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget, reason: 'Step 3 opens after codeSent');
    expect(_inlineError(tester), isNull, reason: 'no false "Verification failed"');
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '654321');
    await _settle(tester);
    expect(phone.confirmed.last, ('vid-2', '654321'), reason: 'Firebase verification id kept');
    expect(find.textContaining('HOME'), findsOneWidget, reason: 'signed in again');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('askodox.auth.token'), 'tok-2', reason: 'new session of the same account');
    expect(prefs.getString('askodox.profile.name'), 'Asha', reason: 'saved profile restored, not asked again');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('codeSent that arrives after the error was shown still opens the code step', (tester) async {
    SharedPreferences.setMockInitialValues({'askodox.locale': 'en'});
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeAuthApi()
      ..on('GET /onboarding/methods', (_) => const ApiSuccess<Object?>({'firebase_phone_auth': true}));
    final phone = FakePhoneAuth()
      ..grace = const Duration(milliseconds: 100)
      ..script = (s) => s.failed('unknown', 'An internal error has occurred.');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        askodoxPhoneAuthProvider.overrideWithValue(phone),
      ],
      child: const _App(),
    ));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('mobile-input')), '98765 43210');
    await tester.tap(find.byKey(const Key('askodoxSendOtp')));
    await _settle(tester);
    expect(_inlineError(tester), contains('(Firebase: unknown – An internal error has occurred.)'));
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget);
    // The SMS was sent after all (late codeSent).
    phone.lastOnLate!(const AskodoxPhoneCodeSent('vid-late', 3));
    await _settle(tester);
    expect(find.byKey(const ValueKey('otp-input')), findsOneWidget);
    expect(_inlineError(tester), isNull, reason: 'the error is cleared');
    await tester.enterText(find.byKey(const ValueKey('otp-input')), '111222');
    await _settle(tester);
    expect(phone.confirmed.last, ('vid-late', '111222'));
    // A stale late event (after "Change number") is ignored.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
