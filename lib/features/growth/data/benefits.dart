import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One verified benefit that applies to a result (from the backend's
/// benefits engine -- never created in the app).
class AskodoxBenefit {
  const AskodoxBenefit({
    required this.id,
    required this.name,
    required this.provider,
    required this.type,
    required this.kind,
    this.value,
    this.percent,
    this.freeBenefit,
    this.conditions = const [],
    this.expiresAt,
    this.verifiedAt,
    this.sourceUrl,
    this.claimable = false,
  });

  final int id;
  final String name;
  final String provider;
  final String type;

  /// instant_discount | discount | coupon | cashback | credit | gift | reward | benefit
  final String kind;
  final double? value;
  final double? percent;
  final String? freeBenefit;
  final List<Map<String, Object?>> conditions;
  final String? expiresAt;
  final String? verifiedAt;
  final String? sourceUrl;
  final bool claimable;

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  factory AskodoxBenefit.fromJson(Map<String, Object?> json) => AskodoxBenefit(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: '${json['name'] ?? ''}',
        provider: '${json['provider'] ?? ''}',
        type: '${json['type'] ?? ''}',
        kind: '${json['kind'] ?? 'benefit'}',
        value: _num(json['value']),
        percent: _num(json['percent']),
        freeBenefit: json['free_benefit']?.toString(),
        conditions: [
          for (final c in (json['conditions'] as List? ?? const []))
            if (c is Map) Map<String, Object?>.from(c),
        ],
        expiresAt: json['expires_at']?.toString(),
        verifiedAt: json['verified_at']?.toString(),
        sourceUrl: json['source_url']?.toString(),
        claimable: json['claimable'] == true,
      );

  static List<AskodoxBenefit> listFrom(Map<String, Object?>? benefits) => [
        for (final o in (benefits?['offers'] as List? ?? const []))
          if (o is Map) AskodoxBenefit.fromJson(Map<String, Object?>.from(o)),
      ];
}

class AskodoxClaimResult {
  const AskodoxClaimResult({this.code, this.value, this.name, this.kind, this.freeBenefit, this.error});
  final String? code;
  final double? value;
  final String? name;
  final String? kind;
  final String? freeBenefit;

  /// sign_in | already_claimed | unavailable | failed
  final String? error;
  bool get ok => error == null;
}

/// Claims, scratch rewards and terms opens (server decides everything).
class AskodoxBenefitsRepository {
  const AskodoxBenefitsRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  /// Records "terms opened" and returns the public terms, or null.
  Future<Map<String, Object?>?> open(int campaignId) async {
    final result = await _client.get<Map<String, Object?>>('/api/benefits/$campaignId');
    return result is ApiSuccess<Map<String, Object?>> ? result.data : null;
  }

  AskodoxClaimResult _parse(ApiResult<Map<String, Object?>> result) {
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final reward = data['reward'];
      if (reward is! Map) return const AskodoxClaimResult(error: 'unavailable');
      return AskodoxClaimResult(
        code: data['code']?.toString(),
        value: AskodoxBenefit._num(reward['value']),
        name: reward['name']?.toString(),
        kind: reward['kind']?.toString(),
        freeBenefit: reward['free_benefit']?.toString(),
      );
    }
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    return AskodoxClaimResult(
      error: switch (failure.statusCode) {
        401 => 'sign_in',
        409 => (failure.message ?? '').contains('already') ? 'already_claimed' : 'unavailable',
        404 => 'unavailable',
        _ => 'failed',
      },
    );
  }

  Future<AskodoxClaimResult> claim(int campaignId, {double? orderValue}) async {
    if (authToken == null || authToken!.isEmpty) return const AskodoxClaimResult(error: 'sign_in');
    return _parse(await _client.post<Map<String, Object?>>('/api/benefits/$campaignId/claim',
        body: {if (orderValue != null) 'order_value': orderValue}, options: _auth));
  }

  /// Scratch & Reveal after a completed order; null reward = none configured.
  Future<AskodoxClaimResult?> scratch(String orderId) async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.post<Map<String, Object?>>('/api/rewards/scratch',
        body: {'trigger': 'order:$orderId'}, options: _auth);
    if (result case ApiSuccess<Map<String, Object?>>(:final data) when data['reward'] == null) return null;
    final parsed = _parse(result);
    return parsed.ok ? parsed : null;
  }
}

final askodoxBenefitsRepositoryProvider = Provider<AskodoxBenefitsRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AskodoxBenefitsRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});
