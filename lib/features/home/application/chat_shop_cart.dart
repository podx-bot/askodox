import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The ONE shop cart being filled in the chat (owner 2026-11-17: order without leaving the chat). The shop's menu card
/// owns it; the home screen shows its bar just above the message box and hands typed / spoken lines to it first
/// ("ఇంకో బిర్యానీ", "ఒక కూల్ డ్రింక్ కూడా"). A line the shop's menu does not understand goes on to the normal chat.
class AskodoxChatShopCart {
  const AskodoxChatShopCart({
    required this.owner,
    required this.shopName,
    required this.count,
    required this.totalPaise,
    required this.kindLabel,
    required this.send,
    required this.hear,
    required this.show,
  });

  /// Identity of the card that owns this cart (a newer card replaces an older one).
  final Object owner;
  final String shopName;
  final int count;
  final int totalPaise;
  final String kindLabel;
  final Future<void> Function() send;

  /// One line from the message box -> the reply to show, or null when it was not about this menu.
  final Future<String?> Function(String text) hear;

  /// Scroll / open the card so the person can see and change the items.
  final void Function() show;
}

final askodoxChatShopCartProvider = StateProvider<AskodoxChatShopCart?>((ref) => null);

/// Cart lines after one heard sentence: `clear`, then `remove`, then `add` (adds to what is there, max 50 each).
Map<String, int> askodoxApplyHeard(Map<String, int> cart, Map<String, Object?> heard) {
  final out = heard['clear'] == true ? <String, int>{} : Map<String, int>.of(cart);
  for (final id in (heard['remove'] as List? ?? const [])) {
    out.remove('$id');
  }
  for (final a in (heard['add'] as List? ?? const [])) {
    if (a is! Map) continue;
    final id = '${a['product_id'] ?? ''}';
    if (id.isEmpty) continue;
    final qty = a['qty'] is num ? (a['qty'] as num).round() : 1;
    final next = (out[id] ?? 0) + (qty < 1 ? 1 : qty);
    out[id] = next > 50 ? 50 : next;
  }
  return out;
}

/// True when a heard sentence changed the cart or asked to place it (otherwise the chat answers it as usual).
bool askodoxHeardIsAboutMenu(Map<String, Object?> heard) =>
    heard['clear'] == true ||
    heard['confirm'] == true ||
    (heard['add'] as List? ?? const []).isNotEmpty ||
    (heard['remove'] as List? ?? const []).isNotEmpty;
