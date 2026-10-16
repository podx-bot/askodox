import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Verification (KYC) from the server (/api/kyc/*). Badges show COMPLETED
/// verification only; AI-read details are never "verified".
class AskodoxKycCheck {
  const AskodoxKycCheck({required this.id, required this.label, required this.status, required this.method,
      this.fields = const {}, this.issues = const [], this.nextSteps = const []});
  final String id, label, status, method;
  final Map<String, String> fields;
  final List<String> issues, nextSteps;

  factory AskodoxKycCheck.fromJson(Map<String, Object?> j) => AskodoxKycCheck(
        id: '${j['id'] ?? ''}',
        label: '${j['label'] ?? j['kind'] ?? ''}',
        status: '${j['status'] ?? ''}',
        method: '${j['method'] ?? ''}',
        fields: {
          for (final e in ((j['fields'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
        },
        issues: [for (final i in (j['issues'] as List?) ?? const []) '$i'],
        nextSteps: [for (final i in (j['next_steps'] as List?) ?? const []) '$i'],
      );
}

class AskodoxKycState {
  const AskodoxKycState({required this.level, required this.levelLabel, required this.consent,
      required this.consentText, required this.consentVersion, this.badges = const [], this.checks = const [],
      this.requirements = const {}});
  final int level;
  final String levelLabel, consentText, consentVersion;
  final bool consent;
  final List<String> badges;
  final List<AskodoxKycCheck> checks;
  final Map<String, bool> requirements;

  factory AskodoxKycState.fromJson(Map<String, Object?> j) => AskodoxKycState(
        level: (j['level'] as num?)?.toInt() ?? 0,
        levelLabel: '${j['level_label'] ?? ''}',
        consent: j['consent'] == true,
        consentText: '${j['consent_text'] ?? ''}',
        consentVersion: '${j['consent_version'] ?? ''}',
        badges: [for (final b in (j['badges'] as List?) ?? const []) if (b is Map) '${b['label']}'],
        checks: [
          for (final c in (j['checks'] as List?) ?? const [])
            if (c is Map) AskodoxKycCheck.fromJson(Map<String, Object?>.from(c)),
        ],
        requirements: {
          for (final e in ((j['requirements'] as Map?) ?? const {}).entries)
            '${e.key}': (e.value is Map) && (e.value as Map)['met'] == true,
        },
      );
}

/// The result of reading one document: what was found (masked), what is
/// missing, problems and what to do next.
class AskodoxKycSubmission {
  const AskodoxKycSubmission({this.status, this.issues = const [], this.nextSteps = const [], this.error});
  final String? status, error;
  final List<String> issues, nextSteps;
}

class KycRepository {
  const KycRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _opts => ApiRequestOptions(authToken: authToken, timeout: const Duration(seconds: 60));

  Future<AskodoxKycState> load() async {
    final r = await _client.get<Map<String, Object?>>('/api/kyc/me', options: _opts);
    if (r case ApiSuccess<Map<String, Object?>>(:final data)) return AskodoxKycState.fromJson(data);
    throw StateError('verification unavailable');
  }

  Future<bool> consent(String version) async {
    final r = await _client.post<Map<String, Object?>>('/api/kyc/consent',
        body: {'accept': true, 'version': version}, options: _opts);
    return r is ApiSuccess;
  }

  Future<bool> withdraw() async {
    final r = await _client.delete<Map<String, Object?>>('/api/kyc/consent', options: _opts);
    return r is ApiSuccess;
  }

  Future<AskodoxKycSubmission> submit(List<int> bytes, {required String name, required String mimeType}) async {
    final r = await _client.post<Map<String, Object?>>('/api/kyc/documents',
        body: {'file_base64': base64Encode(bytes), 'filename': name, 'mime_type': mimeType}, options: _opts);
    return switch (r) {
      ApiSuccess<Map<String, Object?>>(:final data) => AskodoxKycSubmission(
          status: data['check'] is Map ? '${(data['check'] as Map)['status']}' : '${data['kind'] ?? ''}',
          issues: [for (final i in (data['issues'] as List?) ?? const []) '$i'],
          nextSteps: [for (final i in (data['next_steps'] as List?) ?? const []) '$i'],
        ),
      ApiError<Map<String, Object?>>(:final failure) => AskodoxKycSubmission(error: failure.message ?? 'failed'),
    };
  }
}

final kycRepositoryProvider = Provider<KycRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return KycRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final kycProvider = FutureProvider.autoDispose<AskodoxKycState>((ref) => ref.watch(kycRepositoryProvider).load());
