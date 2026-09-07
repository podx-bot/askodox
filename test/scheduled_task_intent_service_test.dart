import 'package:flutter_test/flutter_test.dart';
import 'package:podx/services/scheduled_task_intent_service.dart';

void main() {
  const parser = ScheduledTaskIntentService();
  final now = DateTime(2026, 9, 7, 17, 30);

  test('parses English one-time reminder', () {
    final intent = parser.parse('Remind me to call the shop tomorrow at 9 am', now: now);
    expect(intent?.action, ScheduledTaskIntentAction.create);
    expect(intent?.recurrence, 'once');
    expect(intent?.runAt, DateTime(2026, 9, 8, 9));
  });

  test('parses Telugu daily reminder', () {
    final intent = parser.parse('ప్రతి రోజు ఉదయం 8 am రిమైండర్ పెట్టు', now: now);
    expect(intent?.action, ScheduledTaskIntentAction.create);
    expect(intent?.recurrence, 'daily');
    expect(intent?.runAt, DateTime(2026, 9, 8, 8));
  });

  test('parses list and cancel intents', () {
    expect(
      parser.parse('show my reminders', now: now)?.action,
      ScheduledTaskIntentAction.list,
    );
    final cancel = parser.parse('cancel reminder call the shop', now: now);
    expect(cancel?.action, ScheduledTaskIntentAction.cancel);
    expect(cancel?.cancelQuery, 'call the shop');
  });

  test('does not hijack ordinary commerce requests', () {
    expect(parser.parse('I need chicken near me', now: now), isNull);
  });
}
