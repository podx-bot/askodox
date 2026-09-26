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

  test('a long recording file is uploaded complete and the full transcript is kept', () async {
    // ~60 s of 64 kbps AAC is ~480 KB; every byte must reach the backend,
    // and the multi-sentence transcript must not be cut to a word.
    final recording = List<int>.generate(480 * 1024, (i) => i % 251);
    const fullTranscript = 'నాకు విజయవాడలో రేపు ఉదయం పది గంటలకు రెండు కిలోల చికెన్ కావాలి '
        'స్కిన్‌లెస్ కర్రీ కట్ కావాలి మరియు డెలివరీ మా ఇంటికి కావాలి';
    late List<int> uploaded;
    final service = VoiceTranscriptionService(
      client: MockClient((request) async {
        final body = request.bodyBytes;
        final start = _indexOf(body, recording.sublist(0, 64));
        uploaded = start < 0 ? const [] : body.sublist(start, start + recording.length);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'transcript': fullTranscript,
            'diagnostics': {'segments': 3, 'audio_seconds': 60.2},
          })),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final text = await service.transcribeBytes(recording, locale: 'te');

    expect(uploaded, recording, reason: 'the whole file, not the last chunk');
    expect(text, fullTranscript, reason: 'never replaced by a partial/last word');
    expect(VoiceTranscriptionService.uploadTimeout, greaterThanOrEqualTo(const Duration(seconds: 60)),
        reason: 'segmented long-audio STT needs more than a short-clip timeout');
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
