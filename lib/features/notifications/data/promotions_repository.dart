import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One reviewed promotion delivered to this customer. Compact / quarter /
/// half card only; paid ones always carry a "Sponsored" disclosure.
class AskodoxPromotion {
  const AskodoxPromotion({
    required this.deliveryId,
    required this.title,
    required this.body,
    this.size = 'compact',
    this.imageUrl,
    this.ctaLabel,
    this.deepLink,
    this.disclosure,
    this.advertiser,
  });

  final int deliveryId;
  final String title;
  final String body;
  final String size;
  final String? imageUrl;
  final String? ctaLabel;
  final String? deepLink;
  final String? disclosure;
  final String? advertiser;

  static AskodoxPromotion? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['delivery_id'];
    final title = '${json['title'] ?? ''}'.trim();
    if (id is! num || title.isEmpty) return null;
    String? opt(String key) {
      final v = '${json[key] ?? ''}'.trim();
      return v.isEmpty ? null : v;
    }

    final size = opt('size');
    return AskodoxPromotion(
      deliveryId: id.toInt(),
      title: title,
      body: '${json['body'] ?? ''}',
      size: const {'compact', 'quarter', 'half'}.contains(size) ? size! : 'compact',
      imageUrl: opt('image_url')?.startsWith('https://') == true ? opt('image_url') : null,
      ctaLabel: opt('cta_label'),
      deepLink: opt('deep_link'),
      disclosure: opt('disclosure'),
      advertiser: opt('advertiser'),
    );
  }
}

class PromotionsRepository {
  PromotionsRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  bool get _signedIn => authToken != null && authToken!.isNotEmpty;
  ApiRequestOptions get _auth => ApiRequestOptions(timeout: const Duration(seconds: 20), authToken: authToken);

  Future<List<AskodoxPromotion>> mine() async {
    if (!_signedIn) return const [];
    final result = await _client.get<Map<String, Object?>>('/api/me/promotions', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) return const [];
    return [
      for (final item in (result.data['items'] as List? ?? const []))
        if (AskodoxPromotion.fromJson(item) case final promo?) promo,
    ];
  }

  /// open / click / dismiss -- best effort, never blocks the UI.
  Future<void> track(int deliveryId, String action) async {
    if (!_signedIn) return;
    try {
      await _client.post<Map<String, Object?>>('/api/me/promotions/$deliveryId/$action', options: _auth);
    } catch (_) {}
  }
}

final promotionsRepositoryProvider = Provider<PromotionsRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return PromotionsRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final askodoxPromotionsProvider = FutureProvider.autoDispose<List<AskodoxPromotion>>((ref) async {
  try {
    return await ref.watch(promotionsRepositoryProvider).mine();
  } catch (_) {
    return const [];
  }
});
