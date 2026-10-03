import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Customer demand ASKODOX matched to this seller / provider. Aggregate only
/// (what, how many, area, budget band) -- never who.
class SellerOpportunity {
  const SellerOpportunity({
    required this.id,
    required this.title,
    required this.body,
    required this.subject,
    required this.status,
    this.category = '',
    this.area = '',
    this.searches = 0,
    this.budgetBand,
    this.expiresAt,
    this.canRespond = false,
    this.canFulfil = false,
  });

  final int id;
  final String title;
  final String body;
  final String subject;

  /// new / opened / accepted / declined / expired / fulfilled
  final String status;
  final String category;
  final String area;
  final int searches;
  final String? budgetBand;
  final DateTime? expiresAt;
  final bool canRespond;
  final bool canFulfil;

  static SellerOpportunity? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! num) return null;
    String s(String key) => '${json[key] ?? ''}'.trim();
    return SellerOpportunity(
      id: id.toInt(),
      title: s('title'),
      body: s('body'),
      subject: s('subject'),
      status: s('status').isEmpty ? 'new' : s('status'),
      category: s('category'),
      area: s('area'),
      searches: (json['searches'] as num?)?.toInt() ?? 0,
      budgetBand: s('budget_band').isEmpty ? null : s('budget_band'),
      expiresAt: DateTime.tryParse(s('expires_at')),
      canRespond: json['can_respond'] == true,
      canFulfil: json['can_fulfil'] == true,
    );
  }
}

class SellerOpportunities {
  const SellerOpportunities({this.items = const [], this.privacy = '', this.counts = const {}});

  final List<SellerOpportunity> items;
  final String privacy;
  final Map<String, int> counts;
}

/// One row of the unified inbox (`/api/me/inbox`) that the app does not
/// already load itself: demand opportunities and in-app notices.
class AskodoxInboxEntry {
  const AskodoxInboxEntry({
    required this.key,
    required this.kind,
    required this.title,
    required this.status,
    required this.route,
    this.at,
  });

  final String key;
  final String kind;
  final String title;
  final String status;
  final String route;
  final DateTime? at;
}

class OpportunitiesRepository {
  OpportunitiesRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  bool get _signedIn => authToken != null && authToken!.isNotEmpty;
  ApiRequestOptions get _auth => ApiRequestOptions(timeout: const Duration(seconds: 20), authToken: authToken);

  Future<SellerOpportunities> mine({String language = 'en'}) async {
    if (!_signedIn) return const SellerOpportunities();
    final result = await _client.get<Map<String, Object?>>('/api/opportunities?language=$language', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('opportunities unavailable');
    final counts = <String, int>{};
    final raw = result.data['counts'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is num) counts['${entry.key}'] = (entry.value as num).toInt();
      }
    }
    return SellerOpportunities(
      items: [
        for (final item in (result.data['items'] as List? ?? const []))
          if (SellerOpportunity.fromJson(item) case final o?) o,
      ],
      privacy: '${result.data['privacy'] ?? ''}',
      counts: counts,
    );
  }

  /// accept / decline / fulfil / open. Returns the updated opportunity, or
  /// throws with the server's reason (e.g. expired).
  Future<SellerOpportunity?> act(int id, String action, {String reason = ''}) async {
    final result = await _client.post<Map<String, Object?>>(
      '/api/opportunities/$id/$action',
      body: {'response': action == 'decline' ? 'declined' : 'interested', if (reason.isNotEmpty) 'reason': reason},
      options: _auth,
    );
    if (result is ApiSuccess<Map<String, Object?>>) return SellerOpportunity.fromJson(result.data['item']);
    if (result is ApiError<Map<String, Object?>>) {
      throw StateError(result.failure.message ?? 'Could not update this opportunity');
    }
    return null;
  }

  Future<List<AskodoxInboxEntry>> inbox({String language = 'en'}) async {
    if (!_signedIn) return const [];
    final result = await _client.get<Map<String, Object?>>('/api/me/inbox?language=$language', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) return const [];
    return [
      for (final item in (result.data['items'] as List? ?? const []))
        if (item is Map && (item['kind'] == 'opportunity' || item['kind'] == 'notice'))
          AskodoxInboxEntry(
            key: '${item['key']}',
            kind: '${item['kind']}',
            title: '${item['title'] ?? ''}',
            status: '${item['status'] ?? ''}',
            route: '${item['route'] ?? '/updates'}',
            at: DateTime.tryParse('${item['at'] ?? ''}'),
          ),
    ];
  }
}

final opportunitiesRepositoryProvider = Provider<OpportunitiesRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return OpportunitiesRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final sellerOpportunitiesProvider = FutureProvider.autoDispose.family<SellerOpportunities, String>((ref, language) {
  return ref.watch(opportunitiesRepositoryProvider).mine(language: language);
});
