import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// ASKODOX Talk: anonymous topic discussions (owner 2026-11-08). Nobody sees
/// who anybody is -- the server gives each person a made-up name per room
/// and never sends a number or id; a person's own messages carry `mine`.
class AskodoxTalkRoom {
  const AskodoxTalkRoom({required this.id, required this.topic, this.messages = 0, this.alias, this.aliasEn});
  final String id, topic;
  final int messages;

  /// The caller's own made-up name in this room (only when known).
  final String? alias, aliasEn;

  factory AskodoxTalkRoom.fromJson(Map<String, Object?> j) {
    final you = j['you'] is Map ? j['you'] as Map : const {};
    return AskodoxTalkRoom(
      id: '${j['id'] ?? ''}',
      topic: '${j['topic'] ?? ''}',
      messages: (j['messages'] as num?)?.toInt() ?? 0,
      alias: you['alias'] as String?,
      aliasEn: you['alias_en'] as String?,
    );
  }
}

class AskodoxTalkMessage {
  const AskodoxTalkMessage({required this.id, required this.seq, required this.alias, required this.aliasEn,
      required this.text, this.mine = false, this.masked = false, this.kind = 'text'});
  final String id, alias, aliasEn, text, kind;
  final int seq;
  final bool mine, masked;

  factory AskodoxTalkMessage.fromJson(Map<String, Object?> j) => AskodoxTalkMessage(
        id: '${j['id'] ?? ''}',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        alias: '${j['alias'] ?? ''}',
        aliasEn: '${j['alias_en'] ?? ''}',
        text: '${j['text'] ?? ''}',
        kind: '${j['kind'] ?? 'text'}',
        mine: j['mine'] == true,
        masked: j['masked'] == true,
      );
}

/// What happened to a sent message. [posted] false = held (not shown to anyone).
class AskodoxTalkSent {
  const AskodoxTalkSent({this.posted = false, this.category = 'none', this.text = '', this.maskedWords = 0,
      this.contactsHidden = 0, this.support, this.mutedUntil, this.problem});
  final bool posted;
  final String category, text;
  final int maskedWords, contactsHidden;
  final String? support, mutedUntil, problem;
}

class AskodoxTalkPage {
  const AskodoxTalkPage({required this.messages, this.mutedUntil, this.problem});
  final List<AskodoxTalkMessage> messages;
  final String? mutedUntil, problem;
}

String askodoxTalkProblemText(String code, bool te) => switch (code) {
      'muted' => te
          ? 'మీ కొన్ని messages నియమాలకు విరుద్ధంగా ఉన్నాయి. 24 గంటలు మీరు పంపలేరు, చదవగలరు.'
          : 'Some of your messages broke the rules. You can read, but not send, for 24 hours.',
      'topic_not_allowed' => te
          ? 'ఈ topic పేరులో అనుమతి లేని మాటలు / నంబర్లు ఉన్నాయి. వేరే పేరు ఇవ్వండి.'
          : 'This topic name has words or contacts that are not allowed. Try another name.',
      'topic_length' => te ? 'topic పేరు 2 నుంచి 80 అక్షరాలు ఉండాలి.' : 'A topic needs 2 to 80 characters.',
      'too_long' => te ? 'message చాలా పెద్దది (500 అక్షరాలు వరకు).' : 'The message is too long (up to 500 characters).',
      'AI_CREDITS_LOW' => te
          ? 'వినడానికి AI Credits సరిపోవు. టెక్స్ట్ చదవడం ఉచితం.'
          : 'Not enough AI Credits to listen. Reading the text is free.',
      'rate' => te ? 'కొంచెం నెమ్మదిగా — కొద్దిసేపు ఆగి మళ్ళీ పంపండి.' : 'A little slower — wait a moment and send again.',
      'signin' => te ? 'సైన్ ఇన్ చేయండి.' : 'Please sign in.',
      _ => te ? 'ఇప్పుడు అందుబాటులో లేదు. మళ్ళీ ప్రయత్నించండి.' : 'Not available right now. Please try again.',
    };

String _code(ApiFailure f) {
  if (f.statusCode == 401) return 'signin';
  if (f.statusCode == 429) return 'rate';
  final m = f.message ?? '';
  for (final c in const ['muted', 'topic_not_allowed', 'topic_length', 'too_long', 'AI_CREDITS_LOW']) {
    if (m.contains(c)) return c;
  }
  return 'unavailable';
}

