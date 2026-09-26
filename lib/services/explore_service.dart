import 'dart:convert';

import 'package:http/http.dart' as http;

class ExploreItem {
  const ExploreItem({
    required this.id,
    required this.title,
    required this.segment,
    required this.prompt,
    this.subtitle = '',
    this.price,
    this.source = 'local',
    this.destinationUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final double? price;
  final String segment;
  final String source;

  /// What selecting this item asks ASKODOX in the same chat.
  final String prompt;
  final String? destinationUrl;

  factory ExploreItem.fromJson(Map<String, dynamic> json) => ExploreItem(
        id: '${json['id']}',
        title: '${json['title'] ?? ''}',
        subtitle: '${json['subtitle'] ?? ''}',
        price: (json['price'] as num?)?.toDouble(),
        segment: '${json['segment'] ?? 'registered'}',
        source: '${json['source'] ?? 'local'}',
        prompt: '${json['prompt'] ?? json['title'] ?? ''}',
        destinationUrl: json['destination_url']?.toString(),
      );
}

/// Real Explore discovery from `GET /api/discover/explore`: registered
/// ASKODOX listings (new / used / individual / surplus / deals) and nearby
/// businesses. Any failure degrades to an empty feed, never mock data.
class ExploreService {
  const ExploreService({http.Client? client}) : _client = client;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;

  Future<List<ExploreItem>> feed({String location = '', double? latitude, double? longitude}) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/api/discover/explore').replace(queryParameters: {
            if (location.trim().isNotEmpty) 'location': location.trim(),
            if (latitude != null) 'latitude': '$latitude',
            if (longitude != null) 'longitude': '$longitude',
          }))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['items'] is! List) return const [];
      return [
        for (final item in decoded['items'] as List)
          if (item is Map<String, dynamic>) ExploreItem.fromJson(item),
      ];
    } catch (_) {
      return const [];
    } finally {
      if (_client == null) client.close();
    }
  }
}
