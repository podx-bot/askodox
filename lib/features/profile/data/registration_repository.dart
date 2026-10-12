import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One held role's registration state (server: /api/me/profile/registration).
class AskodoxRoleRegistration {
  const AskodoxRoleRegistration({required this.role, required this.missing, required this.status,
      required this.verification});
  final String role;
  final List<String> missing;

  /// draft / complete
  final String status;

  /// not_requested / pending / verified / rejected
  final String verification;

  bool get canRequestVerification => status == 'complete' && (verification == 'not_requested' || verification == 'rejected');

  factory AskodoxRoleRegistration.fromJson(Map<String, Object?> j) {
    final v = j['verification'];
    return AskodoxRoleRegistration(
      role: '${j['role'] ?? ''}',
      missing: [for (final m in (j['missing'] as List?) ?? const []) '$m'],
      status: '${j['status'] ?? 'draft'}',
      verification: v is String ? v : 'not_requested',
    );
  }
}

class AskodoxRegistration {
  const AskodoxRegistration({required this.basicsMissing, required this.roles, required this.complete});
  final List<String> basicsMissing;
  final List<AskodoxRoleRegistration> roles;
  final bool complete;
}

/// "operating_hours" -> "Operating hours" (field keys come from the server).
String askodoxFieldLabel(String key) {
  final words = key.replaceAll('_', ' ').trim();
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}

class RegistrationRepository {
  const RegistrationRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<AskodoxRegistration?> load() async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.get<Map<String, Object?>>('/api/me/profile/registration', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('registration unavailable');
    final d = result.data;
    return AskodoxRegistration(
      basicsMissing: [for (final m in (d['basics_missing'] as List?) ?? const []) '$m'],
      complete: d['complete'] == true,
      roles: [
        for (final r in (d['roles'] as List?) ?? const [])
          if (r is Map) AskodoxRoleRegistration.fromJson(Map<String, Object?>.from(r)),
      ],
    );
  }

  /// Only the last 4 characters of [reference] are kept by the server.
  Future<String?> requestVerification(String role, {String kind = 'other', String reference = '', String note = ''}) async {
    final result = await _client.post<Map<String, Object?>>('/api/me/profile/verification',
        body: {'role': role, 'reference_kind': kind, 'reference': reference, 'note': note}, options: _auth);
    return result is ApiSuccess<Map<String, Object?>> ? '${result.data['verification'] ?? ''}' : null;
  }
}

final registrationRepositoryProvider = Provider<RegistrationRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return RegistrationRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final registrationProvider =
    FutureProvider.autoDispose<AskodoxRegistration?>((ref) => ref.watch(registrationRepositoryProvider).load());
