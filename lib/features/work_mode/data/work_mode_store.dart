import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../smart_tools/data/phone_meters.dart';
import '../domain/work_mode_plan.dart';

/// Work Mode keeps everything on the phone (nothing is sent to a server):
/// the chosen job, its progress, the daily step log and the seva minutes.
const askodoxWorkModePrefsKey = 'askodox.work_mode.v1';

class AskodoxWorkState {
  const AskodoxWorkState({
    this.loaded = false,
    this.introSeen = false,
    this.jobId,
    this.startedOn,
    this.jobSteps = 0,
    this.finished = 0,
    this.lastCounter,
    this.counted = const {},
    this.manual = const {},
    this.sevaMinutes = const {},
    this.sizeId,
    this.walkTimes = const {},
  });

  final bool loaded;
  final bool introSeen;
  final String? jobId;

  /// Day key (yyyy-mm-dd) the current job started.
  final String? startedOn;

  /// Steps of work done on the current job.
  final int jobSteps;

  /// How many jobs were finished (gives the title).
  final int finished;

  /// Last reading of the phone's step counter.
  final int? lastCounter;

  /// Steps counted by the phone (step counter or the open-screen detector) per day.
  final Map<String, int> counted;

  /// Steps typed by hand (treadmill and similar) per day.
  final Map<String, int> manual;

  /// Seva / meditation minutes per day.
  final Map<String, int> sevaMinutes;

  /// Task size of the current job ('small' / 'medium' / 'large').
  final String? sizeId;

  /// First and last time (epoch seconds) steps were counted, per day (for the replay).
  final Map<String, List<int>> walkTimes;

  AskodoxWorkJob? get job => askodoxWorkJob(jobId);
  AskodoxWorkSize get size => askodoxWorkSize(sizeId);
  AskodoxWorkProgress? get progress {
    final j = job;
    return j == null ? null : askodoxWorkProgress(j, jobSteps, size: size);
  }

  int stepsOn(String day) => (counted[day] ?? 0) + (manual[day] ?? 0);

  AskodoxWorkState copyWith({
    bool? loaded,
    bool? introSeen,
    String? jobId,
    String? startedOn,
    int? jobSteps,
    int? finished,
    int? lastCounter,
    Map<String, int>? counted,
    Map<String, int>? manual,
    Map<String, int>? sevaMinutes,
    String? sizeId,
    Map<String, List<int>>? walkTimes,
  }) =>
      AskodoxWorkState(
        loaded: loaded ?? this.loaded,
        introSeen: introSeen ?? this.introSeen,
        jobId: jobId ?? this.jobId,
        startedOn: startedOn ?? this.startedOn,
        jobSteps: jobSteps ?? this.jobSteps,
        finished: finished ?? this.finished,
        lastCounter: lastCounter ?? this.lastCounter,
        counted: counted ?? this.counted,
        manual: manual ?? this.manual,
        sevaMinutes: sevaMinutes ?? this.sevaMinutes,
        sizeId: sizeId ?? this.sizeId,
        walkTimes: walkTimes ?? this.walkTimes,
      );

  Map<String, Object?> toJson() => {
        'intro_seen': introSeen,
        'job': jobId,
        'started_on': startedOn,
        'job_steps': jobSteps,
        'finished': finished,
        'last_counter': lastCounter,
        'counted': counted,
        'manual': manual,
        'seva_minutes': sevaMinutes,
        'size': sizeId,
        'walk_times': walkTimes,
      };

  static Map<String, int> _ints(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (v is num) out['$k'] = v.toInt();
    });
    return out;
  }

  factory AskodoxWorkState.fromJson(Map<String, Object?> json) => AskodoxWorkState(
        loaded: true,
        introSeen: json['intro_seen'] == true,
        jobId: json['job'] is String ? json['job'] as String : null,
        startedOn: json['started_on'] is String ? json['started_on'] as String : null,
        jobSteps: (json['job_steps'] as num?)?.toInt() ?? 0,
        finished: (json['finished'] as num?)?.toInt() ?? 0,
        lastCounter: (json['last_counter'] as num?)?.toInt(),
        counted: _ints(json['counted']),
        manual: _ints(json['manual']),
        sevaMinutes: _ints(json['seva_minutes']),
        sizeId: json['size'] is String ? json['size'] as String : null,
        walkTimes: _times(json['walk_times']),
      );

  static Map<String, List<int>> _times(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<int>>{};
    raw.forEach((k, v) {
      if (v is List && v.length == 2 && v.every((e) => e is num)) {
        out['$k'] = [(v[0] as num).toInt(), (v[1] as num).toInt()];
      }
    });
    return out;
  }
}

/// The phone's step counter (counts since the phone last started), read from
/// the native `com.askodox.app/hardware` channel. Throws
/// [AskodoxMeterException] with no_sensor / permission_requested /
/// no_reading / unsupported.
abstract interface class AskodoxStepSource {
  Future<int> counter();
}

class DeviceStepSource implements AskodoxStepSource {
  const DeviceStepSource([this.channel = const MethodChannel('com.askodox.app/hardware')]);
  final MethodChannel channel;

  @override
  Future<int> counter() async {
    try {
      final v = await channel.invokeMethod<num>('stepCount');
      if (v == null) throw const AskodoxMeterException('no_reading');
      return v.toInt();
    } on PlatformException catch (e) {
      throw AskodoxMeterException(
          const {'no_sensor', 'permission_requested'}.contains(e.code) ? e.code : 'no_reading');
    } on MissingPluginException {
      throw const AskodoxMeterException('unsupported');
    }
  }
}

