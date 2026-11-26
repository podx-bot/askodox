import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/auth/phone_auth.dart';
import 'package:podx/core/auth/sms_code_listener.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/auth/presentation/onboarding_screen.dart';
import 'package:podx/features/location/application/location_controller.dart' show deviceLocationGatewayProvider;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_fakes.dart';
import '../location/fakes/fake_device_location_gateway.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('first open: location -> language boxes -> helper intro -> terms (read to the end) -> number', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(initialLocation: '/onboarding', routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    ]);
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(FakeAuthApi()),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        askodoxPhoneAuthProvider.overrideWithValue(FakePhoneAuth(available: false)),
        askodoxSmsCodeSourceProvider.overrideWithValue(FakeSmsSource()),
        deviceLocationGatewayProvider.overrideWithValue(FakeDeviceLocationGateway()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await _settle(tester);

    // 1 location
    expect(find.byKey(const Key('askodoxOnboardLocation')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-input')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxLocationContinue')));
    await _settle(tester);

    // 2 language: one box for each of the 23 languages
    expect(find.byKey(const Key('askodoxLanguageContinue')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxLanguageBox-te')), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('askodoxLanguageBox-')),
        findsNWidgets(23));
    await tester.tap(find.byKey(const ValueKey('askodoxLanguageBox-te')));
    await _settle(tester);

    // 3 helper intro
    expect(find.byKey(const Key('askodoxIntroGo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxIntroGo')));
    await _settle(tester);

    // 4 terms: the tick and the button wait until the text is read to the end
    FilledButton accept() => tester.widget<FilledButton>(find.byKey(const Key('askodoxTermsAccept')));
    expect(accept().onPressed, isNull);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('askodoxTermsTick'))).onChanged, isNull);
    await tester.drag(find.byKey(const Key('askodoxTermsScroll')), const Offset(0, -2000));
    await _settle(tester);
    final tick = tester.widget<CheckboxListTile>(find.byKey(const Key('askodoxTermsTick')));
    expect(tick.onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('askodoxTermsTick')));
    await _settle(tester);
    expect(accept().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('askodoxTermsAccept')));
    await _settle(tester);

    // 5 number
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('askodox.terms.accepted.v1'), isTrue);
    expect(prefs.getString('askodox.locale'), 'te');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
