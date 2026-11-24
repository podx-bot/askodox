import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/collect_qr_sheet.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 ("3-step design for the remaining pages"): the Business Kit work pages in 3 pieces.
/// Job cards `/biz/:id/jobs`: list (one number + tiles) -> new job in 3 steps (what -> how much -> ✓ token); tap a job =
/// the next step button + the owner's UPI QR. Monthly `/biz/:id/monthly`: who paid -> how much -> ✓. Bookings
/// `/biz/:id/bookings`: the day's list, tap = confirm / done / QR. The old pages stay at `?full=1` (header ⋮).

String _statusName(String s, bool te) => switch (s) {
      'received' => te ? 'తీసుకున్నాం' : 'Received',
      'working' => te ? 'పని జరుగుతోంది' : 'Working',
      'ready' => te ? 'రెడీ' : 'Ready',
      'delivered' => te ? 'ఇచ్చేశాం' : 'Delivered',
      'cancelled' => te ? 'రద్దు' : 'Cancelled',
      'booked' => te ? 'బుక్ అయింది' : 'Booked',
      'checked_in' => te ? 'వచ్చారు' : 'Arrived',
      'done' => te ? 'అయిపోయింది' : 'Done',
      'no_show' => te ? 'రాలేదు' : 'No-show',
      _ => s,
    };

// ============================================================================ job cards
class AskodoxJobStepsScreen extends ConsumerStatefulWidget {
  const AskodoxJobStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxJobStepsScreen> createState() => _JobStepsState();
}

