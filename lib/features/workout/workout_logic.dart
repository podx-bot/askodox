/// Live Work workout tracker (owner 2026-11-27, phase 4): sets, rest timer, personal records, the week and the
/// streak. Free: nothing here calls the server or AI, everything lives on the phone. Points are NOT part of it
/// (the owner gives the rules later). ASKODOX's own code and its own exercise list.
library;

import 'dart:convert';

const askodoxWorkoutRestSeconds = 90;
const askodoxWorkoutKeepSessions = 400;
const askodoxWorkoutStepGrams = 2500;
const askodoxWorkoutMaxGrams = 500000;
const askodoxWorkoutMaxReps = 200;

class AskodoxWorkoutPart {
  const AskodoxWorkoutPart(this.id, this.en, this.te);
  final String id;
  final String en;
  final String te;
}

const askodoxWorkoutParts = <AskodoxWorkoutPart>[
  AskodoxWorkoutPart('chest', 'Chest', 'ఛాతీ'),
  AskodoxWorkoutPart('back', 'Back', 'వీపు'),
  AskodoxWorkoutPart('legs', 'Legs', 'కాళ్లు'),
  AskodoxWorkoutPart('shoulders', 'Shoulders', 'భుజాలు'),
  AskodoxWorkoutPart('arms', 'Arms', 'చేతులు'),
  AskodoxWorkoutPart('core', 'Core', 'పొట్ట'),
];

class AskodoxWorkoutExercise {
  const AskodoxWorkoutExercise(this.id, this.part, this.en, this.te, {this.own = false});
  final String id;
  final String part;
  final String en;
  final String te;

  /// Added by the person (shown with the name they typed in both languages).
  final bool own;

  String name(bool telugu) => telugu ? te : en;
}

/// The starter list. A person adds their own with one line.
const askodoxWorkoutExercises = <AskodoxWorkoutExercise>[
  AskodoxWorkoutExercise('bench_press', 'chest', 'Bench press', 'బెంచ్ ప్రెస్'),
  AskodoxWorkoutExercise('incline_dumbbell', 'chest', 'Incline dumbbell press', 'ఇంక్లైన్ డంబెల్'),
  AskodoxWorkoutExercise('push_ups', 'chest', 'Push-ups', 'పుష్ అప్స్'),
  AskodoxWorkoutExercise('lat_pulldown', 'back', 'Lat pulldown', 'లాట్ పుల్‌డౌన్'),
  AskodoxWorkoutExercise('seated_row', 'back', 'Seated row', 'సీటెడ్ రో'),
  AskodoxWorkoutExercise('pull_ups', 'back', 'Pull-ups', 'పుల్ అప్స్'),
  AskodoxWorkoutExercise('squat', 'legs', 'Squat', 'స్క్వాట్'),
  AskodoxWorkoutExercise('leg_press', 'legs', 'Leg press', 'లెగ్ ప్రెస్'),
  AskodoxWorkoutExercise('lunges', 'legs', 'Lunges', 'లంజెస్'),
  AskodoxWorkoutExercise('overhead_press', 'shoulders', 'Overhead press', 'ఓవర్‌హెడ్ ప్రెస్'),
  AskodoxWorkoutExercise('lateral_raise', 'shoulders', 'Lateral raise', 'లాటరల్ రైజ్'),
  AskodoxWorkoutExercise('biceps_curl', 'arms', 'Biceps curl', 'బైసెప్స్ కర్ల్'),
  AskodoxWorkoutExercise('triceps_pushdown', 'arms', 'Triceps pushdown', 'ట్రైసెప్స్ పుష్‌డౌన్'),
  AskodoxWorkoutExercise('crunches', 'core', 'Crunches', 'క్రంచెస్'),
  AskodoxWorkoutExercise('leg_raise', 'core', 'Leg raise', 'లెగ్ రైజ్'),
];

class AskodoxWorkoutSet {
  const AskodoxWorkoutSet({required this.exercise, required this.grams, required this.reps, required this.at});
  final String exercise;

  /// The weight in grams (0 = body weight only), so 57.5 kg is exact.
  final int grams;
  final int reps;
  final DateTime at;

  Map<String, Object?> toJson() => {'e': exercise, 'g': grams, 'r': reps, 't': at.toIso8601String()};

  static AskodoxWorkoutSet? from(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['t'] ?? ''}');
    final grams = raw['g'];
    final reps = raw['r'];
    if (at == null || grams is! num || reps is! num || '${raw['e'] ?? ''}'.isEmpty || reps < 1) return null;
    return AskodoxWorkoutSet(exercise: '${raw['e']}', grams: grams.toInt(), reps: reps.toInt(), at: at);
  }
}

