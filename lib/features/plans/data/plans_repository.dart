import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One base plan (server: /api/plans/catalogue). [available] is false until
/// the Owner activates live pricing. Payment (Razorpay, TEST mode for billing
/// testers only) happens on the server's hosted checkout page; the app never
/// sends an amount and never decides that a payment succeeded.
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
  const AskodoxPlansState(
      {required this.plans, this.currentPlan, this.currentStatus, this.payable = const {}, this.paymentMode});
  final List<AskodoxPlan> plans;
  final String? currentPlan, currentStatus;

  /// Plan codes the SERVER says this user may pay for now (/api/billing/options).
  final Set<String> payable;

  /// 'test' (sandbox, no real money) or 'live'; null when no gateway is ready.
  final String? paymentMode;
}

/// A started checkout: the hosted Razorpay page to open, or why not.
class AskodoxCheckoutStart {
  const AskodoxCheckoutStart({this.purchaseId, this.payUrl, this.error});
  final String? purchaseId, payUrl, error;
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
    final payable = <String>{};
    String? mode;
    if (authToken != null && authToken!.isNotEmpty) {
      final opts = await _client.get<Map<String, Object?>>('/api/billing/options',
          options: ApiRequestOptions(authToken: authToken));
      if (opts case ApiSuccess<Map<String, Object?>>(:final data)) {
        mode = data['mode'] as String?;
        for (final i in (data['items'] as List?) ?? const []) {
          if (i is Map && i['payable'] == true) payable.add('${i['plan_code']}');
        }
      }
    }
    return AskodoxPlansState(
        plans: plans, currentPlan: plan, currentStatus: status, payable: payable, paymentMode: mode);
  }

  /// Starts a server-priced checkout (only the plan code is sent).
  Future<AskodoxCheckoutStart> startCheckout(String code) async {
    final result = await _client.post<Map<String, Object?>>('/api/billing/checkout',
        body: {'plan_code': code}, options: ApiRequestOptions(authToken: authToken));
    return switch (result) {
      ApiSuccess<Map<String, Object?>>(:final data) => AskodoxCheckoutStart(
          purchaseId: data['purchase_id'] as String?, payUrl: data['pay_url'] as String?,
          error: data['pay_url'] == null ? 'NO_HOSTED_CHECKOUT' : null),
      ApiError<Map<String, Object?>>(:final failure) => AskodoxCheckoutStart(error: failure.message ?? 'FAILED'),
    };
  }

  /// The purchase status as the SERVER knows it (it reads open purchases back
  /// from Razorpay): PENDING / ACTIVE / FAILED / CANCELLED / EXPIRED / REFUNDED.
  Future<String?> purchaseStatus(String purchaseId) async {
    final result = await _client.get<Map<String, Object?>>('/api/billing/purchases/$purchaseId',
        options: ApiRequestOptions(authToken: authToken));
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final p = data['purchase'];
      return p is Map ? '${p['status'] ?? ''}' : null;
    }
    return null;
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

/// Opens the hosted checkout page (injectable for tests).
typedef AskodoxPayLauncher = Future<bool> Function(Uri url);

final askodoxPayLauncherProvider = Provider<AskodoxPayLauncher>(
    (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication));

final plansProvider = FutureProvider.autoDispose<AskodoxPlansState>((ref) => ref.watch(plansRepositoryProvider).load());
