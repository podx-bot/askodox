import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shopping mode (owner 2026-11-19): ONE switch, the bottom-bar "Shopping" button. ON = green and ASKODOX-registered
/// shops answer first in the chat; OFF = grey and the normal chat. It is OFF whenever the app opens (never saved).
/// There is no separate Shopping page: the whole conversation stays in the chat.
final askodoxShoppingModeProvider = StateProvider<bool>((ref) => false);

/// Buy / sell switch (owner 2026-11-21): ONE app, two sides, flipped by the bottom-bar switch. false = Buyer (what the
/// app opens on the first time), true = Seller (the person's own shop side). The last side is kept on the phone.
final askodoxSellerModeProvider = StateProvider<bool>((ref) => false);

/// Phone storage key for the last side the person used.
const askodoxSellerModePrefsKey = 'askodox.mode.seller.v1';
