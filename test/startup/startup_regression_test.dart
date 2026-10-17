import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/persistence/startup_prefs.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/auth/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_fakes.dart';

/// APK 1335 regression: the app must always get past the startup spinner --
/// to Home for a signed-in user, to sign-in for a new user, and to a clear
/// "Try again" when phone storage cannot be opened (never an endless spinner,
/// never a lost session).
Future<void> _pump(WidgetTester tester) async {
  final router = GoRouter(initialLocation: '/onboarding', routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(FakeAuthApi()),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() => askodoxPrefsLoader = SharedPreferences.getInstance);

  testWidgets('existing signed-in user: startup goes straight to Home', (tester) async {
    SharedPreferences.setMockInitialValues({
      'askodox.onboarding.complete': true,
      'askodox.auth.token': 'tok',
      'askodox.profile.mobile': '919876543210',
      'askodox.profile.name': 'Asha',
      'askodox.locale': 'te',
    });
    await _pump(tester);
    await _frames(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('askodox.auth.token'), 'tok', reason: 'session untouched');
  });

  testWidgets('new user: startup shows the sign-up screen (no spinner)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    await _frames(tester);
    expect(find.text('Language'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('returning user after sign-out (language kept): number step', (tester) async {
    SharedPreferences.setMockInitialValues({'askodox.locale': 'en', 'askodox.stash.accounts': ['phone-919876543210']});
    await _pump(tester);
    await _frames(tester);
    expect(find.byKey(const ValueKey('mobile-input')), findsOneWidget);
  });

  testWidgets('storage plugin fails: "Try again" instead of an endless spinner; retry recovers', (tester) async {
    SharedPreferences.setMockInitialValues({'askodox.onboarding.complete': true, 'askodox.auth.token': 'tok'});
    askodoxPrefsLoader = () => Future<SharedPreferences>.error(StateError('SharedPreferencesApi has not been registered'));
    await _pump(tester);
    await _frames(tester);
    expect(find.byKey(const Key('askodoxStorageFailed')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    askodoxPrefsLoader = SharedPreferences.getInstance;
    await tester.tap(find.byKey(const Key('askodoxStorageRetry')));
    await _frames(tester);
    expect(find.text('HOME'), findsOneWidget, reason: 'the stored session was never deleted');
  });

  testWidgets('storage plugin never answers: the screen gives up after 8 s', (tester) async {
    SharedPreferences.setMockInitialValues({});
    askodoxPrefsLoader = () => Completer<SharedPreferences>().future;
    await _pump(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxStorageFailed')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('shared_preferences_android stays pinned to the version proven on devices', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final overrides = pubspec.split('dependency_overrides:').last;
    expect(overrides, contains('shared_preferences_android: 2.4.28'),
        reason: '2.5.0 (Pigeon JNI) froze startup in APK 1335; change only after a device / emulator proof');
  });
}
