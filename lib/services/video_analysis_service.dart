import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Shared evidence contract for short-video requests.
///
/// A video may contribute visual evidence and spoken evidence independently.
/// This helper combines only evidence that was actually produced; it never
/// invents a description when a frame or transcript is unavailable.
class VideoAnalysisService {
  const VideoAnalysisService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );
  final http.Client? _client;

  Future<Map<String, dynamic>?> analyze({
    required XFile video,
    required String userText,
    required String language,
  }) async {
    try {
      final bytes = await video.readAsBytes();
      if (bytes.isEmpty) return null;
      final client = _client ?? http.Client();
      try {
        final response = await client.post(
          Uri.parse('$_baseUrl/vision/analyze-video'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'video_base64': base64Encode(bytes),
            'mime_type': video.mimeType ?? 'video/mp4',
            'user_text': userText,
            'language': language,
          }),
        ).timeout(const Duration(seconds: 45));
        if (response.statusCode < 200 || response.statusCode >= 300) return null;
        final decoded = jsonDecode(response.body);
        final analysis = decoded is Map<String, dynamic> ? decoded['analysis'] : null;
        return analysis is Map<String, dynamic> ? analysis : null;
      } finally {
        if (_client == null) client.close();
      }
    } catch (_) {
      return null;
    }
  }

  String combinedRequest({
    required String userText,
    String? visualSummary,
    String? spokenTranscript,
  }) {
    final parts = <String>[userText.trim()];
    final visual = visualSummary?.trim();
    final spoken = spokenTranscript?.trim();
    if (visual != null && visual.isNotEmpty) {
      parts.add('Video visual evidence: $visual');
    }
    if (spoken != null && spoken.isNotEmpty) {
      parts.add('Video spoken evidence: $spoken');
    }
    return parts.where((part) => part.isNotEmpty).join('\n');
  }
}
