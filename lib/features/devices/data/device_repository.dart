import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// A device in the user's dashboard. [localId] (the Bluetooth remote id) is
/// kept on this phone only; the server stores a keyed hash of it.
class AskodoxSavedDevice {
  const AskodoxSavedDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.capabilities,
    required this.status,
    this.localId,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String category;
  final List<String> capabilities;
  final String status;
  final String? localId;
  final String? lastSeen;

  factory AskodoxSavedDevice.fromJson(Map<String, Object?> j, {String? localId}) => AskodoxSavedDevice(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        category: '${j['category'] ?? 'unknown'}',
        capabilities: j['capabilities'] is List ? [for (final c in j['capabilities'] as List) '$c'] : const [],
        status: '${j['status'] ?? 'paired'}',
        lastSeen: j['last_seen'] == null ? null : '${j['last_seen']}',
        localId: localId,
      );
}

class AskodoxDeviceException implements Exception {
  const AskodoxDeviceException(this.code);

  /// sign_in | network | failed
  final String code;

  String message(bool te) => switch (code) {
        'sign_in' => te ? 'పరికరాలను సేవ్ చేయడానికి సైన్ ఇన్ చేయండి.' : 'Sign in to save devices to your account.',
        'network' => te ? 'ఇంటర్నెట్ కనెక్షన్ చూడండి.' : 'Check your internet connection.',
        _ => te ? 'ఇప్పుడు కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'That did not work. Please try again.',
      };
}

const _localKey = 'askodox.devices.local.v1';

class AskodoxDeviceRepository {
  AskodoxDeviceRepository(this._client, {this.authToken});
  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _opts => ApiRequestOptions(authToken: authToken, timeout: const Duration(seconds: 20));

  Never _fail(ApiError<Object?> error) {
    throw AskodoxDeviceException(switch (error.failure.statusCode) {
      401 || 403 => 'sign_in',
      null => 'network',
      _ => 'failed',
    });
  }

  Future<Map<String, String>> _localIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveLocal(Map<String, String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localKey, jsonEncode(ids));
  }

  Future<List<AskodoxSavedDevice>> list() async {
    if (authToken == null) throw const AskodoxDeviceException('sign_in');
    final result = await _client.get<Map<String, Object?>>('/api/devices', options: _opts);
    if (result is ApiError<Map<String, Object?>>) _fail(result);
    final data = (result as ApiSuccess<Map<String, Object?>>).data;
    final local = await _localIds();
    return [
      for (final d in (data['devices'] as List? ?? const []))
        if (d is Map) AskodoxSavedDevice.fromJson(Map<String, Object?>.from(d), localId: local['${d['id']}']),
    ];
  }

  Future<AskodoxSavedDevice> add({required String name, required String localId, required List<String> serviceUuids}) async {
    if (authToken == null) throw const AskodoxDeviceException('sign_in');
    final result = await _client.post<Map<String, Object?>>('/api/devices',
        body: {'name': name, 'protocol': 'BLE', 'identifier': localId, 'service_uuids': serviceUuids}, options: _opts);
    if (result is ApiError<Map<String, Object?>>) _fail(result);
    final device = Map<String, Object?>.from((result as ApiSuccess<Map<String, Object?>>).data['device'] as Map);
    final local = await _localIds()..['${device['id']}'] = localId;
    await _saveLocal(local);
    return AskodoxSavedDevice.fromJson(device, localId: localId);
  }

  Future<void> setStatus(String id, String status) async {
    if (authToken == null) return;
    await _client.patch<Map<String, Object?>>('/api/devices/$id', body: {'status': status}, options: _opts);
  }

  Future<void> forget(String id) async {
    if (authToken == null) throw const AskodoxDeviceException('sign_in');
    final result = await _client.delete<Map<String, Object?>>('/api/devices/$id', options: _opts);
    if (result is ApiError<Map<String, Object?>> && result.failure.statusCode != 404) _fail(result);
    final local = await _localIds()..remove(id);
    await _saveLocal(local);
  }
}

final askodoxDeviceRepositoryProvider = Provider<AskodoxDeviceRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  final user = session.user;
  return AskodoxDeviceRepository(ref.watch(apiClientProvider),
      authToken: user == null ? null : session.tokenPlaceholder);
});
