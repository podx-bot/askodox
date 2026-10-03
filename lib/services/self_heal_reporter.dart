import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/providers/backend_providers.dart';

/// Tells the Command Center (Self-healing log) about a GREEN correction the
/// app applied inside one conversation turn. Fixed kinds only, no user text;
/// best effort -- never blocks or fails the chat.
class SelfHealReporter {
  const SelfHealReporter(this._client);

  final ApiClient _client;

  static const kinds = {
    'irrelevant_fallback',
    'duplicate_cta',
    'attachment_intent_mismatch',
    'stale_state',
    'wrong_fallback_branch',
  };

  void report(String kind, {String turnKind = '', String language = ''}) {
    if (!kinds.contains(kind)) return;
    unawaited(_client
        .post<Map<String, Object?>>('/api/selfheal/conversation',
            body: {'kind': kind, 'turn_kind': turnKind, 'language': language})
        .then((_) {}, onError: (Object _) {}));
  }
}

final selfHealReporterProvider = Provider<SelfHealReporter>((ref) => SelfHealReporter(ref.watch(apiClientProvider)));
