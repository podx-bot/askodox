import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shopping mode (owner 2026-11-19): ONE switch, the bottom-bar "Shopping" button. ON = green and ASKODOX-registered
/// shops answer first in the chat; OFF = grey and the normal chat. It is OFF whenever the app opens (never saved).
/// There is no separate Shopping page: the whole conversation stays in the chat.
final askodoxShoppingModeProvider = StateProvider<bool>((ref) => false);

/// Buy / sell switch (owner 2026-11-21): ONE app, two sides, flipped by the bottom-bar switch. false = Buyer (what the
/// app opens on the first time), true = Seller (the person's own shop side). The last side is kept on the phone.
final askodoxSellerModeProvider = StateProvider<bool>((ref) => false);

/// Phone storage key for the last side the person used.
const askodoxSellerModePrefsKey = 'askodox.mode.seller.v1';

/// Flips the app to [seller] (or back to the Buyer side) and keeps the choice on the phone.
Future<void> askodoxSetSellerMode(WidgetRef ref, bool seller) async {
  ref.read(askodoxSellerModeProvider.notifier).state = seller;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(askodoxSellerModePrefsKey, seller);
  } catch (_) {
    // Not saved: the switch still works for this session.
  }
}
