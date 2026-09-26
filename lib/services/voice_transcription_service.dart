import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Main Chat speech-to-text through the backend's Sarvam-first
/// `POST /api/in-app/voice/transcribe` (see in_app_assistant.py). This is
/// the ASKODOX voice pipeline for Telugu, English and mixed speech; the
/// Android system RecognizerIntent is deliberately not used as a fallback.
class VoiceTranscriptionService {
  const VoiceTranscriptionService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  /// Long recordings (up to the 2-minute endpointer maximum) are split into
  /// several Sarvam requests server-side, so allow more than a short clip.
  static const uploadTimeout = Duration(seconds: 90);

  /// Returns the transcript, or null when the audio could not be
  /// transcribed (network error, server error, empty speech).
  Future<String?> transcribeFile(String path, {required String locale}) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      return await transcribeBytes(bytes, locale: locale);
    } catch (_) {
      return null;
    } finally {
      try {
        await File(path).delete();
      } catch (_) {
        // The recording lives in the cache dir; a leftover file is harmless.
      }
    }
  }

  Future<String?> transcribeBytes(List<int> bytes, {required String locale}) async {
    if (bytes.isEmpty) return null;
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
        ));
      request.headers['Accept'] = 'application/json';
      final streamed = await client.send(request).timeout(uploadTimeout);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) return null;
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final transcript = decoded['transcript']?.toString().trim() ?? '';
      // Sizes/counts only -- never audio or transcript text.
      debugPrint('ASKODOX voice: upload_bytes=${bytes.length} '
          'server=${decoded['diagnostics'] ?? {}} transcript_chars=${transcript.length} '
          'transcript_words=${transcript.isEmpty ? 0 : transcript.split(RegExp(r'\s+')).length}');
      return transcript.isEmpty ? null : transcript;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
