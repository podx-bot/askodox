import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/voice_transcription_service.dart';

void main() {
  test('uploads audio to the Sarvam-first ASKODOX endpoint and returns Telugu text', () async {
    late http.BaseRequest seen;
    late String seenBody;
    final service = VoiceTranscriptionService(
      client: MockClient((request) async {
        seen = request;
        seenBody = latin1.decode(request.bodyBytes);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'transcript': 'నాకు చికెన్ కావాలి', 'provider': 'sarvam'})),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final text = await service.transcribeBytes([1, 2, 3], locale: 'te');

    expect(text, 'నాకు చికెన్ కావాలి');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/in-app/voice/transcribe');
    expect(seenBody, contains('name="audio"; filename="askodox_voice.m4a"'));
    expect(seenBody, contains('name="locale"'));
  });

  test('server failure, empty transcript or empty audio yield null (no silent fallback)', () async {
    final failing = VoiceTranscriptionService(
        client: MockClient((_) async => http.Response('{"detail":"x"}', 422)));
    final empty = VoiceTranscriptionService(
        client: MockClient((_) async => http.Response('{"transcript":"  "}', 200)));

    expect(await failing.transcribeBytes([1], locale: 'te'), isNull);
    expect(await empty.transcribeBytes([1], locale: 'en'), isNull);
    expect(await empty.transcribeBytes(const [], locale: 'en'), isNull);
  });
}
