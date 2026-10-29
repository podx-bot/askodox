import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Always speak replies" (owner rule 2026-10-29, replaces the 2026-10-12
/// rule): by default a reply follows how the user asked -- a typed turn gets
/// text only, a voice turn is spoken too. Speaking once NO LONGER turns this
/// on. ON (Profile only, default OFF) -> every conversational reply is spoken,
/// typed turns too. Mute and pause still win; Replay always speaks. The key is
/// v2 so a value the old rule switched on by itself is not carried over.
class AskodoxVoiceMode extends StateNotifier<bool> {
  AskodoxVoiceMode() : super(false) {
    _restore();
  }

  static const _key = 'askodox.voice_mode.v2';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_key);
      if (mounted && saved != null) state = saved;
    } catch (_) {}
  }

  Future<void> set(bool on) async {
    if (state == on) return;
    state = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (_) {}
  }
}

final askodoxVoiceModeProvider = StateNotifierProvider<AskodoxVoiceMode, bool>((ref) => AskodoxVoiceMode());
