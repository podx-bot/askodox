import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/auth/app_restart.dart';
import 'package:podx/core/auth/phone_auth.dart';
import 'package:podx/core/auth/sign_out.dart';
import 'package:podx/core/persistence/local_store.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/shared/widgets/header_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_fakes.dart';

const _account = 'phone-919876543210';

Map<String, Object> _signedInPrefs() => {
      'askodox.auth.token': 'session-token-A',
      'askodox.onboarding.complete': true,
      'askodox.profile.mobile': '919876543210',
      'askodox.profile.name': 'Asha',
      'askodox.conversation_archive.v1': '[{"q":"tv"}]',
      'askodox.saved_options.v1': '[1,2]',
      'askodox.roles.v1': '{"owned":["seller"]}',
      'askodox.locale': 'te',
      'askodox.voice_mode.v1': true,
    };

void main() {
  test('stash puts the account data away, keeps device settings, and restore brings it back', () async {
    SharedPreferences.setMockInitialValues(_signedInPrefs());
    final prefs = await SharedPreferences.getInstance();
    await askodoxStashAccountData(prefs, _account);
    for (final key in askodoxAccountScopedKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    expect(prefs.getString('askodox.locale'), 'te', reason: 'device settings stay');
    expect(prefs.getBool('askodox.voice_mode.v1'), isTrue);
    expect(prefs.getKeys().where((k) => k.contains('auth.token')), isEmpty, reason: 'the session token is never stashed');
    // Another person signs in: nothing of the first account is there.
    expect(await askodoxRestoreAccountData(prefs, 'phone-918888888888'), isFalse);
    expect(prefs.getString('askodox.conversation_archive.v1'), isNull);
    // The same account comes back: its chats / saved options / roles return.
    expect(await askodoxRestoreAccountData(prefs, _account), isTrue);
    expect(prefs.getString('askodox.conversation_archive.v1'), '[{"q":"tv"}]');
    expect(prefs.getString('askodox.roles.v1'), '{"owned":["seller"]}');
    expect(prefs.getKeys().where((k) => k.startsWith('askodox.stash.$_account.')), isEmpty);
  });

  test('at most three signed-out accounts are kept on the phone', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    for (final id in ['a1', 'a2', 'a3', 'a4']) {
      await prefs.setString('askodox.saved_options.v1', id);
      await askodoxStashAccountData(prefs, id);
    }
    expect(prefs.getStringList('askodox.stash.accounts'), ['a2', 'a3', 'a4']);
    expect(prefs.containsKey('askodox.stash.a1.askodox.saved_options.v1'), isFalse);
  });

  test('session check: valid, 401 = invalid, offline = unknown (kept)', () async {
    final api = FakeAuthApi();
    expect(await askodoxCheckSession(api, 't'), AskodoxSessionCheck.valid);
    expect(api.calls.single.$2, '/api/me/session');
    expect(api.calls.single.$4, 't');
    api.on('GET /api/me/session', (_) => httpError(401, 'Session expired or invalid -- please sign in again'));
    expect(await askodoxCheckSession(api, 't'), AskodoxSessionCheck.invalid);
    api.on('GET /api/me/session', (_) => networkError());
    expect(await askodoxCheckSession(api, 't'), AskodoxSessionCheck.unknown);
  });

  testWidgets('side menu Logout: confirm, server revoke, data put away, fresh app on restart', (tester) async {
    SharedPreferences.setMockInitialValues(_signedInPrefs());
    final api = FakeAuthApi()
      ..on('POST /api/me/logout', (_) => const ApiSuccess<Object?>({'signed_out': true, 'server_session': 'revoked'}));
    final phoneAuth = FakePhoneAuth();
    var builds = 0;
    await tester.pumpWidget(AskodoxAppRestart(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        askodoxPhoneAuthProvider.overrideWithValue(phoneAuth),
      ],
      child: Consumer(builder: (context, ref, _) {
        builds++;
        final user = ref.watch(authSessionProvider).user;
        return MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [AskodoxHeaderMenuButton(te: false)]),
            body: Text(user == null ? 'signed-out' : 'hello ${user.displayName}'),
          ),
        );
      }),
    ));
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    await container
        .read(authSessionProvider.notifier)
        .completeOnboarding(mobile: '919876543210', displayName: 'Asha', token: 'session-token-A');
    await tester.pumpAndSettle();
    expect(find.text('hello Asha'), findsOneWidget);

    // Cancel changes nothing.
    await tester.tap(find.byKey(const Key('askodoxHeaderMenu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxMenu-signout')), 120,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('askodoxMenu-signout')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxSignOutDialog')), findsOneWidget);
    expect(find.textContaining('stay saved'), findsOneWidget, reason: 'nothing is deleted');
    await tester.tap(find.byKey(const Key('askodoxSignOutCancel')));
    await tester.pumpAndSettle();
    expect(api.to('POST', '/api/me/logout'), isEmpty);
    expect(find.text('hello Asha'), findsOneWidget);

    // Confirm signs out.
    await tester.tap(find.byKey(const Key('askodoxHeaderMenu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('askodoxMenu-signout')), 120,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const ValueKey('askodoxMenu-signout')));
    await tester.pumpAndSettle();
    final before = builds;
    await tester.tap(find.byKey(const Key('askodoxSignOutConfirm')));
    await tester.pumpAndSettle();
    final logout = api.to('POST', '/api/me/logout').single;
    expect(logout.$4, 'session-token-A', reason: 'the server revokes THIS session');
    expect(api.calls.where((c) => c.$1 == 'DELETE'), isEmpty, reason: 'sign-out never deletes server data');
    expect(phoneAuth.signOuts, 1);
    expect(find.text('signed-out'), findsOneWidget);
    expect(builds, greaterThan(before), reason: 'the app restarted with fresh state');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('askodox.auth.token'), isFalse);
    expect(prefs.containsKey('askodox.conversation_archive.v1'), isFalse);
    expect(prefs.getString('askodox.stash.$_account.askodox.conversation_archive.v1'), '[{"q":"tv"}]');
    expect(prefs.getString('askodox.locale'), 'te');
    // Signed out: the menu no longer offers Logout.
    await tester.tap(find.byKey(const Key('askodoxHeaderMenu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxMenu-signout')), findsNothing);
  });

  testWidgets('sign-out works offline: the phone is signed out even if the server cannot be reached', (tester) async {
    SharedPreferences.setMockInitialValues(_signedInPrefs());
    final api = FakeAuthApi()..on('POST /api/me/logout', (_) => networkError());
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        localStoreProvider.overrideWithValue(MemoryLocalStore()),
        askodoxPhoneAuthProvider.overrideWithValue(FakePhoneAuth()),
      ],
      child: Consumer(builder: (context, ref, _) {
        captured = ref;
        return const MaterialApp(home: SizedBox());
      }),
    ));
    await captured
        .read(authSessionProvider.notifier)
        .completeOnboarding(mobile: '919876543210', displayName: 'Asha', token: 'session-token-A');
    final result = await askodoxSignOut(captured);
    expect(result, AskodoxSignOutServer.unreachable);
    expect(captured.read(authSessionProvider).user, isNull);
    expect((await SharedPreferences.getInstance()).containsKey('askodox.auth.token'), isFalse);
  });
}
