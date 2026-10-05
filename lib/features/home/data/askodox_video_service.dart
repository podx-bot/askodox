import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// What ASKODOX can honestly say about a reviewed video
/// (`POST /api/videos/{id}/explain`). When [analyzed] is false the video's
/// speech was never analyzed and only its title / description are known.
class AskodoxVideoExplanation {
  const AskodoxVideoExplanation({
    required this.videoId,
    required this.analyzed,
    required this.answer,
    this.fromSource = const [],
    this.relationship = 'organic',
    this.relationshipLabel = '',
    this.creator,
    this.next = const [],
  });

  final String videoId;
  final bool analyzed;
  final String answer;

  /// Exact lines from the video's own text (transcript / title /
  /// description) -- never generated.
  final List<String> fromSource;
  final String relationship;

  /// "From the business", "Creator's opinion", "Sponsored", ...
  final String relationshipLabel;
  final String? creator;

  /// Follow-ups ({action, label, ask}) that go through the same chat.
  final List<Map<String, String>> next;

  factory AskodoxVideoExplanation.fromJson(Map<String, Object?> json) => AskodoxVideoExplanation(
        videoId: '${json['video_id'] ?? ''}',
        analyzed: json['analyzed'] == true,
        answer: '${json['answer'] ?? ''}',
        fromSource: [for (final s in (json['from_source'] as List? ?? const [])) '$s'],
        relationship: '${json['relationship'] ?? 'organic'}',
        relationshipLabel: '${json['relationship_label'] ?? ''}',
        creator: json['creator']?.toString(),
        next: [
          for (final n in (json['next'] as List? ?? const []))
            if (n is Map) {for (final e in n.entries) '${e.key}': '${e.value}'},
        ],
      );

  /// Grounding for the assistant: what the source says vs who says it.
  String groundingContext() {
    final lines = <String>[
      analyzed
          ? 'The video was analyzed. Lines quoted from it (source, not ASKODOX):'
          : 'The video was NOT analyzed: only its title/description are known. Do not claim what it says.',
      for (final s in fromSource) '- "$s"',
      if (relationshipLabel.isNotEmpty) 'Relationship: $relationshipLabel (say this when you mention it).',
      if (creator?.isNotEmpty == true) 'Creator: $creator (their opinion, not a verified fact).',
      'Separate what the video says from your own explanation; never invent specs, prices or results.',
    ];
    return lines.join('\n');
  }
}

/// The hard Video Study cap the app checks before offering a study (the
/// backend decides; this only avoids offering an impossible action).
const askodoxVideoStudyMaxSeconds = 180;

/// '0:15', '05:52', '1:02:03' -> seconds; null when unknown.
int? askodoxDurationSeconds(String? text) {
  final raw = (text ?? '').trim();
  final match = RegExp(r'^(?:(\d{1,2}):)?(\d{1,3}):(\d{2})$').firstMatch(raw);
  if (match == null) return int.tryParse(raw);
  return int.parse(match.group(1) ?? '0') * 3600 + int.parse(match.group(2)!) * 60 + int.parse(match.group(3)!);
}

/// 'm:ss' -> seconds (for jump-to-timestamp).
int? askodoxTimestampSeconds(String text) => askodoxDurationSeconds(text);

/// One fact the study found, with where it came from.
class AskodoxVideoFact {
  const AskodoxVideoFact({required this.key, required this.label, required this.value, required this.basis,
      this.timestamp = '', this.evidence = ''});

  final String key;
  final String label;
  final String value;

  /// confirmed_from_video | seller_claim | externally_verified | not_confirmed
  final String basis;
  final String timestamp;
  final String evidence;

  factory AskodoxVideoFact.fromJson(Map<String, Object?> j) => AskodoxVideoFact(
        key: '${j['key'] ?? ''}', label: '${j['label'] ?? ''}', value: '${j['value'] ?? ''}',
        basis: '${j['basis'] ?? 'seller_claim'}', timestamp: '${j['timestamp'] ?? ''}',
        evidence: '${j['evidence'] ?? ''}');
}