final askodoxStepSourceProvider = Provider<AskodoxStepSource>((ref) => const DeviceStepSource());

/// Today, injectable for tests.
final askodoxWorkClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AskodoxWorkController extends StateNotifier<AskodoxWorkState> {
  AskodoxWorkController(this._now) : super(const AskodoxWorkState()) {
    _load();
  }

  final DateTime Function() _now;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(askodoxWorkModePrefsKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map<String, Object?>) {
          state = AskodoxWorkState.fromJson(json);
          return;
        }
      }
    } catch (_) {
      // A broken copy starts fresh; the game never blocks the app.
    }
    state = state.copyWith(loaded: true);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxWorkModePrefsKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  String get _today => askodoxWorkDayKey(_now());

  Future<void> seeIntro() async {
    state = state.copyWith(introSeen: true);
    await _save();
  }

  /// Picks (or switches) the job and its task size: the work starts from zero today.
  Future<void> chooseJob(String jobId, {String size = 'medium'}) async {
    if (askodoxWorkJob(jobId) == null) return;
    state = state.copyWith(introSeen: true, jobId: jobId, startedOn: _today, jobSteps: 0, sizeId: askodoxWorkSize(size).id);
    await _save();
  }

  /// After a finished job: the title goes up and the same job starts again.
  Future<void> startAgain() async {
    final job = state.job;
    if (job == null) return;
    final done = state.jobSteps >= job.totalStepsFor(state.size);
    state = state.copyWith(finished: state.finished + (done ? 1 : 0), startedOn: _today, jobSteps: 0);
    await _save();
  }

  void _credit(int steps, {required bool byHand}) {
    if (steps <= 0) return;
    final day = _today;
    final map = Map<String, int>.from(byHand ? state.manual : state.counted);
    map[day] = (map[day] ?? 0) + steps;
    final at = _now().millisecondsSinceEpoch ~/ 1000;
    final times = Map<String, List<int>>.from(state.walkTimes);
    final was = times[day];
    times[day] = [was == null ? at : was[0], at];
    // Keep two weeks of times only.
    if (times.length > 14) {
      final keys = times.keys.toList()..sort();
      for (final k in keys.take(times.length - 14)) {
        times.remove(k);
      }
    }
    state = state.copyWith(walkTimes: times);
    state = byHand
        ? state.copyWith(manual: map, jobSteps: state.job == null ? null : state.jobSteps + steps)
        : state.copyWith(counted: map, jobSteps: state.job == null ? null : state.jobSteps + steps);
  }

  /// A new reading of the phone's step counter: the steps since the last
  /// reading count for today. Returns the steps added.
  Future<int> applyCounter(int reading) async {
    final delta = askodoxStepCounterDelta(state.lastCounter, reading);
    _credit(delta, byHand: false);
    state = state.copyWith(lastCounter: reading);
    await _save();
    return delta;
  }

  /// Steps counted while the screen was open (phones without a step counter).
  Future<void> addLiveSteps(int steps) async {
    _credit(steps, byHand: false);
    await _save();
  }

  /// Steps typed by hand (treadmill). Kept apart so they are labelled.
  Future<void> addManualSteps(int steps) async {
    if (steps <= 0 || steps > 60000) return;
    _credit(steps, byHand: true);
    await _save();
  }

  Future<void> addSevaMinutes(int minutes) async {
    if (minutes <= 0) return;
    final day = _today;
    final map = Map<String, int>.from(state.sevaMinutes);
    map[day] = (map[day] ?? 0) + minutes;
    state = state.copyWith(sevaMinutes: map);
    await _save();
  }
}

final askodoxWorkControllerProvider = StateNotifierProvider<AskodoxWorkController, AskodoxWorkState>(
    (ref) => AskodoxWorkController(ref.watch(askodoxWorkClockProvider)));

/// The last seven days (oldest first) with the steps of each day.
List<(String day, int steps)> askodoxWorkWeek(AskodoxWorkState state, DateTime today) {
  final out = <(String, int)>[];
  for (var i = 6; i >= 0; i--) {
    final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
    final key = askodoxWorkDayKey(d);
    out.add((key, state.stepsOn(key)));
  }
  return out;
}

/// The text a person shares (they choose where; ASKODOX never posts). Every
/// number is the phone's own count; hand-typed steps are said separately.
String askodoxWorkShareText(AskodoxWorkState state, DateTime today, bool te) {
  final job = state.job;
  final week = askodoxWorkWeek(state, today);
  final steps = week.fold<int>(0, (sum, d) => sum + d.$2);
  final goalDays = week.where((d) => d.$2 >= state.size.stepsPerDay).length;
  var manual = 0;
  for (final d in week) {
    manual += state.manual[d.$1] ?? 0;
  }
  final title = askodoxWorkLevel(state.finished, te);
  final progress = state.progress;
  final lines = <String>[
    te ? 'ASKODOX వర్క్ మోడ్' : 'ASKODOX Work Mode',
    if (job != null && progress != null)
      te
          ? '${job.te} · ${progress.stage.te} · రోజు ${progress.gameDay}/${job.gameDays}'
          : '${job.en} · ${progress.stage.en} · day ${progress.gameDay}/${job.gameDays}',
    te ? 'ఈ వారం: $steps అడుగులు · $goalDays రోజులు పూర్తి పని' : 'This week: $steps steps · $goalDays full work days',
    if (manual > 0) te ? '(చేతితో నమోదు: $manual అడుగులు)' : '($manual steps typed by hand)',
    te ? 'స్థాయి: $title' : 'Title: $title',
  ];
  return lines.join('\n');
}
