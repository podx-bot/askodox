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
