import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../memberships/memberships_logic.dart';
import '../memberships/memberships_screens.dart' show askodoxMyMembershipsProvider;
import 'workout_logic.dart';
import 'workout_store.dart';

/// Live Work workout (owner 2026-11-27, design canvas workout screens): pick an exercise, log each set with two
/// steppers, the rest timer starts by itself, a set better than the old best says so, the end shows time / sets /
/// weight moved. Free and on the phone only; no points.
class AskodoxWorkoutScreen extends ConsumerStatefulWidget {
  const AskodoxWorkoutScreen({super.key});

  @override
  ConsumerState<AskodoxWorkoutScreen> createState() => _AskodoxWorkoutScreenState();
}

class _AskodoxWorkoutScreenState extends ConsumerState<AskodoxWorkoutScreen> {
  final _ownName = TextEditingController();
  String _part = askodoxWorkoutParts.first.id;
  String? _exercise;
  int _grams = 0;
  int _reps = 10;
  int _rest = 0;
  bool _record = false;
  Timer? _timer;
  AskodoxWorkoutSession? _done;
  List<AskodoxWorkoutRecord> _doneRecords = const [];

  @override
  void dispose() {
    _timer?.cancel();
    _ownName.dispose();
    super.dispose();
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  void _open(AskodoxWorkoutExercise exercise, AskodoxWorkoutState state) {
    final last = askodoxWorkoutBestOf(state.active?.sets ?? const [], exercise.id) ?? askodoxWorkoutBest(state.sessions, exercise.id);
    setState(() {
      _exercise = exercise.id;
      _grams = last?.grams ?? 0;
      _reps = last?.reps ?? 10;
      _record = false;
    });
  }

  void _stopRest() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _rest = 0);
  }

  void _startRest() {
    _timer?.cancel();
    setState(() => _rest = askodoxWorkoutRestSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_rest <= 1) {
        timer.cancel();
        _timer = null;
        setState(() => _rest = 0);
        HapticFeedback.mediumImpact();
      } else {
        setState(() => _rest -= 1);
      }
    });
  }

  Future<void> _setDone(AskodoxWorkoutState state) async {
    final id = _exercise;
    if (id == null) return;
    final now = ref.read(askodoxWorkoutClockProvider)();
    final set = AskodoxWorkoutSet(exercise: id, grams: _grams, reps: _reps, at: now);
    // A record beats the best of EARLIER workouts, and is said once: not again for a lighter set of the same workout.
    final today = askodoxWorkoutBestOf(state.active?.sets ?? const [], id);
    final record = askodoxWorkoutIsRecord(askodoxWorkoutBest(state.sessions, id), set) &&
        (today == null || askodoxWorkoutBetter(set, today));
    await ref.read(askodoxWorkoutProvider.notifier).addSet(id, _grams, _reps);
    if (!mounted) return;
    setState(() => _record = record);
    _startRest();
  }

  Future<void> _finish(AskodoxWorkoutState state) async {
    _stopRest();
    final earlier = state.sessions;
    final done = await ref.read(askodoxWorkoutProvider.notifier).finish();
    if (!mounted || done == null) return;
    setState(() {
      _done = done;
      _doneRecords = askodoxWorkoutRecords(earlier, done);
      _exercise = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final state = ref.watch(askodoxWorkoutProvider);
    final Widget body;
    if (!state.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_done != null) {
      body = _doneView(_done!, state, te);
    } else if (_exercise != null && state.exercise(_exercise!) != null) {
      body = _setView(state.exercise(_exercise!)!, state, te);
    } else {
      body = _pickView(state, te);
    }
    return Scaffold(
      key: const Key('askodoxWorkoutScreen'),
      appBar: AppBar(title: Text(te ? 'వర్కౌట్' : 'Workout')),
      body: SafeArea(child: body),
    );
  }

  // ------------------------------------------------------------------------------------------------ pick
  Widget _pickView(AskodoxWorkoutState state, bool te) {
    final today = ref.read(askodoxWorkoutClockProvider)();
    final days = askodoxWorkoutDays([...state.sessions, if (state.active != null) state.active!]);
    final week = askodoxWorkoutWeek(days, today);
    final streak = askodoxWorkoutStreak(days, today);
    final medals = askodoxWorkoutMedals(state.sessions);
    final gyms = ref.watch(askodoxMyMembershipsProvider).valueOrNull ?? const [];
    final sets = state.active?.sets.length ?? 0;
    const names = [('సో', 'M'), ('మం', 'T'), ('బు', 'W'), ('గు', 'T'), ('శు', 'F'), ('శ', 'S'), ('ఆ', 'S')];
    return ListView(key: const Key('askodoxWorkoutPick'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 0; i < 7; i++)
                Column(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: week[i] ? AskodoxLook.good : AskodoxLook.bg,
                        border: Border.all(color: week[i] ? AskodoxLook.good : AskodoxLook.line)),
                    child: week[i] ? const Icon(Icons.check_rounded, size: 18, color: AskodoxLook.bg) : null,
                  ),
                  const SizedBox(height: 4),
                  Text(te ? names[i].$1 : names[i].$2, style: const TextStyle(fontSize: 11.5, color: AskodoxLook.muted)),
                ]),
            ]),
            const SizedBox(height: 10),
            Text(
                askodoxWorkoutStreakText(streak, te),
                key: const Key('askodoxWorkoutStreak'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(te ? 'రికార్డ్ మెడల్స్: $medals' : 'Record medals: $medals',
                key: const Key('askodoxWorkoutMedals'), style: const TextStyle(color: AskodoxLook.muted)),
          ]),
        ),
      ),
      for (final gym in gyms)
        Card(
          key: ValueKey('askodoxWorkoutGym-${gym['business_id']}'),
          child: ListTile(
            leading: const Icon(Icons.badge_rounded, color: AskodoxLook.accentText),
            title: Text('${gym['shop'] ?? ''}'),
            subtitle: Text(te
                ? 'సభ్యత్వం ముగింపు: ${askodoxTermInt(gym['days_left'])} రోజులు'
                : 'Membership ends in ${askodoxTermInt(gym['days_left'])} days'),
            trailing: OutlinedButton(
                onPressed: () => context.push('/me/memberships'), child: Text(te ? 'హాజరు' : 'Check in')),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final part in askodoxWorkoutParts)
          ChoiceChip(
            key: ValueKey('askodoxWorkoutPart-${part.id}'),
            label: Text(te ? part.te : part.en),
            selected: _part == part.id,
            onSelected: (_) => setState(() => _part = part.id),
          ),
      ]),
      const SizedBox(height: 4),
      for (final exercise in state.exercises.where((e) => e.part == _part)) _exerciseRow(exercise, state, te),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('askodoxWorkoutOwnName'),
            controller: _ownName,
            maxLength: 40,
            decoration: InputDecoration(labelText: te ? 'మీ స్వంత వ్యాయామం పేరు' : 'Your own exercise', counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('askodoxWorkoutOwnAdd'),
          onPressed: () async {
            final added = await ref.read(askodoxWorkoutProvider.notifier).addExercise(_ownName.text, _part);
            if (added != null && mounted) _ownName.clear();
          },
          child: Text(te ? 'చేర్చు' : 'Add'),
        ),
      ]),
      if (sets > 0) ...[
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('askodoxWorkoutFinish'),
          onPressed: () => _finish(state),
          child: Text(te ? 'వర్కౌట్ పూర్తి ($sets సెట్లు)' : 'Finish workout ($sets sets)'),
        ),
      ],
      const SizedBox(height: 16),
      Text(te ? 'ఇది ఉచితం. AI Credits ఖర్చు కాదు. మీ వర్కౌట్ ఈ ఫోన్‌లోనే ఉంటుంది.' : 'Free. No AI Credits. Your workouts stay on this phone.',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
    ]);
  }

  Widget _exerciseRow(AskodoxWorkoutExercise exercise, AskodoxWorkoutState state, bool te) {
    final best = askodoxWorkoutBest(state.sessions, exercise.id);
    return Card(
      key: ValueKey('askodoxWorkoutExercise-${exercise.id}'),
      child: ListTile(
        title: Text(exercise.name(te)),
        subtitle: Text(best == null
            ? (te ? 'మొదటి సారి' : 'First time')
            : (te ? 'గత బెస్ట్: ${askodoxWorkoutSetText(best, te)}' : 'Best so far: ${askodoxWorkoutSetText(best, te)}')),
        trailing: FilledButton(
          key: ValueKey('askodoxWorkoutStart-${exercise.id}'),
          onPressed: () => _open(exercise, state),
          child: Text(te ? 'మొదలు' : 'Start'),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ one set
  Widget _stepper(String label, String value, String keyName, VoidCallback less, VoidCallback more) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AskodoxLook.muted)),
          Text(value,
              key: Key('askodoxWorkout$keyName'),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.outlined(
                key: Key('askodoxWorkout${keyName}Less'), onPressed: less, icon: const Icon(Icons.remove_rounded)),
            const SizedBox(width: 12),
            IconButton.outlined(
                key: Key('askodoxWorkout${keyName}More'), onPressed: more, icon: const Icon(Icons.add_rounded)),
          ]),
        ]),
      );

  Widget _setView(AskodoxWorkoutExercise exercise, AskodoxWorkoutState state, bool te) {
    final mine = [for (final s in state.active?.sets ?? const <AskodoxWorkoutSet>[]) if (s.exercise == exercise.id) s];
    return ListView(key: const Key('askodoxWorkoutSetView'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text(exercise.name(te), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text(te ? 'సెట్ ${mine.length + 1}' : 'Set ${mine.length + 1}', style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 12),
      if (_rest > 0)
        Card(
          key: const Key('askodoxWorkoutRest'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'విశ్రాంతి' : 'Rest', style: const TextStyle(color: AskodoxLook.muted)),
                  Text(askodoxWorkoutClock(Duration(seconds: _rest)),
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w800, color: AskodoxLook.accentText,
                          fontFeatures: AskodoxLook.figures)),
                ]),
              ),
              TextButton(key: const Key('askodoxWorkoutRestSkip'), onPressed: _stopRest, child: Text(te ? 'దాటవేయి' : 'Skip')),
            ]),
          ),
        ),
      if (_record)
        Card(
          key: const Key('askodoxWorkoutRecord'),
          child: ListTile(
            leading: const Icon(Icons.military_tech_rounded, color: AskodoxLook.good),
            title: Text(te ? 'కొత్త రికార్డ్!' : 'New record!'),
            subtitle: Text(te ? 'మీ గత బెస్ట్ కంటే ఎక్కువ' : 'More than your best so far'),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _stepper(
                te ? 'కేజీ' : 'kg',
                askodoxWorkoutKg(_grams),
                'Kg',
                () => setState(() => _grams = _grams - askodoxWorkoutStepGrams < 0 ? 0 : _grams - askodoxWorkoutStepGrams),
                () => setState(() =>
                    _grams = _grams + askodoxWorkoutStepGrams > askodoxWorkoutMaxGrams ? askodoxWorkoutMaxGrams : _grams + askodoxWorkoutStepGrams)),
            _stepper(te ? 'సార్లు' : 'Times', '$_reps', 'Reps', () => setState(() => _reps = _reps <= 1 ? 1 : _reps - 1),
                () => setState(() => _reps = _reps >= askodoxWorkoutMaxReps ? askodoxWorkoutMaxReps : _reps + 1)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const Key('askodoxWorkoutSetDone'),
        onPressed: () => _setDone(state),
        child: Text(te ? 'సెట్ పూర్తయింది' : 'Set done'),
      ),
      if (mine.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(te ? 'ఈ రోజు సెట్లు' : 'Sets today', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        for (var i = 0; i < mine.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check_circle_rounded, color: AskodoxLook.good),
            title: Text('${te ? 'సెట్' : 'Set'} ${i + 1} · ${askodoxWorkoutSetText(mine[i], te)}'),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('askodoxWorkoutUndo'),
            onPressed: () {
              _stopRest();
              setState(() => _record = false);
              ref.read(askodoxWorkoutProvider.notifier).undoLastSet();
            },
            child: Text(te ? 'చివరి సెట్ తీసేయి' : 'Take the last set back'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            key: const Key('askodoxWorkoutOther'),
            onPressed: () {
              _stopRest();
              setState(() => _exercise = null);
            },
            child: Text(te ? 'వేరే వ్యాయామం' : 'Another exercise'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            key: const Key('askodoxWorkoutFinishHere'),
            onPressed: (state.active?.sets.isEmpty ?? true) ? null : () => _finish(state),
            child: Text(te ? 'వర్కౌట్ పూర్తి' : 'Finish workout'),
          ),
        ),
      ]),
    ]);
  }

  // ------------------------------------------------------------------------------------------------ done
  Widget _box(String value, String label, String keyName) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(children: [
              Text(value,
                  key: Key(keyName),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
            ]),
          ),
        ),
      );

  Widget _doneView(AskodoxWorkoutSession done, AskodoxWorkoutState state, bool te) {
    final time = (done.end ?? done.start).difference(done.start);
    return ListView(key: const Key('askodoxWorkoutDone'), padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Text(te ? 'వర్కౌట్ పూర్తి' : 'Workout done', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      Text(te ? 'బాగా చేశారు' : 'Well done', style: const TextStyle(color: AskodoxLook.muted)),
      const SizedBox(height: 14),
      Row(children: [
        _box(askodoxWorkoutClock(time), te ? 'సమయం' : 'Time', 'askodoxWorkoutDoneTime'),
        const SizedBox(width: 8),
        _box('${done.sets.length}', te ? 'సెట్లు' : 'Sets', 'askodoxWorkoutDoneSets'),
        const SizedBox(width: 8),
        _box(askodoxWorkoutKg(askodoxWorkoutVolumeGrams(done)), te ? 'మొత్తం కేజీ' : 'Total kg', 'askodoxWorkoutDoneKg'),
      ]),
      for (final record in _doneRecords)
        Card(
          key: ValueKey('askodoxWorkoutDoneRecord-${record.exercise}'),
          child: ListTile(
            leading: const Icon(Icons.military_tech_rounded, color: AskodoxLook.good),
            title: Text(te ? 'కొత్త రికార్డ్!' : 'New record!'),
            subtitle: Text('${state.exercise(record.exercise)?.name(te) ?? record.exercise} '
                '${askodoxWorkoutSetText(record.best, te)} '
                '(${te ? 'గత బెస్ట్' : 'before'}: ${askodoxWorkoutSetText(record.before, te)})'),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('askodoxWorkoutDoneOk'),
        onPressed: () => setState(() {
          _done = null;
          _doneRecords = const [];
        }),
        child: Text(te ? 'సరే' : 'OK'),
      ),
    ]);
  }
}
