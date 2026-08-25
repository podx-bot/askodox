import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../deal_brain/domain/universal_deal.dart';

String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';
final String _guestAppUserId = 'app-guest-${DateTime.now().microsecondsSinceEpoch}';

final universalMatchRepositoryProvider = Provider<UniversalMatchRepository>((ref) {
  final user = ref.watch(authSessionProvider).user;
  return ApiUniversalMatchRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestAppUserId : _appUser(user.id),
  );
});

class UniversalMatch {
  const UniversalMatch({
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
    this.distanceKm,
    this.price,
    this.providerId,
  });

  final String id;
  final String title;
  final String? subtitle;
  final double? score;
  final double? distanceKm;
  final double? price;
  final String? providerId;

  factory UniversalMatch.fromJson(Map<String, Object?> json) => UniversalMatch(
        id: '${json['id'] ?? json['match_id'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? json['provider_name'] ?? 'Match'}',
        subtitle: json['subtitle']?.toString() ?? json['summary']?.toString(),
        score: (json['score'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        price: (json['price'] as num?)?.toDouble(),
        providerId: json['provider_id']?.toString() ?? json['user_id']?.toString(),
      );
}

class UniversalMatchResult {
  const UniversalMatchResult({required this.dealId, required this.matches});
  final String dealId;
  final List<UniversalMatch> matches;
}

abstract interface class UniversalMatchRepository {
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal);
  Future<void> acceptMatch({required String dealId, required String matchId});
}

class ApiUniversalMatchRepository implements UniversalMatchRepository {
  ApiUniversalMatchRepository(this._client, {required this.appUserId});
  final ApiClient _client;
  final String? appUserId;

  @override
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal) async {
    final userId = appUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Unable to establish an app session for matching.');
    }
    final create = await _client.post<Map<String, Object?>>(
      '/deals',
      body: _payload(deal, userId),
    );
    if (create is ApiError<Map<String, Object?>>) {
      throw StateError(create.failure.message ?? 'Unable to create requirement.');
    }
    final created = (create as ApiSuccess<Map<String, Object?>>).data;
    final dealId = '${created['id'] ?? created['deal_id'] ?? ''}';
    if (dealId.isEmpty) {
      throw StateError('Matching backend did not return a deal id.');
    }

    final response = await _client.get<Map<String, Object?>>('/deals/$dealId/matches');
    if (response is ApiError<Map<String, Object?>>) {
      throw StateError(response.failure.message ?? 'Unable to load matches.');
    }
    final data = (response as ApiSuccess<Map<String, Object?>>).data;
    final rows = (data['matches'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => UniversalMatch.fromJson(Map<String, Object?>.from(item)))
        .where((item) => item.id.isNotEmpty)
        .toList();
    return UniversalMatchResult(dealId: dealId, matches: rows);
  }

  @override
  Future<void> acceptMatch({required String dealId, required String matchId}) async {
    final result = await _client.post<Map<String, Object?>>(
      '/deals/$dealId/accept-match',
      body: {'match_id': matchId},
    );
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'Unable to accept this match.');
    }
  }

  Map<String, Object?> _payload(UniversalDeal deal, String userId) => {
        'user_id': userId,
        'raw_text': deal.rawText,
        'intent': deal.intent.name,
        'opposite_intent': deal.oppositeIntent.name,
        'subject': deal.subject,
        'category': deal.category,
        'quantity': deal.quantity,
        'unit': deal.unit,
        'price': deal.price,
        'price_basis': deal.priceBasis,
        'quality': deal.quality,
        'variant': deal.variant,
        'size': deal.size,
        'weight': deal.weight,
        'model': deal.model,
        'availability': deal.availability,
        'fulfilment': deal.fulfilment,
        'timing': deal.timing,
        'location': {
          'label': deal.location.label,
          'latitude': deal.location.latitude,
          'longitude': deal.location.longitude,
          'radius_km': deal.location.radiusKm,
        },
        'dynamic_fields': deal.dynamicFields,
        'party_a': {
          'side': deal.partyA.side.name,
          'role': deal.partyA.role,
          'action': deal.partyA.action,
        },
        'party_b': {
          'side': deal.partyB.side.name,
          'role': deal.partyB.role,
          'action': deal.partyB.action,
        },
      };
}
