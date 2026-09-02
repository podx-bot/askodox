import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../deal_brain/domain/universal_deal.dart';
import 'demo_natural_match_catalog.dart';

String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';
final String _guestAppUserId = 'app-guest-${DateTime.now().microsecondsSinceEpoch}';

final universalMatchRepositoryProvider = Provider<UniversalMatchRepository>((ref) {
  final user = ref.watch(authSessionProvider).user;
  return ApiUniversalMatchRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestAppUserId : _appUser(user.id),
  );
});

class DealNeedsDetailsException implements Exception {
  const DealNeedsDetailsException({
    required this.domain,
    required this.action,
    required this.missingFields,
  });

  final String domain;
  final String action;
  final List<String> missingFields;

  @override
  String toString() => missingFields.isEmpty
      ? 'More details are required before matching.'
      : 'Please complete: ${missingFields.join(', ')}';
}

class UniversalMatch {
  const UniversalMatch({
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
    this.distanceKm,
    this.price,
    this.providerId,
    this.trustScore,
    this.availabilityScore,
  });

  final String id;
  final String title;
  final String? subtitle;
  final double? score;
  final double? distanceKm;
  final double? price;
  final String? providerId;
  final double? trustScore;
  final double? availabilityScore;

  double get totalValueScore {
    final backend = (score ?? 0).clamp(0, 100).toDouble();
    final trust = (trustScore ?? 50).clamp(0, 100).toDouble();
    final available = (availabilityScore ?? 50).clamp(0, 100).toDouble();
    final distance = distanceKm;
    final distanceValue = distance == null
        ? 50.0
        : (100 - (distance.clamp(0, 50).toDouble() * 2)).clamp(0, 100).toDouble();

    return (backend * 0.55) +
        (trust * 0.20) +
        (available * 0.15) +
        (distanceValue * 0.10);
  }

  factory UniversalMatch.fromJson(Map<String, Object?> json) => UniversalMatch(
        id: '${json['id'] ?? json['match_id'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? json['provider_name'] ?? 'Match'}',
        subtitle: json['subtitle']?.toString() ?? json['summary']?.toString(),
        score: (json['score'] as num?)?.toDouble(),
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        price: (json['price'] as num?)?.toDouble(),
        providerId: json['provider_id']?.toString() ?? json['user_id']?.toString(),
        trustScore: ((json['trust_score'] ?? json['trust']) as num?)?.toDouble(),
        availabilityScore:
            ((json['availability_score'] ?? json['availability_fit']) as num?)?.toDouble(),
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

  static const _createOptions = ApiRequestOptions(
    timeout: Duration(seconds: 30),
  );

  static const _matchOptions = ApiRequestOptions(
    timeout: Duration(seconds: 30),
    retryCount: 1,
  );

  @override
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal) async {
    final userId = appUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Unable to establish an app session for matching.');
    }

    // Railway can need more than the global 15 second API timeout while a
    // service is waking up. Creating a real deal is not retried automatically
    // because it is a POST and we must not risk duplicate requirements.
    final create = await _client.post<Map<String, Object?>>(
      '/deals',
      body: _payload(deal, userId),
      options: _createOptions,
    );
    if (create is ApiError<Map<String, Object?>>) {
      final failure = create.failure;
      if (failure.statusCode == 422) {
        final missing = (failure.header('x-askodox-missing-fields') ?? '')
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        throw DealNeedsDetailsException(
          domain: failure.header('x-askodox-intent-domain') ?? '',
          action: failure.header('x-askodox-intent-action') ?? '',
          missingFields: missing,
        );
      }
      throw StateError(failure.message ?? 'Unable to create requirement.');
    }

    final created = (create as ApiSuccess<Map<String, Object?>>).data;
    var dealId = '${created['id'] ?? created['deal_id'] ?? ''}';

    // Demo data is allowed only when the app is explicitly using MockApiClient.
    // A live backend must never be replaced by fake matches, because that hides
    // genuine no-match, validation, and provider-availability states.
    if (dealId.isEmpty && _client is MockApiClient) {
      dealId = 'local-${DateTime.now().microsecondsSinceEpoch}';
      final demoMatches = DemoNaturalMatchCatalog.forDeal(deal, enabled: true)
        ..sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
      return UniversalMatchResult(dealId: dealId, matches: demoMatches);
    }

    if (dealId.isEmpty) {
      throw StateError('Matching backend did not return a deal id.');
    }

    // Match lookup is a safe GET, so retry once after a cold-start/network
    // timeout. A successful empty response then flows to the real no-match UI.
    final response = await _client.get<Map<String, Object?>>(
      '/deals/$dealId/matches',
      options: _matchOptions,
    );
    if (response is ApiError<Map<String, Object?>>) {
      throw StateError(response.failure.message ?? 'Unable to load matches.');
    }

    final data = (response as ApiSuccess<Map<String, Object?>>).data;
    final rows = (data['matches'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => UniversalMatch.fromJson(Map<String, Object?>.from(item)))
        .where((item) => item.id.isNotEmpty)
        .toList();

    rows.sort((a, b) => b.totalValueScore.compareTo(a.totalValueScore));
    return UniversalMatchResult(dealId: dealId, matches: rows);
  }

  @override
  Future<void> acceptMatch({required String dealId, required String matchId}) async {
    if (dealId.startsWith('local-') || matchId.startsWith('demo-')) return;

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
