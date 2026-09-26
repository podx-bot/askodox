import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// How a Command Center user proves who they are. The backend decides what
/// they may do; the app only hides sections the server says are not granted.
enum CommandCenterCredentialKind { ownerKey, staffToken }

class CommandCenterCredential {
  const CommandCenterCredential(this.kind, this.secret);

  final CommandCenterCredentialKind kind;
  final String secret;

  Map<String, String> get headers => {
        kind == CommandCenterCredentialKind.ownerKey
            ? 'X-ASKODOX-Admin-Key'
            : 'X-ASKODOX-Staff-Token': secret,
      };

  // Never print the secret (logs, errors, debug output).
  @override
  String toString() => 'CommandCenterCredential(${kind.name}, ••••)';
}

class CommandCenterException implements Exception {
  const CommandCenterException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get needsConfirmation => statusCode == 409;
  bool get forbidden => statusCode == 403;
  bool get signedOut => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin client for `/admin/cc/*`. Every permission is enforced server-side;
/// the credential lives only in memory for this app session.
class CommandCenterApi {
  CommandCenterApi(this._client);

  final ApiClient _client;
  CommandCenterCredential? _credential;

  bool get signedIn => _credential != null;

  void signOut() => _credential = null;

  Future<Map<String, dynamic>> signIn(CommandCenterCredential credential) async {
    _credential = credential;
    try {
      final me = await get('/admin/cc/me');
      if (me['permissions'] is! List) {
        // Mock backend (no API_BASE_URL): never pretend to be signed in.
        throw const CommandCenterException('Command Center needs the live ASKODOX backend.');
      }
      return me;
    } catch (_) {
      _credential = null;
      rethrow;
    }
  }

  ApiRequestOptions _options([Map<String, Object?> query = const {}]) =>
      ApiRequestOptions(headers: _credential?.headers ?? const {}, query: query);

  Map<String, dynamic> _unwrap(ApiResult<Object?> result) {
    switch (result) {
      case ApiSuccess(:final data):
        if (data is Map) return Map<String, dynamic>.from(data);
        return <String, dynamic>{'value': data};
      case ApiError(:final failure):
        throw CommandCenterException(
          failure.message ?? 'Command Center request failed',
          statusCode: failure.statusCode,
        );
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, Object?> query = const {}}) async =>
      _unwrap(await _client.get<Object?>(path, options: _options(query)));

  Future<Map<String, dynamic>> post(String path, [Object? body]) async =>
      _unwrap(await _client.post<Object?>(path, body: body ?? const {}, options: _options()));

  Future<Map<String, dynamic>> put(String path, Object body) async =>
      _unwrap(await _client.put<Object?>(path, body: body, options: _options()));

  Future<Map<String, dynamic>> patch(String path, Object body) async =>
      _unwrap(await _client.patch<Object?>(path, body: body, options: _options()));
}

final commandCenterApiProvider = Provider<CommandCenterApi>(
  (ref) => CommandCenterApi(ref.watch(apiClientProvider)),
);

List<Map<String, dynamic>> ccItems(Map<String, dynamic> data, [String key = 'items']) => [
      for (final item in (data[key] as List? ?? const []))
        if (item is Map) Map<String, dynamic>.from(item),
    ];

/// CSV of the daily analytics rows (same columns as the backend export).
String commandCenterAnalyticsCsv(Map<String, dynamic> analytics) {
  const columns = ['date', 'requests', 'matches', 'no_match', 'orders', 'escalations', 'seller_joins'];
  final lines = <String>[columns.join(',')];
  for (final row in ccItems(analytics, 'daily')) {
    lines.add(columns.map((c) => '${row[c] ?? 0}').join(','));
  }
  return lines.join('\n');
}
