enum ScheduledTaskIntentAction { create, list, cancel }

class ScheduledTaskIntent {
  const ScheduledTaskIntent({
    required this.action,
    this.title,
    this.prompt,
    this.runAt,
    this.recurrence = 'once',
    this.cancelQuery,
  });

  final ScheduledTaskIntentAction action;
  final String? title;
  final String? prompt;
  final DateTime? runAt;
  final String recurrence;
  final String? cancelQuery;
}

class ScheduledTaskIntentService {
  const ScheduledTaskIntentService();

  ScheduledTaskIntent? parse(String input, {DateTime? now}) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    if (_isListIntent(lower)) {
      return const ScheduledTaskIntent(action: ScheduledTaskIntentAction.list);
    }

    if (_isCancelIntent(lower)) {
      return ScheduledTaskIntent(
        action: ScheduledTaskIntentAction.cancel,
        cancelQuery: _cancelQuery(text),
      );
    }

    if (!_isCreateIntent(lower)) return null;

    final base = now ?? DateTime.now();
    final recurrence = _recurrence(lower);
    final runAt = _runAt(lower, base, recurrence);
    if (runAt == null) return null;

    return ScheduledTaskIntent(
      action: ScheduledTaskIntentAction.create,
      title: _title(text),
      prompt: text,
      runAt: runAt,
      recurrence: recurrence,
    );
  }

  bool _isCreateIntent(String text) {
    return text.contains('remind me') ||
        text.contains('reminder') ||
        text.contains('every day') ||
        text.contains('daily') ||
        text.contains('గుర్తు చేయ') ||
        text.contains('రిమైండర్') ||
        text.contains('ప్రతి రోజు') ||
        text.contains('याद दिल') ||
        text.contains('रिमाइंडर') ||
        text.contains('हर दिन');
  }

  bool _isListIntent(String text) {
    return text.contains('my reminders') ||
        text.contains('list reminders') ||
        text.contains('show reminders') ||
        text.contains('నా రిమైండర్') ||
        text.contains('రిమైండర్లు చూప') ||
        text.contains('मेरे रिमाइंडर') ||
        text.contains('रिमाइंडर दिख');
  }

  bool _isCancelIntent(String text) {
    return text.contains('cancel reminder') ||
        text.contains('delete reminder') ||
        text.contains('stop reminder') ||
        text.contains('రిమైండర్ రద్దు') ||
        text.contains('రిమైండర్ ఆపు') ||
        text.contains('रिमाइंडर रद्द') ||
        text.contains('रिमाइंडर बंद');
  }

  String _recurrence(String text) {
    if (text.contains('every day') ||
        text.contains('daily') ||
        text.contains('ప్రతి రోజు') ||
        text.contains('రోజూ') ||
        text.contains('हर दिन') ||
        text.contains('रोज')) {
      return 'daily';
    }
    if (text.contains('every week') ||
        text.contains('weekly') ||
        text.contains('ప్రతి వారం') ||
        text.contains('हर हफ्ते')) {
      return 'weekly';
    }
    if (text.contains('every hour') ||
        text.contains('hourly') ||
        text.contains('ప్రతి గంట') ||
        text.contains('हर घंटे')) {
      return 'hourly';
    }
    return 'once';
  }

  DateTime? _runAt(String text, DateTime now, String recurrence) {
    var day = DateTime(now.year, now.month, now.day);
    if (text.contains('tomorrow') ||
        text.contains('రేపు') ||
        text.contains('कल')) {
      day = day.add(const Duration(days: 1));
    }

    final time = _extractTime(text);
    if (time != null) {
      var candidate = DateTime(day.year, day.month, day.day, time.$1, time.$2);
      if (!candidate.isAfter(now) && recurrence != 'once') {
        candidate = candidate.add(const Duration(days: 1));
      }
      if (!candidate.isAfter(now)) return null;
      return candidate;
    }

    if (recurrence != 'once') {
      var candidate = DateTime(day.year, day.month, day.day, now.hour, now.minute)
          .add(const Duration(minutes: 1));
      if (!candidate.isAfter(now)) candidate = now.add(const Duration(minutes: 1));
      return candidate;
    }

    if (day.isAfter(DateTime(now.year, now.month, now.day))) {
      return DateTime(day.year, day.month, day.day, 9);
    }
    return null;
  }

  (int, int)? _extractTime(String text) {
    final match = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b').allMatches(text).lastOrNull;
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (hour == null || hour > 23 || minute > 59) return null;

    final meridiem = match.group(3);
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;
    }
    return (hour, minute);
  }

  String _title(String text) {
    var value = text
        .replaceFirst(RegExp(r'^remind me to\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^remind me\s+', caseSensitive: false), '')
        .trim();
    if (value.length > 64) value = value.substring(0, 64).trimRight();
    return value.isEmpty ? 'ASKODOX reminder' : value;
  }

  String? _cancelQuery(String text) {
    final cleaned = text
        .replaceFirst(RegExp(r'^(cancel|delete|stop)\s+(my\s+)?reminder\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^రిమైండర్\s*(రద్దు|ఆపు)\s*'), '')
        .replaceFirst(RegExp(r'^रिमाइंडर\s*(रद्द|बंद)\s*'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
