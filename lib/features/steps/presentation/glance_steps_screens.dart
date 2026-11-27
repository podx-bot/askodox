import '../../../config/theme/askodox_look.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../business/presentation/biz_money.dart' show AskodoxCashEntrySheet, askodoxCashCategory;
import '../../guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_dues_screen.dart' show askodoxDueDateChoices, askodoxIsoDay;
import '../../pos/presentation/pos_purchase_screens.dart' show askodoxSerialLookup;
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, glance pages batch 4): Baaki reminders `/pos/:id/dues`, Bills `/pos/:id/invoices`,
/// Expiry & stock value `/pos/:id/stock-report`, Cashbook `/biz/:id/money/cashbook`, Reports `/biz/:id/reports`.
/// One number on top, one list in the middle, ONE big button at the bottom; the rest in the header ⋮. The old pages
/// stay at `?full=1`.

Future<void> _sheet(BuildContext context, List<Widget> children) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );

// ============================================================================ baaki reminders
class AskodoxDuesRemindersStepsScreen extends ConsumerStatefulWidget {
  const AskodoxDuesRemindersStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxDuesRemindersStepsScreen> createState() => _DuesRemindersState();
}

class _DuesRemindersState extends ConsumerState<AskodoxDuesRemindersStepsScreen> {
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
      final d = await _repo.dueReminders(widget.businessId);
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

