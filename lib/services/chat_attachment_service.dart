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
  });

  final String id;
  final String kind;

  /// Short factual text built by the backend from the real analysis.
  final String facts;
  final Map<String, Object?> analysis;
}

class ChatAttachmentException implements Exception {
  const ChatAttachmentException(this.code, this.message);

  /// unsupported | too_large | unavailable | failed | network
  final String code;
  final String message;

  bool get retryable => code == 'failed' || code == 'network' || code == 'unavailable';

  @override
  String toString() => message;
}

const _mimeByExtension = {
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'heic': 'image/heic',
  'heif': 'image/heif', 'gif': 'image/gif', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/mp4',
  'webm': 'video/webm', '3gp': 'video/3gpp', 'pdf': 'application/pdf', 'txt': 'text/plain', 'csv': 'text/csv',
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
class ApiChatAttachmentService implements ChatAttachmentService {
  const ApiChatAttachmentService(this._client);

  final ApiClient _client;

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
    final result = await _client.post<Map<String, Object?>>(
      '/api/attachments/analyze',
      body: {
        'file_base64': base64Encode(attachment.bytes),
        'filename': attachment.name,
        'mime_type': attachment.mimeType,
        'user_text': userText,
        'language': language,
        'conversation_id': conversationId,
      },
      options: ApiRequestOptions(timeout: Duration(seconds: attachment.isVideo ? 120 : 60)),
    );
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) {
      final facts = '${data['facts'] ?? ''}'.trim();
      final record = data['attachment'];
      if (facts.isEmpty) throw const ChatAttachmentException('failed', 'empty analysis');
      return ChatAttachmentResult(
        id: record is Map ? '${record['id'] ?? ''}' : '',
        kind: record is Map ? '${record['kind'] ?? attachment.kind}' : attachment.kind,
        facts: facts,
        analysis: data['analysis'] is Map ? Map<String, Object?>.from(data['analysis'] as Map) : const {},
      );
    }
    final failure = (result as ApiError<Map<String, Object?>>).failure;
    final code = switch (failure.statusCode) {
      415 => 'unsupported',
      413 => 'too_large',
      503 => 'unavailable',
      null => 'network',
      _ => 'failed',
    };
    throw ChatAttachmentException(code, failure.message ?? code);
  }
}

final chatAttachmentServiceProvider = Provider<ChatAttachmentService>(
  (ref) => ApiChatAttachmentService(ref.watch(apiClientProvider)),
);