/// A grounded study of one video (or why there is none).
class AskodoxVideoStudy {
  const AskodoxVideoStudy({required this.ref, required this.status, this.eligible = true, this.reason,
      this.message = '', this.category = 'other', this.subject = '', this.summary = '', this.facts = const [],
      this.missing = const [], this.suggestedQuestions = const [], this.durationSeconds});

  final String ref;

  /// none | ready | unavailable | not_eligible
  final String status;
  final bool eligible;
  final String? reason;
  final String message;
  final String category;
  final String subject;
  final String summary;
  final List<AskodoxVideoFact> facts;
  final List<String> missing;
  final List<String> suggestedQuestions;
  final int? durationSeconds;

  bool get ready => status == 'ready';

  factory AskodoxVideoStudy.fromJson(Map<String, Object?> j) {
    final inner = j['study'] is Map ? Map<String, Object?>.from(j['study'] as Map) : j;
    return AskodoxVideoStudy(
      ref: '${j['ref'] ?? inner['ref'] ?? ''}',
      status: '${inner['status'] ?? j['status'] ?? 'none'}',
      eligible: j['eligible'] != false,
      reason: j['reason']?.toString(),
      message: '${inner['message'] ?? j['message'] ?? ''}',
      category: '${inner['category'] ?? 'other'}',
      subject: '${inner['subject'] ?? ''}',
      summary: '${inner['summary'] ?? ''}',
      facts: [
        for (final f in (inner['facts'] as List? ?? const []))
          if (f is Map) AskodoxVideoFact.fromJson(Map<String, Object?>.from(f)),
      ],
      missing: [for (final m in (inner['missing'] as List? ?? const [])) '$m'],
      suggestedQuestions: [
        for (final q in (inner['suggested_questions'] as List? ?? j['suggested_questions'] as List? ?? const []))
          '$q'
      ],
      durationSeconds: (inner['duration_seconds'] ?? j['duration_seconds']) is num
          ? ((inner['duration_seconds'] ?? j['duration_seconds']) as num).toInt()
          : null,
    );
  }

  /// One line carrying what the video offers into the request/order flow,
  /// so the customer never re-types it.
  String contextLine() {
    String? value(List<String> hints) {
      for (final f in facts) {
        if (hints.any(f.key.contains)) return f.value;
      }
      return null;
    }

    final parts = <String>[
      for (final k in const ['year', 'make', 'brand', 'product', 'model', 'variant', 'service', 'type'])
        if (value([k]) case final v?) v,
    ];
    final what = (parts.isEmpty ? subject : parts.toSet().join(' ')).trim();
    final price = value(const ['asking', 'price', 'rent', 'quoted']);
    final where = value(const ['location', 'registration']);
    return [what, if (price != null) 'asking $price', if (where != null) 'in $where']
        .where((p) => p.trim().isNotEmpty)
        .join(', ');
  }
}

/// A grounded answer: only from the stored study.
class AskodoxVideoAnswer {
  const AskodoxVideoAnswer({required this.found, required this.answer, this.facts = const [],
      this.timestamps = const [], this.basis});

  final bool found;
  final String answer;
  final List<AskodoxVideoFact> facts;
  final List<String> timestamps;

  /// Registered videos: seen_in_video / said_by_seller / listing / askodox /
  /// unknown (where the answer comes from).
  final String? basis;

  factory AskodoxVideoAnswer.fromJson(Map<String, Object?> j) => AskodoxVideoAnswer(
        found: j['found'] == true,
        answer: '${j['answer'] ?? ''}',
        facts: [
          for (final f in (j['facts'] as List? ?? const []))
            if (f is Map) AskodoxVideoFact.fromJson(Map<String, Object?>.from(f)),
        ],
        timestamps: [for (final t in (j['timestamps'] as List? ?? const [])) '$t'],
        basis: j['basis'] == null ? null : '${j['basis']}',
      );
}