class _JobStepsState extends ConsumerState<AskodoxJobStepsScreen> {
  int _step = 0; // 0 = the list, 1..3 = a new job
  AskodoxJson? _data;
  Object? _error;
  final _item = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _typed = '';
  bool _busy = false;
  String _txn = askodoxNewTxnId();
  AskodoxJson? _made;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _item.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.shopJobs(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _start() => setState(() {
        _item.clear();
        _name.clear();
        _phone.clear();
        _typed = '';
        _txn = askodoxNewTxnId();
        _made = null;
        _step = 1;
      });

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final made = await _repo.addJob(widget.businessId, {
        'item': _item.text.trim(),
        'name': _name.text.trim(),
        'phone': askodoxTenDigits(_phone.text),
        'estimate_paise': askodoxKeypadPaise(_typed),
        'client_txn_id': _txn,
      });
      if (!mounted) return;
      setState(() {
        _made = made;
        _step = 3;
      });
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tapJob(AskodoxJson j) async {
    final te = _te;
    const next = {
      'received': ['working', 'ready'],
      'working': ['ready'],
      'ready': ['delivered'],
    };
    final moves = next['${j['status']}'] ?? const <String>[];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('#${j['token']} · ${j['item']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (askodoxPosInt(j['balance_paise']) > 0)
              Text('${te ? 'మిగతా' : 'Balance'} ${askodoxStepRupees(askodoxPosInt(j['balance_paise']))}',
                  style: const TextStyle(fontSize: 16, color: askodoxStepWarn, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final s in moves)
                FilledButton(
                  key: Key('askodoxJobStepsMove-${j['id']}-$s'),
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 54)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final out = await _repo.updateJob(widget.businessId, '${j['id']}', {'status': s});
                      final wa = '${out['whatsapp_url'] ?? ''}';
                      if (s == 'ready' && wa.isNotEmpty && j['in_app'] != true) {
                        unawaited(launchUrl(Uri.parse(wa), mode: LaunchMode.externalApplication));
                      }
                    } on AskodoxPosException catch (e) {
                      if (mounted) askodoxPosSnack(context, e.message(te));
                    }
                    await _load();
                  },
                  child: Text(_statusName(s, te), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              if (askodoxPosInt(j['balance_paise']) > 0)
                OutlinedButton.icon(
                  key: Key('askodoxJobStepsQr-${j['id']}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(140, 54)),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('UPI QR'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(askodoxShowCollectQr(context, ref, businessId: widget.businessId, kind: 'job', refId: '${j['id']}')
                        .then((_) => _load()));
                  },
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  List<AskodoxStepMore> _more() => [
        AskodoxStepMore('askodoxJobStepsFull', _te ? 'పాత జాబ్ కార్డ్స్ పేజీ' : 'Old job cards page', Icons.menu_book_rounded,
            () => context.push('/biz/${widget.businessId}/jobs?full=1')),
      ];

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'జాబ్ కార్డ్స్' : 'Job cards';
    switch (_step) {
      case 1:
        return AskodoxStepScaffold(
          key: const Key('askodoxJobSteps1'),
          title: title,
          step: 1,
          question: te ? 'ఏం వచ్చింది?' : 'What came in?',
          onBack: () => setState(() => _step = 0),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            TextField(
              key: const Key('askodoxJobStepsItem'),
              controller: _item,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: InputDecoration(hintText: te ? 'ఫోన్, జాకెట్, కేక్…' : 'Phone, blouse, cake…', border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: te ? 'కస్టమర్ పేరు (ఐచ్ఛికం)' : 'Customer name (optional)', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: te ? 'ఫోన్ నంబర్ (రెడీ అయితే చెప్పడానికి)' : 'Phone (to tell when ready)', border: const OutlineInputBorder()),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxJobStepsNext1'),
            label: te ? 'తర్వాత' : 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: _item.text.trim().isEmpty ? null : () => setState(() => _step = 2),
            onSpoken: (w) => setState(() => _item.text = w.trim()),
          ),
        );
      case 2:
        return AskodoxStepScaffold(
          key: const Key('askodoxJobSteps2'),
          title: title,
          step: 2,
          question: te ? 'అంచనా ఎంత?' : 'Estimate?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), children: [
            AskodoxStepAmountPad(value: _typed, onChanged: (v) => setState(() => _typed = v)),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxJobStepsSave'),
            label: te ? 'జాబ్ కార్డ్ చేయి' : 'Make job card',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _save,
            onSpoken: (w) {
              final p = askodoxSpokenRupees(w);
              if (p != null) setState(() => _typed = '${p ~/ 100}');
            },
          ),
        );
      case 3:
        return AskodoxStepScaffold(
          key: const Key('askodoxJobSteps3'),
          title: title,
          step: 3,
          more: _more(),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
            const Center(child: AskodoxStepDoneMark()),
            const SizedBox(height: 22),
            AskodoxStepBigNumber('${te ? 'టోకెన్' : 'Token'} ${_made?['token'] ?? ''}', label: '${_made?['item'] ?? ''}', size: 36),
            const SizedBox(height: 18),
            Center(
              child: Text(te ? 'అడ్వాన్స్ తీసుకోవాలంటే జాబ్ మీద నొక్కి UPI QR.' : 'To take an advance, tap the job and use UPI QR.',
                  textAlign: TextAlign.center),
            ),
          ]),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxJobStepsDone'),
            label: te ? 'ఇంకొకటి' : 'Another',
            icon: Icons.add_rounded,
            onPressed: _start,
          ),
        );
    }
    final jobs = askodoxPosList(_data?['jobs']);
    return AskodoxStepScaffold(
      key: const Key('askodoxJobSteps0'),
      title: title,
      more: _more(),
      body: _error != null && _data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('${jobs.length}', label: te ? 'జరుగుతున్న పనులు' : 'Open jobs', size: 44),
                    const SizedBox(height: 10),
                    if (jobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఏ పనీ లేదు. కింద "కొత్త జాబ్" నొక్కండి.' : 'No jobs. Tap "New job" below.',
                            key: const Key('askodoxJobStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final j in jobs)
                      AskodoxStepPersonRow(
                        key: Key('askodoxJobStepsRow-${j['id']}'),
                        name: '#${j['token']} ${j['item']}',
                        sub: [
                          _statusName('${j['status']}', te),
                          if ('${j['customer_name']}'.isNotEmpty) '${j['customer_name']}',
                        ].join(' · '),
                        amount: askodoxPosInt(j['balance_paise']) > 0 ? askodoxStepRupees(askodoxPosInt(j['balance_paise'])) : '✓',
                        amountColor: askodoxPosInt(j['balance_paise']) > 0 ? askodoxStepWarn : askodoxStepDone,
                        onTap: () => unawaited(_tapJob(j)),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxJobStepsNew'),
        label: te ? 'కొత్త జాబ్' : 'New job',
        icon: Icons.add_rounded,
        onPressed: _start,
      ),
    );
  }
}

