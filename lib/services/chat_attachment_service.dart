import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/api_models.dart';
import '../core/providers/backend_providers.dart';

/// A real attachment waiting in the chat composer: the actual bytes, the
/// MIME type and a preview. It is never reduced to a file name.
class ChatAttachment {
  ChatAttachment({required this.name, required this.bytes, String? mimeType})
      : mimeType = askodoxResolveMimeType(name, mimeType);

  final String name;
  final Uint8List bytes;
  final String mimeType;

  String get kind => askodoxAttachmentKind(mimeType);
  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
}

/// What the backend actually understood from the attachment.
class ChatAttachmentResult {
  const ChatAttachmentResult({
    required this.id,
    required this.kind,
    required this.facts,
    required this.analysis,
    this.lowConfidence = false,
    this.videoStudy,
  });

  /// An uploaded clip's Video Study ({ref, status, eligible, reason,
  /// message, suggested_questions}); null for other kinds.
  final Map<String, Object?>? videoStudy;

  /// The vision brain answered but was not sure -- the chat must say so and
  /// ask the customer to confirm instead of presenting it as fact.
  final bool lowConfidence;

  final String id;
  final String kind;

  /// Short factual text built by the backend from the real analysis.
  final String facts;
  final Map<String, Object?> analysis;
}

class ChatAttachmentException implements Exception {
  const ChatAttachmentException(this.code, this.message, {this.statusCode, this.endpoint, this.kind});

  /// unsupported | too_large | unavailable | not_understood | failed |
  /// timeout | network
  final String code;
  final String message;

  /// HTTP status of the failed call (null = it never got a response).
  final int? statusCode;

  /// Which backend path answered ('unified' or 'legacy').
  final String? endpoint;

  /// image | video | document (null when not known).
  final String? kind;

  bool get retryable => code == 'failed' || code == 'network' || code == 'timeout' || code == 'unavailable';

  /// Safe, short diagnostic for the customer / support: the error code and
  /// HTTP status only -- never the response body or the file content.
  String get diagnostic =>
      [code, if (statusCode != null) 'HTTP $statusCode', if (endpoint != null) endpoint!].join(' · ');

  @override
  String toString() => message;
}

const _mimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'gif': 'image/gif',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'm4v': 'video/mp4',
  'webm': 'video/webm',
  '3gp': 'video/3gpp',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

String askodoxResolveMimeType(String name, String? declared) {
  final mime = (declared ?? '').trim().toLowerCase();
  if (mime.isNotEmpty && mime != 'application/octet-stream') return mime;
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return _mimeByExtension[ext] ?? 'application/octet-stream';
}

String askodoxAttachmentKind(String mimeType) {
  if (mimeType.startsWith('image/')) return 'image';
  if (mimeType.startsWith('video/')) return 'video';
  if (_mimeByExtension.values.contains(mimeType)) return 'document';
  return 'unsupported';
}

abstract interface class ChatAttachmentService {
  Future<ChatAttachmentResult> analyze(
    ChatAttachment attachment, {
    required String userText,
    required String language,
    String conversationId = '',
  });
}

/// POST /api/attachments/analyze -- the ONE path for Camera, Photos, Video
/// and Files. The bytes go to the backend; it picks the image, video or
/// document processor by MIME type.
///
/// A backend that does not have the unified route yet (404/405 -- e.g.
/// production still on an older release) is served by the SAME processors
/// behind the older per-kind routes (`/vision/analyze`,
/// `/vision/analyze-video`, `/documents/analyze`); the facts are then built
/// here from the real analysis ([askodoxAttachmentFacts]). The bytes are
/// always sent; nothing is summarised from the file name.
class ApiChatAttachmentService implements ChatAttachmentService {
  ApiChatAttachmentService(this._client);

  final ApiClient _client;

  /// Remembered after the first 404/405 so later attachments go straight
  /// to the per-kind routes.
  bool _unifiedMissing = false;

