import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../native_video/video_commerce.dart' show askodoxShareTextProvider;
import '../../smart_tools/data/phone_meters.dart';
import '../../smart_tools/presentation/sensor_tools_screen.dart' show askodoxMotionSensorsProvider;
import '../data/work_mode_store.dart';
import '../domain/work_mode_plan.dart';
import 'work_scene.dart';

const _ink = Color(0xFF10204A);
const _green = Color(0xFF1F8A5B);
const _soft = Color(0xFFF6F5F0);

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String _n(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

IconData _jobIcon(String id) => switch (id) {
      'paddy' => Icons.grass_rounded,
      'chilli' => Icons.local_florist_rounded,
      'vegetables' => Icons.eco_rounded,
      'paper' => Icons.newspaper_rounded,
      'delivery' => Icons.local_shipping_rounded,
      'digging' => Icons.construction_rounded,
      'house' => Icons.home_work_rounded,
      'welding' => Icons.local_fire_department_rounded,
      'chicken_shop' => Icons.storefront_rounded,
      _ => Icons.work_rounded,
    };

/// Work Mode: walk, and the chosen job gets done step by step.
/// Opened from the game button beside ASKODOX in the header (`/work`).
class AskodoxWorkModeScreen extends ConsumerWidget {
  const AskodoxWorkModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(askodoxWorkControllerProvider);
    final Widget body;
    if (!state.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!state.introSeen) {
      body = _Intro(te: te, onStart: () => ref.read(askodoxWorkControllerProvider.notifier).seeIntro());
    } else if (state.job == null) {
      body = _JobPicker(te: te, onPick: (id) => ref.read(askodoxWorkControllerProvider.notifier).chooseJob(id));
    } else {
      body = _Today(te: te);
    }
    return Scaffold(
      key: const Key('askodoxWorkModeScreen'),
      backgroundColor: _soft,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(te ? 'వర్క్ మోడ్' : 'Work Mode', style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (state.loaded && state.introSeen)
            IconButton(
              key: const Key('askodoxWorkHowToPlay'),
              tooltip: te ? 'ఎలా ఆడాలి' : 'How to play',
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (sheet) => SafeArea(
                  child: _Intro(te: te, onStart: () => Navigator.of(sheet).pop()),
                ),
              ),
            ),
          if (state.job != null)
            IconButton(
              key: const Key('askodoxWorkChangeJob'),
              tooltip: te ? 'పని మార్చు' : 'Change job',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (sheet) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.of(sheet).size.height * 0.85,
                    child: _JobPicker(
                      te: te,
                      changing: true,
                      onPick: (id) {
                        Navigator.of(sheet).pop();
                        ref.read(askodoxWorkControllerProvider.notifier).chooseJob(id);
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: body,
    );
  }
}

// ------------------------------------------------------------------ intro

class _Intro extends StatelessWidget {
  const _Intro({required this.te, required this.onStart});
  final bool te;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final steps = te
        ? const [
            ('పని ఎంచుకోండి', 'పొలం, పేపర్ బాయ్, డెలివరీ, ఇల్లు కట్టడం... మీకు నచ్చిన పని. మీరు ఆడే ఆట చెబితే సరిపడే పని సూచిస్తాం.'),
            ('నడవండి', 'మీ ఫోన్ లెక్కించే ప్రతి అడుగుతో ఆ పని కొంచెం జరుగుతుంది. 7,000 అడుగులు = ఒక రోజు పూర్తి పని.'),
            ('పని ముందుకు', 'పని అసలు క్రమంలోనే జరుగుతుంది (నారు → నాట్లు → కోత). నిజ జీవితంలో కంటే సగం సమయంలో పూర్తవుతుంది.'),
            ('పంచుకోండి', 'వారం పని రికార్డును మీకు నచ్చిన చోట షేర్ చేయండి. ప్రతి సంఖ్య మీ నిజమైన అడుగుల నుంచే.'),
          ]
        : const [
            ('Pick a job', 'Paddy field, paper boy, delivery, house building... Tell us what you play and we suggest a fitting job.'),
            ('Walk', 'Every step your phone counts does a little of that job. 7,000 steps = one full work day.'),
            ('Watch it grow', 'The work follows the real order (nursery → transplant → harvest), in half the real time.'),
            ('Share', 'Share your week of work wherever you like. Every number comes from your real steps.'),
          ];
    return ListView(
      key: const Key('askodoxWorkIntro'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(18),
      children: [
        const AskodoxWorkSceneView(scene: AskodoxWorkScene.field, overall: 0.55, stageIndex: 3, stageCount: 6, height: 170),
        const SizedBox(height: 14),
        Text(te ? 'ఎలా ఆడాలి?' : 'How to play',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
        const SizedBox(height: 6),
        Text(
          te
              ? 'ఇక్కడ పాయింట్లు, బహుమతులు, డబ్బు ఏమీ లేవు. మీ నడకే పని — ప్రతి రోజు ఒక లక్ష్యం.'
              : 'There are no points, prizes or money here. Your walk is the work — one goal a day.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF5B6670)),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE3F4EA),
                child: Text('${i + 1}', style: const TextStyle(color: _green, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
                  const SizedBox(height: 2),
                  Text(steps[i].$2, style: const TextStyle(fontSize: 13, color: Color(0xFF5B6670))),
                ]),
              ),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF6E0), borderRadius: BorderRadius.circular(14)),
          child: Text(
            te
                ? 'నడుస్తున్నప్పుడు ఫోన్ జేబులో ఉంచండి; ఆగినప్పుడు మాత్రమే స్క్రీన్ చూడండి. ఆదివారం విశ్రాంతి రోజు. నొప్పి ఉంటే ఆపండి; ఆరోగ్య సమస్యలు ఉంటే డాక్టర్‌ని అడగండి.'
                : 'Keep the phone in your pocket while walking; look at the screen only when you stop. Sunday is a rest day. Stop if anything hurts; ask a doctor if you have a health condition.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B4A00)),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('askodoxWorkIntroStart'),
          style: FilledButton.styleFrom(
              backgroundColor: _ink, minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
          onPressed: onStart,
          child: Text(te ? 'మొదలు పెడదాం' : 'Let’s start', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- job picker

class _JobPicker extends StatefulWidget {
  const _JobPicker({required this.te, required this.onPick, this.changing = false});
  final bool te;
  final ValueChanged<String> onPick;
  final bool changing;

  @override
  State<_JobPicker> createState() => _JobPickerState();
}

class _JobPickerState extends State<_JobPicker> {
  String? _sport;

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final sport = askodoxSportMatches.where((s) => s.id == _sport).firstOrNull;
    final suggested = sport?.jobs.toSet() ?? const <String>{};
    return ListView(
      key: const Key('askodoxWorkJobPicker'),
      padding: const EdgeInsets.all(18),
      children: [
        Text(te ? 'ఏ పని చేద్దాం?' : 'Which job today?',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
        if (widget.changing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              te ? 'పని మార్చితే కొత్త పని మొదటి నుంచి మొదలవుతుంది.' : 'A new job starts from the beginning.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A00)),
            ),
          ),
        const SizedBox(height: 12),
        Text(te ? 'మీరు ఏ ఆట / వ్యాయామం చేస్తారు?' : 'What do you already play or do?',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF5B6670))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in askodoxSportMatches)
            ChoiceChip(
              key: ValueKey('askodoxWorkSport-${s.id}'),
              label: Text(s.name(te)),
              selected: _sport == s.id,
              onSelected: (on) => setState(() => _sport = on ? s.id : null),
            ),
        ]),
        if (sport != null)
          Container(
            key: const Key('askodoxWorkSportHint'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(14)),
            child: Text(sport.how(te), style: const TextStyle(fontSize: 13, color: Color(0xFF17603D))),
          ),
        const SizedBox(height: 16),
        for (final job in askodoxWorkJobs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: ValueKey('askodoxWorkJob-${job.id}'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onPick(job.id),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: suggested.contains(job.id) ? _green : const Color(0xFFECEDE7), width: 2),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFFF0F1EC),
                      child: Icon(_jobIcon(job.id), color: _ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(job.name(te),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
                          ),
                          if (suggested.contains(job.id))
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(99)),
                              child: Text(te ? 'మీకు సరిపోతుంది' : 'Fits you',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _green)),
                            ),
                        ]),
                        const SizedBox(height: 2),
                        Text(job.walk(te), style: const TextStyle(fontSize: 12, color: Color(0xFF5B6670))),
                        const SizedBox(height: 2),
                        Text(
                          te
                              ? 'నిజంగా ${job.realDays} రోజులు → ఇక్కడ ${job.gameDays} రోజులు'
                              : '${job.realDays} days in real life → ${job.gameDays} days here',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _green),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          te
              ? 'ఇక్కడి సమయం ఆట కోసం మాత్రమే — నిజ పనికి పట్టే కాలం వేరు.'
              : 'Times here are for the game — real work takes longer.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF7A838C)),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- today

class _Today extends ConsumerStatefulWidget {
  const _Today({required this.te});
  final bool te;

  @override
  ConsumerState<_Today> createState() => _TodayState();
}

class _TodayState extends ConsumerState<_Today> {
  String? _problem;
  bool _reading = false;
  bool _live = false;
  StreamSubscription<Object?>? _sensor;
  AskodoxStepDetector? _detector;
  int _livePending = 0;
  Timer? _flush;
  late final AskodoxWorkController _work;

  @override
  void initState() {
    super.initState();
    _work = ref.read(askodoxWorkControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _readCounter());
  }

  @override
  void dispose() {
    _stopLive();
    super.dispose();
  }

  Future<void> _readCounter() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final reading = await ref.read(askodoxStepSourceProvider).counter();
      await ref.read(askodoxWorkControllerProvider.notifier).applyCounter(reading);
      if (mounted) setState(() => _problem = null);
    } on AskodoxMeterException catch (e) {
      if (mounted) setState(() => _problem = e.code);
    } catch (_) {
      if (mounted) setState(() => _problem = 'no_reading');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _startLive() {
    _detector = AskodoxStepDetector();
    _sensor = ref.read(askodoxMotionSensorsProvider).accelerometer().listen((v) {
      if (_detector?.add(v.length, DateTime.now()) ?? false) _livePending++;
    });
    _flush = Timer.periodic(const Duration(seconds: 5), (_) => _flushLive());
    setState(() => _live = true);
  }

  void _flushLive() {
    final n = _livePending;
    _livePending = 0;
    if (n > 0) unawaited(_work.addLiveSteps(n));
  }

  void _stopLive() {
    _sensor?.cancel();
    _sensor = null;
    _flush?.cancel();
    _flush = null;
    final n = _livePending;
    _livePending = 0;
    if (n > 0) unawaited(_work.addLiveSteps(n));
  }

  Future<void> _typeSteps() async {
    final te = widget.te;
    final controller = TextEditingController();
    final steps = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(te ? 'చేతితో అడుగులు నమోదు' : 'Add steps by hand'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            te
                ? 'ట్రెడ్‌మిల్ లాంటి వాటికి. ఇవి "చేతితో నమోదు" అని విడిగా చూపిస్తాం.'
                : 'For a treadmill and similar. They are shown separately as typed by hand.',
            style: const TextStyle(fontSize: 13),
          ),
          TextField(
            key: const Key('askodoxWorkManualField'),
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: te ? 'ఉదా. 3000' : 'e.g. 3000'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
            key: const Key('askodoxWorkManualSave'),
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: Text(te ? 'జోడించు' : 'Add'),
          ),
        ],
      ),
    );
    if (steps != null && steps > 0) {
      await ref.read(askodoxWorkControllerProvider.notifier).addManualSteps(steps);
    }
  }

  String _problemText(String code, bool te) => switch (code) {
        'permission_requested' => te
            ? 'అడుగులు లెక్కించడానికి "శారీరక కార్యకలాపం" అనుమతి అడిగాం. అనుమతించి మళ్ళీ నొక్కండి.'
            : 'We asked for the "Physical activity" permission. Allow it, then tap again.',
        'no_sensor' => te
            ? 'ఈ ఫోన్‌లో స్టెప్ కౌంటర్ లేదు. స్క్రీన్ తెరిచి ఉంచి "లైవ్ లెక్క" వాడండి, లేదా చేతితో నమోదు చేయండి.'
            : 'This phone has no step counter. Use "Live count" with the screen open, or add steps by hand.',
        'unsupported' => te
            ? 'ఈ యాప్ వెర్షన్ అడుగులు చదవలేదు — యాప్ అప్‌డేట్ చేయండి. అప్పటివరకు "లైవ్ లెక్క" వాడండి.'
            : 'This app version cannot read steps — please update. Until then use "Live count".',
        _ => te ? 'అడుగులు ఇప్పుడు చదవలేకపోయాం. మళ్ళీ ప్రయత్నించండి.' : 'Could not read steps now. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final state = ref.watch(askodoxWorkControllerProvider);
    final job = state.job!;
    final now = ref.watch(askodoxWorkClockProvider)();
    final today = askodoxWorkDayKey(now);
    final progress = askodoxWorkProgress(job, state.jobSteps);
    final started = DateTime.tryParse(state.startedOn ?? '') ?? now;
    final goal = askodoxWorkDailyGoal(started, now);
    final todaySteps = state.stepsOn(today);
    final manualToday = state.manual[today] ?? 0;
    final week = askodoxWorkWeek(state, now);
    final maxDay = week.fold<int>(askodoxWorkStepsPerDay, (m, d) => d.$2 > m ? d.$2 : m);
    final title = askodoxWorkLevel(state.finished, te);

    return ListView(
      key: const Key('askodoxWorkToday'),
      padding: const EdgeInsets.all(16),
      children: [
        AskodoxWorkSceneView(
          scene: job.scene,
          overall: progress.overall,
          stageIndex: progress.stageIndex,
          stageCount: job.stages.length,
          moving: !progress.done,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Icon(_jobIcon(job.id), color: _ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(job.name(te), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(99)),
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _green)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          key: const Key('askodoxWorkStage'),
          te
              ? 'దశ ${progress.stageIndex + 1}/${job.stages.length}: ${progress.stage.te} · రోజు ${progress.gameDay}/${job.gameDays}'
              : 'Stage ${progress.stageIndex + 1}/${job.stages.length}: ${progress.stage.en} · day ${progress.gameDay}/${job.gameDays}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF5B6670)),
        ),
        const SizedBox(height: 12),
        if (progress.done)
          _Card(
            key: const Key('askodoxWorkDone'),
            color: const Color(0xFFE3F4EA),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(te ? 'పని పూర్తయింది!' : 'Job finished!',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _green)),
              const SizedBox(height: 4),
              Text(
                te
                    ? '${job.te} మొత్తం ${job.gameDays} రోజుల పని మీ నడకతో పూర్తి చేశారు.'
                    : 'You walked all ${job.gameDays} days of the ${job.en} job.',
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('askodoxWorkStartAgain'),
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: () => ref.read(askodoxWorkControllerProvider.notifier).startAgain(),
                child: Text(te ? 'మళ్ళీ మొదలు (కొత్త స్థాయి)' : 'Start again (next title)'),
              ),
            ]),
          ),
        _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(te ? 'ఈ రోజు' : 'Today',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5B6670))),
              ),
              if (now.weekday == DateTime.sunday)
                Text(te ? 'విశ్రాంతి రోజు' : 'Rest day',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
            ]),
            const SizedBox(height: 2),
            Text(
              key: const Key('askodoxWorkTodaySteps'),
              te ? '${_n(todaySteps)} / ${_n(goal)} అడుగులు' : '${_n(todaySteps)} / ${_n(goal)} steps',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _ink),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal == 0 ? 0.0 : (todaySteps / goal).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: const Color(0xFFECEDE7),
                color: _green,
              ),
            ),
            if (todaySteps >= goal)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(te ? 'ఈ రోజు లక్ష్యం పూర్తి!' : 'Today’s goal done!',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _green)),
              ),
            if (manualToday > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(te ? 'చేతితో నమోదు: ${_n(manualToday)}' : 'Typed by hand: ${_n(manualToday)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A838C))),
              ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(key: const Key('askodoxWorkStepProblem'), _problemText(_problem!, te),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A00))),
              ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                key: const Key('askodoxWorkRefresh'),
                onPressed: _reading ? null : _readCounter,
                icon: const Icon(Icons.directions_walk_rounded, size: 18),
                label: Text(te ? 'అడుగులు లెక్కించు' : 'Count my steps'),
              ),
              OutlinedButton.icon(
                key: const Key('askodoxWorkLive'),
                onPressed: () {
                  if (_live) {
                    _stopLive();
                    setState(() => _live = false);
                  } else {
                    _startLive();
                  }
                },
                icon: Icon(_live ? Icons.stop_circle_outlined : Icons.sensors_rounded, size: 18),
                label: Text(_live ? (te ? 'లైవ్ ఆపు' : 'Stop live') : (te ? 'లైవ్ లెక్క' : 'Live count')),
              ),
              OutlinedButton.icon(
                key: const Key('askodoxWorkManual'),
                onPressed: _typeSteps,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(te ? 'చేతితో నమోదు' : 'Add by hand'),
              ),
            ]),
          ]),
        ),
        _Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(te ? 'ఈ దశ' : 'This stage',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5B6670))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.stageFraction,
                minHeight: 8,
                backgroundColor: const Color(0xFFECEDE7),
                color: const Color(0xFFE8A317),
              ),
            ),
            const SizedBox(height: 6),
            if (!progress.done)
              Text(
                te
                    ? 'తర్వాతి దశకు ఇంకా ${_n(progress.stepsLeftInStage)} అడుగులు'
                    : '${_n(progress.stepsLeftInStage)} steps to the next stage',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink),
              ),
            const SizedBox(height: 10),
            Row(children: [
              for (var i = 0; i < job.stages.length; i++)
                Expanded(
                  child: Container(
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i < progress.stageIndex || progress.done
                          ? _green
                          : i == progress.stageIndex
                              ? const Color(0xFFE8A317)
                              : const Color(0xFFE3E6DD),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        _Card(
          key: const Key('askodoxWorkTip'),
          color: _ink,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(te ? 'మెలకువ · ${progress.stage.te}' : 'Tip · ${progress.stage.en}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFF5C95C))),
            const SizedBox(height: 4),
            Text(progress.stage.tip(te),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, height: 1.35)),
            const SizedBox(height: 6),
            Text(
              te ? 'ఇవి సాధారణ సూచనలు మాత్రమే.' : 'General tips only.',
              style: const TextStyle(fontSize: 11, color: Color(0xFFC9CDC4)),
            ),
          ]),
        ),
        _Card(
          key: const Key('askodoxWorkWeek'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(te ? 'ఈ వారం' : 'This week',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5B6670))),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final d in week)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: 70 * (d.$2 / maxDay).clamp(0.03, 1.0),
                          decoration: BoxDecoration(
                            color: d.$2 >= askodoxWorkStepsPerDay ? _green : const Color(0xFFB8C2BC),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(d.$1.substring(8), style: const TextStyle(fontSize: 10, color: Color(0xFF7A838C))),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('askodoxWorkShare'),
              onPressed: () => ref.read(askodoxShareTextProvider)(askodoxWorkShareText(state, now, te),
                  subject: te ? 'నా వర్క్ మోడ్ వారం' : 'My Work Mode week'),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: Text(te ? 'షేర్ చేయండి' : 'Share'),
            ),
          ]),
        ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            key: const Key('askodoxWorkSevaEntry'),
            leading: const Icon(Icons.self_improvement_rounded, color: _ink),
            title: Text(te ? 'సేవ / ధ్యానం (ఐచ్ఛికం)' : 'Seva / meditation (optional)',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(te ? 'నడక విరామంలో 15 / 30 / 60 నిమిషాలు' : '15 / 30 / 60 minutes in a walking break'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/work/seva'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color = Colors.white, super.key});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

// -------------------------------------------------------------------- seva

/// Optional seva / meditation in a walking break. Only the minutes are kept
/// (on the phone); which practice was chosen is never stored or sent.
/// Tradition-specific prayers come only after review by that tradition's
/// scholars -- until then they are listed as coming, never invented here.
class AskodoxSevaScreen extends ConsumerStatefulWidget {
  const AskodoxSevaScreen({super.key});

  @override
  ConsumerState<AskodoxSevaScreen> createState() => _AskodoxSevaScreenState();
}

class _AskodoxSevaScreenState extends ConsumerState<AskodoxSevaScreen> {
  String _practice = 'shanti';
  int _minutes = 15;
  Timer? _timer;
  int _elapsed = 0;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
      if (_elapsed >= _minutes * 60) _finish();
    });
    setState(() => _running = true);
  }

  Future<void> _finish() async {
    _timer?.cancel();
    final minutes = _elapsed ~/ 60;
    setState(() {
      _running = false;
      _elapsed = 0;
    });
    if (minutes > 0) await ref.read(askodoxWorkControllerProvider.notifier).addSevaMinutes(minutes);
    if (!mounted) return;
    final te = _te(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(minutes > 0
            ? (te ? '$minutes నిమిషాల సేవ పూర్తి.' : '$minutes minutes done.')
            : (te ? 'ఒక నిమిషం కంటే తక్కువ — నమోదు కాలేదు.' : 'Less than a minute — not recorded.'))));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final state = ref.watch(askodoxWorkControllerProvider);
    final today = askodoxWorkDayKey(ref.watch(askodoxWorkClockProvider)());
    final practices = <(String, String, bool)>[
      ('shanti', te ? 'శాంతి ధ్యానం (ఏ నమ్మకం లేకుండా)' : 'Peace meditation (no religion needed)', true),
      ('own', te ? 'నా స్వంత ప్రార్థన' : 'My own prayer', true),
      ('hindu', te ? 'హిందూ సేవ' : 'Hindu seva', false),
      ('christian', te ? 'క్రైస్తవ ప్రార్థన' : 'Christian prayer', false),
      ('islamic', te ? 'ఇస్లామిక్ దువా' : 'Islamic dua', false),
    ];
    final left = _minutes * 60 - _elapsed;
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');
    final guide = _practice == 'shanti'
        ? (te
            ? 'నెమ్మదిగా శ్వాస తీసుకోండి... నాలుగు లెక్కపెట్టి వదలండి. మనసు వేరే వైపు వెళ్తే మెల్లగా శ్వాస మీదకు తీసుకురండి.'
            : 'Breathe in slowly... out for a count of four. If the mind wanders, gently come back to the breath.')
        : (te ? 'మీ మాటల్లో, మీ పద్ధతిలో ప్రార్థించండి. సమయం మేము చూసుకుంటాం.' : 'Pray in your own words and way. We keep the time.');
    return Scaffold(
      key: const Key('askodoxSevaScreen'),
      backgroundColor: _soft,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(te ? 'సేవ / ధ్యానం' : 'Seva / meditation', style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          te
              ? 'ఎంపిక మీదే, చేయకపోయినా ఏమీ కాదు. మీరు ఏది ఎంచుకున్నారో ఎక్కడా నిల్వ చేయము — నిమిషాలు మాత్రమే మీ ఫోన్‌లో ఉంటాయి.'
              : 'Entirely your choice; skipping is fine. What you choose is never stored — only the minutes stay on your phone.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF5B6670)),
        ),
        const SizedBox(height: 12),
        for (final p in practices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                key: ValueKey('askodoxSevaPractice-${p.$1}'),
                enabled: p.$3 && !_running,
                title: Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: p.$3
                    ? null
                    : Text(te
                        ? 'త్వరలో — ఆ సంప్రదాయ పండితుల సమీక్ష తర్వాత'
                        : 'Coming — after review by scholars of that tradition'),
                trailing: p.$3
                    ? Icon(_practice == p.$1 ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _practice == p.$1 ? _green : const Color(0xFFB8C2BC))
                    : const Icon(Icons.lock_clock_rounded, color: Color(0xFFB8C2BC)),
                onTap: p.$3 ? () => setState(() => _practice = p.$1) : null,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final m in const [15, 30, 60])
            ChoiceChip(
              key: ValueKey('askodoxSevaMinutes-$m'),
              label: Text(te ? '$m నిమిషాలు' : '$m min'),
              selected: _minutes == m,
              onSelected: _running ? null : (_) => setState(() => _minutes = m),
            ),
        ]),
        const SizedBox(height: 16),
        _Card(
          color: _ink,
          child: Column(children: [
            Text(key: const Key('askodoxSevaTimer'), '$mm:$ss',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 8),
            Text(guide,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4)),
          ]),
        ),
        Row(children: [
          Expanded(
            child: FilledButton(
              key: const Key('askodoxSevaStart'),
              style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(50)),
              onPressed: _toggle,
              child: Text(_running ? (te ? 'ఆపు' : 'Pause') : (te ? 'మొదలు' : 'Start')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              key: const Key('askodoxSevaFinish'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _elapsed > 0 ? _finish : null,
              child: Text(te ? 'పూర్తి' : 'Finish'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          te
              ? 'ఈ రోజు సేవ: ${state.sevaMinutes[today] ?? 0} నిమిషాలు'
              : 'Today: ${state.sevaMinutes[today] ?? 0} minutes',
          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
        ),
      ]),
    );
  }
}
