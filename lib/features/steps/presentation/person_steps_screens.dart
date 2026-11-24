import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 7): one person's month `/biz/:id/staff/person/:ref` and the night report
/// `/biz/:id/reports/settings`. The old pages stay at `?full=1`. Money is only recorded.

// ============================================================================ one person's month
class AskodoxStaffPersonStepsScreen extends ConsumerStatefulWidget {
  const AskodoxStaffPersonStepsScreen({super.key, required this.businessId, required this.staffRef});
  final String businessId;
  final String staffRef;

  @override
  ConsumerState<AskodoxStaffPersonStepsScreen> createState() => _PersonState();
}

class _PersonState extends ConsumerState<AskodoxStaffPersonStepsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AskodoxJson? _data;
  Object? _error;
  int _step = 0; // 0 = the month, 1 = how much, 3 = done
  String _kind = 'advance';
  String _typed = '';
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  bool get _mine => widget.staffRef == 'me';
  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await _repo.attendanceMonth(widget.businessId, ref: widget.staffRef, month: _ym);
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

  void _shift(int by) {
    setState(() {
      _month = DateTime(_month.year, _month.month + by);
      _data = null;
    });
    unawaited(_load());
  }

  Future<void> _mark(String date, String status, {int otMin = 0}) async {
    try {
      await _repo.attendanceMark(widget.businessId, widget.staffRef, date, status, otMin: otMin);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  Future<void> _dayMenu(AskodoxJson day) async {
    if (_mine) return;
    final te = _te;
    final date = '${day['date']}';
    var overtime = false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(date, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              if (!overtime)
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final (s, label, color) in [
                    ('P', te ? 'వచ్చారు' : 'Present', askodoxStepDone),
                    ('A', te ? 'రాలేదు' : 'Absent', askodoxStepBad),
                    ('OT', te ? 'ఎక్కువ గంటలు' : 'Overtime', askodoxStepWarn),
                    ('leave', te ? 'సెలవు' : 'Leave', const Color(0xFF5B2A9E)),
                  ])
                    FilledButton(
                      key: Key('askodoxPersonStepsMark-$date-$s'),
                      style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(150, 54)),
                      onPressed: () {
                        if (s == 'OT') {
                          setS(() => overtime = true);
                          return;
                        }
                        Navigator.pop(ctx);
                        unawaited(_mark(date, s));
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
                      key: Key('askodoxPersonStepsOt-$date-$h'),
                      style: FilledButton.styleFrom(backgroundColor: askodoxStepWarn, minimumSize: const Size(80, 54)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_mark(date, 'OT', otMin: h * 60));
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

  Future<void> _giveMoney() async {
    final te = _te;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              key: const Key('askodoxPersonStepsAdvance'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5B2A9E), minimumSize: const Size.fromHeight(58)),
              onPressed: () => Navigator.pop(ctx, 'advance'),
              child: Text(te ? 'అడ్వాన్స్ ఇచ్చాను' : 'Gave an advance', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('askodoxPersonStepsBonus'),
              style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(58)),
              onPressed: () => Navigator.pop(ctx, 'bonus'),
              child: Text(te ? 'బోనస్ ఇస్తున్నా' : 'Give a bonus', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
    if (kind == null || !mounted) return;
    setState(() {
      _kind = kind;
      _typed = '';
      _step = 1;
    });
  }

  Future<void> _save() async {
    final paise = askodoxKeypadPaise(_typed);
    if (paise <= 0) return;
    setState(() => _busy = true);
    try {
      if (_kind == 'bonus') {
        await _repo.staffBonus(widget.businessId, widget.staffRef, paise);
      } else {
        await _repo.staffAdvance(widget.businessId, widget.staffRef, paise);
      }
      await _load();
      if (mounted) setState(() => _step = 3);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      AskodoxStepMore('askodoxPersonStepsPrev', te ? 'ముందు నెల' : 'Previous month', Icons.chevron_left, () => _shift(-1)),
      AskodoxStepMore('askodoxPersonStepsNext', te ? 'తర్వాత నెల' : 'Next month', Icons.chevron_right, () => _shift(1)),
      AskodoxStepMore('askodoxPersonStepsFull', te ? 'పాత పేజీ (జీతం సెట్టింగ్)' : 'Old page (salary settings)', Icons.menu_book_rounded,
          () => context.push('/biz/${widget.businessId}/staff/person/${widget.staffRef}?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final name = _mine
        ? (te ? 'నా హాజరు & జీతం' : 'My attendance & salary')
        : '${d?['name'] ?? ''}'.isEmpty
            ? '••${widget.staffRef}'
            : '${d?['name']}';
    if (_step == 1) {
      final adv = _kind != 'bonus';
      return AskodoxStepScaffold(
        key: const Key('askodoxPersonSteps1'),
        title: name,
        step: 1,
        total: 2,
        question: adv ? (te ? 'అడ్వాన్స్ ఎంత?' : 'How much advance?') : (te ? 'బోనస్ ఎంత?' : 'How much bonus?'),
        onBack: () => setState(() => _step = 0),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepAmountPad(value: _typed, onChanged: (v) => setState(() => _typed = v)),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPersonStepsSave'),
          label: te ? 'సేవ్ ✓' : 'Save ✓',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy || askodoxKeypadPaise(_typed) <= 0 ? null : _save,
        ),
      );
    }
    if (_step == 3) {
      final salary = askodoxPosMap(d?['salary']);
      return AskodoxStepScaffold(
        key: const Key('askodoxPersonSteps3'),
        title: name,
        step: 2,
        total: 2,
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
          const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 26),
          AskodoxStepBigNumber(
              _kind == 'bonus'
                  ? (te ? '${askodoxStepRupees(askodoxKeypadPaise(_typed))} బోనస్' : '${askodoxStepRupees(askodoxKeypadPaise(_typed))} bonus')
                  : (te ? '${askodoxStepRupees(askodoxKeypadPaise(_typed))} అడ్వాన్స్' : '${askodoxStepRupees(askodoxKeypadPaise(_typed))} advance'),
              label: name,
              size: 32),
          if (salary['set'] == true) ...[
            const SizedBox(height: 10),
            Center(child: AskodoxStepPill(te ? 'ఇవ్వాల్సింది ${askodoxStepRupees(askodoxPosInt(salary['net_paise']))}' : 'To give ${askodoxStepRupees(askodoxPosInt(salary['net_paise']))}')),
          ],
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPersonStepsBack'),
          label: te ? 'నెలకి' : 'Back to the month',
          icon: Icons.arrow_back_rounded,
          onPressed: () => setState(() {
            _step = 0;
            _typed = '';
          }),
        ),
      );
    }
    final counts = askodoxPosMap(d?['counts']);
    final salary = askodoxPosMap(d?['salary']);
    final days = askodoxPosList(d?['days']).reversed.toList();
    return AskodoxStepScaffold(
      key: const Key('askodoxStaffPersonSteps'),
      title: name,
      sub: _ym,
      more: _more(),
      body: _error != null && d == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    if (salary['set'] == true)
                      AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(salary['net_paise'])), label: te ? 'ఇవ్వాల్సిన జీతం' : 'Salary to give', size: 40)
                    else
                      AskodoxStepBigNumber('${askodoxPosInt(counts['present'])}', label: te ? 'వచ్చిన రోజులు' : 'Days present', size: 40),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                          te
                              ? 'వచ్చారు ${askodoxPosInt(counts['present'])} · రాలేదు ${askodoxPosInt(counts['absent'])} · అడ్వాన్స్ ${askodoxStepRupees(askodoxPosInt(d['advance_paise']))}'
                              : 'Present ${askodoxPosInt(counts['present'])} · Absent ${askodoxPosInt(counts['absent'])} · Advance ${askodoxStepRupees(askodoxPosInt(d['advance_paise']))}',
                          key: const Key('askodoxPersonStepsSplit'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
                    ),
                    if (salary['set'] != true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            _mine
                                ? (te ? 'ఓనర్ ఇంకా జీతం పెట్టలేదు.' : 'The owner has not set a salary yet.')
                                : (te ? 'జీతం ఇంకా పెట్టలేదు — ⋮ → పాత పేజీలో "జీతం సెట్టింగ్".' : 'Salary not set yet — ⋮ → old page → "Salary settings".'),
                            key: const Key('askodoxPersonStepsNoSalary'),
                            textAlign: TextAlign.center),
                      ),
                    for (final day in days)
                      AskodoxStepPersonRow(
                        key: Key('askodoxPersonStepsDay-${day['date']}'),
                        name: '${day['date']}'.length >= 10 ? '${day['date']}'.substring(8, 10) : '${day['date']}',
                        sub: '${day['date']}',
                        amount: _status(askodoxPosMap(day['att'])['status'], te),
                        amountColor: _statusColor(askodoxPosMap(day['att'])['status']),
                        onTap: () => _dayMenu(day),
                      ),
                  ]),
                ),
      bottom: _mine
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxPersonStepsGive'),
              label: te ? 'అడ్వాన్స్ / బోనస్' : 'Advance / bonus',
              icon: Icons.currency_rupee,
              onPressed: d == null ? null : _giveMoney,
            ),
    );
  }

  String _status(Object? s, bool te) => switch ('$s') {
        'P' => te ? 'వచ్చారు' : 'Present',
        'A' => te ? 'రాలేదు' : 'Absent',
        'OT' => 'OT',
        'leave' => te ? 'సెలవు' : 'Leave',
        'half' => te ? 'సగం' : 'Half',
        _ => '—',
      };

  Color _statusColor(Object? s) => switch ('$s') {
        'P' => askodoxStepDone,
        'A' => askodoxStepBad,
        'OT' => askodoxStepWarn,
        _ => askodoxStepMuted,
      };
}