  static const legacyVideoLimit = 19 * 1024 * 1024;

  static const _legacyPaths = {
    'image': '/vision/analyze',
    'video': '/vision/analyze-video',
    'document': '/documents/analyze',
  };

  ApiRequestOptions _options(ChatAttachment attachment) =>
      ApiRequestOptions(timeout: Duration(seconds: attachment.isVideo ? 120 : 60));

  @override
  Future<ChatAttachmentResult> analyze(
    ChatAttachment attachment, {
    required String userText,
    required String language,
    String conversationId = '',
  }) async {
    if (attachment.kind == 'unsupported') {
      throw const ChatAttachmentException('unsupported', 'unsupported');
    }
    if (attachment.bytes.isEmpty) {
      throw const ChatAttachmentException('failed', 'empty file');
    }
    final encoded = base64Encode(attachment.bytes);
    if (!_unifiedMissing) {
      final result = await _client.post<Map<String, Object?>>(
        '/api/attachments/analyze',
        body: {
          'file_base64': encoded,
          'filename': attachment.name,
          'mime_type': attachment.mimeType,
          'user_text': userText,
          'language': language,
          'conversation_id': conversationId,
        },
        options: _options(attachment),
      );
      if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
        final facts = '${data['facts'] ?? ''}'.trim();
        final record = data['attachment'];
        if (facts.isEmpty) throw const ChatAttachmentException('not_understood', 'empty analysis', endpoint: 'unified');
        return ChatAttachmentResult(
          id: record is Map ? '${record['id'] ?? ''}' : '',
          kind: record is Map ? '${record['kind'] ?? attachment.kind}' : attachment.kind,
          facts: facts,
          analysis: data['analysis'] is Map ? Map<String, Object?>.from(data['analysis'] as Map) : const {},
          lowConfidence: data['understanding'] is Map && (data['understanding'] as Map)['status'] == 'low_confidence',
          videoStudy: data['video_study'] is Map ? Map<String, Object?>.from(data['video_study'] as Map) : null,
        );
      }
      final failure = (result as ApiError<Map<String, Object?>>).failure;
      if (failure.statusCode != 404 && failure.statusCode != 405) {
        throw _exception(failure, 'unified', attachment.kind);
      }
      _unifiedMissing = true;
    }
    return _analyzeLegacy(attachment, encoded, userText: userText, language: language);
  }

  Future<ChatAttachmentResult> _analyzeLegacy(
    ChatAttachment attachment,
    String encoded, {
    required String userText,
    required String language,
  }) async {
    final kind = attachment.kind;
    // The older video route sends the clip inline to the video brain, which
    // cannot take more than ~20 MB: say so instead of uploading in vain.
    if (kind == 'video' && attachment.bytes.length > legacyVideoLimit) {
      throw const ChatAttachmentException('too_large', 'video too large for this server',
          endpoint: 'legacy', kind: 'video');
    }
    final body = switch (kind) {
      'image' => {
          'image_base64': encoded,
          'mime_type': attachment.mimeType,
          'user_text': userText,
          'language': language
        },
      'video' => {
          'video_base64': encoded,
          'mime_type': attachment.mimeType,
          'user_text': userText,
          'language': language
        },
      _ => {'file_base64': encoded, 'filename': attachment.name, 'mime_type': attachment.mimeType},
    };
    final result =
        await _client.post<Map<String, Object?>>(_legacyPaths[kind]!, body: body, options: _options(attachment));
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final analysis =
          data['analysis'] is Map ? Map<String, Object?>.from(data['analysis'] as Map) : const <String, Object?>{};
      final facts = askodoxAttachmentFacts(kind, analysis);
      if (facts.isEmpty) throw const ChatAttachmentException('not_understood', 'empty analysis', endpoint: 'legacy');
      return ChatAttachmentResult(id: '', kind: kind, facts: facts, analysis: analysis);
    }
    throw _exception((result as ApiError<Map<String, Object?>>).failure, 'legacy', kind);
  }

  ChatAttachmentException _exception(ApiFailure failure, String endpoint, String kind) {
    final code = switch (failure.statusCode) {
      415 => 'unsupported',
      413 => 'too_large',
      503 => 'unavailable',
      422 => 'not_understood',
      null when failure.type == ApiFailureType.timeout => 'timeout',
      null => 'network',
      _ => 'failed',
    };
    return ChatAttachmentException(code, failure.message ?? code,
        statusCode: failure.statusCode, endpoint: endpoint, kind: kind);
  }
}

