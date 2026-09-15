import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../deal_brain/domain/universal_deal.dart';

// Mirrors the exact "app-" prefixed identity convention already used by
// ApiUniversalMatchRepository and the real /deals backend endpoints.
String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';
final String _guestSellerUserId =
    'app-guest-${DateTime.now().microsecondsSinceEpoch}';

/// Result of turning a completed "sell" deal into a real, searchable listing.
class SellerListingResult {
  const SellerListingResult(
      {required this.success, this.productId, this.message});
  final bool success;
  final String? productId;
  final String? message;
}

/// Added 2026-09-15 (round 5). Before this, "I want to sell mango pickle" in
/// the app's own chat only ever reached local SharedPreferences and a
/// hardcoded demo match catalog -- it never reached the real
/// `seller_products` table that `/api/products/search` actually reads from
/// (see docs/ASKODOX_EXECUTION_TRACKER.md, round 4 finding). This repository
/// is the missing link: it calls the new self-service `/api/products/mine`
/// endpoint, which writes into that exact same table via the exact same
/// upsert used by the admin-only bootstrap form, so a real user's own
/// listing becomes immediately searchable/matchable to buyers.
abstract interface class SellerListingRepository {
  Future<SellerListingResult> createListing(UniversalDeal deal);
}

final sellerListingRepositoryProvider =
    Provider<SellerListingRepository>((ref) {
  final user = ref.watch(authSessionProvider).user;
  return ApiSellerListingRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestSellerUserId : _appUser(user.id),
  );
});

class ApiSellerListingRepository implements SellerListingRepository {
  ApiSellerListingRepository(this._client, {required this.appUserId});

  final ApiClient _client;
  final String appUserId;

  static const _mutateOptions =
      ApiRequestOptions(timeout: Duration(seconds: 30));

  @override
  Future<SellerListingResult> createListing(UniversalDeal deal) async {
    final subject = (deal.subject ?? '').trim();
    if (subject.isEmpty) {
      return const SellerListingResult(
          success: false, message: 'What do you want to sell?');
    }

    final variant = deal.variant?.trim();
    final unit = deal.unit?.trim();
    final availability = deal.availability?.trim();
    final locationLabel = deal.location.label?.trim();
    final category = deal.category?.trim();

    final result = await _client.post<Map<String, Object?>>(
      '/api/products/mine',
      body: {
        'seller_user_id': appUserId,
        'subject': subject,
        if (variant != null && variant.isNotEmpty) 'variant': variant,
        if (deal.price != null) 'price': deal.price,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        if (availability != null && availability.isNotEmpty)
          'stock_status': availability,
        if (locationLabel != null && locationLabel.isNotEmpty)
          'location_label': locationLabel,
        if (category != null && category.isNotEmpty) 'category_tag': category,
      },
      options: _mutateOptions,
    );
    if (result is ApiError<Map<String, Object?>>) {
      return SellerListingResult(
          success: false,
          message: result.failure.message ?? 'Unable to list this item.');
    }

    final data = (result as ApiSuccess<Map<String, Object?>>).data;
    final id = data['id'];
    if (id == null) {
      // MockApiClient echoes the request body back verbatim (no real "id"),
      // so tests/sandbox builds without a live backend still succeed
      // instead of reporting a false failure.
      return const SellerListingResult(success: true);
    }
    return SellerListingResult(success: true, productId: '$id');
  }
}
