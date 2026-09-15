import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/matching/data/universal_match_repository.dart';

/// Searches the real, seller-supplied `seller_products` catalog (seeded via
/// WhatsApp price-list confirmation or the temporary manual
/// `/admin/products/new` tool) instead of the hardcoded
/// `DemoNaturalMatchCatalog` sandbox data.
///
/// Mirrors `SponsoredAdsService`'s pattern deliberately: same base-URL
/// constant/override, same "any failure degrades to an empty list" behavior
/// (so a slow or unreachable backend never blocks or crashes the chat), and
/// the same injectable `http.Client` for testing.
class RealProductMatchService {
  const RealProductMatchService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl = 'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment('ASKODOX_API_BASE_URL', defaultValue: _defaultBaseUrl);

  final http.Client? _client;

  Future<List<UniversalMatch>> search(String query, {int limit = 10}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];

    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('$_baseUrl/api/products/search').replace(queryParameters: {
              'q': clean,
              'limit': '$limit',
            }),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['items'] is! List) return const [];
      return [
        for (final entry in decoded['items'] as List)
          if (entry is Map<String, dynamic>) UniversalMatch.fromJson(entry),
      ];
    } catch (_) {
      return const [];
    } finally {
      if (ownClient) client.close();
    }
  }
}