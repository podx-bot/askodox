import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'workout_logic.dart';

/// The person's workouts, kept on this phone only (account-scoped: it leaves with a sign-out and comes back with the
/// same account -- see `askodoxAccountScopedKeys`).
const askodoxWorkoutPrefsKey = 'askodox.workout.v1';

final askodoxWorkoutClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AskodoxWorkoutController extends StateNotifier<AskodoxWorkoutState> {
  AskodoxWorkoutController(this._now) : super(const AskodoxWorkoutState()) {
    _load();
  }

  final DateTime Function() _now;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = AskodoxWorkoutState.decode(prefs.getString(askodoxWorkoutPrefsKey));
    } catch (_) {
      if (mounted) state = const AskodoxWorkoutState(loaded: true);
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxWorkoutPrefsKey, state.encode());
    } catch (_) {
      // The workout stays on screen; it is saved with the next change.
    }
  }

  /// One finished set. The first set starts the workout by itself.
  Future<void> addSet(String exercise, int grams, int reps) async {
    if (reps < 1 || reps > askodoxWorkoutMaxReps || grams < 0 || grams > askodoxWorkoutMaxGrams) return;
    final now = _now();
    final active = state.active ?? AskodoxWorkoutSession(id: '${now.microsecondsSinceEpoch}', start: now);
    state = state.copyWith(
        active: active.copyWith(
            sets: [...active.sets, AskodoxWorkoutSet(exercise: exercise, grams: grams, reps: reps, at: now)]));
    await _save();
  }

  /// Takes the last set back (a wrong tap).
  Future<void> undoLastSet() async {
    final active = state.active;
    if (active == null || active.sets.isEmpty) return;
    final sets = active.sets.sublist(0, active.sets.length - 1);
    state = sets.isEmpty ? state.copyWith(clearActive: true) : state.copyWith(active: active.copyWith(sets: sets));
    await _save();
  }

  /// Ends the running workout; null when there is nothing to end.
  Future<AskodoxWorkoutSession?> finish() async {
    final active = state.active;
    if (active == null || active.sets.isEmpty) {
      state = state.copyWith(clearActive: true);
      return null;
    }
    final done = active.copyWith(end: _now());
    final all = [...state.sessions, done];
    state = state.copyWith(
        sessions: all.length > askodoxWorkoutKeepSessions ? all.sublist(all.length - askodoxWorkoutKeepSessions) : all,
        clearActive: true);
    await _save();
    return done;
  }

  /// The person's own exercise under a body part; the same name twice is one exercise.
  Future<AskodoxWorkoutExercise?> addExercise(String name, String part) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty || clean.length > 40) return null;
    for (final e in state.exercises) {
      if (e.part == part && (e.en.toLowerCase() == clean.toLowerCase() || e.te == clean)) return e;
    }
    final added = AskodoxWorkoutExercise('own_${_now().microsecondsSinceEpoch}', part, clean, clean, own: true);
    state = state.copyWith(own: [...state.own, added]);
    await _save();
    return added;
  }
}

final askodoxWorkoutProvider = StateNotifierProvider<AskodoxWorkoutController, AskodoxWorkoutState>(
    (ref) => AskodoxWorkoutController(ref.watch(askodoxWorkoutClockProvider)));
