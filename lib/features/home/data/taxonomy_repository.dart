import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// What the universal category tree (`GET /api/taxonomy/resolve`) says the
/// customer's words are about: the node path, customer vs provider side, and
/// the actions ASKODOX may offer (inherited capabilities).
class AskodoxTaxonomyMatch {
  const AskodoxTaxonomyMatch({required this.key, required this.label, required this.role, required this.actions,
      this.mobilityKind, this.path = const []});

  final String key;
  final String label;
  final String role; // customer | provider
  final List<String> actions;
  final String? mobilityKind;
  final List<String> path;

  bool get provider => role == 'provider';

  static AskodoxTaxonomyMatch? fromJson(Map<String, Object?> j) {
    if (j['matched'] != true) return null;
    return AskodoxTaxonomyMatch(
      key: '${j['key'] ?? ''}',
      label: '${j['label'] ?? ''}',
      role: '${j['role'] ?? 'customer'}',
      actions: [for (final a in (j['actions'] as List? ?? const [])) '$a'],
      mobilityKind: j['mobility_kind'] == null ? null : '${j['mobility_kind']}',
      path: [
        for (final p in (j['path'] as List? ?? const []))
          if (p is Map) '${p['label'] ?? ''}',
      ],
    );
  }
}

class AskodoxTaxonomyRepository {
  AskodoxTaxonomyRepository(this._client);
  final ApiClient _client;

  Future<AskodoxTaxonomyMatch?> resolve(String text) async {
    final result = await _client.get<Map<String, Object?>>(
        '/api/taxonomy/resolve?q=${Uri.encodeQueryComponent(text)}',
        options: const ApiRequestOptions(timeout: Duration(seconds: 4)));
    return switch (result) {
      ApiSuccess(:final data) => AskodoxTaxonomyMatch.fromJson(data),
      ApiError() => null,
    };
  }
}

final askodoxTaxonomyRepositoryProvider =
    Provider<AskodoxTaxonomyRepository>((ref) => AskodoxTaxonomyRepository(ref.watch(apiClientProvider)));
