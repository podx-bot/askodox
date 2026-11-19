import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shopping mode (owner 2026-11-19): ONE switch, the bottom-bar "Shopping" button. ON = green and ASKODOX-registered
/// shops answer first in the chat; OFF = grey and the normal chat. It is OFF whenever the app opens (never saved).
/// There is no separate Shopping page: the whole conversation stays in the chat.
final askodoxShoppingModeProvider = StateProvider<bool>((ref) => false);
