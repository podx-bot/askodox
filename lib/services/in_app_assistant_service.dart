import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/flags/askodox_release_phase.dart';

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

/// One app destination from the chat-actions catalog (key, in-app route,
/// button label). Only internal routes ("/...") are ever accepted.
class AskodoxAppAction {
  const AskodoxAppAction({required this.key, required this.route, required this.label});

  final String key;
  final String route;
  final String label;

  static AskodoxAppAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = '${raw['key'] ?? ''}'.trim();
    final route = '${raw['route'] ?? ''}'.trim();
    final label = '${raw['label'] ?? ''}'.trim();
    if (key.isEmpty || label.isEmpty || !askodoxIsInternalRoute(route)) return null;
    return AskodoxAppAction(key: key, route: route, label: label);
  }
}

/// An in-app path only: starts with one "/", no scheme, host, ".." or spaces.
bool askodoxIsInternalRoute(String route) =>
    RegExp(r'^/[A-Za-z0-9_\-/]*$').hasMatch(route) && !route.startsWith('//') && !route.contains('..');

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
    this.intelligence,
    this.groundingVerified,
    this.groundingMode,
    this.honesty = const <String>[],
    this.appAction,
    this.suggestions = const <String>[],
  });

  /// Smart Answer chips (backend reply_suggestions.py): 2-5 short things the
  /// user can tap to say next, drawn under the latest reply. A tap sends the
  /// chip's text as the user's message. Empty for older backends.
  final List<String> suggestions;

  /// Chat actions (backend chat_actions.py): ONE ASKODOX screen the user
  /// asked to open or use, shown as a button under the reply (never opened
  /// automatically). Null when the turn has none or the backend is older.
  final AskodoxAppAction? appAction;

  /// Live web check for this reply (backend live_lookup.py): true = answered
  /// from live sources, false = a live check was needed but failed, null =
  /// no live check was needed (or an older backend).
  final bool? groundingVerified;

  /// 'quick' (one search) or 'deep' (several angles); null when none ran.
  final String? groundingMode;

  /// Honesty guard reasons the backend applied to this reply (for example an
  /// unbacked "fake / not released" verdict that was removed).
  final List<String> honesty;

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

  /// Master command round 2 (backend intelligence_gate.py): a sourced tax /
  /// GST, fraud & market reality or smart-trick card for THIS turn, only when
  /// the user's own words asked. Null otherwise and from older backends.
  final Map<String, Object?>? intelligence;

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
      intelligence: json['intelligence'] is Map
          ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(json['intelligence'] as Map))
          : null,
      groundingVerified: json['grounding'] is Map ? (json['grounding'] as Map)['verified'] == true : null,
      groundingMode: json['grounding'] is Map ? (json['grounding'] as Map)['mode']?.toString() : null,
      honesty: names(json['honesty']),
      appAction: AskodoxAppAction.fromJson(json['app_action']),
      suggestions: names(json['suggestions']).take(5).toList(growable: false),
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
    String? authToken,
  }) async {
    final clean = message.trim();
    // A real session token lets the brain use THIS user's earlier requests (personal answers).
    final token = authToken == null || authToken.isEmpty || authToken == 'OTP_VERIFIED' || authToken == 'DEMO_ONLY'
        ? null
        : authToken;
    if (clean.isEmpty) return null;
    final cleanLocation = location?.trim();

    final ownClient = _client == null;
    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/in-app/assistant'),
            headers: _headers(token, 'application/json'),
            body: jsonEncode(_body(clean, locale, history, cleanLocation, searchedFor, adviceGiven)),
          )
          // A full how-to guide takes 10-30 s to write (owner probe 2026-11-10); at 15 s the
          // phone gave up and showed the generic reply instead of the answer.
          .timeout(const Duration(seconds: 45));

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

  Map<String, String> _headers(String? token, String accept) => {
        'Accept': accept,
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, Object?> _body(String clean, String locale, List<InAppAssistantTurn> history, String? cleanLocation,
          Map<String, Object?>? searchedFor, List<Map<String, Object?>>? adviceGiven) =>
      {
        'message': clean,
        'locale': locale,
        'history': history.takeLast(12).map((turn) => turn.toJson()).toList(),
        if (cleanLocation != null && cleanLocation.isNotEmpty) 'location': cleanLocation,
        if (searchedFor != null && searchedFor.isNotEmpty) 'searched_for': searchedFor,
        if (adviceGiven != null && adviceGiven.isNotEmpty) 'advice_given': adviceGiven,
        // This build renders [ok] / [caution] / [risk] meaning tags and
        // shows a chat-action button (app_action) under a reply. A Phase 1
        // build opens only Phase 1 screens, so the brain offers only those.
        // 'suggestions' = this build draws tap chips under the reply.
        'capabilities': ['meaning_tags', 'app_actions', 'suggestions', if (!askodoxPhase2) 'phase1_only'],
      };

  /// The same decision as [decide], but a long answer (how-to guide / advice) is shown
  /// while it is written: [onText] gets the whole text so far after every piece ('' when a
  /// started answer is withdrawn for a fallback). The returned decision is the real answer
  /// -- callers handle it exactly like [decide]'s. An older backend without the stream
  /// route (404 / 405) is asked through [decide].
  Future<InAppAssistantDecision?> decideStreaming({
    required String message,
    required String locale,
    required List<InAppAssistantTurn> history,
    required void Function(String textSoFar) onText,
    String? location,
    Map<String, Object?>? searchedFor,
    List<Map<String, Object?>>? adviceGiven,
    String? authToken,
  }) async {
    final clean = message.trim();
    final token = authToken == null || authToken.isEmpty || authToken == 'OTP_VERIFIED' || authToken == 'DEMO_ONLY'
        ? null
        : authToken;
    if (clean.isEmpty) return null;
    final cleanLocation = location?.trim();
    final ownClient = _client == null;
    final client = _client ?? http.Client();
    var shown = '';
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/api/in-app/assistant/stream'))
        ..headers.addAll(_headers(token, 'application/x-ndjson, application/json'))
        ..body = jsonEncode(_body(clean, locale, history, cleanLocation, searchedFor, adviceGiven));
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode == 404 || response.statusCode == 405) {
        await response.stream.drain<void>();
        return await decide(
          message: message,
          locale: locale,
          history: history,
          location: location,
          searchedFor: searchedFor,
          adviceGiven: adviceGiven,
          authToken: authToken,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      // Between two pieces at most 45 s (routing + a full answer can take that long before
      // the first piece); the whole answer has no fixed limit while text keeps coming.
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45));
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line);
        if (event is! Map<String, dynamic>) continue;
        switch (event['type']) {
          case 'delta':
            shown += '${event['text'] ?? ''}';
            onText(shown);
          case 'reset':
            shown = '';
            onText('');
          case 'final':
            final decision = event['decision'];
            return decision is Map<String, dynamic> ? InAppAssistantDecision.fromJson(decision) : null;
          case null when event.containsKey('reply'):
            // A server that answered with the plain /assistant JSON.
            return InAppAssistantDecision.fromJson(event);
        }
      }
      return null;
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