class AskodoxWorkoutSession {
  const AskodoxWorkoutSession({required this.id, required this.start, this.end, this.sets = const []});
  final String id;
  final DateTime start;
  final DateTime? end;
  final List<AskodoxWorkoutSet> sets;

  AskodoxWorkoutSession copyWith({DateTime? end, List<AskodoxWorkoutSet>? sets}) =>
      AskodoxWorkoutSession(id: id, start: start, end: end ?? this.end, sets: sets ?? this.sets);

  Map<String, Object?> toJson() => {
        'id': id,
        's': start.toIso8601String(),
        if (end != null) 'n': end!.toIso8601String(),
        'sets': [for (final s in sets) s.toJson()],
      };

  static AskodoxWorkoutSession? from(Object? raw) {
    if (raw is! Map) return null;
    final start = DateTime.tryParse('${raw['s'] ?? ''}');
    if (start == null) return null;
    final sets = <AskodoxWorkoutSet>[];
    if (raw['sets'] is List) {
      for (final row in raw['sets'] as List) {
        final set = AskodoxWorkoutSet.from(row);
        if (set != null) sets.add(set);
      }
    }
    return AskodoxWorkoutSession(
        id: '${raw['id'] ?? start.microsecondsSinceEpoch}', start: start, end: DateTime.tryParse('${raw['n'] ?? ''}'), sets: sets);
  }
}

/// A personal record of one finished workout.
class AskodoxWorkoutRecord {
  const AskodoxWorkoutRecord(this.exercise, this.best, this.before);
  final String exercise;
  final AskodoxWorkoutSet best;
  final AskodoxWorkoutSet before;
}

/// [a] is a better set than [b]: heavier, or the same weight more times.
bool askodoxWorkoutBetter(AskodoxWorkoutSet a, AskodoxWorkoutSet b) =>
    a.grams > b.grams || (a.grams == b.grams && a.reps > b.reps);

/// The best set of one exercise in [sets]; null when it was never done.
AskodoxWorkoutSet? askodoxWorkoutBestOf(Iterable<AskodoxWorkoutSet> sets, String exercise) {
  AskodoxWorkoutSet? best;
  for (final set in sets) {
    if (set.exercise != exercise) continue;
    if (best == null || askodoxWorkoutBetter(set, best)) best = set;
  }
  return best;
}

/// The best set of one exercise over finished workouts (optionally only those before [before]).
AskodoxWorkoutSet? askodoxWorkoutBest(List<AskodoxWorkoutSession> sessions, String exercise, {DateTime? before}) =>
    askodoxWorkoutBestOf([
      for (final s in sessions)
        if (before == null || s.start.isBefore(before)) ...s.sets,
    ], exercise);

/// A record needs an earlier best to beat: the first time an exercise is done is a start, not a record.
bool askodoxWorkoutIsRecord(AskodoxWorkoutSet? earlierBest, AskodoxWorkoutSet set) =>
    earlierBest != null && askodoxWorkoutBetter(set, earlierBest);

/// The records of one workout against everything done before it started.
List<AskodoxWorkoutRecord> askodoxWorkoutRecords(List<AskodoxWorkoutSession> earlier, AskodoxWorkoutSession session) {
  final out = <AskodoxWorkoutRecord>[];
  final seen = <String>{};
  for (final set in session.sets) {
    if (!seen.add(set.exercise)) continue;
    final best = askodoxWorkoutBestOf(session.sets, set.exercise)!;
    final before = askodoxWorkoutBest(earlier, set.exercise, before: session.start);
    if (before != null && askodoxWorkoutBetter(best, before)) out.add(AskodoxWorkoutRecord(set.exercise, best, before));
  }
  return out;
}

/// Every record ever made (the medal count), walking the workouts in order.
int askodoxWorkoutMedals(List<AskodoxWorkoutSession> sessions) {
  final ordered = [...sessions]..sort((a, b) => a.start.compareTo(b.start));
  var medals = 0;
  for (var i = 0; i < ordered.length; i++) {
    medals += askodoxWorkoutRecords(ordered.sublist(0, i), ordered[i]).length;
  }
  return medals;
}

/// Weight moved in one workout, in grams (weight x times, added up).
int askodoxWorkoutVolumeGrams(AskodoxWorkoutSession session) =>
    session.sets.fold(0, (sum, set) => sum + set.grams * set.reps);

String askodoxWorkoutDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// The days (phone's own calendar) with at least one finished set.
Set<String> askodoxWorkoutDays(List<AskodoxWorkoutSession> sessions) =>
    {for (final s in sessions) if (s.sets.isNotEmpty) askodoxWorkoutDayKey(s.start)};

