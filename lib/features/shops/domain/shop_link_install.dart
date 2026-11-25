import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';

/// Shop link phase 2 (owner 2026-11-25): a person who installed ASKODOX from a shop's link
/// (`askodox.com/s/<slug>` -> Play with `referrer=utm_source=shop_link&utm_campaign=<slug>`) is counted for that shop
/// ONCE per install (a number only, no person), and the app opens that shop after sign-in.

/// Asked once per install; set after the referrer was read (whatever it said).
const askodoxShopLinkInstallAskedKey = 'askodox.shoplink.install.v1';

/// The shop to open once (business id); removed when opened.
const askodoxShopLinkOpenKey = 'askodox.shoplink.open.v1';

final _slug = RegExp(r'^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){2,29}$');

/// The shop's link name inside a Play install referrer, or null when the install did not come from a shop link.
String? askodoxShopLinkSlugFromReferrer(String referrer) {
  final Map<String, String> values;
  try {
    values = Uri.splitQueryString(referrer.trim());
  } catch (_) {
    return null;
  }
  final source = values['utm_source'] ?? '';
  if (source != 'shop_link' && source != 'shop_link_join') return null;
  final slug = (values['utm_campaign'] ?? '').trim().toLowerCase();
  return _slug.hasMatch(slug) ? slug : null;
}

/// Reads the install referrer from the phone (Play builds), tells the server once, and keeps the shop to open.
/// Never throws: an install must not fail to start because of a count.
Future<void> askodoxReportShopLinkInstall(ApiClient api, SharedPreferences prefs,
    {MethodChannel device = const MethodChannel('com.askodox.app/device')}) async {
  if (prefs.getBool(askodoxShopLinkInstallAskedKey) == true) return;
  final String referrer;
  try {
    referrer = await device.invokeMethod<String>('installReferrer') ?? '';
  } catch (_) {
    return; // not this platform / Play not ready: ask again on the next start
  }
  final slug = askodoxShopLinkSlugFromReferrer(referrer);
  if (slug == null) {
    await prefs.setBool(askodoxShopLinkInstallAskedKey, true);
    return;
  }
  try {
    final reply = await api.post<Map<String, dynamic>>('/api/pos/shop-links/installed', body: {'slug': slug});
    if (reply is! ApiSuccess<Map<String, dynamic>>) return; // offline: counted on the next start
    await prefs.setBool(askodoxShopLinkInstallAskedKey, true);
    final id = '${reply.data['business_id'] ?? ''}';
    if (id.isNotEmpty) await prefs.setString(askodoxShopLinkOpenKey, id);
  } catch (_) {
    // counted on the next start
  }
}

/// The shop to open now (once), or null.
Future<String?> askodoxTakeShopLinkToOpen(SharedPreferences prefs) async {
  final id = prefs.getString(askodoxShopLinkOpenKey) ?? '';
  if (id.isEmpty) return null;
  await prefs.remove(askodoxShopLinkOpenKey);
  return id;
}
