import 'dart:convert';

import 'package:http/http.dart' as http;

class ScheduledTaskModel {
  const ScheduledTaskModel({required this.id, required this.userId, required this.title, required this.prompt, required this.kind, required this.recurrence, required this.timezone, required this.enabled, this.nextRunAt, this.condition, this.lastRunAt, this.lastStatus});
  final String id; final String userId; final String title; final String prompt; final String kind; final String recurrence; final String timezone; final bool enabled; final String? nextRunAt; final Map<String, dynamic>? condition; final String? lastRunAt; final String? lastStatus;
  factory ScheduledTaskModel.fromJson(Map<String, dynamic> json) => ScheduledTaskModel(id: json['id'] as String? ?? '', userId: json['user_id'] as String? ?? '', title: json['title'] as String? ?? '', prompt: json['prompt'] as String? ?? '', kind: json['kind'] as String? ?? 'reminder', recurrence: json['recurrence'] as String? ?? 'once', timezone: json['timezone'] as String? ?? 'UTC', enabled: json['enabled'] as bool? ?? false, nextRunAt: json['next_run_at'] as String?, condition: json['condition'] is Map<String, dynamic> ? json['condition'] as Map<String, dynamic> : null, lastRunAt: json['last_run_at'] as String?, lastStatus: json['last_status'] as String?);
}

class ScheduledTaskDeliveryModel {
  const ScheduledTaskDeliveryModel({required this.id, required this.taskId, required this.userId, required this.title, required this.prompt, required this.deliveredAt, required this.read});
  final int id; final String taskId; final String userId; final String title; final String prompt; final String deliveredAt; final bool read;
  factory ScheduledTaskDeliveryModel.fromJson(Map<String, dynamic> json) => ScheduledTaskDeliveryModel(id: (json['id'] as num?)?.toInt() ?? 0, taskId: json['task_id'] as String? ?? '', userId: json['user_id'] as String? ?? '', title: json['title'] as String? ?? '', prompt: json['prompt'] as String? ?? '', deliveredAt: json['delivered_at'] as String? ?? '', read: json['read_at'] != null || json['read'] == true);
}

class ScheduledTasksService {
  const ScheduledTasksService({http.Client? client}) : _client = client;
  static const _defaultBaseUrl = 'https://podx-ai-connect-production-3279.up.railway.app';
  static const _baseUrl = String.fromEnvironment('ASKODOX_API_BASE_URL', defaultValue: _defaultBaseUrl);
  final http.Client? _client;

  Future<ScheduledTaskModel?> create({required String userId, required String title, required String prompt, required DateTime runAt, String kind = 'reminder', String recurrence = 'once', String timezone = 'UTC', Map<String, dynamic>? condition}) async => _withClient<ScheduledTaskModel?>((client) async { final response = await client.post(Uri.parse('$_baseUrl/tasks'), headers: const {'content-type': 'application/json'}, body: jsonEncode({'user_id': userId, 'title': title, 'prompt': prompt, 'kind': kind, 'run_at': runAt.toUtc().toIso8601String(), 'recurrence': recurrence, 'timezone': timezone, if (condition != null) 'condition': condition})).timeout(const Duration(seconds: 20)); return _taskFromResponse(response); });

  Future<List<ScheduledTaskModel>> list({required String userId, bool includeDisabled = false}) async { final result = await _withClient((client) async { final uri = Uri.parse('$_baseUrl/tasks').replace(queryParameters: {'user_id': userId, 'include_disabled': includeDisabled.toString()}); final response = await client.get(uri).timeout(const Duration(seconds: 20)); if (!_ok(response)) return <ScheduledTaskModel>[]; final decoded = jsonDecode(response.body); if (decoded is! Map<String, dynamic> || decoded['status'] != 'success') return <ScheduledTaskModel>[]; final tasks = decoded['tasks']; if (tasks is! List) return <ScheduledTaskModel>[]; return tasks.whereType<Map<String, dynamic>>().map(ScheduledTaskModel.fromJson).toList(growable: false); }); return result ?? const <ScheduledTaskModel>[]; }

  Future<List<ScheduledTaskDeliveryModel>> inbox({required String userId, bool unreadOnly = false, int limit = 50}) async { final result = await _withClient((client) async { final uri = Uri.parse('$_baseUrl/tasks/inbox').replace(queryParameters: {'user_id': userId, 'unread_only': unreadOnly.toString(), 'limit': limit.clamp(1, 200).toString()}); final response = await client.get(uri).timeout(const Duration(seconds: 20)); if (!_ok(response)) return <ScheduledTaskDeliveryModel>[]; final decoded = jsonDecode(response.body); if (decoded is! Map<String, dynamic> || decoded['status'] != 'success') return <ScheduledTaskDeliveryModel>[]; final deliveries = decoded['deliveries']; if (deliveries is! List) return <ScheduledTaskDeliveryModel>[]; return deliveries.whereType<Map<String, dynamic>>().map(ScheduledTaskDeliveryModel.fromJson).toList(growable: false); }); return result ?? const <ScheduledTaskDeliveryModel>[]; }

  Future<ScheduledTaskDeliveryModel?> markInboxRead({required int deliveryId, required String userId}) async => _withClient<ScheduledTaskDeliveryModel?>((client) async { final response = await client.post(Uri.parse('$_baseUrl/tasks/inbox/$deliveryId/read'), headers: const {'content-type': 'application/json'}, body: jsonEncode({'user_id': userId})).timeout(const Duration(seconds: 20)); if (!_ok(response)) return null; final decoded = jsonDecode(response.body); if (decoded is! Map<String, dynamic> || decoded['status'] != 'success' || decoded['delivery'] is! Map<String, dynamic>) return null; return ScheduledTaskDeliveryModel.fromJson(decoded['delivery'] as Map<String, dynamic>); });

  Future<ScheduledTaskModel?> cancel({required String taskId, required String userId}) async => _withClient<ScheduledTaskModel?>((client) async { final response = await client.post(Uri.parse('$_baseUrl/tasks/$taskId/cancel'), headers: const {'content-type': 'application/json'}, body: jsonEncode({'user_id': userId})).timeout(const Duration(seconds: 20)); return _taskFromResponse(response); });

  ScheduledTaskModel? _taskFromResponse(http.Response response) { if (!_ok(response)) return null; final decoded = jsonDecode(response.body); if (decoded is! Map<String, dynamic> || decoded['status'] != 'success') return null; final task = decoded['task']; return task is Map<String, dynamic> ? ScheduledTaskModel.fromJson(task) : null; }
  bool _ok(http.Response response) => response.statusCode >= 200 && response.statusCode < 300;
  Future<T?> _withClient<T>(Future<T> Function(http.Client client) action) async { final client = _client ?? http.Client(); try { return await action(client); } catch (_) { return null; } finally { if (_client == null) client.close(); } }
}