class TalkRepository {
  const TalkRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  bool get signedIn => authToken != null && authToken!.isNotEmpty;
  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<List<AskodoxTalkRoom>> rooms(String query) async {
    if (!signedIn) return const [];
    final q = Uri.encodeQueryComponent(query.trim());
    final result = await _client.get<Map<String, Object?>>('/api/talk/rooms?q=$q', options: _auth);
    if (result is! ApiSuccess<Map<String, Object?>>) return const [];
    return [
      for (final r in (result.data['rooms'] as List?) ?? const [])
        if (r is Map) AskodoxTalkRoom.fromJson(Map<String, Object?>.from(r)),
    ];
  }

  /// Joins (or starts) the room for [topic]. Returns the room or a problem code.
  Future<(AskodoxTalkRoom?, String?)> open(String topic) async {
    final result = await _client.post<Map<String, Object?>>('/api/talk/rooms',
        body: {'topic': topic, 'adult': true}, options: _auth);
    if (result is ApiError<Map<String, Object?>>) return (null, _code(result.failure));
    final room = (result as ApiSuccess<Map<String, Object?>>).data['room'];
    if (room is! Map) return (null, 'unavailable');
    return (AskodoxTalkRoom.fromJson(Map<String, Object?>.from(room)), null);
  }

  Future<AskodoxTalkPage> messages(String roomId, {int after = 0}) async {
    final result =
        await _client.get<Map<String, Object?>>('/api/talk/rooms/$roomId/messages?after=$after', options: _auth);
    if (result is ApiError<Map<String, Object?>>) {
      return AskodoxTalkPage(messages: const [], problem: _code(result.failure));
    }
    final d = (result as ApiSuccess<Map<String, Object?>>).data;
    return AskodoxTalkPage(
      mutedUntil: d['muted_until'] as String?,
      messages: [
        for (final m in (d['messages'] as List?) ?? const [])
          if (m is Map) AskodoxTalkMessage.fromJson(Map<String, Object?>.from(m)),
      ],
    );
  }

  Future<AskodoxTalkSent> send(String roomId, String text, {String kind = 'text', String lang = 'te'}) async {
    final result = await _client.post<Map<String, Object?>>('/api/talk/rooms/$roomId/messages',
        body: {'text': text, 'kind': kind, 'lang': lang}, options: _auth);
    if (result is ApiError<Map<String, Object?>>) return AskodoxTalkSent(problem: _code(result.failure));
    final d = (result as ApiSuccess<Map<String, Object?>>).data;
    return AskodoxTalkSent(
      posted: d['posted'] == true,
      category: '${d['category'] ?? 'none'}',
      text: '${d['text'] ?? ''}',
      maskedWords: (d['masked_words'] as num?)?.toInt() ?? 0,
      contactsHidden: (d['contacts_hidden'] as num?)?.toInt() ?? 0,
      support: d['support'] as String?,
      mutedUntil: d['muted_until'] as String?,
    );
  }

  Future<bool> report(String messageId, String reason) async {
    final result = await _client.post<Map<String, Object?>>('/api/talk/messages/$messageId/report',
        body: {'reason': reason}, options: _auth);
    return result is ApiSuccess<Map<String, Object?>>;
  }

  Future<bool> block(String messageId) async {
    final result = await _client.post<Map<String, Object?>>('/api/talk/messages/$messageId/block', options: _auth);
    return result is ApiSuccess<Map<String, Object?>>;
  }

  /// The message read aloud in the ASKODOX voice (masked words = "beep").
  Future<(Uint8List?, String, String?)> speak(String messageId, String lang) async {
    final result = await _client.post<Map<String, Object?>>('/api/talk/messages/$messageId/speak',
        body: {'lang': lang}, options: _auth);
    if (result is ApiError<Map<String, Object?>>) return (null, '', _code(result.failure));
    final d = (result as ApiSuccess<Map<String, Object?>>).data;
    final b64 = d['audio_b64'];
    return (b64 is String && b64.isNotEmpty ? base64Decode(b64) : null, '${d['text'] ?? ''}', null);
  }
}

final talkRepositoryProvider = Provider<TalkRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return TalkRepository(ref.watch(apiClientProvider), authToken: session.user == null ? null : session.tokenPlaceholder);
});