// ============================================================================ monthly
class AskodoxMonthlyStepsScreen extends ConsumerStatefulWidget {
  const AskodoxMonthlyStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxMonthlyStepsScreen> createState() => _MonthlyStepsState();
}

class _MonthlyStepsState extends ConsumerState<AskodoxMonthlyStepsScreen> {
  int _step = 1;
  AskodoxJson? _data;
  Object? _error;
  AskodoxJson? _member;
  String _typed = '';
  bool _busy = false;
  int _left = 0;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await _repo.monthly(widget.businessId);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(AskodoxJson m) => setState(() {
        _member = m;
        _typed = '${askodoxPosInt(m['left_paise']) ~/ 100}';
        _step = 2;
      });

  Future<void> _pay() async {
    final m = _member;
    if (m == null || _busy) return;
    final paise = askodoxKeypadPaise(_typed);
    setState(() => _busy = true);
    try {
      await _repo.payMonthly(widget.businessId, '${m['id']}', {'amount_paise': paise, 'month': '${_data?['month'] ?? ''}'});
      if (!mounted) return;
      setState(() {
        _left = (askodoxPosInt(m['left_paise']) - paise).clamp(0, 1 << 40);
        _step = 3;
      });
      unawaited(_load());
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AskodoxStepMore> _more() => [
        AskodoxStepMore('askodoxMonthlyStepsFull', _te ? 'పాత నెలవారీ పేజీ (కొత్త సభ్యుడు)' : 'Old monthly page (add member)', Icons.menu_book_rounded,
            () => context.push('/biz/${widget.businessId}/monthly?full=1')),
      ];

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నెలవారీ' : 'Monthly';
    final m = _member;
    if (_step == 2 && m != null) {
      return AskodoxStepScaffold(
        key: const Key('askodoxMonthlySteps2'),
        title: title,
        step: 2,
        question: te ? 'ఎంత కట్టారు?' : 'How much did they pay?',
        onBack: () => setState(() => _step = 1),
        more: [
          AskodoxStepMore('askodoxMonthlyStepsQr', 'UPI QR', Icons.qr_code_2_rounded,
              () => unawaited(askodoxShowCollectQr(context, ref,
                  businessId: widget.businessId, kind: 'member', refId: '${m['id']}', month: '${_data?['month'] ?? ''}')
                  .then((_) => _load()))),
          ..._more(),
        ],
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), children: [
          Center(child: Text('${m['name']} · ${m['plan']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          const SizedBox(height: 8),
          AskodoxStepAmountPad(
            value: _typed,
            onChanged: (v) => setState(() => _typed = v),
            quick: [(te ? 'మొత్తం ${askodoxStepRupees(askodoxPosInt(m['left_paise']))}' : 'All ${askodoxStepRupees(askodoxPosInt(m['left_paise']))}', '${askodoxPosInt(m['left_paise']) ~/ 100}')],
          ),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxMonthlyStepsGot'),
          label: te ? 'వచ్చింది' : 'Received',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: askodoxKeypadPaise(_typed) > 0 ? _pay : null,
          onSpoken: (w) {
            final p = askodoxSpokenRupees(w);
            if (p != null) setState(() => _typed = '${p ~/ 100}');
          },
        ),
      );
    }
    if (_step == 3 && m != null) {
      return AskodoxStepScaffold(
        key: const Key('askodoxMonthlySteps3'),
        title: title,
        step: 3,
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
          const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 22),
          AskodoxStepBigNumber(te ? '${askodoxStepRupees(askodoxKeypadPaise(_typed))} వచ్చింది' : '${askodoxStepRupees(askodoxKeypadPaise(_typed))} received',
              label: '${m['name']}', size: 32),
          const SizedBox(height: 10),
          Center(
              child: AskodoxStepPill(_left > 0 ? (te ? 'ఇంకా ${askodoxStepRupees(_left)}' : 'Still ${askodoxStepRupees(_left)}') : (te ? 'ఈ నెల పూర్తి ✓' : 'This month done ✓'),
                  kind: _left > 0 ? 'warn' : 'good')),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxMonthlyStepsNext'),
          label: te ? 'ఇంకొకరు' : 'Someone else',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => setState(() {
            _member = null;
            _step = 1;
          }),
        ),
      );
    }
    final members = askodoxPosList(_data?['members']).where((x) => x['status'] == 'active').toList();
    return AskodoxStepScaffold(
      key: const Key('askodoxMonthlySteps1'),
      title: title,
      sub: '${_data?['month'] ?? ''}',
      step: 1,
      question: te ? 'ఎవరు కట్టారు?' : 'Who paid?',
      more: _more(),
      body: _error != null && _data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(_data?['owed_paise'])),
                        label: te ? 'ఈ నెల రావాల్సింది' : 'Still to come this month', color: askodoxStepWarn, size: 40),
                    const SizedBox(height: 10),
                    if (members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'సభ్యులు లేరు. ⋮ లో పాత పేజీ నుంచి చేర్చండి.' : 'No members. Add from the old page in ⋮.',
                            key: const Key('askodoxMonthlyStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final x in members)
                      AskodoxStepPersonRow(
                        key: Key('askodoxMonthlyStepsRow-${x['id']}'),
                        name: '${x['name']}',
                        sub: '${x['plan']}${x['late'] == true ? (te ? ' · ఆలస్యం' : ' · late') : ''}',
                        amount: askodoxPosInt(x['left_paise']) > 0 ? askodoxStepRupees(askodoxPosInt(x['left_paise'])) : '✓',
                        amountColor: askodoxPosInt(x['left_paise']) > 0 ? askodoxStepWarn : askodoxStepDone,
                        onTap: askodoxPosInt(x['left_paise']) > 0 ? () => _open(x) : () {},
                      ),
                  ]),
                ),
    );
  }
}

