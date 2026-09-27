import 'dart:convert';

import 'package:http/http.dart' as http;

/// Names the customer's GPS point ("Benz Circle, Vijayawada, Andhra
/// Pradesh") through the backend's `GET /api/discover/place`.
///
/// Returns null when the place could not be resolved (Maps not configured,
/// offline, provider failure). The app then keeps saying "Current location"
/// and never claims a place it did not actually resolve.
class PlaceNameService {
  const PlaceNameService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  Future<String?> resolve(double latitude, double longitude) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/api/discover/place').replace(queryParameters: {
            'latitude': '$latitude',
            'longitude': '$longitude',
          }))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['resolved'] != true) return null;
      final label = decoded['label']?.toString().trim() ?? '';
      return label.isEmpty ? null : label;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}
