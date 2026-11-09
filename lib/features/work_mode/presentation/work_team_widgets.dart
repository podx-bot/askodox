import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/share/askodox_image_share.dart';
import '../../native_video/video_commerce.dart' show askodoxShareTextProvider;
import '../data/work_team_repository.dart';
import '../domain/work_mode_plan.dart';
import 'work_scene.dart';

const _ink = Color(0xFF10204A);
const _green = Color(0xFF1F8A5B);
const _muted = Color(0xFF5B6670);

/// Where a new person gets the app (shared with every invite and result).
const askodoxAppDownloadLink = 'https://askodox.com/app/';

String _wearLabel(String wear, bool te) => switch (wear) {
      'saree' => te ? 'చీర' : 'Saree',
      'shirt' => te ? 'చొక్కా' : 'Shirt',
      _ => te ? 'లుంగీ' : 'Lungi',
    };

String askodoxWorkTeamProblemText(String code, bool te) => switch (code) {
      'signin' => te ? 'కలిసి ఆడాలంటే ముందు సైన్ ఇన్ చేయండి.' : 'Sign in first to play together.',
      'CODE_NOT_FOUND' => te ? 'ఈ code తో టీమ్ లేదు. మళ్లీ చూసి వేయండి.' : 'No team has this code. Check it and try again.',
      'TEAM_FULL' => te ? 'ఈ టీమ్ నిండిపోయింది (4 మంది).' : 'This team is full (4 people).',
      'ALREADY_IN_TEAM' =>
        te ? 'మీరు ఇప్పటికే ఒక టీమ్‌లో ఉన్నారు. ముందు అందులోంచి బయటకు రండి.' : 'You are already in a team. Leave it first.',
      'rate' => te ? 'కొంచెం ఆగి మళ్లీ ప్రయత్నించండి.' : 'Please wait a moment and try again.',
      _ => te ? 'ఇప్పుడు టీమ్ అందుబాటులో లేదు. నెట్ చూసి మళ్లీ ప్రయత్నించండి.' : 'The team is not reachable now. Check the network and try again.',
    };

/// The invite a person sends: the code, how to use it, and where to get the app.
String askodoxWorkInviteText(AskodoxWorkTeam team, bool te) {
  final job = askodoxWorkJob(team.job);
  final jobName = job == null ? team.job : (te ? job.te : job.en);
  return te
      ? 'నాతో కలిసి ASKODOX వర్క్ మోడ్‌లో "$jobName" పని చేయండి! మన అడుగులతోనే పని జరుగుతుంది.\n'
          'యాప్‌లో 🎮 → టీమ్ → "Code తో చేరండి" లో ఈ code వేయండి: ${team.code}\n'
          'యాప్: $askodoxAppDownloadLink'
      : 'Do the "$jobName" job with me in ASKODOX Work Mode! Our steps do the work.\n'
          'In the app: 🎮 → Team → "Join with a code", enter: ${team.code}\n'
          'Get the app: $askodoxAppDownloadLink';
}

/// The scene's crew from the team (you first follow this phone's walking).
List<AskodoxWorkCrewMember>? askodoxWorkCrewOf(AskodoxWorkTeam? team, {required bool meWalking}) {
  if (team == null || team.members.length < 2) return null;
  final ordered = [...team.members.where((m) => m.me), ...team.members.where((m) => !m.me)];
  return [
    for (final m in ordered) AskodoxWorkCrewMember(name: m.name, active: m.me ? meWalking : m.active, wear: m.wear),
  ];
}

class _TeamForm {
  const _TeamForm(this.name, this.wear, [this.code = '']);
  final String name, wear, code;
}

/// Team card on the Work Mode day screen: make a team, join with a code,
/// invite, see who did how much today, leave.
class AskodoxWorkTeamCard extends ConsumerStatefulWidget {
  const AskodoxWorkTeamCard({
    super.key,
    required this.te,
    required this.job,
    required this.sizeId,
    required this.stepsPerUnit,
    required this.onTeamJob,
  });

  final bool te;
  final AskodoxWorkJob job;
  final String sizeId;
  final double stepsPerUnit;

  /// A joined team works on another job: switch to it.
  final Future<void> Function(String job, String size) onTeamJob;

  @override
  ConsumerState<AskodoxWorkTeamCard> createState() => _AskodoxWorkTeamCardState();
}

class _AskodoxWorkTeamCardState extends ConsumerState<AskodoxWorkTeamCard> {
  bool _busy = false;
  String? _problem;

