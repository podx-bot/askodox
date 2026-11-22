import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

const _night = Color(0xFF1E293B);

/// `/pos/:id/day` (owner 2026-11-22, "3 steps"): ① is today's online money right? (the bills' UPI / card total, yes /
/// there is a difference -> the bill history) ② how much cash is in the drawer? (dialer keypad, "should be ₹X",
/// the difference live) ③ ✓ today's sales in three blocks + send on WhatsApp. Closing is final, so step 2 asks once.
/// A day already closed opens straight on ③. The old page stays at `?full=1`.
class AskodoxDayStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDayStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDayStepsScreen> createState() => _AskodoxDayStepsScreenState();
}

class _AskodoxDayStepsScreenState extends ConsumerState<AskodoxDayStepsScreen> {
  final _date = askodoxPosToday();
  int _step = 1;
  AskodoxJson? _day;
  Object? _error;
  String _typed = '';
  int _floatPaise = 0;
  bool _busy = false;
  String _shopName = '';

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(ref.read(askodoxPosRepositoryProvider).shopState(widget.businessId).then((shop) {
      if (mounted) setState(() => _shopName = '${shop['name'] ?? ''}');
    }, onError: (_) {}));
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).day(widget.businessId, _date);
      if (!mounted) return;
      setState(() {
        _day = d;
        _error = null;
        if (d['closed'] != null) _step = 3;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  AskodoxJson get _payments => askodoxPosMap(_day?['payments']);
  int _net(String method) => askodoxPosInt(askodoxPosMap(_payments[method])['net_paise']);
  int get _cash => _net('cash');
  int get _online => _payments.keys.where((k) => k != 'cash').fold(0, (sum, k) => sum + _net(k));
  int get _expected => _floatPaise + _cash;

  String _methodName(String m, bool te) => switch (m) {
        'upi' => 'UPI',
        'card' => te ? 'కార్డ్' : 'Card',
        'bank_transfer' => te ? 'బ్యాంక్' : 'Bank',
        'cheque' => te ? 'చెక్' : 'Cheque',
        _ => m,
      };

  Future<void> _close() async {
    final te = _te;
    final counted = askodoxKeypadPaise(_typed);
    if (_typed.isEmpty) {
      askodoxPosSnack(context, te ? 'డ్రాయర్‌లో ఉన్న క్యాష్ రాయండి (లేకపోతే 0).' : 'Type the cash in the drawer (0 if none).');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(te ? 'ఈ రోజు ముగించాలా?' : 'Close today?'),
        content: Text(te
            ? 'క్యాష్ ${askodoxStepRupees(counted)} · తేడా ${askodoxStepRupees(counted - _expected)}.\nముగించిన తర్వాత మార్చలేం.'
            : 'Cash ${askodoxStepRupees(counted)} · difference ${askodoxStepRupees(counted - _expected)}.\nClosing is final.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(te ? 'వద్దు' : 'Not yet')),
          FilledButton(
              key: const Key('askodoxDayStepsConfirm'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(te ? 'ముగించు' : 'Close')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final d = await ref
          .read(askodoxPosRepositoryProvider)
          .closeDay(widget.businessId, {'local_date': _date, 'opening_float_paise': _floatPaise, 'counted_cash_paise': counted});
      if (mounted) {
        setState(() {
          _day = d;
          _step = 3;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      if (e.code == 'day_closed') unawaited(_load());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _summaryText(bool te) {
    final d = _day ?? const <String, Object?>{};
    final closed = askodoxPosMap(d['closed']);
    final shop = _shopName.isEmpty ? 'ASKODOX' : _shopName;
    final lines = te
        ? [
            '$shop · ${_date.substring(8)}/${_date.substring(5, 7)} రోజు ముగింపు',
            'అమ్మకం ${askodoxStepRupees(askodoxPosInt(d['sales_paise']))} · ${askodoxPosInt(d['invoices'])} బిల్లులు',
            'క్యాష్ ${askodoxStepRupees(_cash)} · ఆన్‌లైన్ ${askodoxStepRupees(_online)}',
            if (closed.isNotEmpty)
              'డ్రాయర్ ${askodoxStepRupees(askodoxPosInt(closed['counted_cash_paise']))} · తేడా ${askodoxStepRupees(askodoxPosInt(closed['difference_paise']))}',
          ]
        : [
            '$shop · day close ${_date.substring(8)}/${_date.substring(5, 7)}',
            'Sales ${askodoxStepRupees(askodoxPosInt(d['sales_paise']))} · ${askodoxPosInt(d['invoices'])} bills',
            'Cash ${askodoxStepRupees(_cash)} · online ${askodoxStepRupees(_online)}',
            if (closed.isNotEmpty)
              'Drawer ${askodoxStepRupees(askodoxPosInt(closed['counted_cash_paise']))} · difference ${askodoxStepRupees(askodoxPosInt(closed['difference_paise']))}',
          ];
    return lines.join('\n');
  }

  Future<void> _send() async {
    final te = _te;
    final text = _summaryText(te);
    final opened = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) askodoxPosSnack(context, te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.');
    }
  }

  Future<void> _askFloat() async {
    final te = _te;
    final paise = await askodoxAskAmount(context,
        title: te ? 'ఉదయం డ్రాయర్‌లో పెట్టిన క్యాష్' : 'Cash put in the drawer this morning', initialPaise: _floatPaise);
    if (paise != null && mounted) setState(() => _floatPaise = paise);
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxDayStepsHistory', te ? 'ఈ రోజు బిల్లులు' : "Today's bills", Icons.history_rounded,
          () => context.push('/biz/$id/money/history')),
      AskodoxStepMore('askodoxDayStepsFull', te ? 'పాత రోజు ముగింపు పేజీ' : 'Old day-close page', Icons.nightlight_round,
          () => context.push('/pos/$id/day?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'రోజు ముగింపు' : 'Close the day';
    if (_day == null) {
      return AskodoxStepScaffold(
        key: const Key('askodoxDaySteps0'),
        title: title,
        sub: _shopName,
        color: _night,
        body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    return switch (_step) {
      2 => AskodoxStepScaffold(
          key: const Key('askodoxDaySteps2'),
          title: title,
          sub: _shopName,
          step: 2,
          color: _night,
          question: te ? 'డ్రాయర్‌లో క్యాష్ ఎంత?' : 'How much cash is in the drawer?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: _cashStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxDayStepsClose'),
            label: te ? 'రోజు ముగించు' : 'Close the day',
            icon: Icons.check_rounded,
            color: _night,
            busy: _busy,
            onPressed: _typed.isEmpty ? null : _close,
            onSpoken: (words) {
              final paise = askodoxSpokenRupees(words);
              if (paise != null) setState(() => _typed = '${paise ~/ 100}');
            },
          ),
        ),
      3 => AskodoxStepScaffold(
          key: const Key('askodoxDaySteps3'),
          title: title,
          sub: _shopName,
          step: 3,
          color: _night,
          more: _more(),
          body: _doneStep(te),
          bottom: AskodoxStepBottom(
              buttonKey: const Key('askodoxDayStepsSend'),
              label: te ? 'WhatsApp కి పంపు' : 'Send on WhatsApp',
              icon: Icons.send_rounded,
              color: const Color(0xFF15803D),
              onPressed: _send),
        ),
      _ => AskodoxStepScaffold(
          key: const Key('askodoxDaySteps1'),
          title: title,
          sub: _shopName,
          step: 1,
          color: _night,
          question: te ? 'ఆన్‌లైన్ డబ్బు సరేనా?' : 'Is the online money right?',
          hint: te ? 'ఈ రోజు బిల్లుల్లో UPI / కార్డ్ — బ్యాంక్ యాప్‌తో పోల్చండి' : "Today's UPI / card on bills — compare with your bank app",
          more: _more(),
          body: _onlineStep(te),
        ),
    };
  }

  Widget _onlineStep(bool te) {
    final methods = _payments.keys.where((k) => k != 'cash' && _net(k) != 0).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16), children: [
      AskodoxStepBigNumber(askodoxStepRupees(_online),
          label: methods.isEmpty
              ? (te ? 'ఈ రోజు ఆన్‌లైన్ డబ్బు లేదు' : 'No online money today')
              : methods.map((m) => '${_methodName(m, te)} ${askodoxStepRupees(_net(m))}').join(' · '),
          color: const Color(0xFF1D4ED8),
          size: 46),
      const SizedBox(height: 6),
      Center(
        child: Text(te ? '${askodoxPosInt(_day?['invoices'])} బిల్లులు ఈ రోజు' : '${askodoxPosInt(_day?['invoices'])} bills today',
            style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
      ),
      const SizedBox(height: 18),
      AskodoxStepChoice(
        key: const Key('askodoxDayStepsOnlineOk'),
        icon: Icons.check_rounded,
        color: const Color(0xFF15803D),
        title: te ? 'సరే, సరిపోయింది' : 'Yes, it matches',
        sub: te ? 'బ్యాంక్ యాప్‌లో కూడా ఇంతే' : 'The bank app shows the same',
        onTap: () => setState(() => _step = 2),
      ),
      const SizedBox(height: 12),
      AskodoxStepChoice(
        key: const Key('askodoxDayStepsOnlineDiff'),
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFC2410C),
        title: te ? 'తేడా ఉంది' : 'There is a difference',
        sub: te ? 'ఈ రోజు బిల్లులు చూపిస్తాం — సరిచేసి మళ్ళీ రండి' : "We show today's bills — fix and come back",
        onTap: () => context.push('/biz/${widget.businessId}/money/history'),
      ),
    ]);
  }

  Widget _cashStep(bool te) {
    final counted = askodoxKeypadPaise(_typed);
    final diff = counted - _expected;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), children: [
      AskodoxStepAmountPad(
        value: _typed,
        label: te ? 'లెక్కించినది' : 'Counted',
        onChanged: (v) => setState(() => _typed = v),
      ),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        AskodoxStepPill(te ? 'ఉండాల్సింది ${askodoxStepRupees(_expected)}' : 'Should be ${askodoxStepRupees(_expected)}', kind: 'grey'),
        if (_typed.isNotEmpty)
          AskodoxStepPill(
              diff == 0
                  ? (te ? 'సరిగ్గా ఉంది ✓' : 'Exact ✓')
                  : (te ? 'తేడా ${diff > 0 ? '+' : ''}${askodoxStepRupees(diff)}' : 'Difference ${diff > 0 ? '+' : ''}${askodoxStepRupees(diff)}'),
              kind: diff == 0 ? 'good' : 'warn'),
      ]),
      TextButton(
        key: const Key('askodoxDayStepsFloat'),
        onPressed: _askFloat,
        child: Text(te
            ? 'ఉదయం డ్రాయర్‌లో పెట్టింది: ${askodoxStepRupees(_floatPaise)} ✎'
            : 'Put in the drawer this morning: ${askodoxStepRupees(_floatPaise)} ✎'),
      ),
    ]);
  }

  Widget _doneStep(bool te) {
    final d = _day ?? const <String, Object?>{};
    final closed = askodoxPosMap(d['closed']);
    final diff = askodoxPosInt(closed['difference_paise']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 26, 16, 16), children: [
      const Center(child: AskodoxStepDoneMark()),
      const SizedBox(height: 26),
      AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(d['sales_paise'])),
          label: te ? 'ఈ రోజు అమ్మకం · ${askodoxPosInt(d['invoices'])} బిల్లులు' : "Today's sales · ${askodoxPosInt(d['invoices'])} bills",
          size: 42),
      const SizedBox(height: 14),
      AskodoxStepBlocks([
        (te ? 'క్యాష్' : 'Cash', askodoxStepRupees(_cash), const Color(0xFF0F6B3C)),
        (te ? 'ఆన్‌లైన్' : 'Online', askodoxStepRupees(_online), askodoxStepInfo),
        (te ? 'పన్ను' : 'Tax', askodoxStepRupees(askodoxPosInt(d['tax_paise'])), askodoxStepWarn),
      ]),
      const SizedBox(height: 12),
      if (closed.isNotEmpty)
        Center(
          child: AskodoxStepPill(
              diff == 0
                  ? (te ? 'డ్రాయర్ సరిగ్గా ఉంది ✓' : 'Drawer exact ✓')
                  : (te ? 'డ్రాయర్ తేడా ${diff > 0 ? '+' : ''}${askodoxStepRupees(diff)}' : 'Drawer difference ${diff > 0 ? '+' : ''}${askodoxStepRupees(diff)}'),
              kind: diff == 0 ? 'good' : 'warn'),
        ),
      const SizedBox(height: 8),
      Text(te ? 'ఈ రోజు ముగిసింది (మార్చలేం).' : 'This day is closed (final).',
          key: const Key('askodoxDayStepsClosed'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: askodoxStepMuted)),
    ]);
  }
}
