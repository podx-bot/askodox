import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// A place found by address search or chosen on the map.
class AskodoxPlace {
  const AskodoxPlace({required this.latitude, required this.longitude, required this.label});
  final double latitude;
  final double longitude;
  final String label;
}

/// Pickup -> drop: real road distance/time and quotes that registered
/// delivery partners listed themselves (never an ASKODOX estimate).
class AskodoxRouteQuote {
  const AskodoxRouteQuote({this.distanceKm, this.durationMinutes, this.quotes = const [], this.note = ''});
  final double? distanceKm;
  final int? durationMinutes;
  final List<({String title, double quote, String rateUnit})> quotes;
  final String note;
}

class AskodoxReferral {
  const AskodoxReferral({required this.code, required this.shareText});
  final String code;
  final String shareText;
}

/// A customer request ASKODOX sent to this registered provider (in-app
/// lead). The requester's identity is shared only after they accept.
class AskodoxLead {
  const AskodoxLead({required this.requestId, required this.message, this.responded = false});
  final String requestId;
  final String message;
  final bool responded;
}

class AskodoxCatalogDraft {
  const AskodoxCatalogDraft({required this.id, required this.draft, required this.missing});
  final int id;
  final Map<String, Object?> draft;
  final List<String> missing;
  String get title => '${draft['title'] ?? draft['subject'] ?? ''}';
}

abstract interface class GrowthRepository {
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude});
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop);

  /// Needs sign-in (it records who referred).
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId});
  Future<AskodoxCatalogDraft?> draftListing({String text = '', Map<String, Object?>? imageAnalysis,
      Map<String, Object?>? videoAnalysis});
  Future<int?> publishDraft(int draftId, Map<String, Object?> reviewed);

  /// Requests broadcast to me as a registered provider (needs sign-in).
  Future<List<AskodoxLead>> leads();

  /// "I can do this" -> the customer sees my interest and decides.
  Future<bool> expressInterest(String requestId);
}

final growthRepositoryProvider = Provider<GrowthRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return ApiGrowthRepository(
    ref.watch(apiClientProvider),
    authToken: session.user == null ? null : session.tokenPlaceholder,
  );
});

class ApiGrowthRepository implements GrowthRepository {
  ApiGrowthRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth =>
      ApiRequestOptions(timeout: const Duration(seconds: 30), authToken: authToken);

  bool get _signedIn => authToken != null && authToken!.isNotEmpty;

  Map<String, Object?>? _data(ApiResult<Map<String, Object?>> result) =>
      result is ApiSuccess<Map<String, Object?>> ? result.data : null;

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  @override
  Future<List<AskodoxPlace>> searchPlaces(String query, {double? latitude, double? longitude}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final params = <String>[
      'q=${Uri.encodeQueryComponent(q)}',
      if (latitude != null) 'latitude=$latitude',
      if (longitude != null) 'longitude=$longitude',
    ].join('&');
    final data = _data(await _client.get<Map<String, Object?>>('/api/discover/places?$params'));
    return [
      for (final item in (data?['items'] as List? ?? const []))
        if (item is Map && _num(item['latitude']) != null && _num(item['longitude']) != null)
          AskodoxPlace(
            latitude: _num(item['latitude'])!,
            longitude: _num(item['longitude'])!,
            label: [item['name'], item['address']].where((v) => '${v ?? ''}'.isNotEmpty).join(', '),
          ),
    ];
  }

  @override
  Future<AskodoxRouteQuote?> routeQuote(AskodoxPlace pickup, AskodoxPlace drop) async {
    final data = _data(await _client.post<Map<String, Object?>>('/api/discover/route', body: {
      'pickup': {'latitude': pickup.latitude, 'longitude': pickup.longitude, 'label': pickup.label},
      'drop': {'latitude': drop.latitude, 'longitude': drop.longitude, 'label': drop.label},
    }));
    if (data == null) return null;
    return AskodoxRouteQuote(
      distanceKm: _num(data['distance_km']),
      durationMinutes: _num(data['duration_minutes'])?.round(),
      note: '${data['quote_note'] ?? ''}',
      quotes: [
        for (final q in (data['quotes'] as List? ?? const []))
          if (q is Map && _num(q['quote']) != null)
            (title: '${q['title'] ?? ''}', quote: _num(q['quote'])!, rateUnit: '${q['rate_unit'] ?? ''}'),
      ],
    );
  }

  @override
  Future<AskodoxReferral?> refer({required String category, String area = '', String? dealId}) async {
    if (!_signedIn) return null;
    final data = _data(await _client.post<Map<String, Object?>>('/api/referrals',
        body: {'category': category, 'area': area, if (dealId != null && dealId.isNotEmpty) 'deal_id': dealId},
        options: _auth));
    final code = '${data?['code'] ?? ''}';
    return code.isEmpty ? null : AskodoxReferral(code: code, shareText: '${data?['share_text'] ?? ''}');
  }

  @override
  Future<AskodoxCatalogDraft?> draftListing({String text = '', Map<String, Object?>? imageAnalysis,
      Map<String, Object?>? videoAnalysis}) async {
    if (!_signedIn) return null;
    final data = _data(await _client.post<Map<String, Object?>>('/api/catalog/drafts', body: {
      'text': text,
      if (imageAnalysis != null) 'image_analysis': imageAnalysis,
      if (videoAnalysis != null) 'video_analysis': videoAnalysis,
    }, options: _auth));
    final id = (data?['id'] as num?)?.toInt();
    if (id == null) return null;
    return AskodoxCatalogDraft(
      id: id,
      draft: Map<String, Object?>.from((data?['draft'] as Map?) ?? const {}),
      missing: [for (final m in (data?['missing'] as List? ?? const [])) '$m'],
    );
  }

  @override
  Future<int?> publishDraft(int draftId, Map<String, Object?> reviewed) async {
    if (!_signedIn) return null;
    final data = _data(await _client.post<Map<String, Object?>>('/api/catalog/drafts/$draftId/publish',
        body: reviewed, options: _auth));
    return (data?['listing_id'] as num?)?.toInt();
  }

  @override
  Future<List<AskodoxLead>> leads() async {
    if (!_signedIn) return const [];
    final data = _data(await _client.get<Map<String, Object?>>('/deals/leads', options: _auth));
    return [
      for (final lead in (data?['leads'] as List? ?? const []))
        if (lead is Map && lead['request_id'] != null)
          AskodoxLead(
            requestId: '${lead['request_id']}',
            message: '${lead['lead_message'] ?? lead['subject'] ?? ''}',
            responded: '${lead['my_response'] ?? ''}'.isNotEmpty,
          ),
    ];
  }

  @override
  Future<bool> expressInterest(String requestId) async {
    if (!_signedIn) return false;
    final result = await _client.post<Map<String, Object?>>('/deals/$requestId/interest', options: _auth);
    return result is ApiSuccess<Map<String, Object?>>;
  }
}