// ============================================================================ bookings
class AskodoxBookingStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBookingStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBookingStepsScreen> createState() => _BookingStepsState();
}

class _BookingStepsState extends ConsumerState<AskodoxBookingStepsScreen> {
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
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final d = await _repo.shopBookings(widget.businessId, day: day);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _tap(AskodoxJson b) async {
    final te = _te;
    const next = {
      'booked': ['checked_in', 'done', 'no_show', 'cancelled'],
      'checked_in': ['done'],
    };
    final moves = next['${b['status']}'] ?? const <String>[];
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${b['item']} · ${b['customer_name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final s in moves)
                FilledButton(
                  key: Key('askodoxBookingStepsMove-${b['id']}-$s'),
                  style: FilledButton.styleFrom(minimumSize: const Size(130, 54)),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await _repo.bookingStatus(widget.businessId, '${b['id']}', s);
                    } on AskodoxPosException catch (e) {
                      if (mounted) askodoxPosSnack(context, e.message(te));
                    }
                    await _load();
                  },
                  child: Text(_statusName(s, te), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              OutlinedButton.icon(
                key: Key('askodoxBookingStepsQr-${b['id']}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(130, 54)),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('UPI QR'),
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(askodoxShowCollectQr(context, ref, businessId: widget.businessId, kind: 'booking', refId: '${b['id']}'));
                },
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final list = askodoxPosList(_data?['bookings']);
    return AskodoxStepScaffold(
      key: const Key('askodoxBookingSteps0'),
      title: te ? 'బుకింగ్స్' : 'Bookings',
      sub: te ? 'ఈ రోజు' : 'Today',
      more: [
        AskodoxStepMore('askodoxBookingStepsFull', te ? 'పాత బుకింగ్స్ పేజీ (కొత్త బుకింగ్, వస్తువులు)' : 'Old bookings page (new booking, things)',
            Icons.menu_book_rounded, () => context.push('/biz/${widget.businessId}/bookings?full=1')),
      ],
      body: _error != null && _data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('${list.length}', label: te ? 'ఈ రోజు బుకింగ్స్' : "Today's bookings", size: 44),
                    const SizedBox(height: 10),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఈ రోజు బుకింగ్స్ లేవు.' : 'No bookings today.',
                            key: const Key('askodoxBookingStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final b in list)
                      AskodoxStepPersonRow(
                        key: Key('askodoxBookingStepsRow-${b['id']}'),
                        name: '${b['item']}',
                        sub: [if ('${b['customer_name']}'.isNotEmpty) '${b['customer_name']}', _statusName('${b['status']}', te)].join(' · '),
                        amount: '${b['people']}',
                        amountColor: askodoxStepInfo,
                        onTap: () => unawaited(_tap(b)),
                      ),
                  ]),
                ),
    );
  }
}
