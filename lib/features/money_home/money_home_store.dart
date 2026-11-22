import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/backend_providers.dart';
import '../pos/data/pos_repository.dart';
import 'launcher_layout.dart';

/// Saved per side (owner 2026-11-22): the Buyer and the Seller screens are separate, each with its own folders.
String askodoxMoneyLayoutKey(bool seller) => 'askodox.money.layout.v1.${seller ? 'seller' : 'buyer'}';

/// The shop the Seller side shows (a person may run or help in more than one).
const askodoxMoneyShopKey = 'askodox.money.shop.v1';

/// The Buyer side keeps one screen; the Seller side keeps one per shop (a hotel and a kirana need different pages),
/// all under the one Seller key: {"v": 1, "shops": {shop id: layout}}.
Future<AskodoxLaunchLayout?> askodoxLoadMoneyLayout(bool seller, {String? shop}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(askodoxMoneyLayoutKey(seller));
    if (!seller) return AskodoxLaunchLayout.decode(text);
    final shops = _shopLayouts(text);
    return shop == null ? null : AskodoxLaunchLayout.decode(shops[shop]);
  } catch (_) {
    return null;
  }
}

Map<String, String> _shopLayouts(String? text) {
  if (text == null || text.isEmpty) return {};
  try {
    final j = jsonDecode(text);
    if (j is Map && j['shops'] is Map) {
      return {for (final e in (j['shops'] as Map).entries) '${e.key}': jsonEncode(e.value)};
    }
  } catch (_) {}
  return {};
}

/// [layout] null = back to the shipped screen.
Future<void> askodoxSaveMoneyLayout(bool seller, AskodoxLaunchLayout? layout, {String? shop}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = askodoxMoneyLayoutKey(seller);
    if (!seller) {
      layout == null ? await prefs.remove(key) : await prefs.setString(key, layout.encode());
      return;
    }
    if (shop == null) return;
    final shops = _shopLayouts(prefs.getString(key));
    if (layout == null) {
      shops.remove(shop);
    } else {
      shops[shop] = layout.encode();
    }
    await prefs.setString(key, jsonEncode({'v': 1, 'shops': {for (final e in shops.entries) e.key: jsonDecode(e.value)}}));
  } catch (_) {
    // Best effort: the shipped screen comes back next time.
  }
}

/// The shop in view on the Seller side (null = the first one).
final askodoxMoneyShopProvider = StateNotifierProvider<AskodoxMoneyShop, String?>((ref) => AskodoxMoneyShop());

class AskodoxMoneyShop extends StateNotifier<String?> {
  AskodoxMoneyShop() : super(null) {
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(askodoxMoneyShopKey);
      if (mounted && state == null && id != null && id.isNotEmpty) state = id;
    } catch (_) {}
  }

  Future<void> choose(String id) async {
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxMoneyShopKey, id);
    } catch (_) {}
  }
}

/// Every shop this person runs OR helps in (owner and staff) -- the Seller side shows each one's own tools, only those
/// its role allows. Signed out = none (the screen offers sign-in).
final askodoxMyShopsProvider = FutureProvider.autoDispose<List<AskodoxJson>>((ref) async {
  if (ref.watch(authSessionProvider).user == null) return const [];
  return ref.watch(askodoxPosRepositoryProvider).businesses();
});

/// The shop to show: the chosen one when it is still in the list, else the first owned shop, else the first.
AskodoxJson? askodoxPickShop(List<AskodoxJson> shops, String? chosen) {
  if (shops.isEmpty) return null;
  for (final s in shops) {
    if ('${s['id']}' == chosen) return s;
  }
  for (final s in shops) {
    if ('${s['role']}' == 'owner') return s;
  }
  return shops.first;
}
