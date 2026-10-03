import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Greeting configured in the Command Center (Owner setup -> Greetings),
/// chosen by the server from the user's LOCAL hour, language (any BCP-47
/// tag) and context (returning user), with {name} filled in. Not repeated:
/// at most once per [minGap] on this phone (and per signed-in user on the
/// server), and never the same text twice in a row.
class GreetingRepository {
  GreetingRepository(this._client, {this.authToken, DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final ApiClient _client;
  final String? authToken;
  final DateTime Function() _now;

  static const minGap = Duration(hours: 4);
  static const _lastAtKey = 'askodox.greeting.last_at';
  static const _lastTextKey = 'askodox.greeting.last_text';
  static const _seenKey = 'askodox.greeting.seen_before';

  Future<String?> next({required String language, String name = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = _now();
    final lastAt = DateTime.tryParse(prefs.getString(_lastAtKey) ?? '');
    if (lastAt != null && now.difference(lastAt) < minGap) return null;
    final returning = prefs.getBool(_seenKey) ?? false;
    final query = {
      'language': language,
      'local_hour': '${now.hour}',
      'returning': '$returning',
      if (name.trim().isNotEmpty) 'name': name.trim().split(RegExp(r'\s+')).first,
      'last': prefs.getString(_lastTextKey) ?? '',
    };
    final result = await _client.get<Map<String, Object?>>(
      Uri(path: '/api/greeting', queryParameters: query).toString(),
      options: ApiRequestOptions(timeout: const Duration(seconds: 8), authToken: authToken),
    );
    await prefs.setBool(_seenKey, true);
    if (result is! ApiSuccess<Map<String, Object?>>) return null;
    final greeting = result.data['greeting'];
    final text = greeting is Map ? '${greeting['text'] ?? ''}'.trim() : '';
    if (text.isEmpty) return null;
    await prefs.setString(_lastAtKey, now.toIso8601String());
    await prefs.setString(_lastTextKey, text);
    return text;
  }
}

extension GreetingSignOff on GreetingRepository {
  /// Closing line in the customer's language (null = no template in that
  /// language: the AI writes the sign-off instead, so any language works).
  Future<String?> signoff({required String language, String name = ''}) async {
    final now = _now();
    final result = await _client.get<Map<String, Object?>>(
      Uri(path: '/api/greeting', queryParameters: {
        'kind': 'signoff',
        'language': language,
        'local_hour': '${now.hour}',
        if (name.trim().isNotEmpty) 'name': name.trim().split(RegExp(r'\s+')).first,
      }).toString(),
      options: ApiRequestOptions(timeout: const Duration(seconds: 8), authToken: authToken),
    );
    if (result is! ApiSuccess<Map<String, Object?>>) return null;
    final greeting = result.data['greeting'];
    if (greeting is! Map || greeting['language_matched'] != true) return null;
    final text = '${greeting['text'] ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

final greetingRepositoryProvider = Provider<GreetingRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return GreetingRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

/// The greeting for this app open (null = none due / none configured / offline).
final askodoxGreetingProvider = FutureProvider.family<String?, String>((ref, language) async {
  final session = ref.watch(authSessionProvider);
  try {
    return await ref.read(greetingRepositoryProvider).next(language: language, name: session.user?.displayName ?? '');
  } catch (_) {
    return null;
  }
});