// ============================================================================ night report
class AskodoxReportSettingsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxReportSettingsStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxReportSettingsStepsScreen> createState() => _NightState();
}

class _NightState extends ConsumerState<AskodoxReportSettingsStepsScreen> {
  AskodoxJson? _s;
  Object? _error;
  int _step = 1; // 1 = every night?, 2 = when?, 3 = done
  bool _busy = false;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).reportSettings(widget.businessId);
      if (mounted) {
        setState(() {
          _s = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _s == null) setState(() => _error = e);
    }
  }

  Future<bool> _save(AskodoxJson change) async {
    setState(() => _busy = true);
    try {
      final s = await ref.read(askodoxPosRepositoryProvider).saveReportSettings(widget.businessId, change);
      if (mounted) setState(() => _s = s);
      return true;
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _otherTime() async {
    final cur = '${_s?['send_time'] ?? '23:00'}'.split(':');
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: int.tryParse(cur.first) ?? 23, minute: int.tryParse(cur.last) ?? 0));
    if (t != null && await _save({'send_time': _hhmm(t)}) && mounted) setState(() => _step = 3);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final s = _s;
    final title = te ? 'రాత్రి రిపోర్ట్' : 'Night report';
    final more = [
      AskodoxStepMore('askodoxNightStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/biz/${widget.businessId}/reports/settings?full=1')),
    ];
    if (_error != null && s == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxNightSteps'), title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    }
    if (s == null) {
      return AskodoxStepScaffold(key: const Key('askodoxNightSteps'), title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    }
    final on = s['night_push'] == true;
    final time = '${s['send_time'] ?? ''}';
    switch (_step) {
      case 2:
        return AskodoxStepScaffold(
          key: const Key('askodoxNightSteps2'),
          title: title,
          step: 2,
          total: 2,
          question: te ? 'ఎప్పుడు పంపాలి?' : 'When should it come?',
          hint: te ? 'ప్రస్తుతం $time' : 'Now $time',
          onBack: () => setState(() => _step = 1),
          more: more,
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            for (final (k, en, tel) in const [
              ('21:00', '9 PM', 'రాత్రి 9'),
              ('22:00', '10 PM', 'రాత్రి 10'),
              ('23:00', '11 PM', 'రాత్రి 11'),
              ('00:00', 'Midnight (the day that just ended)', 'అర్ధరాత్రి 12 (అయిపోయిన రోజు)'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AskodoxStepChoice(
                  key: Key('askodoxNightStepsTime-$k'),
                  icon: Icons.schedule,
                  color: askodoxStepGreen,
                  title: te ? tel : en,
                  sub: '',
                  selected: time == k,
                  onTap: _busy
                      ? null
                      : () async {
                          if (await _save({'send_time': k}) && mounted) setState(() => _step = 3);
                        },
                ),
              ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxNightStepsOther'),
            label: te ? 'వేరే సమయం' : 'Other time',
            icon: Icons.schedule,
            outline: true,
            onPressed: _busy ? null : _otherTime,
          ),
        );
      case 3:
        return AskodoxStepScaffold(
          key: const Key('askodoxNightSteps3'),
          title: title,
          step: 2,
          total: 2,
          more: more,
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
            const Center(child: AskodoxStepDoneMark()),
            const SizedBox(height: 26),
            AskodoxStepBigNumber(on ? time : (te ? 'ఆఫ్' : 'Off'),
                label: on ? (te ? 'ప్రతి రాత్రి రిపోర్ట్ వస్తుంది' : 'The report comes every night') : (te ? 'రాత్రి రిపోర్ట్ రాదు' : 'No night report'),
                size: 40),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxNightStepsDone'),
            label: te ? 'రిపోర్ట్స్‌కి' : 'Back to reports',
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.pop(),
          ),
        );
      default:
        return AskodoxStepScaffold(
          key: const Key('askodoxNightSteps'),
          title: title,
          step: 1,
          total: 2,
          question: te ? 'ప్రతి రాత్రి రిపోర్ట్ పంపాలా?' : 'Send the report every night?',
          hint: te ? 'మీకు, రిపోర్ట్స్ చూడగలిగే మేనేజర్ / అకౌంటెంట్‌కి ఒక నోటిఫికేషన్' : 'One notification to you and the manager / accountant who can see reports',
          more: more,
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
            AskodoxStepChoice(
              key: const Key('askodoxNightStepsOn'),
              icon: Icons.nightlight_round,
              color: askodoxStepGreen,
              title: te ? 'అవును, పంపండి' : 'Yes, send it',
              sub: on ? '$time' : '',
              selected: on,
              onTap: _busy
                  ? null
                  : () async {
                      if (await _save({'night_push': true}) && mounted) setState(() => _step = 2);
                    },
            ),
            const SizedBox(height: 10),
            AskodoxStepChoice(
              key: const Key('askodoxNightStepsOff'),
              icon: Icons.notifications_off_outlined,
              color: askodoxStepMuted,
              title: te ? 'వద్దు' : 'No',
              sub: '',
              selected: !on,
              onTap: _busy
                  ? null
                  : () async {
                      if (await _save({'night_push': false}) && mounted) setState(() => _step = 3);
                    },
            ),
          ]),
        );
    }
  }
}
