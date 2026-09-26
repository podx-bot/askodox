import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Main Chat reply voice via the backend's existing Sarvam Bulbul v3 TTS
/// (`POST /api/in-app/voice/speak`). Returns the audio only when the backend
/// confirms Bulbul produced it; otherwise null, and the app falls back to
/// device TextToSpeech (never labelled as Sarvam).
class ReplySpeechService {
  const ReplySpeechService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  Future<Uint8List?> sarvamAudio(String text, {required String locale}) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/voice/speak'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'text': clean, 'locale': locale}),
          )
          .timeout(const Duration(seconds: 15));
      final model = response.headers['x-askodox-tts-model'] ?? '';
      if (response.statusCode != 200 ||
          !model.toLowerCase().startsWith('bulbul') ||
          response.bodyBytes.isEmpty) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