/// Explain + funnel tracking for reviewed videos. Tracking is
/// fire-and-forget and never blocks the customer.
class AskodoxVideoService {
  const AskodoxVideoService(this._client);

  final ApiClient _client;

  static const trackedEvents = {
    'video_impression', 'video_open', 'video_watch_start', 'video_watch_complete', 'video_ask',
    'video_product_click', 'video_service_click', 'video_local_search', 'video_affiliate_click', 'video_contact',
  };

  Future<AskodoxVideoExplanation?> explain(String videoId, {String question = '', String language = 'en'}) async {
    final result = await _client.post<Map<String, Object?>>(
      '/api/videos/${Uri.encodeComponent(videoId)}/explain',
      body: {'question': question, 'language': language},
    );
    return switch (result) {
      ApiSuccess(:final data) => AskodoxVideoExplanation.fromJson(data),
      ApiError() => null,
    };
  }

  /// Eligibility + cached study (no model call).
  Future<AskodoxVideoStudy?> studyStatus(String videoId, {String language = 'en'}) async {
    final result = await _client.get<Map<String, Object?>>(
        '/api/videos/${Uri.encodeComponent(videoId)}/study?language=${Uri.encodeQueryComponent(language)}');
    return switch (result) {
      ApiSuccess(:final data) => AskodoxVideoStudy.fromJson(data),
      ApiError() => null,
    };
  }

  /// Study the video now (only when eligible; cached by the backend).
  Future<AskodoxVideoStudy?> study(String videoId, {String language = 'en'}) async {
    final result = await _client.post<Map<String, Object?>>('/api/videos/${Uri.encodeComponent(videoId)}/study',
        body: {'language': language}, options: const ApiRequestOptions(timeout: Duration(seconds: 120)));
    return switch (result) {
      ApiSuccess(:final data) => AskodoxVideoStudy.fromJson(data),
      ApiError() => null,
    };
  }

  Future<AskodoxVideoAnswer?> ask(String videoId, String question, {String language = 'en'}) async {
    // A registered ASKODOX video (`nv_<id>`) is answered by the commerce
    // endpoint: study + the seller's listing / FAQ, sensitive topics to the
    // seller, every answer labelled with its basis.
    final path = videoId.startsWith('nv_')
        ? '/api/videos/native/${Uri.encodeComponent(videoId.substring(3))}/ask'
        : '/api/videos/${Uri.encodeComponent(videoId)}/ask';
    final result = await _client.post<Map<String, Object?>>(path, body: {'question': question, 'language': language});
    return switch (result) {
      ApiSuccess(:final data) => AskodoxVideoAnswer.fromJson(data),
      ApiError() => null,
    };
  }

  /// External market comparison (kept apart from the video's own facts).
  Future<Map<String, Object?>?> market(String videoId, {String language = 'en', Map<String, Object?>? location}) async {
    final result = await _client.post<Map<String, Object?>>('/api/videos/${Uri.encodeComponent(videoId)}/market',
        body: {'language': language, if (location != null) 'location': location},
        options: const ApiRequestOptions(timeout: Duration(seconds: 60)));
    return switch (result) {
      ApiSuccess(:final data) => data,
      ApiError() => null,
    };
  }

  void track(String event, String? videoId, {String category = '', String language = ''}) {
    if (videoId == null || videoId.isEmpty || !trackedEvents.contains(event)) return;
    _client.post<Map<String, Object?>>('/api/track', body: {
      'event': event,
      'ids': {'video_id': videoId},
      if (category.isNotEmpty) 'category': category,
      if (language.isNotEmpty) 'language': language,
    }).then((_) {}, onError: (_) {});
  }
}

final askodoxVideoServiceProvider =
    Provider<AskodoxVideoService>((ref) => AskodoxVideoService(ref.watch(apiClientProvider)));
