import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/askodox_voice_service.dart';

void main() {
  // These tests cover only the network contract of the Sarvam Bulbul v3
  // voice-reply call and its fallback-triggering behaviour. Actual on-device
  // audio playback of a successful response requires real platform audio
  // plugins and is verified by real-phone testing, not a host-only unit
  // test -- see the PR's real-phone acceptance checklist.

  test('speak() posts the reply text to the existing Sarvam voice endpoint '
      'and falls back to system TTS when the backend fails', () async {
    late Uri requestedUri;
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      requestedUri = request.url;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('synthesis failed', 502);
    });
    final service = AskodoxVoiceService(client: client);
    var fallbackCalled = false;

    final played = await service.speak(
      'Your order is confirmed.',
      onSarvamUnavailable: () async {
        fallbackCalled = true;
      },
    );

    expect(requestedUri.path, '/api/in-app/voice/speak');
    expect(body['text'], 'Your order is confirmed.');
    expect(played, isFalse);
    expect(fallbackCalled, isTrue);
  });

  test('speak() treats an empty audio response as unavailable and falls '
      'back instead of trying to play nothing', () async {
    final client = MockClient((request) async {
      return http.Response.bytes(const [], 200);
    });
    final service = AskodoxVoiceService(client: client);
    var fallbackCalled = false;

    final played = await service.speak(
      'Namaste',
      onSarvamUnavailable: () async {
        fallbackCalled = true;
      },
    );

    expect(played, isFalse);
    expect(fallbackCalled, isTrue);
  });

  test('speak() falls back when the voice backend call throws (network '
      'error, timeout, etc.) instead of propagating the exception', () async {
    final client = MockClient((request) async {
      throw const SocketExceptionStub();
    });
    final service = AskodoxVoiceService(client: client);
    var fallbackCalled = false;

    final played = await service.speak(
      'Namaste',
      onSarvamUnavailable: () async {
        fallbackCalled = true;
      },
    );

    expect(played, isFalse);
    expect(fallbackCalled, isTrue);
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
