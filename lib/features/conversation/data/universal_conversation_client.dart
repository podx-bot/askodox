import 'dart:convert';
import 'dart:io';

class UniversalConversationClient {
  const UniversalConversationClient({
    this.baseUrl = '',
    this.endpointPath = '/debug/message',
    this.useProductionFallback = true,
  });

  static const productionBaseUrl =
      'https://podx-ai-connect-production-3279.up.railway.app';

  static const _configuredBaseUrl = String.fromEnvironment(
    'PODX_API_BASE_URL',
  );
  static const _legacyConfiguredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  final String baseUrl;
  final String endpointPath;
  final bool useProductionFallback;

  String get resolvedBaseUrl {
    final explicit = baseUrl.trim();
    if (explicit.isNotEmpty) return explicit;
    if (_configuredBaseUrl.trim().isNotEmpty) {
      return _configuredBaseUrl.trim();
    }
    if (_legacyConfiguredBaseUrl.trim().isNotEmpty) {
      return _legacyConfiguredBaseUrl.trim();
    }
    return useProductionFallback ? productionBaseUrl : '';
  }

  bool get isConfigured => resolvedBaseUrl.isNotEmpty;

  Future<String> send({
    required String senderId,
    required String message,
  }) async {
    final root = Uri.tryParse(resolvedBaseUrl);
    if (root == null || !root.hasScheme || root.host.isEmpty) {
      throw StateError(
        'ASKODOX conversation server is not configured for this build.',
      );
    }

    final uri = root.replace(
      path: _joinPaths(root.path, endpointPath),
      query: null,
      fragment: null,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(uri).timeout(
            const Duration(seconds: 12),
          );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(
        jsonEncode({
          'sender_mobile': senderId,
          'message': message,
        }),
      );

      final response = await request.close().timeout(
            const Duration(seconds: 25),
          );
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Conversation server returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Conversation response is not an object.');
      }
      final reply = decoded['reply']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        throw const FormatException('Conversation response did not include reply.');
      }
      return reply;
    } finally {
      client.close(force: true);
    }
  }

  static String _joinPaths(String basePath, String childPath) {
    final left = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final right = childPath.startsWith('/') ? childPath : '/$childPath';
    return '$left$right';
  }
}
