import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Internet push-to-talk groups (`/api/ptt/*`): store-and-forward voice clips,
/// members only, clips expire after 24 h. Not an offline radio.
class AskodoxPttChannel {
  const AskodoxPttChannel({required this.id, required this.code, required this.name, required this.members});
  final String id;
  final String code;
  final String name;
  final int members;

  factory AskodoxPttChannel.fromJson(Map<String, Object?> j) => AskodoxPttChannel(
      id: '${j['id']}', code: '${j['code']}', name: '${j['name']}', members: (j['members'] as num?)?.toInt() ?? 0);
}

class AskodoxPttClip {
  const AskodoxPttClip(
      {required this.id, required this.senderName, required this.mine, required this.durationMs, required this.createdAt});
  final String id;
  final String senderName;
  final bool mine;
  final int durationMs;
  final String createdAt;

  factory AskodoxPttClip.fromJson(Map<String, Object?> j) => AskodoxPttClip(
        id: '${j['id']}',
        senderName: '${j['sender_name'] ?? ''}',
        mine: j['mine'] == true,
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        createdAt: '${j['created_at'] ?? ''}',
      );
}

class AskodoxPttException implements Exception {
  const AskodoxPttException(this.code, [this.status]);

  /// sign_in | not_found | not_member | too_long | network | failed
  final String code;
  final int? status;

  String message(bool te) => switch (code) {
        'sign_in' => te ? 'వాకీ-టాకీ కోసం సైన్ ఇన్ చేయండి.' : 'Sign in to use push-to-talk.',
        'not_found' => te ? 'ఈ కోడ్‌తో గ్రూప్ లేదు.' : 'No group with this code.',
        'not_member' => te ? 'ముందు గ్రూప్‌లో చేరండి.' : 'Join the group first.',
        'too_long' => te ? 'క్లిప్ చాలా పొడవు (60 సెకన్లు గరిష్టం).' : 'Clip too long (60 seconds max).',
        'network' => te ? 'ఇంటర్నెట్ కావాలి — ఇది ఆఫ్‌లైన్ రేడియో కాదు.' : 'Internet is needed — this is not an offline radio.',
        _ => te ? 'ఇప్పుడు కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'That did not work. Please try again.',
      };
}

AskodoxPttException _error(int? status) => AskodoxPttException(
    switch (status) {
      401 => 'sign_in',
      403 => 'not_member',
      404 => 'not_found',
      413 || 422 => 'too_long',
      null => 'network',
      _ => 'failed',
    },
    status);

class AskodoxPttRepository {
  AskodoxPttRepository(this._client, {this.authToken, http.Client? httpClient}) : _http = httpClient;
  final ApiClient _client;
  final String? authToken;
  final http.Client? _http;

  static const _baseUrl = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  ApiRequestOptions get _opts => ApiRequestOptions(authToken: authToken, timeout: const Duration(seconds: 30));

  Map<String, Object?> _data(ApiResult<Map<String, Object?>> result) {
    if (result case ApiSuccess<Map<String, Object?>>(:final data)) return data;
    throw _error((result as ApiError<Map<String, Object?>>).failure.statusCode);
  }

  void _needToken() {
    if (authToken == null) throw const AskodoxPttException('sign_in');
  }

  Future<List<AskodoxPttChannel>> mine() async {
    _needToken();
    final data = _data(await _client.get<Map<String, Object?>>('/api/ptt/channels', options: _opts));
    return [
      for (final c in data['channels'] as List? ?? const [])
        if (c is Map) AskodoxPttChannel.fromJson(Map<String, Object?>.from(c)),
    ];
  }

  Future<AskodoxPttChannel> create(String name, String displayName) async {
    _needToken();
    final data = _data(await _client.post<Map<String, Object?>>('/api/ptt/channels',
        body: {'name': name, 'display_name': displayName}, options: _opts));
    return AskodoxPttChannel.fromJson(Map<String, Object?>.from(data['channel'] as Map));
  }

  Future<AskodoxPttChannel> join(String code, String displayName) async {
    _needToken();
    final data = _data(await _client.post<Map<String, Object?>>('/api/ptt/join',
        body: {'code': code, 'display_name': displayName}, options: _opts));
    return AskodoxPttChannel.fromJson(Map<String, Object?>.from(data['channel'] as Map));
  }

  Future<void> leave(String channelId) async {
    _needToken();
    _data(await _client.post<Map<String, Object?>>('/api/ptt/channels/$channelId/leave', body: const {}, options: _opts));
  }

  Future<AskodoxPttClip> send(String channelId, Uint8List audio, int durationMs) async {
    _needToken();
    final data = _data(await _client.post<Map<String, Object?>>('/api/ptt/channels/$channelId/clips',
        body: {'audio_base64': base64Encode(audio), 'mime_type': 'audio/mp4', 'duration_ms': durationMs}, options: _opts));
    return AskodoxPttClip.fromJson(Map<String, Object?>.from(data['clip'] as Map));
  }

  Future<List<AskodoxPttClip>> clips(String channelId, {String after = ''}) async {
    _needToken();
    final path = after.isEmpty ? '/api/ptt/channels/$channelId/clips' : '/api/ptt/channels/$channelId/clips?after=${Uri.encodeQueryComponent(after)}';
    final data = _data(await _client.get<Map<String, Object?>>(path, options: _opts));
    return [
      for (final c in data['clips'] as List? ?? const [])
        if (c is Map) AskodoxPttClip.fromJson(Map<String, Object?>.from(c)),
    ];
  }

  Future<Uint8List> audio(String clipId) async {
    _needToken();
    final client = _http ?? http.Client();
    try {
      final response = await client
          .get(Uri.parse('$_baseUrl/api/ptt/clips/$clipId/audio'), headers: {'Authorization': 'Bearer $authToken'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw _error(response.statusCode);
      return response.bodyBytes;
    } on AskodoxPttException {
      rethrow;
    } catch (_) {
      throw const AskodoxPttException('network');
    } finally {
      if (_http == null) client.close();
    }
  }
}

final askodoxPttRepositoryProvider = Provider<AskodoxPttRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AskodoxPttRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});
