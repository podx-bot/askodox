import 'askodox_user_identity_service.dart';
import 'scheduled_task_intent_service.dart';
import 'scheduled_tasks_service.dart';

class ScheduledTaskCoordinatorResult {
  const ScheduledTaskCoordinatorResult({
    required this.handled,
    required this.success,
    this.message,
    this.tasks = const <ScheduledTaskModel>[],
  });

  final bool handled;
  final bool success;
  final String? message;
  final List<ScheduledTaskModel> tasks;
}

class ScheduledTaskCoordinator {
  const ScheduledTaskCoordinator({
    ScheduledTaskIntentService? intentService,
    AskodoxUserIdentityService? identityService,
    ScheduledTasksService? tasksService,
  })  : _intentService = intentService ?? const ScheduledTaskIntentService(),
        _identityService = identityService ?? const AskodoxUserIdentityService(),
        _tasksService = tasksService ?? const ScheduledTasksService();

  final ScheduledTaskIntentService _intentService;
  final AskodoxUserIdentityService _identityService;
  final ScheduledTasksService _tasksService;

  Future<ScheduledTaskCoordinatorResult> handle(String input) async {
    final intent = _intentService.parse(input);
    if (intent == null) {
      return const ScheduledTaskCoordinatorResult(
        handled: false,
        success: false,
      );
    }

    final userId = await _identityService.currentUserId();
    if (userId == null) {
      return const ScheduledTaskCoordinatorResult(
        handled: true,
        success: false,
        message: 'Please complete mobile verification before using reminders.',
      );
    }

    switch (intent.action) {
      case ScheduledTaskIntentAction.create:
        final runAt = intent.runAt;
        if (runAt == null) {
          return const ScheduledTaskCoordinatorResult(
            handled: true,
            success: false,
            message: 'Please include when you want me to remind you.',
          );
        }
        final task = await _tasksService.create(
          userId: userId,
          title: intent.title ?? 'ASKODOX reminder',
          prompt: intent.prompt ?? input,
          runAt: runAt,
          recurrence: intent.recurrence,
          timezone: _timezoneFor(runAt),
        );
        if (task == null) {
          return const ScheduledTaskCoordinatorResult(
            handled: true,
            success: false,
            message: 'I could not save that reminder. Please try again.',
          );
        }
        return ScheduledTaskCoordinatorResult(
          handled: true,
          success: true,
          message: _createdMessage(task),
          tasks: <ScheduledTaskModel>[task],
        );

      case ScheduledTaskIntentAction.list:
        final tasks = await _tasksService.list(userId: userId);
        return ScheduledTaskCoordinatorResult(
          handled: true,
          success: true,
          message: tasks.isEmpty
              ? 'You do not have any active reminders.'
              : 'You have ${tasks.length} active reminder${tasks.length == 1 ? '' : 's'}.',
          tasks: tasks,
        );

      case ScheduledTaskIntentAction.cancel:
        final tasks = await _tasksService.list(userId: userId);
        final target = _findCancelTarget(tasks, intent.cancelQuery);
        if (target == null) {
          return const ScheduledTaskCoordinatorResult(
            handled: true,
            success: false,
            message: 'I could not find a matching active reminder.',
          );
        }
        final cancelled = await _tasksService.cancel(
          taskId: target.id,
          userId: userId,
        );
        if (cancelled == null || cancelled.enabled) {
          return const ScheduledTaskCoordinatorResult(
            handled: true,
            success: false,
            message: 'I could not cancel that reminder. Please try again.',
          );
        }
        return ScheduledTaskCoordinatorResult(
          handled: true,
          success: true,
          message: 'Cancelled reminder: ${target.title}',
          tasks: <ScheduledTaskModel>[cancelled],
        );
    }
  }

  ScheduledTaskModel? _findCancelTarget(
    List<ScheduledTaskModel> tasks,
    String? query,
  ) {
    if (tasks.isEmpty) return null;
    final normalized = query?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return tasks.length == 1 ? tasks.single : null;
    }
    for (final task in tasks) {
      if (task.title.toLowerCase().contains(normalized) ||
          task.prompt.toLowerCase().contains(normalized)) {
        return task;
      }
    }
    return null;
  }

  String _timezoneFor(DateTime value) {
    if (!value.isUtc && value.timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
      return 'Asia/Kolkata';
    }
    return 'UTC';
  }

  String _createdMessage(ScheduledTaskModel task) {
    final when = task.nextRunAt ?? 'the scheduled time';
    final recurrence = task.recurrence == 'once' ? '' : ' (${task.recurrence})';
    return 'Reminder saved$recurrence for $when: ${task.title}';
  }
}
