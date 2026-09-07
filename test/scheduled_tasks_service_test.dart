import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/scheduled_tasks_service.dart';

void main() {
  test('creates reminder through scheduled tasks API', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/tasks');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['user_id'], 'u1');
      expect(body['kind'], 'reminder');
      expect(body['recurrence'], 'once');
      return http.Response(
        jsonEncode({
          'status': 'success',
          'task': {
            'id': 't1',
            'user_id': 'u1',
            'title': 'Call shop',
            'prompt': 'Remind me to call the shop',
            'kind': 'reminder',
            'recurrence': 'once',
            'timezone': 'Asia/Kolkata',
            'next_run_at': '2026-09-07T12:00:00Z',
            'enabled': true,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = ScheduledTasksService(client: client);
    final task = await service.create(
      userId: 'u1',
      title: 'Call shop',
      prompt: 'Remind me to call the shop',
      runAt: DateTime.parse('2026-09-07T17:30:00+05:30'),
      timezone: 'Asia/Kolkata',
    );

    expect(task?.id, 't1');
    expect(task?.enabled, isTrue);
  });

  test('lists and cancels scheduled tasks', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/tasks');
        expect(request.url.queryParameters['user_id'], 'u1');
        return http.Response(
          jsonEncode({
            'status': 'success',
            'tasks': [
              {
                'id': 't2',
                'user_id': 'u1',
                'title': 'Daily brief',
                'prompt': 'Send daily brief',
                'kind': 'scheduled',
                'recurrence': 'daily',
                'timezone': 'Asia/Kolkata',
                'next_run_at': '2026-09-08T03:00:00Z',
                'enabled': true,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      expect(request.method, 'POST');
      expect(request.url.path, '/tasks/t2/cancel');
      return http.Response(
        jsonEncode({
          'status': 'success',
          'task': {
            'id': 't2',
            'user_id': 'u1',
            'title': 'Daily brief',
            'prompt': 'Send daily brief',
            'kind': 'scheduled',
            'recurrence': 'daily',
            'timezone': 'Asia/Kolkata',
            'next_run_at': '2026-09-08T03:00:00Z',
            'enabled': false,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = ScheduledTasksService(client: client);
    final tasks = await service.list(userId: 'u1');
    expect(tasks, hasLength(1));
    expect(tasks.single.recurrence, 'daily');

    final cancelled = await service.cancel(taskId: 't2', userId: 'u1');
    expect(cancelled?.enabled, isFalse);
  });

  test('fails softly on backend error', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final service = ScheduledTasksService(client: client);

    final tasks = await service.list(userId: 'u1');
    expect(tasks, isEmpty);
  });
}