  Future<void> _whatsApp(AskodoxJson r) async {
    final te = _te;
    final uri = Uri.parse('https://wa.me/${r['whatsapp_to'] ?? ''}?text=${Uri.encodeComponent('${r['text'] ?? ''}')}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!mounted) return;
    if (!ok) {
      askodoxPosSnack(context, te ? 'WhatsApp తెరవలేకపోయాను.' : 'Could not open WhatsApp.');
      return;
    }
    try {
      await _repo.markDueReminded(widget.businessId, '${r['invoice_id']}');
    } catch (_) {}
    await _load();
  }

  /// Owner 2026-11-25: the shop owner's own switch -- reminders for people who are not on ASKODOX go by themselves.
  Future<void> _setAuto(bool on) async {
    final te = _te;
    try {
      await _repo.setDueAuto(widget.businessId, on);
      if (!mounted) return;
      askodoxPosSnack(
          context,
          on
              ? (te ? 'ఆన్: ఇక గుర్తులు WhatsApp లో వాటంతట అవే వెళ్తాయి (రోజుకి ఒకసారి).' : 'On: reminders now go on WhatsApp by themselves (once a day).')
              : (te ? 'ఆఫ్: ఒక్కొక్కరికి మీరే నొక్కి పంపాలి.' : 'Off: you send each one with a tap.'));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _setDate(AskodoxJson r, DateTime date) async {
    try {
      await _repo.setDueDate(widget.businessId, '${r['invoice_id']}', askodoxIsoDay(date));
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
  }

  String _when(AskodoxJson r) {
    final te = _te;
    final left = askodoxPosInt(r['days_left']);
    if (left < 0) return te ? '${-left} రోజులు దాటింది' : '${-left} days late';
    if (left == 0) return te ? 'ఈరోజే' : 'today';
    if (left == 1) return te ? 'రేపు' : 'tomorrow';
    return te ? '$left రోజుల్లో' : 'in $left days';
  }

  bool _canSend(AskodoxJson r) => r['state'] == 'remind' && r['sent_today'] != true && '${r['whatsapp_to'] ?? ''}'.isNotEmpty;

  Future<void> _open(AskodoxJson r) async {
    final te = _te;
    await _sheet(context, [
      Text('${'${r['customer'] ?? ''}'.isEmpty ? (te ? 'కస్టమర్' : 'Customer') : r['customer']} · ${askodoxStepRupees(askodoxPosInt(r['due_paise']))}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text('${r['number']} · ${te ? 'కట్టాల్సిన తేదీ' : 'Pay by'} ${r['pay_date']} (${_when(r)})',
          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (_canSend(r))
        Builder(
          builder: (ctx) => FilledButton.icon(
            key: Key('askodoxDuesStepsWhatsApp-${r['invoice_id']}'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF63CBBB), minimumSize: const Size.fromHeight(54)),
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_whatsApp(r));
            },
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ),
      if (r['state'] == 'remind' && '${r['whatsapp_to'] ?? ''}'.isEmpty)
        Text(te ? 'ఫోన్ నంబర్ లేదు — కస్టమర్ వివరాల్లో నంబర్ చేర్చండి.' : 'No phone number — add it to the customer.'),
      const SizedBox(height: 10),
      Text(te ? 'కొత్త తేదీ:' : 'New date:', style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Builder(
        builder: (ctx) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in askodoxDueDateChoices(DateTime.now()))
            OutlinedButton(
              key: Key('askodoxDuesStepsDate-${r['invoice_id']}-${c.$1}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(100, 48)),
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_setDate(r, c.$3));
              },
              child: Text(te ? c.$2 : c.$1),
            ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final data = _data;
    final items = askodoxPosList(data?['items']);
    final order = {'remind': 0, 'overdue': 1, 'later': 2};
    final sorted = [...items]..sort((a, b) => (order['${a['state']}'] ?? 3).compareTo(order['${b['state']}'] ?? 3));
    final total = items.fold<int>(0, (s, r) => s + askodoxPosInt(r['due_paise']));
    final next = sorted.where(_canSend).firstOrNull;
    final auto = askodoxPosMap(data?['auto']);
    return AskodoxStepScaffold(
      key: const Key('askodoxDuesRemindersSteps'),
      title: te ? 'బాకీ గుర్తులు' : 'Baaki reminders',
      more: [
        if (auto['available'] == true && auto['owner'] == true)
          AskodoxStepMore(
              'askodoxDuesStepsAuto',
              auto['on'] == true
                  ? (te ? 'ఆటోమేటిక్ WhatsApp ఆఫ్ చేయి' : 'Turn automatic WhatsApp off')
                  : (te ? 'ఆటోమేటిక్ WhatsApp ఆన్ చేయి' : 'Turn automatic WhatsApp on'),
              Icons.auto_mode_rounded,
              () => _setAuto(auto['on'] != true)),
        AskodoxStepMore('askodoxDuesStepsFull', te ? 'పాత బాకీ గుర్తుల పేజీ' : 'Old reminders page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/dues?full=1')),
      ],
      body: _error != null && data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(total), label: te ? 'రావాల్సిన బాకీ' : 'Baaki to collect', size: 40),
                    const SizedBox(height: 10),
                    if (auto['on'] == true && auto['available'] == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AskodoxStepPill(
                            te ? 'ఆటోమేటిక్ WhatsApp ఆన్ · రోజుకి ఒకసారి వాటంతట అవే వెళ్తాయి' : 'Automatic WhatsApp on · sent by itself once a day',
                            key: const Key('askodoxDuesStepsAutoOn')),
                      ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'బాకీ బిల్లులు లేవు 🎉' : 'No baaki bills 🎉',
                            key: const Key('askodoxDuesStepsNone'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                      ),
                    for (final r in sorted)
                      AskodoxStepPersonRow(
                        key: Key('askodoxDuesStepsRow-${r['invoice_id']}'),
                        name: '${'${r['customer'] ?? ''}'.isEmpty ? (te ? 'కస్టమర్' : 'Customer') : r['customer']}',
                        sub: r['sent_auto'] == true
                            ? (te ? '✓ WhatsApp దానంతట అదే వెళ్ళింది · ${_when(r)}' : '✓ WhatsApp sent by itself · ${_when(r)}')
                            : r['sent_today'] == true
                                ? (te ? '✓ పంపాం · ${_when(r)}' : '✓ Sent · ${_when(r)}')
                                : _when(r),
                        amount: askodoxStepRupees(askodoxPosInt(r['due_paise'])),
                        amountColor: r['state'] == 'overdue' ? askodoxStepBad : askodoxStepWarn,
                        onTap: () => _open(r),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxDuesStepsNext'),
        label: next != null ? (te ? 'తర్వాతి వారికి గుర్తు చేయి' : 'Remind next') : (te ? 'అందరికీ పంపాం ✓' : 'All reminded ✓'),
        icon: Icons.chat,
        onPressed: next == null ? null : () => _whatsApp(next),
      ),
    );
  }
}

// ============================================================================ bills
class AskodoxInvoicesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxInvoicesStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxInvoicesStepsScreen> createState() => _InvoicesState();
}

class _InvoicesState extends ConsumerState<AskodoxInvoicesStepsScreen> {
  List<AskodoxJson>? _list;
  Object? _error;
  final _search = TextEditingController();
  String _q = '';

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await ref.read(askodoxPosRepositoryProvider).invoices(widget.businessId);
      if (mounted) {
        setState(() {
          _list = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _list == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final list = _list;
    final live = [for (final i in list ?? <AskodoxJson>[]) if (i['status'] != 'cancelled') i];
    final total = live.fold<int>(0, (s, i) => s + askodoxPosInt(i['grand_total_paise']));
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final i in list ?? <AskodoxJson>[])
        if (q.isEmpty || '${i['number']} ${i['customer_name']}'.toLowerCase().contains(q)) i
    ];
    return AskodoxStepScaffold(
      key: const Key('askodoxInvoicesSteps'),
      title: te ? 'బిల్లులు' : 'Bills',
      more: [
        AskodoxStepMore('askodoxInvoicesStepsFull', te ? 'పాత బిల్లుల పేజీ' : 'Old bills page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/invoices?full=1')),
      ],
      body: _error != null && list == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(total),
                        label: te ? '${live.length} బిల్లులు' : '${live.length} bills', size: 40),
                    const SizedBox(height: 10),
                    AskodoxStepSearch(
                      controller: _search,
                      hint: te ? 'బిల్లు నంబర్ / పేరు' : 'Bill number / name',
                      fieldKey: const Key('askodoxInvoicesStepsSearch'),
                      onChanged: (v) => setState(() => _q = v),
                    ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'బిల్లులు ఇంకా లేవు.' : 'No bills yet.',
                            key: const Key('askodoxInvoicesStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final i in shown)
                      AskodoxStepPersonRow(
                        key: Key('askodoxInvoicesStepsRow-${i['id']}'),
                        name: '${'${i['customer_name'] ?? ''}'.isEmpty ? (te ? 'కస్టమర్' : 'Walk-in') : i['customer_name']}',
                        sub: '${i['number']} · ${i['local_date']}${i['status'] == 'cancelled' ? (te ? ' · రద్దు' : ' · cancelled') : ''}',
                        amount: askodoxStepRupees(askodoxPosInt(i['grand_total_paise'])),
                        amountColor: i['status'] == 'cancelled' ? askodoxStepMuted : askodoxStepInk,
                        onTap: () => context.push('/pos/${widget.businessId}/invoice/${i['id']}'),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxInvoicesStepsNew'),
        label: te ? 'కొత్త బిల్లు' : 'New bill',
        icon: Icons.receipt_long,
        onPressed: () async {
          await context.push('/my-shop/sale');
          if (mounted) await _load();
        },
      ),
    );
  }
}

// ============================================================================ expiry & stock value
class AskodoxStockStepsScreen extends ConsumerStatefulWidget {
  const AskodoxStockStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxStockStepsScreen> createState() => _StockState();
}

class _StockState extends ConsumerState<AskodoxStockStepsScreen> {
  AskodoxJson? _expiry;
  AskodoxJson? _value;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final e = await repo.expiryReport(widget.businessId, days: 60);
      AskodoxJson? v;
      try {
        v = await repo.valuation(widget.businessId);
      } on AskodoxPosException {
        v = null; // the role may not see reports
      }
      if (mounted) {
        setState(() {
          _expiry = e;
          _value = v;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _expiry == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final expiry = _expiry;
    final items = askodoxPosList(expiry?['items']);
    final value = _value;
    final expired = items.where((i) => i['expired'] == true).length;
    return AskodoxStepScaffold(
      key: const Key('askodoxStockSteps'),
      title: te ? 'ఎక్స్‌పైరీ & స్టాక్' : 'Expiry & stock',
      more: [
        AskodoxStepMore('askodoxStockStepsFull', te ? 'పాత స్టాక్ పేజీ' : 'Old stock page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/stock-report?full=1')),
      ],
      body: _error != null && expiry == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : expiry == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    if (value != null)
                      AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(value['total_value_paise'])),
                          label: te ? 'స్టాక్ విలువ' : 'Stock value', size: 40)
                    else
                      AskodoxStepBigNumber('${items.length}', label: te ? '60 రోజుల్లో ఎక్స్‌పైర్' : 'Expiring in 60 days', size: 40),
                    if (value != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            te
                                ? '60 రోజుల్లో ఎక్స్‌పైర్: ${items.length}${expired > 0 ? ' · అయిపోయినవి: $expired' : ''}'
                                : 'Expiring in 60 days: ${items.length}${expired > 0 ? ' · expired: $expired' : ''}',
                            key: const Key('askodoxStockStepsCount'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: expired > 0 ? askodoxStepBad : askodoxStepMuted, fontWeight: FontWeight.w700)),
                      ),
                    const SizedBox(height: 10),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఎక్స్‌పైర్ అయ్యేవి ఏమీ లేవు ✓' : 'Nothing is about to expire ✓',
                            key: const Key('askodoxStockStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final i in items)
                      AskodoxStepPersonRow(
                        key: Key('askodoxStockStepsRow-${i['batch_no']}'),
                        name: '${i['name']}',
                        sub: '${i['expiry_date']}${i['expired'] == true ? (te ? ' · అమ్మకానికి రాదు' : ' · cannot be sold') : ''}',
                        amount: askodoxQty(askodoxPosInt(i['qty_milli']), '${i['unit']}'),
                        amountColor: i['expired'] == true ? askodoxStepBad : askodoxStepWarn,
                        onTap: () {},
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxStockStepsSerial'),
        label: te ? 'సీరియల్ / IMEI వెతుకు' : 'Find serial / IMEI',
        icon: Icons.manage_search,
        onPressed: () => askodoxSerialLookup(context, ref, widget.businessId),
      ),
    );
  }
}

// ============================================================================ cashbook
class AskodoxCashbookStepsScreen extends ConsumerStatefulWidget {
  const AskodoxCashbookStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxCashbookStepsScreen> createState() => _CashbookState();
}

class _CashbookState extends ConsumerState<AskodoxCashbookStepsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _ym => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).cashbook(widget.businessId, month: _ym);
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

  Future<void> _add(String kind) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskodoxCashEntrySheet(businessId: widget.businessId, kind: kind),
    );
    if (saved == true) await _load();
  }

  Future<void> _pickKind() async {
    final te = _te;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              key: const Key('askodoxCashbookStepsIn'),
              style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(58)),
              onPressed: () => Navigator.pop(ctx, 'income'),
              child: Text(te ? '+ ఆదాయం' : '+ Money in', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('askodoxCashbookStepsOut'),
              style: FilledButton.styleFrom(backgroundColor: askodoxStepBad, minimumSize: const Size.fromHeight(58)),
              onPressed: () => Navigator.pop(ctx, 'expense'),
              child: Text(te ? '− ఖర్చు' : '− Money out', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
    if (kind != null && mounted) await _add(kind);
  }

  Future<void> _remove(AskodoxJson e) async {
    final te = _te;
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      await repo.cashbookRemove(widget.businessId, '${e['id']}');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(te ? 'తీసేశాం' : 'Removed'),
        action: SnackBarAction(
          label: te ? 'వెనక్కి' : 'Undo',
          onPressed: () async {
            await repo.cashbookRemove(widget.businessId, '${e['id']}', undo: true);
            await _load();
          },
        ),
      ));
    } on AskodoxPosException catch (err) {
      if (mounted) askodoxPosSnack(context, err.message(te));
    }
  }

  Future<void> _open(AskodoxJson e) async {
    final te = _te;
    final income = e['kind'] == 'income';
    await _sheet(context, [
      Text('${income ? '+' : '−'}${askodoxStepRupees(askodoxPosInt(e['amount_paise']))}',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: income ? askodoxStepDone : askodoxStepBad)),
      Text('${'${e['note'] ?? ''}'.isNotEmpty ? '${e['note']} · ' : ''}${askodoxCashCategory('${e['category']}', te)} · ${e['local_date']}',
          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (e['auto'] == true)
        Text(te ? 'ఇది బిల్లుల నుంచి ఆటోగా వచ్చింది.' : 'This comes from your bills automatically.')
      else
        Builder(
          builder: (ctx) => OutlinedButton.icon(
            key: Key('askodoxCashbookStepsRemove-${e['id']}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_remove(e));
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(te ? 'తీసేయి' : 'Remove'),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final entries = askodoxPosList(d?['entries']);
    const monthsTe = ['జనవరి', 'ఫిబ్రవరి', 'మార్చి', 'ఏప్రిల్', 'మే', 'జూన్', 'జూలై', 'ఆగస్టు', 'సెప్టెంబర్', 'అక్టోబర్', 'నవంబర్', 'డిసెంబర్'];
    const monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final monthName = '${(te ? monthsTe : monthsEn)[_month.month - 1]} ${_month.year}';
    return AskodoxStepScaffold(
      key: const Key('askodoxCashbookSteps'),
      title: te ? 'క్యాష్‌బుక్' : 'Cashbook',
      sub: monthName,
      more: [
        AskodoxStepMore('askodoxCashbookStepsPrev', te ? 'ముందు నెల' : 'Previous month', Icons.chevron_left, () => _shift(-1)),
        AskodoxStepMore('askodoxCashbookStepsNext', te ? 'తర్వాత నెల' : 'Next month', Icons.chevron_right, () => _shift(1)),
        AskodoxStepMore('askodoxCashbookStepsFull', te ? 'పాత క్యాష్‌బుక్ పేజీ' : 'Old cashbook page', Icons.menu_book_rounded,
            () => context.push('/biz/${widget.businessId}/money/cashbook?full=1')),
      ],
      body: _error != null && d == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(d['balance_paise'])),
                        label: te ? 'ఈ నెల మిగిలింది' : 'Left this month', size: 40),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          '${te ? 'ఆదాయం' : 'In'} ${askodoxStepRupees(askodoxPosInt(d['income_paise']))} · ${te ? 'ఖర్చు' : 'Out'} ${askodoxStepRupees(askodoxPosInt(d['expense_paise']))}',
                          key: const Key('askodoxCashbookStepsSplit'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఈ నెల ఇంకా ఏమీ లేదు.' : 'Nothing this month yet.',
                            key: const Key('askodoxCashbookStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final e in entries)
                      AskodoxStepPersonRow(
                        key: Key('askodoxCashbookStepsRow-${e['id']}'),
                        name: e['auto'] == true
                            ? (te ? 'బిల్లుల అమ్మకం' : 'Bill sales')
                            : ('${e['note'] ?? ''}'.isNotEmpty ? '${e['note']}' : askodoxCashCategory('${e['category']}', te)),
                        sub: '${e['local_date']} · ${askodoxCashCategory('${e['category']}', te)}',
                        amount: '${e['kind'] == 'income' ? '+' : '−'}${askodoxStepRupees(askodoxPosInt(e['amount_paise']))}',
                        amountColor: e['kind'] == 'income' ? askodoxStepDone : askodoxStepBad,
                        onTap: () => _open(e),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxCashbookStepsAdd'),
        label: te ? 'ఎంట్రీ రాయి' : 'Write an entry',
        icon: Icons.edit_note,
        onPressed: _pickKind,
      ),
    );
  }
}

// ============================================================================ reports
class AskodoxReportsStepsScreen extends ConsumerStatefulWidget {
  const AskodoxReportsStepsScreen({super.key, required this.businessId, this.date = ''});
  final String businessId;

  /// `/biz/:id/reports/day?date=YYYY-MM-DD`: that one day (a night report or a day close opens it).
  final String date;

  @override
  ConsumerState<AskodoxReportsStepsScreen> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<AskodoxReportsStepsScreen> {
  String _period = 'today'; // today / yesterday / 7 / 30 / day (one given date)
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);
  bool get _range => _period == '7' || _period == '30';

  @override
  void initState() {
    super.initState();
    if (widget.date.isNotEmpty) _period = 'day';
    unawaited(_load());
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final d = _range
          ? await repo.reportRange(widget.businessId, days: int.parse(_period))
          : await repo.reportDay(widget.businessId,
              date: _period == 'day'
                  ? widget.date
                  : _ymd(_period == 'yesterday' ? DateTime.now().subtract(const Duration(days: 1)) : DateTime.now()));
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

  String _label(String p, bool te) => switch (p) {
        'day' => widget.date,
        'yesterday' => te ? 'నిన్న' : 'Yesterday',
        '7' => te ? '7 రోజులు' : '7 days',
        '30' => te ? '30 రోజులు' : '30 days',
        _ => te ? 'ఈ రోజు' : 'Today',
      };

  Future<void> _choose() async {
    final te = _te;
    final p = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in const ['today', 'yesterday', '7', '30'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  key: Key('askodoxReportsStepsPeriod-$k'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, k),
                  child: Text(_label(k, te), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (p == null || !mounted || p == _period) return;
    setState(() {
      _period = p;
      _data = null;
    });
    unawaited(_load());
  }

  Future<void> _listen(AskodoxJson r) async {
    final te = _te;
    final text = '${te ? r['say_te'] : r['say_en']}';
    if (text.isEmpty || text == 'null') return;
    try {
      await ref.read(askodoxGuideSpeakerProvider)(text, te ? 'te' : 'en');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final r = _data;
    final sales = askodoxPosMap(r?['sales']);
    final total = _range ? askodoxPosInt(r?['total_paise']) : askodoxPosInt(sales['paise']);
    final bills = _range ? askodoxPosInt(r?['bills']) : askodoxPosInt(sales['bills']);
    final problems = _range ? <AskodoxJson>[] : askodoxPosList(r?['problems']);
    final tops = _range ? askodoxPosList(r?['items_top']) : <AskodoxJson>[];
    return AskodoxStepScaffold(
      key: const Key('askodoxReportsSteps'),
      title: te ? 'రిపోర్ట్స్' : 'Reports',
      sub: _label(_period, te),
      more: [
        if (r != null && !_range)
          AskodoxStepMore('askodoxReportsStepsListen', te ? 'వినండి' : 'Listen', Icons.volume_up_rounded, () => unawaited(_listen(r))),
        AskodoxStepMore('askodoxReportsStepsFull', te ? 'పూర్తి రిపోర్ట్ (పాత పేజీ)' : 'Full report (old page)', Icons.menu_book_rounded,
            () => context.push('/biz/${widget.businessId}/reports?full=1')),
        AskodoxStepMore('askodoxReportsStepsNight', te ? 'రాత్రి రిపోర్ట్' : 'Night report', Icons.nightlight_round,
            () => context.push('/biz/${widget.businessId}/reports/settings')),
      ],
      body: _error != null && r == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(total),
                        label: te ? 'అమ్మకం · $bills బిల్లులు' : 'Sales · $bills bills', size: 40),
                    const SizedBox(height: 10),
                    if (!_range && problems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'సమస్యలు లేవు ✓' : 'No problems ✓',
                            key: const Key('askodoxReportsStepsNone'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                      ),
                    for (final p in problems)
                      Container(
                        key: Key('askodoxReportsStepsProblem-${p['key']}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AskodoxLook.sheet,
                            borderRadius: BorderRadius.circular(14),
                            border: Border(left: BorderSide(color: p['level'] == 'high' ? askodoxStepBad : askodoxStepWarn, width: 6))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${te ? p['text_te'] : p['text_en']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('💡 ${te ? p['do_te'] : p['do_en']}'),
                        ]),
                      ),
                    if (_range && tops.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఈ కాలంలో అమ్మకాలు లేవు.' : 'No sales in this period.',
                            key: const Key('askodoxReportsStepsNoTop'), textAlign: TextAlign.center),
                      ),
                    for (final it in tops)
                      AskodoxStepPersonRow(
                        key: Key('askodoxReportsStepsTop-${it['name']}'),
                        name: '${it['name']}',
                        sub: te ? 'ఎక్కువ అమ్మినవి' : 'Top seller',
                        amount: askodoxStepRupees(askodoxPosInt(it['paise'])),
                        amountColor: askodoxStepDone,
                        onTap: () {},
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxReportsStepsChange'),
        label: te ? 'రోజు మార్చు' : 'Change day',
        icon: Icons.calendar_today,
        onPressed: _choose,
      ),
    );
  }
}
