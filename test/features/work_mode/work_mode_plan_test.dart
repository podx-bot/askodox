import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/work_mode/data/work_mode_store.dart';
import 'package:podx/features/work_mode/domain/work_mode_plan.dart';

void main() {
  test('every job runs in exactly half of its real-world time, stages in the real order', () {
    expect(askodoxWorkJobs.length, greaterThanOrEqualTo(8));
    for (final job in askodoxWorkJobs) {
      expect(job.gameDays * 2, job.realDays, reason: job.id);
      expect(job.stages, isNotEmpty);
      expect(job.stages.every((s) => s.days > 0 && s.tipEn.isNotEmpty && s.tipTe.isNotEmpty), isTrue);
    }
    final paddy = askodoxWorkJob('paddy')!;
    expect(paddy.gameDays, 45);
    expect(paddy.totalSteps, 45 * askodoxWorkStepsPerDay);
    expect(paddy.stages.map((s) => s.id).toList(), ['nursery', 'plough', 'transplant', 'water', 'weed', 'harvest']);
  });

  test('progress follows the steps: stage, day, steps left, done', () {
    final paddy = askodoxWorkJob('paddy')!;
    final start = askodoxWorkProgress(paddy, 0);
    expect(start.stage.id, 'nursery');
    expect(start.gameDay, 1);
    expect(start.stepsLeftInStage, 7 * askodoxWorkStepsPerDay);

    final plough = askodoxWorkProgress(paddy, 7 * askodoxWorkStepsPerDay);
    expect(plough.stage.id, 'plough');
    expect(plough.gameDay, 8);
    expect(plough.stageFraction, 0);

    final mid = askodoxWorkProgress(paddy, 7 * askodoxWorkStepsPerDay + 3500);
    expect(mid.stageFraction, closeTo(3500 / (5 * askodoxWorkStepsPerDay), 1e-9));

    final done = askodoxWorkProgress(paddy, paddy.totalSteps + 10);
    expect(done.done, isTrue);
    expect(done.overall, 1);
    expect(done.gameDay, 45);
    expect(done.stepsLeftInStage, 0);
  });

  test('daily goal ramps by week and is light on Sunday', () {
    final monday = DateTime(2026, 11, 2);
    expect(askodoxWorkDailyGoal(monday, monday), 4000);
    expect(askodoxWorkDailyGoal(monday, monday.add(const Duration(days: 7))), 5000);
    expect(askodoxWorkDailyGoal(monday, monday.add(const Duration(days: 14))), 6000);
    expect(askodoxWorkDailyGoal(monday, monday.add(const Duration(days: 21))), 7000);
    expect(askodoxWorkDailyGoal(monday, monday.add(const Duration(days: 70))), 7000);
    expect(askodoxWorkDailyGoal(monday, DateTime(2026, 11, 8)), askodoxWorkRestDaySteps); // Sunday
  });

  test('step counter delta: first reading gives nothing, restart counts from zero', () {
    expect(askodoxStepCounterDelta(null, 12000), 0);
    expect(askodoxStepCounterDelta(12000, 12450), 450);
    expect(askodoxStepCounterDelta(12450, 300), 300);
    expect(askodoxStepCounterDelta(5, -1), 0);
  });

  test('accelerometer detector counts one step per rise, never twice too fast', () {
    final d = AskodoxStepDetector();
    var t = DateTime(2026, 11, 7, 7);
    for (var i = 0; i < 10; i++) {
      d.add(9.0, t);
      t = t.add(const Duration(milliseconds: 200));
      d.add(12.0, t);
      t = t.add(const Duration(milliseconds: 300));
    }
    expect(d.steps, 10);
    // A second peak 50 ms later is ignored.
    d.add(9.0, t);
    d.add(12.0, t.add(const Duration(milliseconds: 10)));
    d.add(9.0, t.add(const Duration(milliseconds: 20)));
    d.add(12.0, t.add(const Duration(milliseconds: 60)));
    expect(d.steps, 11);
  });

  test('titles come from finished jobs only', () {
    expect(askodoxWorkLevel(0, false), 'Apprentice');
    expect(askodoxWorkLevel(1, false), 'Worker');
    expect(askodoxWorkLevel(3, false), 'Expert');
    expect(askodoxWorkLevel(4, true), 'మాస్టర్');
  });

  test('sport matches only point at real jobs', () {
    for (final s in askodoxSportMatches) {
      expect(s.jobs.every((id) => askodoxWorkJob(id) != null), isTrue, reason: s.id);
    }
  });

  test('share text uses the phone counts and names hand-typed steps separately', () {
    const state = AskodoxWorkState(
      loaded: true,
      introSeen: true,
      jobId: 'paddy',
      jobSteps: 50000,
      counted: {'2026-11-06': 7200, '2026-11-07': 4000},
      manual: {'2026-11-07': 1000},
    );
    final text = askodoxWorkShareText(state, DateTime(2026, 11, 7), false);
    expect(text, contains('12200 steps'));
    expect(text, contains('1 full work days'));
    expect(text, contains('1000 steps typed by hand'));
    expect(text, contains('Paddy field'));
    expect(text.toLowerCase(), isNot(contains('point')));
  });

  test('state survives a save / load round trip', () {
    const state = AskodoxWorkState(
      loaded: true,
      introSeen: true,
      jobId: 'house',
      startedOn: '2026-11-02',
      jobSteps: 1234,
      finished: 2,
      lastCounter: 99,
      counted: {'2026-11-02': 1234},
      sevaMinutes: {'2026-11-02': 15},
    );
    final back = AskodoxWorkState.fromJson(state.toJson());
    expect(back.jobId, 'house');
    expect(back.jobSteps, 1234);
    expect(back.finished, 2);
    expect(back.lastCounter, 99);
    expect(back.stepsOn('2026-11-02'), 1234);
    expect(back.sevaMinutes['2026-11-02'], 15);
  });
}
