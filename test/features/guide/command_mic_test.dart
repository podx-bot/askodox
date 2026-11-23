import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide/command_mic.dart';
import 'package:podx/services/voice_endpointing.dart';

VoiceEndpointDecision _run(List<int> levels) {
  final ear = askodoxCommandEndpointer();
  var decision = VoiceEndpointDecision.keepRecording;
  for (final (i, level) in levels.indexed) {
    decision = ear.add(level, Duration(milliseconds: 150 * (i + 1)));
    if (decision != VoiceEndpointDecision.keepRecording) return decision;
  }
  return decision;
}

void main() {
  test('stops 2 s after the person stops talking', () {
    final levels = [...List.filled(4, 100), ...List.filled(10, 9000), ...List.filled(14, 100)];
    expect(_run(levels), VoiceEndpointDecision.stopAfterSilence);
    // A short pause (1 s) keeps listening.
    expect(_run([...List.filled(4, 100), ...List.filled(10, 9000), ...List.filled(6, 100)]),
        VoiceEndpointDecision.keepRecording);
  });

  test('gives up after 6 s when nothing was said', () {
    expect(_run(List.filled(41, 100)), VoiceEndpointDecision.stopNoSpeech);
    expect(_run(List.filled(30, 100)), VoiceEndpointDecision.keepRecording);
  });

  test('the heard words go out by themselves after 3 s', () {
    expect(askodoxCommandSendAfter, 3);
  });
}
