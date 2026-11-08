import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/smart_tools/data/phone_meters.dart';
import 'package:podx/features/work_mode/data/work_mode_store.dart';
import 'package:podx/features/work_mode/domain/work_mode_plan.dart';
import 'package:podx/features/work_mode/presentation/work_mode_screens.dart';
import 'package:podx/features/work_mode/presentation/work_scene.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSteps implements AskodoxStepSource {
  int value = 10000;
  String? error;

  @override
  Future<int> counter() async {
    final e = error;
    if (e != null) throw AskodoxMeterException(e);
    return value;
  }
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The scene animates forever, so tests pump frames instead of settling.
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_FakeSteps> _open(WidgetTester tester, Widget screen,
    {Map<String, Object> prefs = const {}, DateTime? today}) async {
  SharedPreferences.setMockInitialValues(prefs);
  _tallView(tester);
  final steps = _FakeSteps();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      askodoxStepSourceProvider.overrideWithValue(steps),
      // A Monday, the first day of the job.
      askodoxWorkClockProvider.overrideWithValue(() => today ?? DateTime(2026, 11, 2, 7)),
    ],
    child: MaterialApp(home: screen),
  ));
  await _frames(tester);
  return steps;
}

void main() {
  testWidgets('first open explains how to play, then a sport suggests jobs, then the job starts', (tester) async {
    final steps = await _open(tester, const AskodoxWorkModeScreen());
    expect(find.byKey(const Key('askodoxWorkIntro')), findsOneWidget);
    expect(find.textContaining('no points'), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxWorkIntroStart')));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxWorkJobPicker')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('askodoxWorkSport-shuttle')));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxWorkSportHint')), findsOneWidget);
    expect(find.text('Fits you'), findsNWidgets(2)); // paper boy + welding

    await tester.tap(find.byKey(const ValueKey('askodoxWorkJob-paddy')));
    await _frames(tester);
    // Task size: 10 / 50 / 100 acres.
    expect(find.text('50 acres'), findsOneWidget);
    expect(find.text('100 acres'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxWorkSize-medium')));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxWorkToday')), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkScene')), findsWidgets);
    expect(find.textContaining('Stage 1/6: Raise the nursery'), findsOneWidget);
    // The first reading only sets the start point; nothing walked yet -> the work is waiting.
    expect(find.text('0 / 4,000 steps'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkWaiting')), findsOneWidget);
    expect(find.text('Raise the nursery: 0 / 50 acres'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkReplay')), findsNothing);

    // Walk 4,200 steps and count again.
    steps.value = 14200;
    await tester.tap(find.byKey(const Key('askodoxWorkRefresh')));
    await _frames(tester);
    expect(find.text('4,200 / 4,000 steps'), findsOneWidget);
    expect(find.text('Today’s goal done!'), findsOneWidget);
    expect(find.text('Raise the nursery: 4 / 50 acres'), findsOneWidget);
    expect(find.text('700 more steps → 1 more done (acres)'), findsOneWidget);
    expect(find.textContaining('44,800 steps to finish this stage (46 acres left)'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkWaiting')), findsNothing);
    expect(find.textContaining('On schedule'), findsOneWidget);

    // The day's work replays fast.
    await tester.tap(find.byKey(const Key('askodoxWorkReplay')));
    await _frames(tester, 10);
    expect(find.byKey(const Key('askodoxWorkReplaySheet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxWorkReplaySpeed-4')));
    // The restarted ticker takes its start time on the first frame after the tap.
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await _frames(tester);
    expect(find.textContaining('+4,200 steps'), findsOneWidget);
  });

  testWidgets('treadmill steps typed by hand are labelled; a missing permission is explained', (tester) async {
    final steps = await _open(tester, const AskodoxWorkModeScreen(), prefs: {
      askodoxWorkModePrefsKey: '{"intro_seen":true,"job":"paper","started_on":"2026-11-02","job_steps":0}',
    });
    expect(find.byKey(const Key('askodoxWorkToday')), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxWorkManual')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('askodoxWorkManualField')), '3000');
    await tester.tap(find.byKey(const Key('askodoxWorkManualSave')));
    await _frames(tester);
    expect(find.text('3,000 / 4,000 steps'), findsOneWidget);
    expect(find.text('Typed by hand: 3,000'), findsOneWidget);

    steps.error = 'permission_requested';
    await tester.tap(find.byKey(const Key('askodoxWorkRefresh')));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxWorkStepProblem')), findsOneWidget);
    expect(find.textContaining('Physical activity'), findsOneWidget);
  });

  testWidgets('seva: only reviewed practices open; traditions wait for scholars', (tester) async {
    await _open(tester, const AskodoxSevaScreen());
    expect(find.byKey(const ValueKey('askodoxSevaPractice-shanti')), findsOneWidget);
    final hindu = tester.widget<ListTile>(find.byKey(const ValueKey('askodoxSevaPractice-hindu')));
    expect(hindu.enabled, isFalse);
    expect(find.textContaining('after review by scholars'), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('askodoxSevaMinutes-30')));
    await _frames(tester);
    expect(find.text('30:00'), findsOneWidget);
  });

  testWidgets('Sunday is a rest day: light goal, the work goes on, the chip explains it', (tester) async {
    await _open(tester, const AskodoxWorkModeScreen(),
        prefs: {askodoxWorkModePrefsKey: '{"intro_seen":true,"job":"house","started_on":"2026-11-02","job_steps":0}'},
        today: DateTime(2026, 11, 8, 7));
    expect(find.text('0 / 3,000 steps'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkRestNote')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxWorkRestDay')));
    await _frames(tester);
    expect(find.text('Sunday = rest day'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkLiveStatus')), findsOneWidget);
  });

  test('every job, every stage paints at any progress, walking or not', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final job in askodoxWorkJobs) {
      for (var i = 0; i < job.stages.length; i++) {
        for (final f in const [0.0, 0.01, 0.37, 0.5, 0.99, 1.0]) {
          for (final active in const [true, false]) {
            for (final sec in const [0.0, 13.7, 59.9]) {
              final recorder = ui.PictureRecorder();
              AskodoxWorkScenePainter(
                job: job,
                stageIndex: i,
                fraction: f,
                seconds: sec,
                active: active,
                bubble: 0.4,
                gain: 120,
              ).paint(Canvas(recorder), const Size(360, 240));
              recorder.endRecording();
            }
          }
        }
      }
    }
  });
}
