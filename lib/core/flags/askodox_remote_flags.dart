import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_models.dart';
import '../auth/auth_models.dart';
import '../providers/backend_providers.dart';

/// Command Center feature flags as resolved for THIS app (platform, role,
/// optional category, stable per-install id for % rollouts) from
/// `GET /api/flags`.
///
/// Safety rules:
/// * Built-in defaults (everything ON, as before flags existed) until a real
///   answer arrives -- a missing or failed fetch never switches anything off.
/// * The last good answer is cached on the device (and per category in
///   memory) and keeps working offline; a failed refresh keeps it.
/// * A flag the server does not send keeps its default.
class AskodoxRemoteFlags {
  const AskodoxRemoteFlags(this.values, {this.fetchedAt, this.fromServer = false});

  /// Defaults: every client flag ON (the app's behaviour before targeting).
  static const defaults = <String, bool>{
    'advisor.enabled': true,
    'results.videos': true,
    'results.online': true,
    'results.used': true,
    'results.deals': true,
    'results.sponsored': true,
    'results.affiliate': true,
    'ai.assistant': true,
    'voice.sarvam_tts': true,
    'companion.enabled': true,
    'companion.floating_bubble': true,
    'companion.screen_guide': true,
    'referrals': true,
    'coupons': true,
    'rewards': true,
    'support.escalation': true,
    'links.smart': true,
    'offers.merchant': true,
  };

  static const fallback = AskodoxRemoteFlags(defaults);

  final Map<String, bool> values;
  final DateTime? fetchedAt;
  final bool fromServer;

  bool enabled(String key) => values[key] ?? defaults[key] ?? true;

  /// Merge a server answer over the defaults (unknown / non-bool keys ignored).
  static AskodoxRemoteFlags parse(Object? json, {DateTime? at}) {
    final merged = Map<String, bool>.from(defaults);
    final flags = json is Map ? json['flags'] : null;
    if (flags is Map) {
      for (final entry in flags.entries) {
        if (entry.value is bool) merged['${entry.key}'] = entry.value as bool;
      }
    }
    return AskodoxRemoteFlags(merged, fetchedAt: at ?? DateTime.now(), fromServer: true);
  }

  Map<String, Object?> toJson() =>
      {'flags': values, if (fetchedAt != null) 'fetched_at': fetchedAt!.toIso8601String()};
}

/// The server role words used by flag targeting.
String askodoxFlagRole(UserRole role) => switch (role) {
      UserRole.guest => 'guest',
      UserRole.buyer => 'buyer',
      UserRole.seller => 'seller',
      _ => 'staff',
    };

class AskodoxFlagsRepository {
  AskodoxFlagsRepository(this._client, {SharedPreferences? prefs, Random? random, this.ttl = const Duration(minutes: 10)})
      : _prefs = prefs,
        _random = random ?? Random.secure();

  final ApiClient _client;
  SharedPreferences? _prefs;
  final Random _random;
  final Duration ttl;
  final _memory = <String, AskodoxRemoteFlags>{};

  static const _cacheKey = 'askodox.flags.v1';
  static const _installKey = 'askodox.flags.install_id';

  Future<SharedPreferences> get _store async => _prefs ??= await SharedPreferences.getInstance();

  /// Stable anonymous id for percentage rollouts (same bucket every time).
  Future<String> installId() async {
    final prefs = await _store;
    var id = prefs.getString(_installKey);
    if (id == null || id.isEmpty) {
      id = List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_installKey, id);
    }
    return id;
  }

  /// Last good answer stored on the device (or the defaults).
  Future<AskodoxRemoteFlags> cached() async {
    try {
      final raw = (await _store).getString(_cacheKey);
      if (raw == null) return AskodoxRemoteFlags.fallback;
      final json = jsonDecode(raw) as Map<String, Object?>;
      return AskodoxRemoteFlags.parse(json, at: DateTime.tryParse('${json['fetched_at'] ?? ''}'));
    } catch (_) {
      return AskodoxRemoteFlags.fallback;
    }
  }

  /// Resolved flags; never throws. ``category`` narrows to category-targeted
  /// rules (cached separately in memory).
  Future<AskodoxRemoteFlags> load({required UserRole role, String? subject, String category = ''}) async {
    final key = category.trim().toLowerCase();
    final known = _memory[key];
    if (known != null && known.fetchedAt != null && DateTime.now().difference(known.fetchedAt!) < ttl) {
      return known;
    }
    final base = known ?? (key.isEmpty ? await cached() : (_memory[''] ?? await cached()));
    try {
      final query = {
        'platform': 'android',
        'role': askodoxFlagRole(role),
        'subject': subject?.isNotEmpty == true ? subject! : await installId(),
        if (key.isNotEmpty) 'category': key,
      };
      final path = '/api/flags?${Uri(queryParameters: query).query}';
      final result = await _client.get<Map<String, Object?>>(path,
          options: const ApiRequestOptions(timeout: Duration(seconds: 6)));
      if (result is! ApiSuccess<Map<String, Object?>>) return base;
      final flags = AskodoxRemoteFlags.parse(result.data);
      _memory[key] = flags;
      if (key.isEmpty) {
        try {
          await (await _store).setString(_cacheKey, jsonEncode(flags.toJson()));
        } catch (_) {}
      }
      return flags;
    } catch (_) {
      return base; // offline / timeout / bad answer: keep what we had
    }
  }
}

final askodoxFlagsRepositoryProvider =
    Provider<AskodoxFlagsRepository>((ref) => AskodoxFlagsRepository(ref.watch(apiClientProvider)));

/// App-wide flags (role-aware, refreshed when the signed-in user changes).
final askodoxRemoteFlagsProvider = FutureProvider<AskodoxRemoteFlags>((ref) async {
  final session = ref.watch(authSessionProvider);
  return ref
      .watch(askodoxFlagsRepositoryProvider)
      .load(role: session.role, subject: session.user?.id);
});

/// Synchronous read with the safe default while loading or on error.
final askodoxFlagProvider = Provider.family<bool, String>((ref, key) {
  final flags = ref.watch(askodoxRemoteFlagsProvider).valueOrNull ?? AskodoxRemoteFlags.fallback;
  return flags.enabled(key);
});
