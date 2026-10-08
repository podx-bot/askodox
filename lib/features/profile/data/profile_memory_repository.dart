import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One thing ASKODOX remembers from the person's conversations (private
/// unless they publish it with consent). Server: /api/me/memory.
class AskodoxMemoryItem {
  const AskodoxMemoryItem({
    required this.id,
    required this.role,
    required this.kind,
    required this.subject,
    required this.status,
    this.category = '',
    this.details = const {},
    this.visibility = 'private',
  });

  final int id;

  /// buyer / seller / service_provider / service_taker
  final String role;
  final String kind;
  final String category;
  final String subject;
  final Map<String, Object?> details;

  /// active / updated / completed / cancelled / expired
  final String status;
  final String visibility;

  factory AskodoxMemoryItem.fromJson(Map<String, Object?> json) => AskodoxMemoryItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        role: '${json['role'] ?? ''}',
        kind: '${json['kind'] ?? ''}',
        category: '${json['category'] ?? ''}',
        subject: '${json['subject'] ?? ''}',
        details: json['details'] is Map ? Map<String, Object?>.from(json['details'] as Map) : const {},
        status: '${json['status'] ?? 'active'}',
        visibility: '${json['visibility'] ?? 'private'}',
      );
}

class AskodoxMemory {
  const AskodoxMemory({required this.enabled, required this.items});
  final bool enabled;
  final List<AskodoxMemoryItem> items;
}

class ProfileMemoryRepository {
  const ProfileMemoryRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<AskodoxMemory?> load() async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.get<Map<String, Object?>>('/api/me/memory', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('memory unavailable');
    final data = result.data;
    return AskodoxMemory(
      enabled: data['enabled'] != false,
      items: [
        for (final row in (data['items'] as List?) ?? const [])
          if (row is Map) AskodoxMemoryItem.fromJson(Map<String, Object?>.from(row)),
      ],
    );
  }

  Future<bool> setEnabled(bool on) async =>
      (await _client.put<Map<String, Object?>>('/api/me/memory/settings', body: {'enabled': on}, options: _auth))
          is ApiSuccess;

  Future<bool> correct(int id, Map<String, Object?> fields) async =>
      (await _client.patch<Map<String, Object?>>('/api/me/memory/$id', body: fields, options: _auth)) is ApiSuccess;

  Future<bool> delete(int id) async =>
      (await _client.delete<Map<String, Object?>>('/api/me/memory/$id', options: _auth)) is ApiSuccess;

  Future<bool> deleteAll() async =>
      (await _client.delete<Map<String, Object?>>('/api/me/memory?confirm=DELETE', options: _auth)) is ApiSuccess;
}

final profileMemoryRepositoryProvider = Provider<ProfileMemoryRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return ProfileMemoryRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

final profileMemoryProvider =
    FutureProvider.autoDispose<AskodoxMemory?>((ref) => ref.watch(profileMemoryRepositoryProvider).load());
