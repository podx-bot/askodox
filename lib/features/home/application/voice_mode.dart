import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voice Mode (owner rule 2026-10-12): ON -> every conversational reply is
/// spoken, typed turns too; OFF (Text Mode) -> replies are spoken only for
/// voice turns or on Replay. Turned on by speaking to ASKODOX, off / on from
/// Profile. Mute and pause still win.
class AskodoxVoiceMode extends StateNotifier<bool> {
  AskodoxVoiceMode() : super(false) {
    _restore();
  }

  static const _key = 'askodox.voice_mode.v1';

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
