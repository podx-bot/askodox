import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

String _named(Object? names, String lang) {
  if (names is Map) {
    return '${names[lang] ?? names['en'] ?? names.values.firstOrNull ?? ''}';
  }
  return '${names ?? ''}';
}

class AskodoxCatalogueItem {
  const AskodoxCatalogueItem({required this.key, required this.names, required this.unit, required this.sizes});

  final String key;
  final Map<String, String> names;
  final String unit;
  final List<String> sizes;

  String name(String lang) => _named(names, lang);

  factory AskodoxCatalogueItem.fromJson(Map<String, Object?> json) => AskodoxCatalogueItem(
        key: '${json['key']}',
        names: {for (final e in ((json['name'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        unit: '${json['unit'] ?? ''}',
        sizes: [for (final s in (json['sizes'] as List? ?? const [])) '$s'],
      );
}

class AskodoxCatalogueCategory {
  const AskodoxCatalogueCategory({required this.key, required this.names, required this.items});

  final String key;
  final Map<String, String> names;
  final List<AskodoxCatalogueItem> items;

  String name(String lang) => _named(names, lang);

  factory AskodoxCatalogueCategory.fromJson(Map<String, Object?> json) => AskodoxCatalogueCategory(
        key: '${json['key']}',
        names: {for (final e in ((json['name'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        items: [
          for (final i in (json['items'] as List? ?? const []))
            if (i is Map) AskodoxCatalogueItem.fromJson(Map<String, Object?>.from(i)),
        ],
      );
}

class AskodoxCatalogueTemplate {
  const AskodoxCatalogueTemplate({required this.key, required this.names, required this.categories});

  final String key;
  final Map<String, String> names;
  final List<AskodoxCatalogueCategory> categories;

  String name(String lang) => _named(names, lang);
  int get itemCount => categories.fold(0, (sum, c) => sum + c.items.length);

  factory AskodoxCatalogueTemplate.fromJson(Map<String, Object?> json) => AskodoxCatalogueTemplate(
        key: '${json['key']}',
        names: {for (final e in ((json['name'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        categories: [
          for (final c in (json['categories'] as List? ?? const []))
            if (c is Map) AskodoxCatalogueCategory.fromJson(Map<String, Object?>.from(c)),
        ],
      );
}

/// One item the seller reviewed: their size, price, stock and photo.
class AskodoxCatalogueEntry {
  AskodoxCatalogueEntry({required this.item, required this.size, this.price, this.inStock = true, this.photoBase64});

  final AskodoxCatalogueItem item;
  String size;
  double? price;
  bool inStock;
  String? photoBase64;

  Map<String, Object?> toJson() => {
        'item_key': item.key,
        'size': size,
        if (price != null) 'price': price,
        'stock_status': inStock ? 'IN_STOCK' : 'OUT_OF_STOCK',
        if (photoBase64 != null) 'photo_base64': photoBase64,
      };
}

class AskodoxCataloguePublishResult {
  const AskodoxCataloguePublishResult({this.published = 0, this.drafts = 0, this.skipped = 0, this.error});

  final int published;
  final int drafts;
  final int skipped;

  /// sign_in | shop_details | unavailable | failed
  final String? error;
  bool get ok => error == null;
}

/// Ready-made seller catalogues (GET /api/catalog/templates...) and the
/// seller's reviewed publish -- the backend creates ordinary listings.
class AskodoxCatalogueRepository {
  const AskodoxCatalogueRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  Future<List<({String key, Map<String, String> names, int items})>> templates() async {
    final result = await _client.get<Map<String, Object?>>('/api/catalog/templates');
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      return [
        for (final t in (data['items'] as List? ?? const []))
          if (t is Map)
            (
              key: '${t['key']}',
              names: {for (final e in ((t['name'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
              items: (t['items'] as num?)?.toInt() ?? 0,
            ),
      ];
    }
    return const [];
  }

  Future<AskodoxCatalogueTemplate?> template(String key) async {
    final result = await _client.get<Map<String, Object?>>('/api/catalog/templates/$key');
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) return AskodoxCatalogueTemplate.fromJson(data);
    return null;
  }

  Future<AskodoxCataloguePublishResult> publish(
    String key,
    List<AskodoxCatalogueEntry> entries, {
    String? businessName,
    String? businessAddress,
    String language = 'en',
  }) async {
    if (authToken == null || authToken!.isEmpty) return const AskodoxCataloguePublishResult(error: 'sign_in');
    final result = await _client.post<Map<String, Object?>>(
      '/api/catalog/templates/$key/publish',
      body: {
        'items': [for (final e in entries) e.toJson()],
        if (businessName != null && businessName.trim().isNotEmpty) 'business_name': businessName.trim(),
        if (businessAddress != null && businessAddress.trim().isNotEmpty) 'business_address': businessAddress.trim(),
        'language': language,
      },
      options: ApiRequestOptions(authToken: authToken, timeout: const Duration(seconds: 60)),
    );
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      return AskodoxCataloguePublishResult(
        published: (data['published'] as List? ?? const []).length,
        drafts: (data['drafts'] as List? ?? const []).length,
        skipped: (data['skipped'] as List? ?? const []).length,
      );
    }
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    return AskodoxCataloguePublishResult(
      error: switch (failure.statusCode) {
        401 => 'sign_in',
        422 => 'shop_details',
        404 => 'unavailable',
        _ => 'failed',
      },
    );
  }
}

final askodoxCatalogueRepositoryProvider = Provider<AskodoxCatalogueRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AskodoxCatalogueRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});
