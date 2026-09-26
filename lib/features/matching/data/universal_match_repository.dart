import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../deal_brain/domain/universal_deal.dart';
import '../domain/sandbox_party_gate.dart';
import 'demo_natural_match_catalog.dart';

String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';
final String _guestAppUserId = 'app-guest-${DateTime.now().microsecondsSinceEpoch}';

String _acceptanceKey(String dealId, String matchId) => '$dealId::$matchId';

class SandboxMatchAcceptanceStore {
  final Set<String> _accepted = <String>{};

  void accept({required String dealId, required String matchId}) {
    _accepted.add(_acceptanceKey(dealId, matchId));
  }

  bool isAccepted({required String dealId, required String matchId}) =>
      _accepted.contains(_acceptanceKey(dealId, matchId));

  void clear({required String dealId, required String matchId}) {
    _accepted.remove(_acceptanceKey(dealId, matchId));
  }
}

final universalMatchRepositoryProvider = Provider<UniversalMatchRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  final user = session.user;
  return ApiUniversalMatchRepository(
    ref.watch(apiClientProvider),
    appUserId: user == null ? _guestAppUserId : _appUser(user.id),
    // Added 2026-09-16 (round 14): the real signed session token from
    // POST /onboarding/otp/verify (see session_tokens.py on the backend).
    // This is an urgent fix -- round 13 required this same token on
    // POST /deals and POST /deals/{id}/accept-match (see universal_deals.py),
    // but this repository (the app's main "publish a request and get
    // matched" flow, used by universal_match_screen.dart and
    // home_screen.dart) was never updated to send it, so every real
    // signed-in user's request/accept calls started failing with "Sign in
    // required" the moment round 13 merged. A guest (user == null) still
    // has no token; that call now correctly gets a 401 instead of
    // silently acting as a throwaway identity, matching every other
    // repository's fix (orders, self-service listings, deal chat).
    authToken: user == null ? null : session.tokenPlaceholder,
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
    this.source = 'local',
    this.imageUrl,
    this.locationLabel,
    this.availability,
    this.destinationUrl,
    this.disclosure,
    this.affiliate = false,
    this.ratingAverage,
    this.reviewCount = 0,
    this.segment,
    this.sourceName,
    this.duration,
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
  final String source;
  final String? imageUrl;
  final String? locationLabel;
  final String? availability;
  final String? destinationUrl;
  final String? disclosure;
  final bool affiliate;

  /// Average review rating from completed deals, when the backend has any.
  final double? ratingAverage;
  final int reviewCount;

  /// Result section from the multi-source backend (registered, used,
  /// surplus, deals, nearby_external, ...). Null on older rows.
  final String? segment;

  /// Real seller/site/creator name returned by the source (never invented).
  final String? sourceName;

  /// Video length as returned by the video source (e.g. "08:12").
  final String? duration;

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
          source: '${json['source'] ?? json['match_source'] ?? json['channel'] ?? 'local'}',
          imageUrl: json['image_url']?.toString() ?? json['image']?.toString(),
          locationLabel: json['location_label']?.toString() ?? json['location']?.toString(),
          availability: json['availability']?.toString() ?? json['stock_status']?.toString(),
          destinationUrl: json['destination_url']?.toString() ?? json['normal_url']?.toString(),
          disclosure: json['disclosure']?.toString(),
          affiliate: json['affiliate'] == true,
          ratingAverage: (json['rating_average'] as num?)?.toDouble(),
          reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
          segment: json['segment']?.toString(),
          sourceName: json['source_name']?.toString(),
          duration: json['duration']?.toString(),
      );

  /// Round-trips through [UniversalMatch.fromJson] (History restoration).
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'score': score,
        'distance_km': distanceKm,
        'price': price,
        'provider_id': providerId,
        'trust_score': trustScore,
        'availability_score': availabilityScore,
        'source': source,
        'image_url': imageUrl,
        'location_label': locationLabel,
        'availability': availability,
        'destination_url': destinationUrl,
        'disclosure': disclosure,
        'affiliate': affiliate,
        'rating_average': ratingAverage,
        'review_count': reviewCount,
        'segment': segment,
        'source_name': sourceName,
        'duration': duration,
      };
}

class UniversalMatchResult {
  const UniversalMatchResult({
    required this.dealId,
    required this.matches,
    this.sourceStatus = const <String, String>{},
  });
  final String dealId;
  final List<UniversalMatch> matches;

