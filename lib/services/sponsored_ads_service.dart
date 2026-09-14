import 'dart:convert';

import 'package:http/http.dart' as http;

class SponsoredAdItem {
  const SponsoredAdItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl = '',
    this.ctaType = 'shop',
    this.ctaTarget = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String ctaType;
  final String ctaTarget;

  factory SponsoredAdItem.fromJson(Map<String, dynamic> json) => SponsoredAdItem(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
        imageUrl: (json['image_url'] ?? '').toString(),
        ctaType: (json['cta_type'] ?? 'shop').toString(),
        ctaTarget: (json['cta_target'] ?? '').toString(),
      );

  String? get route {
    final target = ctaTarget.trim();
    if (target.isEmpty) return null;
    return ctaType.trim().toLowerCase() == 'product' ? '/product/$target' : '/shop/$target';
  }
}

class SponsoredAdsService {
  const SponsoredAdsService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl = 'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment('ASKODOX_API_BASE_URL', defaultValue: _defaultBaseUrl);

  final http.Client? _client;

  Future<List<SponsoredAdItem>> fetch({String placement = 'explore_top'}) async {
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('$_baseUrl/api/discover/sponsored').replace(queryParameters: {'placement': placement}),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['items'] is! List) return const [];
      return [
        for (final entry in decoded['items'] as List)
          if (entry is Map<String, dynamic>) SponsoredAdItem.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    } finally {
      if (ownClient) client.close();
    }
  }
}
