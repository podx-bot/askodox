import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../business/presentation/biz_staff.dart' show askodoxAttTodayProvider;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, work pages batch 3): Today's attendance `/biz/:id/staff/today` and Salary
/// `/biz/:id/staff/salary`. One number on top, one list in the middle, ONE big button at the bottom; the old pages stay
/// at `?full=1` (header ⋮). The Tasks page already gives a task with one tap (chips + staff photos), so it is not rebuilt.

String _todayDate() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

String _clockOf(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')}${t.hour < 12 ? ' AM' : ' PM'}';
}

// ============================================================================ today's attendance
class AskodoxAttendanceStepsScreen extends ConsumerStatefulWidget {
  const AskodoxAttendanceStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxAttendanceStepsScreen> createState() => _AttendanceStepsState();
}

class _AttendanceStepsState extends ConsumerState<AskodoxAttendanceStepsScreen> {
  bool get _te => askodoxPosTe(context);

  Future<void> _mark(String person, String status, {int otMin = 0}) async {
    try {
      await ref.read(askodoxPosRepositoryProvider).attendanceMark(widget.businessId, person, _todayDate(), status, otMin: otMin);
      ref.invalidate(askodoxAttTodayProvider(widget.businessId));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  Future<void> _tapPerson(AskodoxJson p) async {
    final te = _te;
    final ref0 = '${p['ref']}';
    final name = '${p['name']}'.isEmpty ? '••$ref0' : '${p['name']}';
    var overtime = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              if (!overtime)
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final (s, label, color) in [
                    ('P', te ? 'వచ్చారు' : 'Present', askodoxStepDone),
                    ('A', te ? 'రాలేదు' : 'Absent', askodoxStepBad),
                    ('OT', te ? 'ఎక్కువ గంటలు' : 'Overtime', askodoxStepWarn),
                    ('leave', te ? 'సెలవు' : 'Leave', const Color(0xFFCDBAFF)),
                  ])
                    FilledButton(
                      key: Key('askodoxAttStepsMark-$ref0-$s'),
                      style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(150, 54)),
                      onPressed: () {
                        if (s == 'OT') {
                          setS(() => overtime = true);
                          return;
                        }
                        Navigator.pop(ctx);
                        unawaited(_mark(ref0, s));
                      },
                      child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                ])
              else ...[
                Text(te ? 'ఎన్ని గంటలు ఎక్కువ?' : 'How many extra hours?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final h in const [1, 2, 3, 4])
                    FilledButton(
                      key: Key('askodoxAttStepsOt-$ref0-$h'),
                      style: FilledButton.styleFrom(backgroundColor: askodoxStepWarn, minimumSize: const Size(80, 54)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_mark(ref0, 'OT', otMin: h * 60));
                      },
                      child: Text('$h ${te ? 'గం' : 'h'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final data = ref.watch(askodoxAttTodayProvider(widget.businessId));
    return AskodoxStepScaffold(
      key: const Key('askodoxAttendanceSteps'),
      title: te ? 'ఈ రోజు హాజరు' : "Today's attendance",
      more: [
        AskodoxStepMore('askodoxAttendanceStepsFull', te ? 'పాత హాజరు పేజీ (లొకేషన్, ఆలస్యం వివరాలు)' : 'Old attendance page (location, late details)',
            Icons.menu_book_rounded, () => context.push('/biz/${widget.businessId}/staff/today?full=1')),
        AskodoxStepMore('askodoxAttendanceStepsKiosk', te ? 'షాప్ ఫోన్ హాజరు' : 'Shop phone attendance', Icons.phone_android_rounded,
            () => context.push('/biz/${widget.businessId}/staff/kiosk')),
        AskodoxStepMore('askodoxAttendanceStepsSetup', te ? 'హాజరు సెటప్' : 'Attendance setup', Icons.schedule_rounded,
            () => context.push('/biz/${widget.businessId}/staff/setup')),
      ],
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AskodoxPosError(error: e, onRetry: () => ref.invalidate(askodoxAttTodayProvider(widget.businessId))),
        data: (d) {
          final people = askodoxPosList(d['people']);
          final counts = askodoxPosMap(d['counts']);
          final present = askodoxPosInt(counts['present']);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(askodoxAttTodayProvider(widget.businessId)),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              AskodoxStepBigNumber('$present / ${people.length}', label: te ? 'ఈ రోజు వచ్చారు' : 'Here today', size: 44),
              const SizedBox(height: 10),
              if (people.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(te ? 'సిబ్బంది లేరు.' : 'No staff yet.', key: const Key('askodoxAttendanceStepsNone'), textAlign: TextAlign.center),
                ),
              for (final p in people) _row(p, te),
            ]),
          );
        },
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxAttendanceStepsCheckin'),
        label: te ? 'నా హాజరు వేయి' : 'Check in / out',
        icon: Icons.fingerprint_rounded,
        onPressed: () => context.push('/biz/${widget.businessId}/staff/checkin'),
      ),
    );
  }

  Widget _row(AskodoxJson p, bool te) {
    final t = askodoxPosMap(p['today']);
    final status = t.isEmpty ? '' : '${t['status']}';
    final name = '${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}';
    final (mark, color) = switch (status) {
      'P' => ('P', askodoxStepDone),
      'A' => ('A', askodoxStepBad),
      'OT' => ('OT', askodoxStepWarn),
      'leave' => (te ? 'సె' : 'L', const Color(0xFFCDBAFF)),
      _ => ('—', askodoxStepMuted),
    };
    final inAt = _clockOf(t['in_at']);
    final outAt = _clockOf(t['out_at']);
    return AskodoxStepPersonRow(
      key: Key('askodoxAttendanceStepsRow-${p['ref']}'),
      name: name,
      sub: [
        '${p['role'] ?? ''}',
        if (inAt.isNotEmpty) '${te ? 'వచ్చింది' : 'in'} $inAt',
        if (outAt.isNotEmpty) '${te ? 'వెళ్ళింది' : 'out'} $outAt',
        if (askodoxPosInt(t['late_min']) > 0) (te ? 'ఆలస్యం ${askodoxPosInt(t['late_min'])} ని.' : 'late ${askodoxPosInt(t['late_min'])} min'),
      ].where((s) => s.isNotEmpty).join(' · '),
      amount: mark,
      amountColor: color,
      onTap: () => unawaited(_tapPerson(p)),
    );
  }
}

