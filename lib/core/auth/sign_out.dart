import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/push_registration.dart';
import '../api/api_client.dart';
import '../api/api_models.dart';
import '../providers/backend_providers.dart';
import 'app_restart.dart';
import 'phone_auth.dart';

/// Sign-out: ONE flow for Profile -> Settings & Privacy and the side menu.
///
/// 1. the server revokes THIS session and unlinks this phone's push token
///    (POST /api/me/logout) -- nothing on the server is deleted;
/// 2. this phone deletes its FCM token and signs out of Firebase;
/// 3. everything stored on the phone for this account is put away (see
///    [askodoxAccountScopedKeys]) so the next person who signs in sees none
///    of it -- and it comes back when the same account signs in again;
/// 4. the app restarts with fresh state on the welcome / sign-in screen, so
///    Back cannot reopen an authenticated screen.

/// Phone-side data that belongs to the signed-in account. Device settings
/// (language, voice, companion, location in use, flags) stay.
const askodoxAccountScopedKeys = <String>[
  'askodox.auth.token',
  'askodox.onboarding.complete',
  'askodox.profile.mobile',
  'askodox.profile.name',
  'askodox.local.session',
  'askodox.local.buyerPreferences',
  'askodox.local.savedLocations',
  'askodox.local.watchlist',
  'askodox.local.alertPreferences',
  'askodox.local.recentSearches',
  'askodox.local.sellerDrafts',
  'askodox.saved_options.v1',
  'askodox.devices.local.v1',
  'askodox.roles.v1',
  'askodox.notifications.v1',
  'askodox.updates.seen.v1',
  'askodox.conversation_current.v1',
  'askodox.conversation_archive.v1',
  'askodox.active_universal_deal.v1',
  'askodox.active_conversation_turns.v1',
  'askodox.greeting.seen_before',
  'askodox.greeting.last_text',
  'askodox.greeting.last_at',
  'askodox.recent_locations.v1',
];

/// Keys that only make sense for the session itself (never stashed).
const _sessionOnlyKeys = {'askodox.auth.token', 'askodox.onboarding.complete', 'askodox.local.session'};

const _stashIndex = 'askodox.stash.accounts';
const _maxStashedAccounts = 3;

String _stashKey(String account, String key) => 'askodox.stash.$account.$key';

/// Moves this account's phone-side data out of the way (kept on this phone
/// for at most [_maxStashedAccounts] accounts) and clears it.
Future<void> askodoxStashAccountData(SharedPreferences prefs, String? account) async {
  final id = (account ?? '').trim();
  if (id.isNotEmpty) {
    for (final key in askodoxAccountScopedKeys) {
      if (_sessionOnlyKeys.contains(key) || !prefs.containsKey(key)) continue;
      final value = prefs.get(key);
      final target = _stashKey(id, key);
      if (value is String) {
        await prefs.setString(target, value);
      } else if (value is bool) {
        await prefs.setBool(target, value);
      } else if (value is int) {
        await prefs.setInt(target, value);
      } else if (value is double) {
        await prefs.setDouble(target, value);
      } else if (value is List) {
        await prefs.setStringList(target, value.map((e) => '$e').toList());
      }
    }
    final accounts = [...(prefs.getStringList(_stashIndex) ?? const <String>[])]..remove(id);
    accounts.add(id);
    while (accounts.length > _maxStashedAccounts) {
      final dropped = accounts.removeAt(0);
      for (final key in prefs.getKeys().where((k) => k.startsWith('askodox.stash.$dropped.')).toList()) {
        await prefs.remove(key);
      }
    }
    await prefs.setStringList(_stashIndex, accounts);
  }
  for (final key in askodoxAccountScopedKeys) {
    await prefs.remove(key);
  }
}