String _factText(Object? value) {
  // "[Page 1]" markers alone (a PDF without a text layer) are not content.
  if ('${value ?? ''}'.replaceAll(RegExp(r'\[Page \d+\]'), '').trim().isEmpty) return '';
  final text = '${value ?? ''}'.trim().split(RegExp(r'\s+')).join(' ');
  return const {'', 'null', 'none', 'unknown'}.contains(text.toLowerCase()) ? '' : text;
}

/// Short factual text from ANY analysis shape (image, video, document).
/// Mirrors `backend/app/services/attachment_facts.py`; only values the
/// analysis actually produced are used -- nothing is invented.
String askodoxAttachmentFacts(String kind, Map<String, Object?> data) {
  final parts = <String>[];
  void add(String label, Object? value) {
    final text = _factText(value);
    if (text.isEmpty || parts.any((p) => p.contains(text))) return;
    parts.add(label.isEmpty ? text : '$label: $text');
  }

  bool present(Object? v) => v != null && '$v' != '';
  if (kind == 'image') {
    add('Shows', data['subject']);
    add('Type', data['domain']);
    add('Brand', data['brand']);
    add('Model', data['model']);
    if (present(data['quantity'])) add('Quantity', '${data['quantity']} ${_factText(data['unit'])}'.trim());
    if (present(data['price'])) add('Price visible', '${_factText(data['currency'])} ${data['price']}'.trim());
    add('Visible text', data['visible_text']);
    add('Place', data['location_text']);
    final constraints = [
      for (final c in (data['constraints'] as List? ?? const []))
        if (_factText(c).isNotEmpty) _factText(c),
    ];
    if (constraints.isNotEmpty) add('Details', constraints.take(6).join(', '));
    final side = _factText(data['side']).toUpperCase();
    if (side == 'NEED' || side == 'OFFER') {
      add('The customer seems to', side == 'NEED' ? 'want this' : 'offer/sell this');
    }
    add('Summary', data['summary']);
  } else if (kind == 'video') {
    add('Shows', data['subject']);
    add('Video shows', _factText(data['visual_summary']).isNotEmpty ? data['visual_summary'] : data['summary']);
    add('Said in the video',
        _factText(data['spoken_transcript']).isNotEmpty ? data['spoken_transcript'] : data['transcript']);
    add('Brand', data['brand']);
  } else {
    add('Document', _factText(data['title']).isNotEmpty ? data['title'] : data['document_type']);
    add('Summary', data['summary']);
    add('', _factText(data['text']).isNotEmpty ? data['text'] : data['visible_text']);
    for (final page in (data['pages'] as List? ?? const []).take(6)) {
      if (page is Map) add('', page['text']);
    }
    for (final sheet in (data['sheets'] as List? ?? const []).take(3)) {
      if (sheet is! Map) continue;
      final rows = [
        for (final row in (sheet['rows'] as List? ?? const []).take(15))
          if (row is List) row.map((c) => '$c').join(' | '),
      ];
      add('Sheet ${_factText(sheet['name'])}'.trim(), rows.join('; '));
    }
  }
  final joined = parts.join('\n');
  return (joined.length > 1500 ? joined.substring(0, 1500) : joined).trim();
}

final chatAttachmentServiceProvider = Provider<ChatAttachmentService>(
  (ref) => ApiChatAttachmentService(ref.watch(apiClientProvider)),
);
