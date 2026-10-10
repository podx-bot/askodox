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
      ..._n(45, 150),
    ];
    final d = _run(e, levels);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
    expect(d.length, greaterThan(3 + 300), reason: 'stopped only after the full 60 s of speech');
  });

  test('genuine silence after speech stops the turn', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 150), ..._n(20, 4000), ..._n(45, 150)]);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
    expect(d.length, 3 + 20 + 40, reason: 'only after 8 s of silence (safety limit)');
  });

  test('noisy room: background noise is not speech and does not block silence detection', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 1500), ..._n(25, 9000), ..._n(45, 1600)]);
    expect(d.last, VoiceEndpointDecision.stopAfterSilence);
  });

  test('APK 1312: a 5 s thinking pause and a short phrase never end the turn', () {
    final e = AskodoxVoiceEndpointer();
    // "I want..." (1 s) -- 5 s pause -- the rest of the request (3 s) -- 5 s pause.
    final levels = [..._n(3, 150), ..._n(5, 3000), ..._n(25, 200), ..._n(15, 3000), ..._n(25, 200)];
    final d = _run(e, levels);
    expect(d.every((x) => x == VoiceEndpointDecision.keepRecording), isTrue);
  });

  test('a cough is not speech that arms the silence stop', () {
    final e = AskodoxVoiceEndpointer();
    final d = _run(e, [..._n(3, 150), ..._n(2, 6000), ..._n(50, 150)]);
    expect(d.contains(VoiceEndpointDecision.stopAfterSilence), isFalse);
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

  test('Main Chat (until Stop): long silence or no speech never ends the turn; only the max-duration cap does', () {
    final silent = _run(AskodoxVoiceEndpointer.untilStop(), _n(500, 150)); // 100 s of nothing
    expect(silent.every((x) => x == VoiceEndpointDecision.keepRecording), isTrue);
    final paused = _run(AskodoxVoiceEndpointer.untilStop(),
        [..._n(3, 150), ..._n(20, 5000), ..._n(200, 150), ..._n(20, 5000)]); // 40 s pause mid-speech
    expect(paused.every((x) => x == VoiceEndpointDecision.keepRecording), isTrue);
    final runaway = _run(AskodoxVoiceEndpointer.untilStop(), _n(700, 5000));
    expect(runaway.last, VoiceEndpointDecision.stopMaxDuration);
    expect(runaway.length, 600, reason: 'two-minute safety cap');
  });

  test('one draft: typed words + transcript, no duplication, nothing dropped', () {
    expect(askodoxMergeVoiceDraft('', 'నాకు AC కావాలి'), 'నాకు AC కావాలి');
    expect(askodoxMergeVoiceDraft('1.5 ton', 'split AC under 40000'), '1.5 ton split AC under 40000');
    expect(askodoxMergeVoiceDraft('AC', 'AC repair near me'), 'AC repair near me');
    expect(askodoxMergeVoiceDraft('  bill  ', ''), 'bill');
  });
}