/// Brings back what [askodoxStashAccountData] put away for this account.
/// Returns true when something was restored. Never overwrites a value the
/// new session already wrote.
Future<bool> askodoxRestoreAccountData(SharedPreferences prefs, String? account) async {
  final id = (account ?? '').trim();
  if (id.isEmpty) return false;
  final prefix = 'askodox.stash.$id.';
  final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
  for (final stashed in keys) {
    final key = stashed.substring(prefix.length);
    final value = prefs.get(stashed);
    if (!prefs.containsKey(key)) {
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.map((e) => '$e').toList());
      }
    }
    await prefs.remove(stashed);
  }
  await prefs.setStringList(_stashIndex, [...(prefs.getStringList(_stashIndex) ?? const <String>[])]..remove(id));
  return keys.isNotEmpty;
}

/// "Sign out?" -- explains that nothing is deleted.
Future<bool> askodoxConfirmSignOut(BuildContext context, {required bool te}) async {
  String t(String en, String tel) => te ? tel : en;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('askodoxSignOutDialog'),
      title: Text(t('Sign out?', 'సైన్ అవుట్ చేయాలా?')),
      content: Text(t(
          'You will be signed out on this phone. Your profile, listings, orders and business details stay saved '
              'and come back when you sign in again.',
          'ఈ ఫోన్‌లో సైన్ అవుట్ అవుతారు. మీ ప్రొఫైల్, లిస్టింగ్‌లు, ఆర్డర్లు, వ్యాపార వివరాలు సేవ్ అయి ఉంటాయి; '
              'మళ్లీ సైన్ ఇన్ చేసినప్పుడు తిరిగి వస్తాయి.')),
      actions: [
        TextButton(
            key: const Key('askodoxSignOutCancel'),
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('Cancel', 'రద్దు'))),
        FilledButton(
            key: const Key('askodoxSignOutConfirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('Sign out', 'సైన్ అవుట్'))),
      ],
    ),
  );
  return ok == true;
}

/// What the server said (the phone is signed out either way).
enum AskodoxSignOutServer { revoked, alreadyInvalid, unreachable }

/// The secure sign-out. The caller confirms first ([askodoxConfirmSignOut]).
Future<AskodoxSignOutServer> askodoxSignOut(WidgetRef ref, {BuildContext? restartFrom}) async {
  final session = ref.read(authSessionProvider);
  final token = (session.tokenPlaceholder ?? '').trim();
  final account = session.user?.id;
  final push = ref.read(askodoxPushRegistrationProvider);
  String? pushToken;
  try {
    pushToken = await push.currentToken();
  } catch (_) {}
  var server = AskodoxSignOutServer.unreachable;
  if (token.isNotEmpty && token != 'OTP_VERIFIED' && token != 'DEMO_ONLY') {
    final result = await ref.read(apiClientProvider).post<Map<String, Object?>>(
          '/api/me/logout',
          body: {if (pushToken != null) 'push_token': pushToken},
          options: ApiRequestOptions(authToken: token),
        );
    if (result is ApiSuccess<Map<String, Object?>>) {
      server = result.data['server_session'] == 'revoked'
          ? AskodoxSignOutServer.revoked
          : AskodoxSignOutServer.alreadyInvalid;
    }
  } else {
    server = AskodoxSignOutServer.alreadyInvalid;
  }
  try {
    await push.signOutDevice();
  } catch (_) {}
  try {
    await ref.read(askodoxPhoneAuthProvider).signOut();
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await askodoxStashAccountData(prefs, account);
  await ref.read(authSessionProvider.notifier).logout();
  final context = restartFrom;
  if (context != null && context.mounted) AskodoxAppRestart.restart(context);
  return server;
}

/// Startup check: is the stored session still valid on the server?
/// Valid / invalid (401: expired, signed out elsewhere, revoked) / unknown
/// (offline, server error -- the phone keeps the session and retries later).
enum AskodoxSessionCheck { valid, invalid, unknown }

Future<AskodoxSessionCheck> askodoxCheckSession(ApiClient client, String token) async {
  final result = await client.get<Map<String, Object?>>('/api/me/session', options: ApiRequestOptions(authToken: token));
  if (result is ApiSuccess<Map<String, Object?>>) return AskodoxSessionCheck.valid;
  if (result is ApiError<Map<String, Object?>> && result.failure.statusCode == 401) return AskodoxSessionCheck.invalid;
  return AskodoxSessionCheck.unknown;
}