/// Days in a row ending today -- or yesterday, so today's workout is still to come and the run is not lost yet.
int askodoxWorkoutStreak(Set<String> days, DateTime today) {
  var day = DateTime(today.year, today.month, today.day);
  if (!days.contains(askodoxWorkoutDayKey(day))) day = DateTime(day.year, day.month, day.day - 1);
  var run = 0;
  while (days.contains(askodoxWorkoutDayKey(day))) {
    run++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return run;
}

/// "4 days in a row"; with no run yet, an invitation to start.
String askodoxWorkoutStreakText(int streak, bool te) {
  if (streak <= 0) return te ? 'ఈ రోజే మొదలుపెట్టండి' : 'Start today';
  if (streak == 1) return te ? '1 రోజు · రేపు కూడా రండి' : '1 day · come again tomorrow';
  return te ? '$streak రోజులు వరుసగా' : '$streak days in a row';
}

/// Monday .. Sunday of this week: worked out or not.
List<bool> askodoxWorkoutWeek(Set<String> days, DateTime today) {
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  return [for (var i = 0; i < 7; i++) days.contains(askodoxWorkoutDayKey(DateTime(monday.year, monday.month, monday.day + i)))];
}

/// "60" / "57.5" from grams.
String askodoxWorkoutKg(int grams) {
  final kg = grams / 1000;
  if (grams % 1000 == 0) return '${grams ~/ 1000}';
  return grams % 100 == 0 ? kg.toStringAsFixed(1) : kg.toStringAsFixed(2);
}

/// "60 kg × 8", or "25 times" for a body-weight exercise.
String askodoxWorkoutSetText(AskodoxWorkoutSet set, bool te) => set.grams > 0
    ? (te ? '${askodoxWorkoutKg(set.grams)} కేజీ × ${set.reps}' : '${askodoxWorkoutKg(set.grams)} kg × ${set.reps}')
    : (te ? '${set.reps} సార్లు' : '${set.reps} times');

/// "48:20", or "1:05:09" from an hour up.
String askodoxWorkoutClock(Duration time) {
  final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
  final two = (seconds % 60).toString().padLeft(2, '0');
  final minutes = (seconds ~/ 60) % 60;
  final hours = seconds ~/ 3600;
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$two' : '${minutes.toString().padLeft(2, '0')}:$two';
}

class AskodoxWorkoutState {
  const AskodoxWorkoutState({this.loaded = false, this.sessions = const [], this.active, this.own = const []});
  final bool loaded;

  /// Finished workouts, oldest first.
  final List<AskodoxWorkoutSession> sessions;
  final AskodoxWorkoutSession? active;
  final List<AskodoxWorkoutExercise> own;

  List<AskodoxWorkoutExercise> get exercises => [...askodoxWorkoutExercises, ...own];

  AskodoxWorkoutExercise? exercise(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  AskodoxWorkoutState copyWith(
          {bool? loaded, List<AskodoxWorkoutSession>? sessions, AskodoxWorkoutSession? active, bool clearActive = false,
          List<AskodoxWorkoutExercise>? own}) =>
      AskodoxWorkoutState(
          loaded: loaded ?? this.loaded,
          sessions: sessions ?? this.sessions,
          active: clearActive ? null : (active ?? this.active),
          own: own ?? this.own);

  String encode() => jsonEncode({
        'v': 1,
        'sessions': [for (final s in sessions) s.toJson()],
        if (active != null) 'active': active!.toJson(),
        'own': [
          for (final e in own) {'id': e.id, 'part': e.part, 'name': e.en},
        ],
      });

  /// What was saved; anything unreadable is left out (never a crash, never an invented workout).
  static AskodoxWorkoutState decode(String? raw) {
    if (raw == null || raw.isEmpty) return const AskodoxWorkoutState(loaded: true);
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const AskodoxWorkoutState(loaded: true);
      final sessions = <AskodoxWorkoutSession>[];
      if (data['sessions'] is List) {
        for (final row in data['sessions'] as List) {
          final session = AskodoxWorkoutSession.from(row);
          if (session != null) sessions.add(session);
        }
      }
      final own = <AskodoxWorkoutExercise>[];
      if (data['own'] is List) {
        for (final row in data['own'] as List) {
          if (row is Map && '${row['id'] ?? ''}'.isNotEmpty && '${row['name'] ?? ''}'.isNotEmpty) {
            own.add(AskodoxWorkoutExercise('${row['id']}', '${row['part'] ?? 'chest'}', '${row['name']}', '${row['name']}', own: true));
          }
        }
      }
      return AskodoxWorkoutState(loaded: true, sessions: sessions, active: AskodoxWorkoutSession.from(data['active']), own: own);
    } catch (_) {
      return const AskodoxWorkoutState(loaded: true);
    }
  }
}
