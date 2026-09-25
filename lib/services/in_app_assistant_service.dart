import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class InAppAssistantTurn {
  const InAppAssistantTurn({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, String> toJson() => {'role': role, 'text': text};
}

// Added 2026-09-16 (round 9, roadmap Phase 1: "Reconnect what already
// works"). Mirrors backend/app/services/buyer_intelligence_service.py's
// build_buying_guide() output, now attached to the in-app assistant's
// response (see backend/app/api/routes/in_app_assistant.py) instead of only
// ever being computed for the WhatsApp pipeline. Parsed here so the data is
// available to the app rather than silently dropped -- the same mistake
// round 7 found and fixed for `entities`. No screen renders this yet; that
// UI is a deliberately separate next step (see
// docs/ASKODOX_EXECUTION_TRACKER.md's round-9 entry).
class BuyingGuide {
  const BuyingGuide({
    required this.subject,
    required this.questions,
    required this.decisionFramework,
  });

  final String subject;
  final List<String> questions;
  final List<String> decisionFramework;

  factory BuyingGuide.fromJson(Map<String, dynamic> json) => BuyingGuide(
        subject: (json['subject'] ?? '').toString(),
        questions: _stringList(json['questions']),
        decisionFramework: _stringList(json['decision_framework']),
      );

  static List<String> _stringList(Object? raw) => raw is List
      ? [for (final item in raw) item.toString()]
      : const <String>[];
}

class InAppAssistantDecision {
  const InAppAssistantDecision({
    required this.reply,
    required this.domain,
    required this.transactional,
    required this.action,
    required this.confidence,
    required this.source,
    this.entities = const <String, Object?>{},
    this.buyingGuide,
    this.activeRole = '',
    this.activeRoleConfidence = 0.0,
  });

  final String reply;
  final String domain;
  final bool transactional;
  final String action;
  final double confidence;
  final String source;

  /// Semantic facts extracted by the Universal AI layer. These are deliberately
  /// separate from the natural reply so deterministic business modules can use
  /// meaning directly instead of re-parsing keyword-prefixed text.
  final Map<String, Object?> entities;

  /// Present only for a genuine buy-side PRODUCT/FOOD message with a known
  /// subject -- see buyer_guide_gate.py on the backend. Null otherwise.
  final BuyingGuide? buyingGuide;

  /// Active Role = the current message's request intent (e.g. BUYER,
  /// SELLER, SERVICE_PROVIDER, WORKER, DELIVERY_PARTNER), re-derived by the
  /// backend on every message -- never a permanent lock-in. Empty when the
  /// message's intent was not clear enough to classify confidently. See
  /// in_app_assistant.py's `_suggest_active_role`.
  final String activeRole;
  final double activeRoleConfidence;

  bool get usable => source == 'universal_ai' && reply.trim().isNotEmpty;

  factory InAppAssistantDecision.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    final entities = <String, Object?>{};
    if (rawEntities is Map) {
      for (final entry in rawEntities.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        if (key.isNotEmpty && entry.value != null) {
          entities[key] = entry.value;
        }
      }
    }

    final rawGuide = json['buying_guide'];

    return InAppAssistantDecision(
      reply: (json['reply'] ?? '').toString(),
      domain: (json['domain'] ?? 'UNKNOWN').toString().toUpperCase(),
      transactional: json['transactional'] == true,
      action: (json['action'] ?? '').toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      source: (json['source'] ?? 'fallback').toString(),
      entities: Map.unmodifiable(entities),
      buyingGuide:
          rawGuide is Map ? BuyingGuide.fromJson(Map<String, dynamic>.from(rawGuide)) : null,
      activeRole: (json['active_role'] ?? '').toString(),
      activeRoleConfidence: (json['active_role_confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String? entityText(String key) {
    final value = entities[key.trim().toLowerCase()];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  num? entityNumber(String key) {
    final value = entities[key.trim().toLowerCase()];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

class InAppAssistantService {
  const InAppAssistantService({http.Client? client}) : _client = client;

  static const _defaultBaseUrl =
      'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  final http.Client? _client;

  Future<InAppAssistantDecision?> decide({
    required String message,
    required String locale,
    required List<InAppAssistantTurn> history,
    String? location,
  }) async {
    final clean = message.trim();
    if (clean.isEmpty) return null;
    final cleanLocation = location?.trim();

    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/assistant'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': clean,
              'locale': locale,
              'history': history.takeLast(12).map((turn) => turn.toJson()).toList(),
              if (cleanLocation != null && cleanLocation.isNotEmpty) 'location': cleanLocation,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return InAppAssistantDecision.fromJson(decoded);
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    } finally {
      if (ownClient) client.close();
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    if (count <= 0) return const Iterable.empty();
    final list = toList(growable: false);
    if (list.length <= count) return list;
    return list.skip(list.length - count);
  }
}
