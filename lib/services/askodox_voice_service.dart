import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// In-app microphone capture and Sarvam-backed voice pipeline for ASKODOX
/// Main Chat.
///
/// This replaces the external Google speech-recognition popup
/// (`RecognizerIntent.ACTION_RECOGNIZE_SPEECH`) with ASKODOX's own recording
/// control -- recording only starts and stops when this class is told to,
/// so natural Telugu/English/mixed speech is never cut off after 1-2
/// seconds by a platform silence timer. Captured audio is sent through the
/// existing production Sarvam Saaras v3 STT backend
/// (`POST /api/in-app/voice/transcribe`), and replies are played through the
/// existing Sarvam Bulbul v3 TTS backend (`POST /api/in-app/voice/speak`).
/// Both backends already exist and are used by the WhatsApp bot; no new
/// speech service is created here.
class AskodoxVoiceException implements Exception {
  const AskodoxVoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AskodoxVoiceService {
  AskodoxVoiceService({
    http.Client? client,
    AudioRecorder? recorder,
    AudioPlayer? player,
  })  : _client = client,
        _providedRecorder = recorder,
        _providedPlayer = player;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;
  final AudioRecorder? _providedRecorder;
  final AudioPlayer? _providedPlayer;
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  String? _recordingPath;

  // Constructed lazily, only on first actual use -- not in the constructor
  // -- so simply creating an AskodoxVoiceService (e.g. in a widget's State)
  // never touches the microphone/audio platform plugins until the user
  // actually records or plays something.
  AudioRecorder get _rec => _recorder ??= _providedRecorder ?? AudioRecorder();
  AudioPlayer get _ply => _player ??= _providedPlayer ?? AudioPlayer();

  /// Starts in-app microphone recording. Throws [AskodoxVoiceException] if
  /// microphone permission is unavailable/denied.
  Future<void> startListening() async {
    final hasPermission = await _rec.hasPermission();
    if (!hasPermission) {
      throw const AskodoxVoiceException('microphone_permission_denied');
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/askodox_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _recordingPath = path;
  }

  /// Stops recording (ASKODOX itself decides when speech is complete, not a
  /// fixed platform silence timeout) and transcribes it through the
  /// existing Sarvam voice-assistant backend. Returns null when nothing
  /// usable was captured or transcribed -- callers should treat that as "I
  /// could not hear that" rather than a hard error.
  Future<String?> stopAndTranscribe({required String locale}) async {
    final path = await _rec.stop();
    final recordedPath = path ?? _recordingPath;
    _recordingPath = null;
    if (recordedPath == null) return null;
    final file = File(recordedPath);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return await _transcribe(bytes, locale: locale);
    } finally {
      unawaited(file.exists().then((exists) {
        if (exists) file.delete();
      }));
    }
  }

  /// Discards an in-progress recording without transcribing it.
  Future<void> cancel() async {
    if (await _rec.isRecording()) {
      await _rec.cancel();
    }
    _recordingPath = null;
  }

  Future<String?> _transcribe(List<int> bytes, {required String locale}) async {
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/in-app/voice/transcribe'),
      )
        ..fields['locale'] = locale
        ..files.add(http.MultipartFile.fromBytes(
          'audio',
          bytes,
          filename: 'askodox_voice.m4a',
          contentType: MediaType('audio', 'm4a'),
        ));
      final streamed = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final transcript = (decoded['transcript'] as String?)?.trim();
      return (transcript == null || transcript.isEmpty) ? null : transcript;
    } catch (_) {
      return null;
    } finally {
      if (ownClient) client.close();
    }
  }

  /// Plays [text] through the existing Sarvam Bulbul v3 voice reply
  /// backend. If the network call or local playback fails,
  /// [onSarvamUnavailable] is invoked so the caller can fall back to
  /// Android system TTS -- Sarvam remains the primary reply path, system
  /// TTS is only a resilience fallback, never the default.
  Future<bool> speak(
    String text, {
    required Future<void> Function() onSarvamUnavailable,
  }) async {
    final audioBytes = await _fetchSpeech(text);
    if (audioBytes == null || audioBytes.isEmpty) {
      await onSarvamUnavailable();
      return false;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/askodox_reply_${DateTime.now().microsecondsSinceEpoch}.ogg');
      await file.writeAsBytes(audioBytes);
      await _ply.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      await onSarvamUnavailable();
      return false;
    }
  }

  Future<List<int>?> _fetchSpeech(String text) async {
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/voice/speak'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    } finally {
      if (ownClient) client.close();
    }
  }

  void dispose() {
    _recorder?.dispose();
    _player?.dispose();
  }
}
