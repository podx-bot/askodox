import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Main Chat reply voice via the backend (`POST /api/in-app/voice/speak`):
/// an ElevenLabs human voice first, Sarvam Bulbul v3 when ElevenLabs is off or
/// failing. Returns the audio only when the backend confirms one of those
/// engines produced it; otherwise null, and the app falls back to device
/// TextToSpeech.
class ReplySpeechService {
  const ReplySpeechService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  /// [voice]: the Profile choice (automatic | male | female). Audio is used
  /// only when the server confirms it was made with that voice.
  /// [timeout]: how long to wait for the server's voice before the caller falls
  /// back to the phone's own voice (guides pass a short one so text and voice
  /// stay together).
  /// [engine]: '' = ElevenLabs first, Sarvam when it fails; 'elevenlabs' / 'sarvam' = only that engine (owner
  /// 2026-11-21: the parts of ONE reply keep the voice of its first part -- never two voices in one answer). The
  /// engine that made the audio is readable with [askodoxAudioEngine].
  Future<Uint8List?> sarvamAudio(String text,
      {required String locale,
      String voice = 'automatic',
      Duration timeout = const Duration(seconds: 15),
      String engine = '',
      String purpose = ''}) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/voice/speak'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': clean,
              'locale': locale,
              'voice': voice,
              if (engine.isNotEmpty) 'engine': engine,
              // 'guide' = a fixed page-guide line: the server records it once and plays it to everyone.
              if (purpose.isNotEmpty) 'purpose': purpose,
            }),
          )
          .timeout(timeout);
      final model = response.headers['x-askodox-tts-model'] ?? '';
      if (response.statusCode != 200 ||
          !askodoxServerVoiceModel(model) ||
          response.bodyBytes.isEmpty ||
          (voice != 'automatic' && response.headers['x-askodox-tts-voice'] != voice)) {
        return null;
      }
      final audio = response.bodyBytes;
      askodoxAudioEngine[audio] = askodoxEngineOfModel(model);
      return audio;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// Engines the app accepts reply audio from (ElevenLabs `eleven_*`, Sarvam `bulbul*`).
bool askodoxServerVoiceModel(String model) {
  final m = model.toLowerCase();
  return m.startsWith('bulbul') || m.startsWith('eleven');
}

/// Which engine made a reply audio ('elevenlabs' / 'sarvam'); empty for audio from elsewhere.
final Expando<String> askodoxAudioEngine = Expando<String>('askodoxAudioEngine');

/// 'elevenlabs' for `eleven_*` models, 'sarvam' for `bulbul*`, else ''.
String askodoxEngineOfModel(String model) {
  final m = model.toLowerCase();
  if (m.startsWith('eleven')) return 'elevenlabs';
  if (m.startsWith('bulbul')) return 'sarvam';
  return '';
}
