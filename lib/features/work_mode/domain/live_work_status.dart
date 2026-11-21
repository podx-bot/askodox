import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom-bar "Live Work" dot (owner 2026-11-21): green and blinking while steps are being counted,
/// grey while the phone is still, red "!" when the person has to do something (step permission / sensor).
enum AskodoxLiveWorkStatus { live, idle, attention }

/// Steps counted within this many seconds = the work is running right now.
const askodoxLiveWorkWindowSeconds = 300;

/// [lastCountedAt] / [now] are epoch seconds; [lastCountedAt] is the last time steps were counted today.
AskodoxLiveWorkStatus askodoxLiveWorkStatus({required int? lastCountedAt, required int now, bool needsAttention = false}) {
  if (needsAttention) return AskodoxLiveWorkStatus.attention;
  if (lastCountedAt != null && now >= lastCountedAt && now - lastCountedAt <= askodoxLiveWorkWindowSeconds) {
    return AskodoxLiveWorkStatus.live;
  }
  return AskodoxLiveWorkStatus.idle;
}

/// True once a step reading failed in this app session (permission taken away, no sensor): the dot turns red and
/// the shell stops reading until the person opens the game, where the normal permission flow runs.
final askodoxLiveWorkAttentionProvider = StateProvider<bool>((ref) => false);
