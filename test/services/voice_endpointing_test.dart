import 'package:flutter_test/flutter_test.dart';
import 'package:podx/services/voice_endpointing.dart';

List<VoiceEndpointDecision> _run(AskodoxVoiceEndpointer e, List<int> levels) {
  final decisions = <VoiceEndpointDecision>[];
  for (var i = 0; i < levels.length; i++) {
    final d = e.add(levels[i], Duration(milliseconds: 200 * (i + 1)));
    decisions.add(d);
    if (d != VoiceEndpointDecision.keepRecording) break;
  }
  return decisions;
}

List<int> _n(int count, int level) => List.filled(count, level);

void main() {
  test('soft speech in a quiet room is heard (Build 1237 threshold was 1800)', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 120), ..._n(60, 900)]); // 12 s of soft speech
    expect(d.last, VoiceEndpointDecision.keepRecording);
    expect(e.heardSpeech, isTrue);
  });

  test('pauses shorter than the silence window never end the turn', () {
    final e = AskodoxVoiceEndpointer();
    final levels = [
      ..._n(3, 150),
      for (var i = 0; i < 8; i++) ...[..._n(15, 4000), ..._n(12, 200)], // 2.4 s pauses
    ];
    expect(_run(e, levels).last, VoiceEndpointDecision.keepRecording);
  });

  test('35 s of continuous Telugu speech with short pauses keeps recording (Build 1241)', () {
    final e = AskodoxVoiceEndpointer();
    final levels = [
      ..._n(3, 150),
      // 35 s: 5 s phrases with 1 s breaths, like a long Telugu request.
      for (var i = 0; i < 6; i++) ...[..._n(25, 2500), ..._n(5, 300)],
      ..._n(10, 2500),
    ];
    final d = _run(e, levels);
    expect(d.length, levels.length, reason: 'no decision other than keepRecording for 35 s');
    expect(d.every((x) => x == VoiceEndpointDecision.keepRecording), isTrue);
  });

  test('60 s of speech keeps recording, then genuine silence ends it once', () {
    final e = AskodoxVoiceEndpointer();
    final levels = [
      ..._n(3, 150),
      for (var i = 0; i < 10; i++) ...[..._n(25, 2200), ..._n(5, 250)], // 60 s
      ..._n(20, 150),
    ];
    final d = _run(e, levels);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
    expect(d.length, greaterThan(3 + 300), reason: 'stopped only after the full 60 s of speech');
  });

  test('genuine silence after speech stops the turn', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 150), ..._n(20, 4000), ..._n(20, 150)]);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
    expect(d.length, 3 + 20 + 15, reason: 'exactly 3 s of silence');
  });

  test('noisy room: background noise is not speech and does not block silence detection', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 1500), ..._n(25, 9000), ..._n(30, 1600)]);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
  });

  test('no speech at all ends only after the long timeout', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, _n(200, 150));
    expect(d.last, VoiceEndpointDecision.stopNoSpeech);
    expect(d.length, 75, reason: '15 seconds');
  });

  test('a two-minute cap bounds a runaway recording', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 150), ..._n(700, 5000)]);
    expect(d.last, VoiceEndpointDecision.stopMaxDuration);
  });

  test('reply language follows the reply, then the question, then the UI', () {
    expect(askodoxSpeechLanguage(reply: 'సరే', userText: 'hi', uiTelugu: false), 'te');
    expect(askodoxSpeechLanguage(reply: 'Okay', userText: 'నమస్తే', uiTelugu: true), 'en');
    expect(askodoxSpeechLanguage(reply: '👍', userText: 'నమస్తే', uiTelugu: false), 'te');
    expect(askodoxSpeechLanguage(reply: '👍', userText: '42', uiTelugu: true), 'te');
  });
}
