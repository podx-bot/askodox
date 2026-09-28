import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Voice hooks for the ASKODOX friend: what the microphone hears (listening)
/// and what ASKODOX is saying (speaking -> lip-sync).
///
/// Everything is driven by REAL signals, never a canned loop:
/// * listening: the same microphone amplitude that drives the voice bars;
/// * speaking with device TTS: native word ranges (`speechRange`, Android
///   `UtteranceProgressListener.onRangeStart`) of the text being spoken;
/// * speaking with Sarvam audio: the player's position/duration mapped
///   onto the reply text.
/// When no timing arrives (older phones), the text is paced at an average
/// speaking rate so the mouth still follows the words' vowels.
///
/// Mouth shapes come from [askodoxViseme]: open vowels open wide, closed
/// consonants (m/b/p) close the lips -- for Latin and Indic scripts alike.
class AskodoxCompanionVoice extends ChangeNotifier {
  AskodoxCompanionVoice({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Average speaking pace used only when the engine gives no timing.
  static const charsPerSecond = 14.0;

  double _mic = 0;
  String _text = '';
  DateTime? _speechStart;
  int _rangeStart = -1;
  int _rangeEnd = -1;
  DateTime? _rangeAt;
  Duration? _position;
  Duration? _duration;
  DateTime? _positionAt;

  /// 0..1 microphone level while the user speaks.
  double get micLevel => _mic;
  bool get speaking => _speechStart != null;
  String get text => _text;

  void setMicLevel(double level) {
    final next = level.isNaN ? 0.0 : level.clamp(0.0, 1.0);
    if ((next - _mic).abs() < .01) return;
    _mic = next;
    notifyListeners();
  }

  /// ASKODOX starts saying [text].
  void speechBegin(String text) {
    _text = text;
    _speechStart = _clock();
    _rangeStart = _rangeEnd = -1;
    _rangeAt = null;
    _position = _duration = _positionAt = null;
    notifyListeners();
  }

  /// Native TTS reports the word now being spoken ([start], [end] are
  /// character offsets into the spoken text).
  void speechRange(int start, int end) {
    if (!speaking) return;
    _rangeStart = start.clamp(0, _text.length);
    _rangeEnd = end.clamp(_rangeStart, _text.length);
    _rangeAt = _clock();
    notifyListeners();
  }

  /// Audio playback position of the reply (Sarvam voice).
  void speechProgress(Duration position, Duration duration) {
    if (!speaking || duration <= Duration.zero) return;
    _position = position;
    _duration = duration;
    _positionAt = _clock();
    notifyListeners();
  }

  void speechEnd() {
    if (!speaking && _mic == 0) return;
    _speechStart = null;
    _text = '';
    _mic = 0;
    notifyListeners();
  }

  /// Index of the character being voiced right now, or -1.
  int currentCharIndex() {
    final start = _speechStart;
    if (start == null || _text.isEmpty) return -1;
    final now = _clock();
    int index;
    if (_rangeAt != null && _rangeStart >= 0) {
      // Inside the current word, advance at the average pace.
      final into = now.difference(_rangeAt!).inMilliseconds / 1000 * charsPerSecond;
      final wordEnd = _rangeEnd > _rangeStart ? _rangeEnd : _rangeStart + 1;
      index = (_rangeStart + into.floor()).clamp(_rangeStart, wordEnd - 1);
    } else if (_position != null && _duration != null) {
      final extra = now.difference(_positionAt!);
      final fraction = (_position! + extra).inMilliseconds / _duration!.inMilliseconds;
      index = (fraction * _text.length).floor();
    } else {
      index = (now.difference(start).inMilliseconds / 1000 * charsPerSecond).floor();
    }
    if (index >= _text.length) return -1;
    return index;
  }

  /// How open the friend's mouth is right now (0 closed .. 1 wide).
  double mouthOpenness() {
    final i = currentCharIndex();
    if (i < 0) return 0;
    final here = askodoxViseme(_text.codeUnitAt(i));
    final next = i + 1 < _text.length ? askodoxViseme(_text.codeUnitAt(i + 1)) : 0.0;
    return here * .7 + next * .3; // co-articulation: lips move toward the next sound
  }
}

/// Mouth openness for one character (UTF-16 code unit). Script-agnostic:
/// Latin vowels, Devanagari/Telugu/other Indic vowels and vowel signs open
/// the mouth; labial consonants close it; other letters are mid; spaces and
/// punctuation relax it.
double askodoxViseme(int unit) {
  final c = String.fromCharCode(unit).toLowerCase();
  if ('aáàâä'.contains(c)) return 1.0;
  if ('oóòôö'.contains(c)) return .85;
  if ('eéèêëií'.contains(c)) return .6;
  if ('uúùûü'.contains(c)) return .45;
  if ('mbp'.contains(c)) return 0.05;
  if ('fv'.contains(c)) return .2;
  if (RegExp(r'[a-z]').hasMatch(c)) return .3;
  if (unit >= 0x0900 && unit <= 0x0DFF) {
    // Indic blocks (Devanagari 0900.., Telugu 0C00.., etc.): each block of
    // 0x80 has independent vowels at +0x04..0x14 and vowel signs at
    // +0x3E..0x4C; labials (pa/pha/ba/bha/ma) at +0x2A..0x2E.
    final o = unit & 0x7F;
    if (o >= 0x05 && o <= 0x14) return o <= 0x06 ? 1.0 : .7;
    if (o >= 0x3E && o <= 0x4C) return o == 0x3E ? 1.0 : .6;
    if (o >= 0x2A && o <= 0x2E) return .05;
    if (o >= 0x15 && o <= 0x39) return .35;
    return .15;
  }
  if (unit > 0x7F && RegExp(r'\p{L}', unicode: true).hasMatch(c)) return .4;
  return 0.05;
}

final askodoxCompanionVoiceProvider =
    ChangeNotifierProvider<AskodoxCompanionVoice>((ref) => AskodoxCompanionVoice());
