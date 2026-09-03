import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class VisionApiService {
  const VisionApiService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl =
      'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client? _client;

  Future<Map<String, dynamic>?> analyze({
    required XFile image,
    required String userText,
    required String language,
  }) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
      final mimeType = _mimeType(image);
      final client = _client ?? http.Client();
      try {
        final response = await client
            .post(
              Uri.parse('$_baseUrl/vision/analyze'),
              headers: const {'content-type': 'application/json'},
              body: jsonEncode({
                'image_base64': base64Encode(bytes),
                'mime_type': mimeType,
                'user_text': userText,
                'language': language,
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 300) return null;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) return null;
        if (decoded['status'] != 'success') return null;
        final analysis = decoded['analysis'];
        return analysis is Map<String, dynamic> ? analysis : null;
      } finally {
        if (_client == null) client.close();
      }
    } catch (_) {
      return null;
    }
  }

  String _mimeType(XFile image) {
    final direct = image.mimeType?.trim().toLowerCase();
    if (direct != null && direct.startsWith('image/')) return direct;
    final lower = image.name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }
}
