import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One labelled insight from `/api/business/command-center`:
/// CONFIRMED_FACT / POSSIBLE_CAUSE / RECOMMENDATION, red / orange / green,
/// and the app screen that acts on it.
class BusinessInsight {
  const BusinessInsight({
    required this.kind,
    required this.label,
    required this.severity,
    required this.title,
    this.detail = '',
    this.actionLabel,
    this.actionRoute,
  });

  final String kind;
  final String label;
  final String severity;
  final String title;
  final String detail;
  final String? actionLabel;
  final String? actionRoute;

  static BusinessInsight? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final action = raw['action'];
    return BusinessInsight(
      kind: '${raw['kind'] ?? ''}',
      label: '${raw['label'] ?? ''}',
      severity: '${raw['severity'] ?? 'orange'}',
      title: '${raw['title'] ?? ''}',
      detail: '${raw['detail'] ?? ''}',
      actionLabel: action is Map ? '${action['label'] ?? ''}' : null,
      actionRoute: action is Map ? '${action['route'] ?? ''}' : null,
    );
  }
}

class BusinessCenter {
  const BusinessCenter({this.summary = const {}, this.insights = const [], this.basis = ''});

  final Map<String, int> summary;
  final List<BusinessInsight> insights;
  final String basis;
}

class BusinessCenterRepository {
  BusinessCenterRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  Future<BusinessCenter> load({String language = 'en'}) async {
    if (authToken == null || authToken!.isEmpty) return const BusinessCenter();
    final result = await _client.get<Map<String, Object?>>(
      '/api/business/command-center?language=$language',
      options: ApiRequestOptions(timeout: const Duration(seconds: 20), authToken: authToken),
    );
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('business center unavailable');
    final summary = <String, int>{};
    final raw = result.data['summary'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value is num) summary['${entry.key}'] = (entry.value as num).toInt();
      }
    }
    return BusinessCenter(
      summary: summary,
      insights: [
        for (final item in (result.data['insights'] as List? ?? const []))
          if (BusinessInsight.fromJson(item) case final i?) i,
      ],
      basis: '${result.data['basis'] ?? ''}',
    );
  }
}

final businessCenterRepositoryProvider = Provider<BusinessCenterRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return BusinessCenterRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final businessCenterProvider = FutureProvider.autoDispose.family<BusinessCenter, String>((ref, language) {
  return ref.watch(businessCenterRepositoryProvider).load(language: language);
});
