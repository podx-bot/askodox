import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/reply_speech_service.dart';

void main() {
  http.Response audio(String voice) => http.Response.bytes([1, 2, 3], 200,
      headers: {'x-askodox-tts-model': 'bulbul:v3', 'x-askodox-tts-voice': voice});

  test('APK 1273: the Profile voice choice is sent with every Sarvam request', () async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      sent.add(body);
      return audio(body['voice'] as String);
    });
    final speech = ReplySpeechService(client: client);
    for (final voice in ['automatic', 'male', 'female']) {
      expect(await speech.sarvamAudio('hello', locale: 'en-IN', voice: voice), isNotNull);
    }
    expect([for (final b in sent) b['voice']], ['automatic', 'male', 'female']);
  });

  test('audio made with a different voice than asked is refused (device TTS takes over)', () async {
    final speech = ReplySpeechService(client: MockClient((_) async => audio('automatic')));
    expect(await speech.sarvamAudio('hello', locale: 'en-IN', voice: 'female'), isNull);
    final old = ReplySpeechService(client: MockClient((_) async =>
        http.Response.bytes([1], 200, headers: {'x-askodox-tts-model': 'bulbul:v3'})));
    expect(await old.sarvamAudio('hello', locale: 'en-IN', voice: 'female'), isNull,
        reason: 'a server that ignores the voice never plays the wrong gender');
    expect(await old.sarvamAudio('hello', locale: 'en-IN'), isNotNull);
  });
}
