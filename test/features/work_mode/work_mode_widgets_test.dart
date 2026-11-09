import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/smart_tools/data/phone_meters.dart';
import 'package:podx/features/work_mode/data/work_mode_store.dart';
import 'package:podx/features/work_mode/data/work_team_repository.dart';
import 'package:podx/features/work_mode/domain/work_mode_plan.dart';
import 'package:podx/features/work_mode/presentation/work_mode_screens.dart';
import 'package:podx/features/work_mode/presentation/work_scene.dart';
import 'package:podx/features/work_mode/presentation/work_team_widgets.dart';
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

/// A signed-in team server in memory: names and day totals only.
class _FakeTeam implements WorkTeamRepository {
  AskodoxWorkTeam? team;
  final reported = <int>[];

  @override
  bool get signedIn => true;

  @override
  Future<AskodoxWorkTeamAnswer> mine(String day) async => (team: team, problem: null);

  @override
  Future<AskodoxWorkTeamAnswer> create(
      {required String name, required String job, required String size, required String wear}) async {
    team = AskodoxWorkTeam(code: 'KQ7M2P', name: name, job: job, size: size, members: [
      AskodoxWorkTeamMember(member: 'm_1', name: name, wear: wear, me: true),
      const AskodoxWorkTeamMember(member: 'm_2', name: 'Lakshmi', wear: 'saree', steps: 2940, active: true),
    ]);
    return (team: team, problem: null);
  }

  @override
  Future<AskodoxWorkTeamAnswer> join({required String code, required String name, required String wear}) async =>
      (team: null, problem: 'CODE_NOT_FOUND');

  @override
  Future<AskodoxWorkTeamAnswer> reportSteps(String day, int steps) async {
    reported.add(steps);
    final t = team;
    if (t != null) {
      team = AskodoxWorkTeam(code: t.code, name: t.name, job: t.job, size: t.size, members: [
        for (final m in t.members)
          m.me ? AskodoxWorkTeamMember(member: m.member, name: m.name, wear: m.wear, steps: steps, me: true) : m,
      ]);
    }
    return (team: team, problem: null);
  }

  @override
  Future<bool> leave() async {
    team = null;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeSteps> _open(WidgetTester tester, Widget screen,
    {Map<String, Object> prefs = const {}, DateTime? today, WorkTeamRepository? team}) async {
  SharedPreferences.setMockInitialValues(prefs);
  _tallView(tester);
  final steps = _FakeSteps();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      askodoxStepSourceProvider.overrideWithValue(steps),
      // A Monday, the first day of the job.
      askodoxWorkClockProvider.overrideWithValue(() => today ?? DateTime(2026, 11, 2, 7)),
      if (team != null) workTeamRepositoryProvider.overrideWithValue(team),
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

  testWidgets('a team: make it, invite with a code and the app link, see who did how much; result card',
      (tester) async {
    final fake = _FakeTeam();
    final steps = await _open(tester, const AskodoxWorkModeScreen(),
        prefs: {
          askodoxWorkModePrefsKey:
              '{"intro_seen":true,"job":"paddy","started_on":"2026-11-02","job_steps":0,"last_counter":10000}',
        },
        team: fake);
    expect(find.byKey(const Key('askodoxWorkTeam')), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkResult')), findsOneWidget);
    expect(find.text('Today so far'), findsOneWidget);

    await tester.tap(find.byKey(const Key('askodoxWorkTeamCreate')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('askodoxWorkTeamNameField')), 'Dad');
    await tester.tap(find.byKey(const Key('askodoxWorkTeamFormSave')));
    await _frames(tester);
    expect(find.textContaining('Code: KQ7M2P'), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxWorkTeamMember-m_2')), findsOneWidget);
    expect(find.text('Dad (you)'), findsOneWidget);
    expect(find.byKey(const Key('askodoxWorkTeamInvite')), findsOneWidget);
    final invite = askodoxWorkInviteText(fake.team!, false);
    expect(invite, contains('KQ7M2P'));
    expect(invite, contains(askodoxAppDownloadLink));

    // Walking: this phone's day total goes to the team.
    steps.value = 14200;
    await tester.tap(find.byKey(const Key('askodoxWorkRefresh')));
    await _frames(tester);
    expect(fake.reported, contains(4200));
    expect(find.text('Dad: 4,200 steps · 4 acres'), findsOneWidget);
  });

  testWidgets('a wrong invite code is explained', (tester) async {
    await _open(tester, const AskodoxWorkModeScreen(),
        prefs: {askodoxWorkModePrefsKey: '{"intro_seen":true,"job":"paddy","started_on":"2026-11-02","job_steps":0}'},
        team: _FakeTeam());
    await tester.tap(find.byKey(const Key('askodoxWorkTeamJoin')));
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('askodoxWorkTeamCodeField')), 'ZZZZZZ');
    await tester.enterText(find.byKey(const Key('askodoxWorkTeamNameField')), 'Ravi');
    await tester.tap(find.byKey(const Key('askodoxWorkTeamFormSave')));
    await _frames(tester);
    expect(find.byKey(const Key('askodoxWorkTeamProblem')), findsOneWidget);
    expect(find.textContaining('No team has this code'), findsOneWidget);
  });

  test('the new jobs exist and fit their sports', () {
    for (final id in ['milk', 'veg_cart', 'cattle', 'fishing']) {
      expect(askodoxWorkJob(id), isNotNull, reason: id);
      expect(askodoxSportMatches.any((s) => s.jobs.contains(id)), isTrue, reason: id);
    }
  });

  test('every job, every stage paints at any progress, walking or not, alone or as a team', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final job in askodoxWorkJobs) {
      for (var i = 0; i < job.stages.length; i++) {
        for (final f in const [0.0, 0.01, 0.37, 0.5, 0.99, 1.0]) {
          for (final active in const [true, false]) {
            for (final sec in const [0.0, 4.1, 13.7, 59.9]) {
              for (final crew in [null, _team(active)]) {
                final recorder = ui.PictureRecorder();
                AskodoxWorkScenePainter(
                  job: job,
                  stageIndex: i,
                  fraction: f,
                  seconds: sec,
                  active: active,
                  bubble: 0.4,
                  gain: 120,
                  te: sec > 5,
                  crew: crew,
                ).paint(Canvas(recorder), const Size(360, 240));
                recorder.endRecording();
              }
            }
          }
        }
      }
    }
  });
}

/// A team of three: you (following [active]), one walking, one who has not walked.
List<AskodoxWorkCrewMember> _team(bool active) => [
      AskodoxWorkCrewMember(name: 'You', active: active),
      const AskodoxWorkCrewMember(name: 'Lakshmi', active: true, wear: 'saree'),
      const AskodoxWorkCrewMember(name: 'Ravi', active: false, wear: 'shirt'),
    ];
