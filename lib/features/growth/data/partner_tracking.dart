import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/backend_providers.dart';
import '../../matching/data/universal_match_repository.dart';

/// Affiliate / partner result tracking (Partner Hub). The app only reports
/// what happened on its side (card viewed, link tapped) for a result the
/// backend showed, identified by its click id -- no user identity, no
/// secrets. Opening goes through ASKODOX's tracked redirect so the backend
/// records "partner opened" before handing over to the partner.
class AskodoxPartnerTracker {
  const AskodoxPartnerTracker(this._client, this._apiBase);

  final ApiClient _client;
  final Uri? _apiBase;

  /// The URL to open: ASKODOX's redirect for partner rows, otherwise the
  /// result's own destination.
  Uri? openUri(UniversalMatch match) {
    final redirect = match.redirectPath?.trim();
    final base = _apiBase;
    if (redirect != null && redirect.startsWith('/go/') && base != null && base.hasScheme) {
      return base.resolve(redirect);
    }
    final raw = match.destinationUrl?.trim();
    return raw == null || raw.isEmpty ? null : Uri.tryParse(raw);
  }

  /// Fire-and-forget: tracking never blocks or breaks the customer's action.
  void track(UniversalMatch match, String event) {
    final clickId = match.clickId?.trim();
    // Sponsored campaigns count their own opens via /go/sp/ (not partner events).
    if (clickId == null || clickId.isEmpty || match.sponsored) return;
    _client
        .post<Map<String, Object?>>('/api/partners/event', body: {'click_id': clickId, 'event': event})
        .then((_) {}, onError: (_) {});
  }
}

final askodoxPartnerTrackerProvider = Provider<AskodoxPartnerTracker>((ref) {
  final config = ref.watch(appConfigProvider);
  return AskodoxPartnerTracker(ref.watch(apiClientProvider), config.apiBaseUrl);
});
