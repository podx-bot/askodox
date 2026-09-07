import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:podx/services/scheduled_task_coordinator.dart';
import 'package:podx/services/scheduled_tasks_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'askodox.profile.mobile': '+91 98765 43210',
    });
  });

  test('creates a natural reminder with verified mobile identity', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/tasks');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['user_id'], 'mobile:+919876543210');
      expect(body['recurrence'], 'once');
      return http.Response(
        jsonEncode({
          'status': 'success',
          'task': {
            'id': 't1',
            'user_id': 'mobile:+919876543210',
            'title': 'call the shop tomorrow at 9 am',
            'prompt': 'Remind me to call the shop tomorrow at 9 am',
            'kind': 'reminder',
            'recurrence': 'once',
            'timezone': 'UTC',
            'next_run_at': '2026-09-08T03:30:00.000Z',
            'enabled': true,
          },
        }),
        200,
      );
    });

    final coordinator = ScheduledTaskCoordinator(
      tasksService: ScheduledTasksService(client: client),
    );
    final result = await coordinator.handle(
      'Remind me to call the shop tomorrow at 9 am',
    );

    expect(result.handled, isTrue);
    expect(result.success, isTrue);
    expect(result.tasks.single.id, 't1');
  });

  test('ordinary commerce requests remain unhandled', () async {
    final coordinator = ScheduledTaskCoordinator(
      tasksService: ScheduledTasksService(
        client: MockClient((request) async => http.Response('unexpected', 500)),
      ),
    );

    final result = await coordinator.handle('I need chicken near me');
    expect(result.handled, isFalse);
  });

  test('lists active reminders', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      return http.Response(
        jsonEncode({
          'status': 'success',
          'tasks': [
            {
              'id': 't2',
              'user_id': 'mobile:+919876543210',
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
      );
    });

    final result = await ScheduledTaskCoordinator(
      tasksService: ScheduledTasksService(client: client),
    ).handle('show my reminders');

    expect(result.handled, isTrue);
    expect(result.success, isTrue);
    expect(result.tasks, hasLength(1));
  });
}
