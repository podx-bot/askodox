/// Main Chat voice endpointing: decides when an in-app recording should end.
///
/// Build 1237 stopped recordings after ~10 seconds while people were still
/// talking: the native loop used a fixed amplitude threshold (1800), so
/// quieter speech never counted as speech and the 8-second "no speech"
/// timeout fired; natural pauses over 2.5 s also ended the recording. This
/// endpointer calibrates to the room's noise floor, requires sustained
/// speech before any silence can end the turn, and only stops on genuine
/// silence after speech, a long no-speech timeout, a generous maximum, or
/// the user's own Stop.
enum VoiceEndpointDecision {
  keepRecording,
  stopAfterSilence,
  stopNoSpeech,
  stopMaxDuration,
}

class AskodoxVoiceEndpointer {
  AskodoxVoiceEndpointer({
    this.calibration = const Duration(milliseconds: 600),
    // APK 1312: 3 s ended turns on a natural thinking pause ("stops after
    // 1-2 seconds of talking"). The user's Stop ends a turn; long silence
    // is only a SAFETY limit.
    this.silenceAfterSpeech = const Duration(seconds: 8),
    this.noSpeechTimeout = const Duration(seconds: 15),
    this.maxDuration = const Duration(minutes: 2),
    // A cough or a click is not speech that may arm the silence stop.
    this.minimumSpeech = const Duration(milliseconds: 800),
    this.minimumThreshold = 600,
  });

  /// Main Chat (owner requirement after APK 1316): the microphone stays open
  /// until the user's own Stop -- no silence or no-speech auto-stop. Only the
  /// [maxDuration] safety limit remains (the backend segments long audio).
  AskodoxVoiceEndpointer.untilStop({Duration maxDuration = const Duration(minutes: 2)})
      : this(silenceAfterSpeech: null, noSpeechTimeout: null, maxDuration: maxDuration);

  final Duration calibration;
  /// Null = never stop on silence (only Stop / [maxDuration]).
  final Duration? silenceAfterSpeech;

  /// Null = never stop because nothing was heard yet.
  final Duration? noSpeechTimeout;
  final Duration maxDuration;
  final Duration minimumSpeech;
  final int minimumThreshold;

  double? _noiseFloor;
  Duration _lastSample = Duration.zero;
  Duration _speech = Duration.zero;
  Duration? _lastSpeechAt;

  bool get heardSpeech => _speech >= minimumSpeech;

  /// Current amplitude a sample must reach to count as speech.
  double get threshold {
    // A gentle multiplier: a noisy pause must never push the threshold above
    // a soft speaker's voice.
    final floor = _noiseFloor ?? 0;
    final adaptive = floor * 1.8 + 250;
    return adaptive > minimumThreshold ? adaptive : minimumThreshold.toDouble();
  }

  /// Feed one amplitude sample (Android `MediaRecorder.getMaxAmplitude`,
  /// 0–32767) taken [elapsed] after recording started.
  VoiceEndpointDecision add(int amplitude, Duration elapsed) {
    final step = elapsed - _lastSample;
    _lastSample = elapsed;
    final level = amplitude < 0 ? 0 : amplitude;

    if (elapsed <= calibration) {
      // The quietest calibration sample is the room, even if the user
      // started talking immediately.
      final floor = _noiseFloor;
      _noiseFloor = floor == null || level < floor ? level.toDouble() : floor;
    } else if (level >= threshold) {
      _speech += step;
      _lastSpeechAt = elapsed;
    } else {
      // Track slow changes in background noise (fan, traffic) without
      // letting speech raise the floor.
      final floor = _noiseFloor ?? level.toDouble();
      _noiseFloor = floor * 0.97 + level * 0.03;
    }

    if (elapsed >= maxDuration) return VoiceEndpointDecision.stopMaxDuration;
    final lastSpeech = _lastSpeechAt;
    final silence = silenceAfterSpeech;
    if (silence != null && heardSpeech && lastSpeech != null &&
        elapsed - lastSpeech >= silence) {
      return VoiceEndpointDecision.stopAfterSilence;
    }
    final noSpeech = noSpeechTimeout;
    if (noSpeech != null && !heardSpeech && elapsed >= noSpeech) {
      return VoiceEndpointDecision.stopNoSpeech;
    }
    return VoiceEndpointDecision.keepRecording;
  }
}

/// One composer draft from what the user typed and what they then said:
/// typed words first, the transcript after (no duplicate when the transcript
/// already contains the typed words).
String askodoxMergeVoiceDraft(String typed, String transcript) {
  final t = typed.trim(), v = transcript.trim();
  if (t.isEmpty) return v;
  if (v.isEmpty || v.contains(t)) return v.isEmpty ? t : v;
  return '$t $v';
}

final _teluguScript = RegExp(r'[ఀ-౿]');
final _latinLetters = RegExp(r'[A-Za-z]');

/// Language ASKODOX should speak a reply in: the language the reply is
/// written in, else the language of the user's question, else the app's
/// selected language. Telugu question → Telugu voice; English → English.
String askodoxSpeechLanguage({
  required String reply,
  required String userText,
  required bool uiTelugu,
}) {
  if (_teluguScript.hasMatch(reply)) return 'te';
  if (_latinLetters.hasMatch(reply)) return 'en';
  if (_teluguScript.hasMatch(userText)) return 'te';
  if (_latinLetters.hasMatch(userText)) return 'en';
  return uiTelugu ? 'te' : 'en';
}
