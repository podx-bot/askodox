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
    this.mode = 'chat',
    this.searchReady,
    this.nextQuestion,
    this.searchSubject,
    this.facts = const <String, Object?>{},
    this.flexible = const <String>[],
    this.unknownCritical = const <String>[],
    this.readyReason = '',
    this.newNeed = false,
    this.conversationRelation = 'unknown',
    this.subjectChanged = false,
    this.advice,
    this.adviceLedger,
  });

  /// One-time advice memory: the concern raised in THIS reply (key,
  /// summary, severity, repeated, allowed), or null.
  final Map<String, Object?>? advice;

  /// The conversation's advice ledger after this turn; send it back as
  /// `adviceGiven` next turn. Null when the backend did not return one
  /// (older backend) -- keep the ledger you have.
  final List<Map<String, Object?>>? adviceLedger;

  /// The brain: this message starts a DIFFERENT need (not an answer to the
  /// one being discussed).
  final bool newNeed;

  /// Deterministic conversation-relation layer (APK 1305): same_topic /
  /// refinement / result_action / comparison / new_topic /
  /// return_to_previous / unknown.
  final String conversationRelation;

  /// True when the SUBJECT itself changed while the conversation continues
  /// (a comparison of new items, or a new subject inside the same domain):
  /// the active result deck belongs to a different need and must retire.
  final bool subjectChanged;

  /// Conversation Decision Brain: is a search justified NOW? Null = the
  /// backend gave no readiness (older backend / model omitted it); the app
  /// then keeps its offline rule.
  final bool? searchReady;

  /// The ONE next question when the search is not justified yet.
  final String? nextQuestion;

  /// One consolidated search phrase built from everything the user said.
  final String? searchSubject;

  /// Accumulated facts from the whole conversation (keys chosen by the brain).
  final Map<String, Object?> facts;

  /// Facts the user is flexible about ("any", "X okay, others also fine").
  final List<String> flexible;

  /// What still materially changes the decision.
  final List<String> unknownCritical;
  final String readyReason;

  /// The brain decides readiness for this turn.
  bool get gatesSearch => usable && searchReady != null;

  /// Decision-brain mode from the backend: `advice` (reasoning, never result
  /// cards), `commerce` (search / act), `follow_up` (about options already
  /// shown) or `chat`. Older backends omit it (= chat).
  final String mode;

  bool get isAdvice => mode == 'advice';

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
    final state = json['state'] is Map ? Map<String, dynamic>.from(json['state'] as Map) : const <String, dynamic>{};
    List<String> names(Object? raw) => raw is List ? [for (final v in raw) '$v'.trim()].where((v) => v.isNotEmpty).toList() : const [];
    final rawReady = json['search_ready'];

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
      mode: (json['mode'] ?? 'chat').toString().toLowerCase(),
      searchReady: rawReady is bool ? rawReady : null,
      nextQuestion: (json['next_question'] as String?)?.trim().isEmpty ?? true ? null : (json['next_question'] as String).trim(),
      searchSubject: (json['search_subject'] as String?)?.trim().isEmpty ?? true ? null : (json['search_subject'] as String).trim(),
      facts: state['facts'] is Map ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(state['facts'] as Map)) : const {},
      flexible: names(state['flexible']),
      unknownCritical: names(state['unknown_critical']),
      readyReason: (json['ready_reason'] ?? '').toString(),
      newNeed: json['new_need'] == true,
      conversationRelation: (json['conversation_relation'] ?? 'unknown').toString(),
      subjectChanged: json['subject_changed'] == true,
      advice: json['advice'] is Map ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(json['advice'] as Map)) : null,
      adviceLedger: json['advice_ledger'] is List
          ? List<Map<String, Object?>>.unmodifiable([
              for (final entry in json['advice_ledger'] as List)
                if (entry is Map) Map<String, Object?>.unmodifiable(Map<String, Object?>.from(entry)),
            ])
          : null,
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
    Map<String, Object?>? searchedFor,
    List<Map<String, Object?>>? adviceGiven,
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
              if (searchedFor != null && searchedFor.isNotEmpty) 'searched_for': searchedFor,
              if (adviceGiven != null && adviceGiven.isNotEmpty) 'advice_given': adviceGiven,
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
  static final Map<String, String> _localized = {};

  /// One deal question in the conversation language (any language the AI
  /// supports). Null when it cannot be localized -- the caller keeps its own
  /// fallback. English needs no call.
  Future<String?> localizeQuestion(String text, {required String language}) async {
    final clean = text.trim();
    final lang = language.trim().toLowerCase();
    if (clean.isEmpty || lang.isEmpty || lang.split('-').first == 'en') return null;
    final key = '$lang|$clean';
    if (_localized[key] case final cached?) return cached;
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/assistant/localize'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'text': clean, 'language': language}),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final out = decoded is Map ? '${decoded['text'] ?? ''}'.trim() : '';
      if (out.isEmpty || decoded['localized'] != true) return null;
      return _localized[key] = out;
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
