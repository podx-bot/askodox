import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/memberships/memberships_screens.dart' show askodoxMyMembershipsProvider;
import 'package:podx/features/workout/workout_logic.dart';
import 'package:podx/features/workout/workout_screen.dart';
import 'package:podx/features/workout/workout_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AskodoxWorkoutSet _set(String exercise, int grams, int reps, DateTime at) =>
    AskodoxWorkoutSet(exercise: exercise, grams: grams, reps: reps, at: at);

AskodoxWorkoutSession _session(DateTime start, List<AskodoxWorkoutSet> sets, {int minutes = 40}) =>
    AskodoxWorkoutSession(id: '${start.microsecondsSinceEpoch}', start: start, end: start.add(Duration(minutes: minutes)), sets: sets);

void main() {
  final mon = DateTime(2026, 11, 23, 7);
  final tue = DateTime(2026, 11, 24, 7);
  final wed = DateTime(2026, 11, 25, 7);
  final fri = DateTime(2026, 11, 27, 7);

  group('workout rules', () {
    test('a better set is heavier, or the same weight more times', () {
      expect(askodoxWorkoutBetter(_set('squat', 60000, 5, mon), _set('squat', 57500, 8, mon)), isTrue);
      expect(askodoxWorkoutBetter(_set('squat', 60000, 9, mon), _set('squat', 60000, 8, mon)), isTrue);
      expect(askodoxWorkoutBetter(_set('squat', 60000, 8, mon), _set('squat', 60000, 8, mon)), isFalse);
      expect(askodoxWorkoutBetter(_set('squat', 55000, 20, mon), _set('squat', 60000, 8, mon)), isFalse);
      // Body weight only (0 kg): more times is better.
      expect(askodoxWorkoutBetter(_set('push_ups', 0, 26, mon), _set('push_ups', 0, 25, mon)), isTrue);
    });

    test('the first time is a start, not a record; beating the old best is one record per exercise', () {
      final first = _session(mon, [_set('bench_press', 50000, 10, mon), _set('bench_press', 57500, 8, mon)]);
      expect(askodoxWorkoutRecords(const [], first), isEmpty);
      final second = _session(wed, [
        _set('bench_press', 55000, 8, wed),
        _set('bench_press', 60000, 8, wed),
        _set('bench_press', 60000, 6, wed),
        _set('squat', 80000, 5, wed),
      ]);
      final records = askodoxWorkoutRecords([first], second);
      expect(records, hasLength(1));
      expect(records.single.exercise, 'bench_press');
      expect(records.single.best.grams, 60000);
      expect(records.single.best.reps, 8);
      expect(records.single.before.grams, 57500);
      expect(askodoxWorkoutMedals([second, first]), 1);
      // The same weight and times again is not a record.
      expect(askodoxWorkoutRecords([first, second], _session(fri, [_set('bench_press', 60000, 8, fri)])), isEmpty);
    });

    test('weight moved, kg text, set text and the clock', () {
      final session = _session(mon, [_set('squat', 60000, 8, mon), _set('squat', 57500, 8, mon), _set('push_ups', 0, 25, mon)]);
      expect(askodoxWorkoutVolumeGrams(session), 940000);
      expect(askodoxWorkoutKg(940000), '940');
      expect(askodoxWorkoutKg(57500), '57.5');
      expect(askodoxWorkoutKg(1250), '1.25');
      expect(askodoxWorkoutSetText(_set('squat', 60000, 8, mon), true), '60 కేజీ × 8');
      expect(askodoxWorkoutSetText(_set('push_ups', 0, 25, mon), false), '25 times');
      expect(askodoxWorkoutClock(const Duration(minutes: 48, seconds: 20)), '48:20');
      expect(askodoxWorkoutClock(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
      expect(askodoxWorkoutClock(const Duration(seconds: -4)), '00:00');
    });

    test('the week and the days in a row', () {
      final days = askodoxWorkoutDays([
        _session(mon, [_set('squat', 60000, 8, mon)]),
        _session(tue, [_set('squat', 60000, 8, tue)]),
        _session(wed, [_set('squat', 60000, 8, wed)]),
        _session(fri, const []),
      ]);
      expect(days, {'2026-11-23', '2026-11-24', '2026-11-25'});
      expect(askodoxWorkoutWeek(days, fri), [true, true, true, false, false, false, false]);
      expect(askodoxWorkoutStreak(days, wed), 3);
      // Thursday morning, before today's workout: the run still stands.
      expect(askodoxWorkoutStreak(days, DateTime(2026, 11, 26, 6)), 3);
      // A missed day ends it.
      expect(askodoxWorkoutStreak(days, fri), 0);
      // Across a month end.
      expect(askodoxWorkoutStreak({'2026-11-30', '2026-12-01'}, DateTime(2026, 12, 1, 9)), 2);
      expect(askodoxWorkoutStreakText(0, false), 'Start today');
      expect(askodoxWorkoutStreakText(4, true), '4 రోజులు వరుసగా');
    });

    test('what is saved comes back the same; a broken copy is an empty start', () {
      final state = AskodoxWorkoutState(
        loaded: true,
        sessions: [_session(mon, [_set('squat', 57500, 8, mon)])],
        active: AskodoxWorkoutSession(id: 'a', start: wed, sets: [_set('own_1', 0, 12, wed)]),
        own: const [AskodoxWorkoutExercise('own_1', 'core', 'Plank hold', 'Plank hold', own: true)],
      );
      final back = AskodoxWorkoutState.decode(state.encode());
      expect(back.loaded, isTrue);
      expect(back.sessions.single.sets.single.grams, 57500);
      expect(back.sessions.single.end, mon.add(const Duration(minutes: 40)));
      expect(back.active!.sets.single.reps, 12);
      expect(back.exercise('own_1')!.part, 'core');
      expect(back.exercise('squat')!.te, 'స్క్వాట్');
      expect(AskodoxWorkoutState.decode('{not json').sessions, isEmpty);
      expect(AskodoxWorkoutState.decode('{not json').loaded, isTrue);
      expect(AskodoxWorkoutState.decode(null).active, isNull);
    });

    test('every starter exercise sits under a listed body part, with one id each', () {
      final parts = {for (final p in askodoxWorkoutParts) p.id};
      expect({for (final e in askodoxWorkoutExercises) e.id}.length, askodoxWorkoutExercises.length);
      for (final e in askodoxWorkoutExercises) {
        expect(parts, contains(e.part), reason: e.id);
      }
      for (final p in askodoxWorkoutParts) {
        expect(askodoxWorkoutExercises.where((e) => e.part == p.id), isNotEmpty, reason: p.id);
      }
    });
  });

  group('workout store', () {
    test('sets start a workout, undo takes one back, finish keeps it, an own exercise is added once', () async {
      SharedPreferences.setMockInitialValues({});
      var now = mon;
      final container = ProviderContainer(overrides: [askodoxWorkoutClockProvider.overrideWithValue(() => now)]);
      addTearDown(container.dispose);
      final store = container.read(askodoxWorkoutProvider.notifier);
      for (var i = 0; i < 20 && !container.read(askodoxWorkoutProvider).loaded; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(askodoxWorkoutProvider).loaded, isTrue);

      await store.addSet('squat', 60000, 8);
      await store.addSet('squat', 60000, 0); // not a set
      await store.addSet('squat', 62500, 6);
      expect(container.read(askodoxWorkoutProvider).active!.sets, hasLength(2));
      await store.undoLastSet();
      expect(container.read(askodoxWorkoutProvider).active!.sets.single.grams, 60000);

      now = mon.add(const Duration(minutes: 30));
      final done = await store.finish();
      expect(done!.end, now);
      expect(container.read(askodoxWorkoutProvider).active, isNull);
      expect(container.read(askodoxWorkoutProvider).sessions, hasLength(1));
      expect(await store.finish(), isNull);

      final own = await store.addExercise('  Plank   hold ', 'core');
      expect(own!.en, 'Plank hold');
      expect((await store.addExercise('plank hold', 'core'))!.id, own.id);
      expect(await store.addExercise('   ', 'core'), isNull);
      expect(container.read(askodoxWorkoutProvider).own, hasLength(1));

      final prefs = await SharedPreferences.getInstance();
      final saved = AskodoxWorkoutState.decode(prefs.getString(askodoxWorkoutPrefsKey));
      expect(saved.sessions.single.sets.single.reps, 8);
      expect(saved.own.single.en, 'Plank hold');
    });
  });

  group('workout screen', () {
    testWidgets('pick -> set done -> rest timer -> record -> finish', (tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final earlier = AskodoxWorkoutState(loaded: true, sessions: [
        _session(mon, [_set('bench_press', 57500, 8, mon)]),
      ]);
      SharedPreferences.setMockInitialValues({askodoxWorkoutPrefsKey: earlier.encode()});
      var now = wed;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          askodoxWorkoutClockProvider.overrideWithValue(() => now),
          askodoxMyMembershipsProvider.overrideWith((ref) async => [
                {'business_id': 'b1', 'shop': 'Power Fit', 'days_left': 12},
              ]),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const AskodoxWorkoutScreen()),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('askodoxWorkoutPick')), findsOneWidget);
      expect(find.text('Best so far: 57.5 kg × 8'), findsOneWidget);
      expect(find.text('Record medals: 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('askodoxWorkoutGym-b1')), findsOneWidget);
      expect(find.byKey(const Key('askodoxWorkoutFinish')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('askodoxWorkoutStart-bench_press')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxWorkoutSetView')), findsOneWidget);
      // Starts from the last best: 57.5 x 8. One step up = 60.
      expect(tester.widget<Text>(find.byKey(const Key('askodoxWorkoutKg'))).data, '57.5');
      await tester.tap(find.byKey(const Key('askodoxWorkoutKgMore')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('askodoxWorkoutKg'))).data, '60');

      await tester.tap(find.byKey(const Key('askodoxWorkoutSetDone')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('askodoxWorkoutRest')), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.byKey(const Key('askodoxWorkoutRecord')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('01:29'), findsOneWidget);

      // A lighter set straight after: the timer starts again, the record is not said twice.
      await tester.tap(find.byKey(const Key('askodoxWorkoutKgLess')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('askodoxWorkoutSetDone')));
      await tester.pump();
      await tester.pump();
      expect(find.text('01:30'), findsOneWidget);
      expect(find.byKey(const Key('askodoxWorkoutRecord')), findsNothing);
      await tester.tap(find.byKey(const Key('askodoxWorkoutRestSkip')));
      await tester.pump();
      expect(find.byKey(const Key('askodoxWorkoutRest')), findsNothing);

      now = wed.add(const Duration(minutes: 48, seconds: 20));
      await tester.tap(find.byKey(const Key('askodoxWorkoutFinishHere')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('askodoxWorkoutDone')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('askodoxWorkoutDoneTime'))).data, '48:20');
      expect(tester.widget<Text>(find.byKey(const Key('askodoxWorkoutDoneSets'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const Key('askodoxWorkoutDoneKg'))).data, '940');
      expect(find.byKey(const ValueKey('askodoxWorkoutDoneRecord-bench_press')), findsOneWidget);

      await tester.tap(find.byKey(const Key('askodoxWorkoutDoneOk')));
      await tester.pump();
      expect(find.text('Best so far: 60 kg × 8'), findsOneWidget);
      expect(find.text('Record medals: 1'), findsOneWidget);
      expect(find.text('1 day · come again tomorrow'), findsOneWidget);
    });
  });
}
