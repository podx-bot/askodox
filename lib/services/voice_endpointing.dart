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
  // How loud the person's own voice has been (slowly fading). A pause is "quiet" relative to THAT, so a room that is
  // always louder than the calibrated floor (shop, fan, traffic) can no longer count as speech forever -- which made
  // talk mode wait for a screen tap (owner 2026-11-16).
  double _speechPeak = 0;
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
    final base = adaptive > minimumThreshold ? adaptive : minimumThreshold.toDouble();
    // Once real speech was heard, a sample must reach 38% of the voice level to still count as speech.
    final relative = _speechPeak * 0.38;
    return relative > base ? relative : base;
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
      // Loud samples build the voice level; it fades a little each sample so a changed distance / volume adapts.
      _speechPeak = level > _speechPeak ? _speechPeak * 0.7 + level * 0.3 : _speechPeak * 0.995;
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

/// Voice conversation (talk mode): how long the mic waits for the person after a reply before pausing.
const askodoxTalkNoSpeechTimeout = Duration(seconds: 10);

/// Voice conversation: the gap between ASKODOX's voice ending and the mic opening again (no echo of its own voice).
const askodoxTalkEchoGap = Duration(milliseconds: 700);

/// How long the FIRST spoken part of a reply may be (owner 2026-11-25: was 160 for typed turns -- the voice waited
/// for ~160 written characters and a long first clip; now the same short first part as talk mode).
int askodoxFirstSpeechMax({required bool talk}) => talk ? 80 : 90;

/// The shortest first spoken part made by a comma cut ([askodoxSpeechChunks]).
const askodoxFirstChunkMin = 24;

/// A reply spoken in sentence-sized chunks (cut on line / sentence ends):
/// the first words play almost at once instead of after the WHOLE reply is
/// synthesised (production: 10 s before a long reply started), and each
/// chunk's text is revealed while it is spoken. Offsets index [text].
///
/// Owner 2026-11-25 ("chat speed chala important"; deploy log: a 100-140 character first part took 2-3 s to voice):
/// when the FIRST sentence is longer than [firstMax], the first part ends at the last comma between
/// [askodoxFirstChunkMin] and [firstMax] characters, so the voice starts on a short phrase. The cut is taken only once
/// the text has run past [firstMax] with no sentence end, so a reply that is still streaming keeps the same first part.
List<({int start, int end})> askodoxSpeechChunks(String text, {int firstMax = 160, int maxChars = 320}) {
  final cuts = <int>[0];
  for (final m in RegExp(r'\n+|(?<=[.!?।])\s+').allMatches(text)) {
    if (m.end > cuts.last) cuts.add(m.end);
  }
  if (cuts.last != text.length) cuts.add(text.length);
  final firstEnd = cuts.length > 1 ? cuts[1] : 0;
  if (firstEnd > firstMax) {
    var comma = -1;
    for (final m in RegExp(r'[,،;:]\s+|\s[-–—]\s').allMatches(text.substring(0, firstMax))) {
      if (m.end >= askodoxFirstChunkMin) comma = m.end;
    }
    if (comma > 0) cuts.insert(1, comma);
  }
  final out = <({int start, int end})>[];
  var start = 0;
  for (var i = 1; i < cuts.length; i++) {
    final end = cuts[i];
    final next = i + 1 < cuts.length ? cuts[i + 1] : null;
    final limit = out.isEmpty ? firstMax : maxChars;
    if (next == null || next - start > limit) {
      if (text.substring(start, end).trim().isNotEmpty) out.add((start: start, end: end));
      start = end;
    }
  }
  return out;
}

/// The part of a markup reply shown while it is being spoken: cut at the end
/// of a word, with an open **bold** closed so no raw "**" ever shows.
String askodoxRevealPrefix(String markup, int end) {
  if (end >= markup.length) return markup;
  var cut = end.clamp(0, markup.length);
  while (cut < markup.length && !RegExp(r'\s').hasMatch(markup[cut])) {
    cut++;
  }
  final prefix = markup.substring(0, cut).trimRight();
  return '**'.allMatches(prefix).length.isOdd ? '$prefix**' : prefix;
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