// ============================================================================ salary
class AskodoxSalaryStepsScreen extends ConsumerStatefulWidget {
  const AskodoxSalaryStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxSalaryStepsScreen> createState() => _SalaryStepsState();
}

class _SalaryStepsState extends ConsumerState<AskodoxSalaryStepsScreen> {
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await _repo.teamSalary(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  int _net(AskodoxJson p) => askodoxPosInt(askodoxPosMap(p['salary'])['net_paise']);
  bool _set(AskodoxJson p) => askodoxPosMap(p['salary'])['set'] == true;
  bool _due(AskodoxJson p) => p['paid'] == null && _set(p);

  Future<void> _paid(AskodoxJson p) async {
    final te = _te;
    final net = askodoxPaise(_net(p));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? '${p['name']} కి $net ఇచ్చారా?' : 'Gave $net to ${p['name']}?'),
        content: Text(te ? 'క్యాష్‌బుక్‌లో జీతం ఖర్చుగా రాస్తాం.' : 'It is written in the cashbook as salary.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxSalaryStepsConfirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'ఇచ్చేశాను ✓' : 'Given ✓')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.salaryPaid(widget.businessId, '${p['ref']}', '${_data?['month']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final data = _data;
    final people = askodoxPosList(data?['people']);
    final due = people.where(_due).toList();
    final toGive = due.fold<int>(0, (s, p) => s + _net(p));
    return AskodoxStepScaffold(
      key: const Key('askodoxSalarySteps'),
      title: te ? 'జీతాలు ${data?['month'] ?? ''}' : 'Salary ${data?['month'] ?? ''}',
      more: [
        AskodoxStepMore('askodoxSalaryStepsFull', te ? 'పాత జీతాల పేజీ' : 'Old salary page', Icons.menu_book_rounded,
            () => context.push('/biz/${widget.businessId}/staff/salary?full=1')),
      ],
      body: _error != null && data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxPaise(toGive), label: te ? 'ఇవ్వాల్సిన జీతాలు' : 'Salaries to give', size: 40),
                    const SizedBox(height: 10),
                    if (people.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'సిబ్బంది లేరు.' : 'No staff yet.', key: const Key('askodoxSalaryStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final p in people)
                      AskodoxStepPersonRow(
                        key: Key('askodoxSalaryStepsRow-${p['ref']}'),
                        name: '${p['name']}'.isEmpty ? '••${p['ref']}' : '${p['name']}',
                        sub: _set(p)
                            ? '${askodoxPosMap(p['salary'])['days']} ${te ? 'రోజులు' : 'days'}'
                            : (te ? 'జీతం పెట్టలేదు' : 'Salary not set'),
                        amount: p['paid'] != null ? '✓' : (_set(p) ? askodoxPaise(_net(p)) : '—'),
                        amountColor: p['paid'] != null ? askodoxStepDone : askodoxStepWarn,
                        onTap: () => context.push('/biz/${widget.businessId}/staff/person/${p['ref']}'),
                      ),
                  ]),
                ),
      bottom: due.isEmpty
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxSalaryStepsGive'),
              label: te ? '${due.first['name']} కి ఇచ్చాను' : 'Gave ${due.first['name']}',
              icon: Icons.check_rounded,
              onPressed: () => unawaited(_paid(due.first)),
            ),
    );
  }
}
