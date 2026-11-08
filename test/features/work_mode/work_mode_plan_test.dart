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

  test('task size: units scale 10 / 50 / 100, steps a day 4,000 / 7,000 / 10,000, same days', () {
    final paddy = askodoxWorkJob('paddy')!;
    expect([for (final z in askodoxWorkSizes) paddy.units(z)], [10, 50, 100]);
    expect([for (final z in askodoxWorkSizes) z.stepsPerDay], [4000, 7000, 10000]);
    final big = askodoxWorkSize('large');
    expect(paddy.totalStepsFor(big), 45 * 10000);
    final p = askodoxWorkProgress(paddy, 7 * 10000 + 5 * 10000 + 4 * 10000, size: big); // 4 of 9 transplant days
    expect(p.stage.id, 'transplant');
    expect(p.unitsTotal, 100);
    expect(p.unitsDone, 44);
    expect(p.stepsPerUnit, closeTo(900, 1e-9));
    expect(p.stepsToNextUnit, 500);
    expect(p.daysLeft, 45 - 16);
    final monday = DateTime(2026, 11, 2);
    expect(askodoxWorkDailyGoal(monday, monday, size: big), 5700);
    expect(askodoxWorkDailyGoal(monday, monday.add(const Duration(days: 21)), size: big), 10000);
    expect(askodoxWorkDailyGoal(monday, DateTime(2026, 11, 8), size: askodoxWorkSize('small')), 1700);
    expect(askodoxWorkSize('nope').id, 'medium');
  });

  test('the plan before today adds the daily goals of the earlier days', () {
    final monday = DateTime(2026, 11, 2);
    expect(askodoxWorkPlannedBefore(monday, monday), 0);
    // Mon..Sat = 6 x 4,000, Sunday = 3,000.
    expect(askodoxWorkPlannedBefore(monday, DateTime(2026, 11, 9)), 6 * 4000 + 3000);
  });

  test('every job says what is waiting when nobody walks, and counts work in its own unit', () {
    for (final job in askodoxWorkJobs) {
      expect(job.waitEn.isNotEmpty && job.waitTe.isNotEmpty, isTrue, reason: job.id);
      expect(job.unitEn.isNotEmpty && job.unitTe.isNotEmpty && job.baseUnits > 0, isTrue, reason: job.id);
    }
    expect(askodoxWorkJob('hotel')!.gameDays, 15);
  });
}
