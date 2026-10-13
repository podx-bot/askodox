import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One base plan (server: /api/plans/catalogue). [available] is false until
/// the Owner activates live pricing; nothing here takes payment.
class AskodoxPlan {
  const AskodoxPlan({required this.code, required this.name, required this.price, required this.periodDays,
      this.trialDays = 0, this.available = false});
  final String code, name;
  final num price;
  final int periodDays, trialDays;
  final bool available;

  factory AskodoxPlan.fromJson(Map<String, Object?> j) => AskodoxPlan(
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        price: (j['price'] as num?) ?? 0,
        periodDays: (j['period_days'] as num?)?.toInt() ?? 30,
        trialDays: (j['trial_days'] as num?)?.toInt() ?? 0,
        available: j['available'] == true,
      );
}

class AskodoxPlansState {
  const AskodoxPlansState({required this.plans, this.currentPlan, this.currentStatus});
  final List<AskodoxPlan> plans;
  final String? currentPlan, currentStatus;
}

class PlansRepository {
  const PlansRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  Future<AskodoxPlansState> load() async {
    final result = await _client.get<Map<String, Object?>>('/api/plans/catalogue');
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('plans unavailable');
    final plans = [
      for (final p in (result.data['items'] as List?) ?? const [])
        if (p is Map) AskodoxPlan.fromJson(Map<String, Object?>.from(p)),
    ];
    String? plan, status;
    if (authToken != null && authToken!.isNotEmpty) {
      final me = await _client.get<Map<String, Object?>>('/api/subscriptions/me',
          options: ApiRequestOptions(authToken: authToken));
      if (me case ApiSuccess<Map<String, Object?>>(:final data)) {
        final sub = data['subscription'];
        if (sub is Map) {
          plan = '${sub['plan_code'] ?? ''}';
          status = '${sub['status'] ?? ''}';
        }
      }
    }
    return AskodoxPlansState(plans: plans, currentPlan: plan, currentStatus: status);
  }

  /// Only an AVAILABLE plan can be chosen (the server refuses others).
  Future<String?> choose(String code) async {
    final result = await _client.post<Map<String, Object?>>('/api/subscriptions',
        body: {'plan_code': code}, options: ApiRequestOptions(authToken: authToken));
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final sub = data['subscription'];
      return sub is Map ? '${sub['status'] ?? ''}' : null;
    }
    return null;
  }
}

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return PlansRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final plansProvider = FutureProvider.autoDispose<AskodoxPlansState>((ref) => ref.watch(plansRepositoryProvider).load());
