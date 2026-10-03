import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../matching/data/universal_match_repository.dart';

/// Options the user saved from the conversation (kept on this phone; the
/// same card data that was shown -- nothing added). Max 50, newest first.
class AskodoxSavedOptions extends StateNotifier<List<UniversalMatch>> {
  AskodoxSavedOptions() : super(const []) {
    _load();
  }

  static const _key = 'askodox.saved_options.v1';
  static const max = 50;

  static String keyOf(UniversalMatch m) => '${m.source}:${m.id}';

  bool contains(UniversalMatch m) => state.any((s) => keyOf(s) == keyOf(m));

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || !mounted) return;
      state = [
        for (final item in (jsonDecode(raw) as List))
          if (item is Map) UniversalMatch.fromJson(Map<String, Object?>.from(item)),
      ];
    } catch (_) {}
  }

  Future<void> toggle(UniversalMatch m) async {
    state = contains(m)
        ? [for (final s in state) if (keyOf(s) != keyOf(m)) s]
        : [m, ...state].take(max).toList();
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final s in state) s.toJson()]));
    } catch (_) {}
  }
}

final askodoxSavedOptionsProvider =
    StateNotifierProvider<AskodoxSavedOptions, List<UniversalMatch>>((ref) => AskodoxSavedOptions());

/// Maps directions to the option: real coordinates when known, otherwise
/// its address text. Null when there is nothing to navigate to.
Uri? askodoxDirectionsUri(UniversalMatch m) {
  if (m.latitude != null && m.longitude != null) {
    return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${m.latitude},${m.longitude}');
  }
  final place = [m.title, m.locationLabel].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
  if (m.locationLabel?.trim().isNotEmpty != true) return null;
  return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(place)}');
}

/// Local vs online at a glance: the lowest REAL price on each side (page
/// prices marked unverified), the nearest local distance, the online source.
class AskodoxLocalOnlineSummary {
  const AskodoxLocalOnlineSummary({
    this.localPrice,
    this.localDistanceKm,
    this.localCount = 0,
    this.onlinePrice,
    this.onlineVerified = true,
    this.onlineSource,
    this.onlineCount = 0,
  });

  final double? localPrice;
  final double? localDistanceKm;
  final int localCount;
  final double? onlinePrice;
  final bool onlineVerified;
  final String? onlineSource;
  final int onlineCount;

  static AskodoxLocalOnlineSummary? of(List<UniversalMatch> matches) {
    final local = matches.where((m) => m.source == 'local' || m.source == 'external').toList();
    final online = matches.where((m) => m.source == 'online' || m.source == 'partner' || m.affiliate).toList();
    if (local.isEmpty || online.isEmpty) return null;
    final localPriced = local.where((m) => m.price != null).toList()..sort((a, b) => a.price!.compareTo(b.price!));
    final onlinePriced = online.where((m) => m.price != null).toList()..sort((a, b) => a.price!.compareTo(b.price!));
    final distances = local.map((m) => m.distanceKm).whereType<double>().toList()..sort();
    final best = onlinePriced.firstOrNull;
    return AskodoxLocalOnlineSummary(
      localPrice: localPriced.firstOrNull?.price,
      localDistanceKm: distances.firstOrNull,
      localCount: local.length,
      onlinePrice: best?.price,
      onlineVerified: best?.priceVerified ?? true,
      onlineSource: (best ?? online.first).sourceName,
      onlineCount: online.length,
    );
  }
}
