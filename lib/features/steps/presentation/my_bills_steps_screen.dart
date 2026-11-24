import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_bills_screens.dart' show askodoxBillRupees;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 21): the customer's own bills `/me/bills`. Top = how much is left to pay, middle =
/// ONE list of the bills (tap = pay by UPI / show the QR / "I have paid" / "I will pay on ..."), bottom = ONE big button
/// (pay the first bill). Paid bills are in the menu ⋮; the old page stays at `?full=1`. Money goes straight to the shop's
/// own UPI; ASKODOX never holds it.
class AskodoxMyBillsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxMyBillsStepsScreen({super.key});

  @override
  ConsumerState<AskodoxMyBillsStepsScreen> createState() => _MyBillsState();
}

class _MyBillsState extends ConsumerState<AskodoxMyBillsStepsScreen> {
  List<AskodoxJson>? _bills;
  Object? _error;
  bool _paidView = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await _repo.myBills();
      if (mounted) {
        setState(() {
          _bills = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _bills == null) setState(() => _error = e);
    }
  }

  String _upi(AskodoxJson bill) {
    for (final p in askodoxPosList(bill['pay'])) {
      if ('${p['upi_link'] ?? ''}'.isNotEmpty) return '${p['upi_link']}';
    }
    return '';
  }

  String _day(Object? iso) {
    final s = '$iso';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _pay(AskodoxJson bill) async {
    final te = _te;
    final ok = await launchUrl(Uri.parse(_upi(bill)), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      askodoxPosSnack(context, te ? 'UPI యాప్ తెరుచుకోలేదు — QR చూపించి వేరే ఫోన్‌తో కట్టండి.' : 'No UPI app opened — show the QR and pay from another phone.');
    }
  }

  void _qr(AskodoxJson bill) {
    final te = _te;
    showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text('${bill['shop']} · ${askodoxBillRupees(askodoxPosInt(bill['due_paise']))}'),
              content: SizedBox(
                  width: 260,
                  child: AskodoxQrPoster(
                    qrKey: const Key('askodoxMyBillStepsQr'),
                    data: _upi(bill),
                    te: te,
                    title: '${bill['shop']}',
                    size: 190,
                    actions: false,
                    fileName: 'askodox-bill-qr',
                    footnoteEn: "Shop's own UPI · ASKODOX never holds your money",
                    footnoteTe: 'షాప్ సొంత UPI · ASKODOX మీ డబ్బు ఉంచుకోదు',
                  )),
              actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'సరే' : 'OK'))],
            ));
  }

  Future<void> _saidPaid(AskodoxJson bill) async {
    final te = _te;
    try {
      await _repo.myBillPaid('${bill['token']}', '');
      if (mounted) askodoxPosSnack(context, te ? 'షాప్‌కి చెప్పాం. వాళ్ళు చూసి "కట్టారు" అని మారుస్తారు.' : 'The shop has been told. They confirm and close the bill.');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _promise(AskodoxJson bill) async {
    final te = _te;
    final today = DateTime.now();
    final day = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 60)),
        helpText: te ? 'ఎప్పుడు కడతారు?' : 'When will you pay?');
    if (day == null || !mounted) return;
    final date = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    try {
      await _repo.myBillPromise('${bill['token']}', date);
      if (mounted) askodoxPosSnack(context, te ? 'షాప్‌కి తేదీ చెప్పాం ✓ అప్పటి వరకు గుర్తు చేయం.' : 'The shop has the date ✓ No reminders until then.');
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _bill(AskodoxJson b) async {
    final te = _te;
    final due = askodoxPosInt(b['due_paise']);
    final upi = _upi(b);
    final token = '${b['token']}';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${b['shop']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${b['number']} · ${_day(b['issued_at'])}', style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 8),
            for (final l in askodoxPosList(b['lines']))
              Row(children: [
                Expanded(child: Text('${l['name']} × ${(askodoxPosInt(l['qty_milli']) / 1000).toString().replaceAll(RegExp(r'\.0$'), '')}')),
                Text(askodoxBillRupees(askodoxPosInt(l['amount_paise']))),
              ]),
            const Divider(),
            Row(children: [
              Expanded(child: Text(due > 0 ? (te ? 'కట్టాల్సింది' : 'To pay') : (te ? 'మొత్తం' : 'Total'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(askodoxBillRupees(due > 0 ? due : askodoxPosInt(b['total_paise'])), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 10),
            if ('${b['status']}' == 'cancelled')
              Text(te ? 'ఈ బిల్లు రద్దు అయింది.' : 'This bill was cancelled.')
            else if (due <= 0)
              Text('${te ? 'కట్టారు' : 'Paid'} ✓ ${(b['paid_with'] as List? ?? const []).join(', ')}',
                  style: const TextStyle(color: askodoxStepDone, fontWeight: FontWeight.w800))
            else ...[
              if (upi.isNotEmpty) ...[
                FilledButton.icon(
                    key: Key('askodoxMyBillStepsPay-$token'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () => Navigator.pop(ctx, 'pay'),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(te ? 'UPI లో ${askodoxBillRupees(due)} కట్టు' : 'Pay ${askodoxBillRupees(due)} by UPI')),
                const SizedBox(height: 8),
                OutlinedButton(
                    key: Key('askodoxMyBillStepsQrBtn-$token'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: () => Navigator.pop(ctx, 'qr'),
                    child: Text(te ? 'QR చూపించు' : 'Show QR')),
                const SizedBox(height: 8),
                OutlinedButton(
                    key: Key('askodoxMyBillStepsPaid-$token'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: b['customer_says_paid'] == true ? null : () => Navigator.pop(ctx, 'paid'),
                    child: Text(b['customer_says_paid'] == true ? (te ? 'షాప్‌కి చెప్పాం' : 'Shop told') : (te ? 'కట్టేశాను' : 'I have paid'))),
                const SizedBox(height: 8),
                Text(te ? 'డబ్బు నేరుగా షాప్ UPI కి వెళ్తుంది. ASKODOX డబ్బు పట్టుకోదు.' : "Money goes straight to the shop's UPI. ASKODOX never holds it.",
                    style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
              ] else
                Text(te ? 'షాప్‌లో కట్టండి (షాప్ UPI ఇంకా జోడించలేదు).' : 'Pay at the shop (the shop has not added its UPI yet).'),
              TextButton.icon(
                key: Key('askodoxMyBillStepsPromise-$token'),
                onPressed: () => Navigator.pop(ctx, 'promise'),
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text('${b['promised_date'] ?? ''}'.isNotEmpty
                    ? (te ? '${b['promised_date']} న కడతానన్నారు · మార్చు' : 'You said ${b['promised_date']} · change')
                    : (te ? 'ఇప్పుడు కాదా? ఎప్పుడు కడతారో చెప్పండి' : 'Not now? Tell the shop when you will pay')),
              ),
            ],
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'pay') await _pay(b);
    if (action == 'qr') _qr(b);
    if (action == 'paid') await _saidPaid(b);
    if (action == 'promise') await _promise(b);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా బిల్లులు' : 'My bills';
    final more = [
      AskodoxStepMore('askodoxMyBillsStepsView', _paidView ? (te ? 'కట్టాల్సినవి చూపు' : 'Show bills to pay') : (te ? 'కట్టినవి చూపు' : 'Show paid bills'),
          Icons.swap_horiz_rounded, () => setState(() => _paidView = !_paidView)),
      AskodoxStepMore('askodoxMyBillsStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push('/me/bills?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final bills = _bills;
    if (bills == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final due = [for (final b in bills) if ('${b['status']}' == 'due') b];
    final rest = [for (final b in bills) if ('${b['status']}' != 'due') b];
    final shown = _paidView ? rest : due;
    final total = due.fold<int>(0, (a, b) => a + askodoxPosInt(b['due_paise']));
    return AskodoxStepScaffold(
      key: const Key('askodoxMyBillsSteps'),
      title: title,
      sub: _paidView ? (te ? 'కట్టినవి' : 'Paid') : '',
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber(askodoxBillRupees(total),
              label: due.isEmpty ? (te ? 'ఏ బిల్లూ కట్టాల్సినది లేదు ✓' : 'Nothing to pay ✓') : (te ? 'కట్టాల్సింది · ${due.length} బిల్లులు' : 'To pay · ${due.length} bills'),
              color: due.isEmpty ? askodoxStepDone : askodoxStepInk,
              size: 44),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    te ? 'ఇక్కడ బిల్లులు లేవు. షాప్ మీ నంబర్‌కి బిల్లు పంపితే ఇక్కడ కనిపిస్తుంది.' : 'No bills here. A bill a shop sends to your number shows up here.',
                    textAlign: TextAlign.center)),
          for (final b in shown)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxMyBillStepsRow-${b['token']}'),
              name: '${b['shop']}',
              sub: '${b['number']} · ${_day(b['issued_at'])}${'${b['promised_date'] ?? ''}'.isNotEmpty ? (te ? ' · ${b['promised_date']} న' : ' · on ${b['promised_date']}') : ''}',
              amount: askodoxBillRupees(askodoxPosInt(b['due_paise']) > 0 ? askodoxPosInt(b['due_paise']) : askodoxPosInt(b['total_paise'])),
              amountColor: askodoxPosInt(b['due_paise']) > 0 ? askodoxStepWarn : askodoxStepDone,
              onTap: () => _bill(b),
            ),
        ]),
      ),
      bottom: due.isEmpty || _paidView
          ? null
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxMyBillsStepsPay'),
              label: te ? 'కట్టు · ${due.first['shop']}' : 'Pay · ${due.first['shop']}',
              icon: Icons.payments_outlined,
              onPressed: () => _bill(due.first),
            ),
    );
  }
}
