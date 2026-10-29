import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// "Tell me when it is available" (server: /api/me/availability-watches,
/// backend services/availability_watch.py). One push per watch when a
/// matching listing appears later; watches end after 30 days.
class AvailabilityWatchRepository {
  const AvailabilityWatchRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  bool get signedIn => authToken != null && authToken!.isNotEmpty && authToken != 'DEMO_ONLY';

  /// The saved watch (`already` = the same item was already being watched),
  /// or null when not signed in / the server refused.
  Future<Map<String, Object?>?> watch(String subject, {String location = '', String category = ''}) async {
    if (!signedIn || subject.trim().isEmpty) return null;
    final result = await _client.post<Map<String, Object?>>('/api/me/availability-watches',
        body: {'subject': subject.trim(), 'location': location, 'category': category},
        options: ApiRequestOptions(authToken: authToken));
    if (result is! ApiSuccess<Map<String, Object?>>) return null;
    final watch = result.data['watch'];
    return watch is Map ? Map<String, Object?>.from(watch) : null;
  }
}

final availabilityWatchRepositoryProvider = Provider<AvailabilityWatchRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AvailabilityWatchRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});