  /// Per source (askodox, nearby, used_deals, online, videos): ok,
  /// no_results or unavailable -- as reported by the backend.
  final Map<String, String> sourceStatus;
}

abstract interface class UniversalMatchRepository {
  Future<UniversalMatchResult> createAndMatch(UniversalDeal deal);
  Future<void> acceptMatch({required String dealId, required String matchId});

  /// Explicit Party B acknowledgement for production-like sandbox flows.
  /// Live flows continue to use the backend acceptance/interest endpoints.
  Future<void> acceptSandboxPartyB({required String dealId, required String matchId});

  bool sandboxConversationReady({required String dealId, required String matchId});
  bool sandboxContactSharingAllowed({required String dealId, required String matchId});
}

class ApiUniversalMatchRepository implements UniversalMatchRepository {
  ApiUniversalMatchRepository(
    this._client, {
    required this.appUserId,
    this.authToken,
    SandboxMatchAcceptanceStore? sandboxAcceptanceStore,
    SandboxPartyGateStore? sandboxPartyGateStore,
  })  : sandboxAcceptanceStore = sandboxAcceptanceStore ?? SandboxMatchAcceptanceStore(),
        sandboxPartyGateStore = sandboxPartyGateStore ?? SandboxPartyGateStore();

  final ApiClient _client;
  final String? appUserId;
  final String? authToken;
  final SandboxMatchAcceptanceStore sandboxAcceptanceStore;
  final SandboxPartyGateStore sandboxPartyGateStore;

  // Added 2026-09-16 (round 14): no longer `static const` since these must
  // carry this instance's authToken (mirrors order_repository.dart's,
  // seller_listing_repository.dart's, and deal_screens.dart's identical
  // round-10/12/13 changes).
  ApiRequestOptions get _createOptions => ApiRequestOptions(
        timeout: const Duration(seconds: 30),
        authToken: authToken,
      );

  ApiRequestOptions get _matchOptions => ApiRequestOptions(
        timeout: const Duration(seconds: 30),
        retryCount: 1,
        authToken: authToken,
      );

  ApiRequestOptions get _acceptOptions => ApiRequestOptions(authToken: authToken);

  bool _isSandbox(String dealId, String matchId) =>
      dealId.startsWith('local-') || matchId.startsWith('demo-');

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
    final status = data['source_status'];
    return UniversalMatchResult(
      dealId: dealId,
      matches: rows,
      sourceStatus: status is Map
          ? {for (final e in status.entries) '${e.key}': '${e.value}'}
          : const {},
    );
  }

  @override
  Future<void> acceptMatch({required String dealId, required String matchId}) async {
    if (_isSandbox(dealId, matchId)) {
      // This action is Party A accepting the selected Party B match.
      sandboxAcceptanceStore.accept(dealId: dealId, matchId: matchId);
      sandboxPartyGateStore.accept(
        dealId: dealId,
        matchId: matchId,
        side: SandboxPartySide.partyA,
      );
      return;
    }

    final result = await _client.post<Map<String, Object?>>(
      '/deals/$dealId/accept-match',
      body: {'match_id': matchId},
      options: _acceptOptions,
    );
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'Unable to accept this match.');
    }
  }

  @override
  Future<void> acceptSandboxPartyB({
    required String dealId,
    required String matchId,
  }) async {
    if (!_isSandbox(dealId, matchId)) {
      throw StateError('Party B sandbox acceptance is only available in TEST/SANDBOX.');
    }
    if (!sandboxAcceptanceStore.isAccepted(dealId: dealId, matchId: matchId)) {
      throw StateError('Party A must accept the match before Party B can confirm it.');
    }
    sandboxPartyGateStore.accept(
      dealId: dealId,
      matchId: matchId,
      side: SandboxPartySide.partyB,
    );
  }

  @override
  bool sandboxConversationReady({required String dealId, required String matchId}) {
    if (!_isSandbox(dealId, matchId)) return false;
    return sandboxPartyGateStore.canOpenConversation(dealId: dealId, matchId: matchId);
  }

  @override
  bool sandboxContactSharingAllowed({required String dealId, required String matchId}) {
    if (!_isSandbox(dealId, matchId)) return false;
    return sandboxPartyGateStore.canShareContact(dealId: dealId, matchId: matchId);
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