  Future<_TeamForm?> _ask({required bool join}) {
    final te = widget.te;
    final name = TextEditingController();
    final code = TextEditingController();
    var wear = 'lungi';
    return showDialog<_TeamForm>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(join ? (te ? 'Code తో చేరండి' : 'Join with a code') : (te ? 'టీమ్ పెట్టండి' : 'Make a team')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (join)
                TextField(
                  key: const Key('askodoxWorkTeamCodeField'),
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  decoration: InputDecoration(labelText: 'Invite code', hintText: 'ABC234'),
                ),
              TextField(
                key: const Key('askodoxWorkTeamNameField'),
                controller: name,
                maxLength: 20,
                decoration: InputDecoration(
                    labelText: te ? 'టీమ్‌లో మీ పేరు' : 'Your name in the team', hintText: te ? 'ఉదా. నాన్న' : 'e.g. Dad'),
              ),
              Text(te ? 'మీ పనివాడి బట్టలు' : 'Your worker wears', style: const TextStyle(fontSize: 13, color: _muted)),
              Wrap(spacing: 8, children: [
                for (final w in const ['lungi', 'saree', 'shirt'])
                  ChoiceChip(
                    key: ValueKey('askodoxWorkTeamWear-$w'),
                    label: Text(_wearLabel(w, te)),
                    selected: wear == w,
                    onSelected: (_) => setLocal(() => wear = w),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(
                te
                    ? 'టీమ్‌లో అందరికీ మీ పేరు, ఈ రోజు అడుగుల మొత్తం మాత్రమే కనిపిస్తాయి. ఫోన్ నంబర్, location ఎవరికీ కనిపించవు.'
                        '${join ? ' చేరితే మీ పని టీమ్ పనికి మారుతుంది.' : ''}'
                    : 'The team sees only your name and today\'s step total. No number or location is shared.'
                        '${join ? ' Joining switches your job to the team\'s job.' : ''}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(
              key: const Key('askodoxWorkTeamFormSave'),
              onPressed: () {
                if (name.text.trim().isEmpty || (join && code.text.trim().length < 4)) return;
                Navigator.of(context).pop(_TeamForm(name.text.trim(), wear, code.text.trim()));
              },
              child: Text(join ? (te ? 'చేరండి' : 'Join') : (te ? 'పెట్టండి' : 'Make')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    final problem = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  Future<void> _create() async {
    final form = await _ask(join: false);
    if (form == null) return;
    await _run(() => ref
        .read(askodoxWorkTeamProvider.notifier)
        .create(name: form.name, job: widget.job.id, size: widget.sizeId, wear: form.wear));
  }

  Future<void> _join() async {
    final form = await _ask(join: true);
    if (form == null) return;
    await _run(() async {
      final problem =
          await ref.read(askodoxWorkTeamProvider.notifier).join(code: form.code, name: form.name, wear: form.wear);
      final team = ref.read(askodoxWorkTeamProvider).team;
      if (problem == null && team != null && team.job != widget.job.id && askodoxWorkJob(team.job) != null) {
        await widget.onTeamJob(team.job, team.size);
      }
      return problem;
    });
  }

  Future<void> _leave() async {
    final te = widget.te;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(te ? 'టీమ్ నుంచి బయటకు రావాలా? మీ పని మీ దగ్గరే ఉంటుంది.' : 'Leave the team? Your own work stays with you.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxWorkTeamLeaveConfirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(te ? 'బయటకు' : 'Leave')),
        ],
      ),
    );
    if (sure == true) await ref.read(askodoxWorkTeamProvider.notifier).leave();
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final teamState = ref.watch(askodoxWorkTeamProvider);
    final signedIn = ref.watch(workTeamRepositoryProvider).signedIn;
    final team = teamState.team;
    final unit = widget.job.unit(te);
    final children = <Widget>[
      Row(children: [
        const Icon(Icons.groups_rounded, color: _green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            team == null ? (te ? 'కలిసి పని చేయండి' : 'Work together') : '${te ? 'టీమ్' : 'Team'}: ${team.name}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _ink),
          ),
        ),
        if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 6),
    ];
    if (!signedIn) {
      children.addAll([
        Text(
          te
              ? 'ఇంట్లోవాళ్ళు, స్నేహితులతో (4 మంది వరకు) ఒకే పని చేయండి — ఎవరి అడుగులు వాళ్ళ పనివాడిని నడుపుతాయి.'
              : 'Do one job with family or friends (up to 4) — each person\'s steps move their own worker.',
          style: const TextStyle(fontSize: 13, color: _muted),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('askodoxWorkTeamSignIn'),
          onPressed: () => context.push('/onboarding?signin=1'),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(te ? 'సైన్ ఇన్ చేసి మొదలుపెట్టండి' : 'Sign in to start'),
        ),
      ]);
    } else if (team == null) {
      children.addAll([
        Text(
          te
              ? 'టీమ్ పెట్టి code ని ఇంట్లోవాళ్ళకు, స్నేహితులకు పంపండి. ఎవరి అడుగులు వాళ్ళ పనివాడిని నడుపుతాయి; ఎవరు ఎంత చేశారో ఇక్కడ కనిపిస్తుంది.'
              : 'Make a team and send the code to family or friends. Each person\'s steps move their own worker; here you see who did how much.',
          style: const TextStyle(fontSize: 13, color: _muted),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            key: const Key('askodoxWorkTeamCreate'),
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.group_add_rounded, size: 18),
            label: Text(te ? 'టీమ్ పెట్టండి' : 'Make a team'),
          ),
          OutlinedButton.icon(
            key: const Key('askodoxWorkTeamJoin'),
            onPressed: _busy ? null : _join,
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: Text(te ? 'Code తో చేరండి' : 'Join with a code'),
          ),
        ]),
      ]);
    } else {
      final maxSteps = team.members.fold<int>(1, (m, x) => x.steps > m ? x.steps : m);
      final teamJob = askodoxWorkJob(team.job);
      children.addAll([
        Row(children: [
          Expanded(
            child: Text(
              key: const Key('askodoxWorkTeamCode'),
              'Code: ${team.code} · ${team.members.length}/${team.maxMembers}'
              '${teamJob == null ? '' : ' · ${te ? teamJob.te : teamJob.en}'}',
              style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, letterSpacing: 0.5),
            ),
          ),
          if (team.members.length < team.maxMembers)
            FilledButton.icon(
              key: const Key('askodoxWorkTeamInvite'),
              style: FilledButton.styleFrom(backgroundColor: _green, visualDensity: VisualDensity.compact),
              onPressed: () => ref.read(askodoxShareTextProvider)(askodoxWorkInviteText(team, te),
                  subject: te ? 'ASKODOX వర్క్ మోడ్ ఆహ్వానం' : 'ASKODOX Work Mode invite'),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(te ? 'ఆహ్వానించండి' : 'Invite'),
            ),
        ]),
        const SizedBox(height: 8),
        for (final m in team.members)
          Padding(
            key: ValueKey('askodoxWorkTeamMember-${m.member}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.circle, size: 9, color: m.active ? _green : const Color(0xFFB0BEC5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${m.name}${m.me ? (te ? ' (మీరు)' : ' (you)') : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                ),
                Text(
                  te
                      ? '${_fmt(m.steps)} అడుగులు · ${(m.steps / widget.stepsPerUnit).floor()} $unit'
                      : '${_fmt(m.steps)} steps · ${(m.steps / widget.stepsPerUnit).floor()} $unit',
                  style: const TextStyle(fontSize: 12.5, color: _muted, fontFeatures: [ui.FontFeature.tabularFigures()]),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: m.steps / maxSteps,
                  minHeight: 7,
                  backgroundColor: const Color(0xFFE3F4EA),
                  color: m.me ? _green : const Color(0xFF3F6E9E),
                ),
              ),
            ]),
          ),
        if (team.members.length < 2)
          Text(
            te ? 'ఇంకా ఎవరూ చేరలేదు — "ఆహ్వానించండి" నొక్కి code పంపండి.' : 'Nobody has joined yet — tap "Invite" to send the code.',
            style: const TextStyle(fontSize: 12.5, color: _muted),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('askodoxWorkTeamLeave'),
            onPressed: _leave,
            child: Text(te ? 'టీమ్ నుంచి బయటకు' : 'Leave the team'),
          ),
        ),
      ]);
    }
    final problem = _problem ?? (teamState.problem == 'signin' ? null : teamState.problem);
    if (problem != null && signedIn) {
      children.add(Text(
        key: const Key('askodoxWorkTeamProblem'),
        askodoxWorkTeamProblemText(problem, te),
        style: const TextStyle(fontSize: 12.5, color: Color(0xFFC62828), fontWeight: FontWeight.w700),
      ));
    }
    return Container(
      key: const Key('askodoxWorkTeam'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

String _fmt(int n) {
  final s = '$n';
  if (s.length <= 3) return s;
  final head = s.substring(0, s.length - 3);
  final groups = <String>[];
  for (var i = head.length; i > 0; i -= 2) {
    groups.insert(0, head.substring(i - 2 < 0 ? 0 : i - 2, i));
  }
  return '${groups.join(',')},${s.substring(s.length - 3)}';
}

/// "Today's result": the day's steps, the work they did, and the team's share
/// -- drawn as a card that can be shared as a picture with the app link.
class AskodoxWorkResultCard extends ConsumerStatefulWidget {
  const AskodoxWorkResultCard({
    super.key,
    required this.te,
    required this.job,
    required this.stageIndex,
    required this.stageFraction,
    required this.todaySteps,
    required this.stepsPerUnit,
    required this.now,
    this.crew,
  });

  final bool te;
  final AskodoxWorkJob job;
  final int stageIndex;
  final double stageFraction;
  final int todaySteps;
  final double stepsPerUnit;
  final DateTime now;
  final List<AskodoxWorkCrewMember>? crew;

  @override
  ConsumerState<AskodoxWorkResultCard> createState() => _AskodoxWorkResultCardState();
}

class _AskodoxWorkResultCardState extends ConsumerState<AskodoxWorkResultCard> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  String _caption(int units) {
    final te = widget.te;
    final job = te ? widget.job.te : widget.job.en;
    return te
        ? 'ఈ రోజు నా అడుగులతో ASKODOX వర్క్ మోడ్‌లో "$job": ${_fmt(widget.todaySteps)} అడుగులు = $units ${widget.job.unit(te)} పని!\n'
            'మీరూ ఆడండి: $askodoxAppDownloadLink'
        : 'Today my steps did "$job" in ASKODOX Work Mode: ${_fmt(widget.todaySteps)} steps = $units ${widget.job.unit(te)}!\n'
            'Play too: $askodoxAppDownloadLink';
  }

  Future<void> _share(int units) async {
    setState(() => _sharing = true);
    var shared = false;
    try {
      final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 2.5);
      final data = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        shared = await askodoxShareImage(data.buffer.asUint8List(), name: 'askodox-work-result', text: _caption(units));
      }
    } catch (_) {
      shared = false;
    }
    if (!shared) await ref.read(askodoxShareTextProvider)(_caption(units), subject: 'ASKODOX');
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final evening = widget.now.hour >= 18;
    final units = (widget.todaySteps / widget.stepsPerUnit).floor();
    final stage = widget.job.stages[widget.stageIndex];
    final d = widget.now;
    final date = '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    final crew = widget.crew;
    return Column(
      key: const Key('askodoxWorkResult'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        RepaintBoundary(
          key: _boundary,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F3D2E), Color(0xFF1F8A5B)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    evening ? (te ? 'ఈ రోజు ఫలితం' : 'Today\'s result') : (te ? 'ఈ రోజు ఇప్పటి వరకు' : 'Today so far'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(date, style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AskodoxWorkSceneView(
                  job: widget.job,
                  stageIndex: widget.stageIndex,
                  stageFraction: widget.stageFraction,
                  active: widget.todaySteps > 0,
                  height: 150,
                  te: te,
                  crew: crew,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                key: const Key('askodoxWorkResultUnits'),
                '$units ${widget.job.unit(te)}',
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
              ),
              Text(
                te
                    ? '${_fmt(widget.todaySteps)} అడుగులతో · ${widget.job.te} · ${stage.te}'
                    : '${_fmt(widget.todaySteps)} steps · ${widget.job.en} · ${stage.en}',
                style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              if (crew != null) ...[
                const SizedBox(height: 8),
                Text(te ? 'టీమ్' : 'Team', style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                ..._teamLines(te),
              ],
              const SizedBox(height: 10),
              const Row(children: [
                Icon(Icons.sports_esports_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text('ASKODOX · askodox.com/app',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('askodoxWorkResultShare'),
          style: FilledButton.styleFrom(backgroundColor: _ink, minimumSize: const Size.fromHeight(46)),
          onPressed: _sharing || widget.todaySteps == 0 ? null : () => _share(units),
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: Text(te ? 'ఫలితం షేర్ చేయండి' : 'Share the result'),
        ),
      ],
    );
  }

  List<Widget> _teamLines(bool te) {
    final team = ref.watch(askodoxWorkTeamProvider).team;
    if (team == null) return const [];
    return [
      for (final m in team.members)
        Text(
          te
              ? '${m.name}: ${_fmt(m.steps)} అడుగులు · ${(m.steps / widget.stepsPerUnit).floor()} ${widget.job.unit(te)}'
              : '${m.name}: ${_fmt(m.steps)} steps · ${(m.steps / widget.stepsPerUnit).floor()} ${widget.job.unit(te)}',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
    ];
  }
}
