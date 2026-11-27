import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, work pages batch 1): Live orders `/desk/:id`, Kitchen `/pos/:id/kitchen`,
/// Tables `/pos/:id/tables`, Suppliers & purchases `/pos/:id/suppliers`. One number on top, one list / tiles in the
/// middle, ONE big button at the bottom; the rest in the header ⋮. The old pages stay at `?full=1`.
/// Delivery `/pos/:id/deliveries` is already a 3-step page (what -> who -> follow), so it is not rebuilt here.

String _stage(String s, bool te) => switch (s) {
      'placed' => te ? 'కొత్త' : 'New',
      'accepted' => te ? 'అంగీకరించారు' : 'Accepted',
      'preparing' => te ? 'తయారవుతోంది' : 'Preparing',
      'ready' => te ? 'సిద్ధం' : 'Ready',
      'packed' => te ? 'ప్యాక్' : 'Packed',
      'served' => te ? 'వడ్డించారు' : 'Served',
      'handed' => te ? 'అందజేశారు' : 'Handed over',
      'out_for_delivery' => te ? 'డెలివరీకి వెళ్ళింది' : 'On the way',
      'delivered' => te ? 'డెలివరీ అయింది' : 'Delivered',
      'done' => te ? 'పూర్తి' : 'Done',
      _ => s,
    };

String _kindName(AskodoxJson o, bool te) {
  final table = '${o['table_name'] ?? ''}';
  if (table.isNotEmpty && table != 'null') return te ? 'టేబుల్ $table' : 'Table $table';
  return switch ('${o['kind']}') {
    'dine_in' => te ? 'టేబుల్' : 'Dine in',
    'takeaway' => te ? 'పార్సిల్' : 'Takeaway',
    'delivery' => te ? 'డెలివరీ' : 'Delivery',
    _ => '${o['kind'] ?? ''}',
  };
}

// ============================================================================ live orders
class AskodoxOrdersStepsScreen extends ConsumerStatefulWidget {
  const AskodoxOrdersStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxOrdersStepsScreen> createState() => _OrdersStepsState();
}

class _OrdersStepsState extends ConsumerState<AskodoxOrdersStepsScreen> {
  AskodoxJson? _data;
  Object? _error;
  Timer? _timer;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.deskOrders(widget.businessId);
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

  Future<void> _run(Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  /// Which delivery person: the people the desk offers, delivery people first.
  Future<AskodoxJson?> _pickPerson() async {
    List<AskodoxJson> people = const [];
    try {
      people = await _repo.deskPeople(widget.businessId);
    } on AskodoxPosException {
      people = const [];
    }
    if (!mounted) return null;
    final delivery = people.where((p) => p['role'] == 'delivery').toList();
    final shown = delivery.isNotEmpty ? delivery : people;
    return showModalBottomSheet<AskodoxJson>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
          Text(_te ? 'ఎవరు తీసుకెళ్తారు?' : 'Who takes it?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (shown.isEmpty) Text(_te ? 'సిబ్బంది లేరు. పాత పేజీలో పేరు రాయండి.' : 'No staff. Type a name on the old page.'),
          for (final p in shown)
            ListTile(
              key: Key('askodoxOrdersStepsPerson-${p['id']}'),
              title: Text('${p['you'] == true ? (_te ? 'నేను' : 'Me') : p['label']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              subtitle: Text('${p['role']}'),
              onTap: () => Navigator.pop(ctx, {'id': '${p['id']}', 'label': '${p['label']}'}),
            ),
        ]),
      ),
    );
  }

  Future<void> _tapOrder(AskodoxJson o) async {
    final te = _te;
    final stage = '${o['stage']}';
    final next = o['next_stage'] as String?;
    final billed = o['invoice'] is Map;
    final estimate = askodoxPosInt(o['estimate_paise']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_kindName(o, te)}${'${o['customer_name'] ?? ''}'.isEmpty ? '' : ' · ${o['customer_name']}'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(_stage(stage, te), style: const TextStyle(fontSize: 14, color: askodoxStepMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final i in askodoxPosList(o['items']))
              Text('${i['name']} × ${(i['qty'] as num?)?.round() ?? 1}'
                  '${'${i['note'] ?? ''}'.isEmpty ? '' : ' (${i['note']})'}',
                  style: const TextStyle(fontSize: 16)),
            if ('${o['notes'] ?? ''}'.isNotEmpty) Text('📝 ${o['notes']}'),
            const SizedBox(height: 6),
            Text(askodoxPaise(estimate), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (o['kind'] == 'delivery' && '${o['address'] ?? ''}'.isNotEmpty) Text('${o['address']}'),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (stage == 'placed') ...[
                FilledButton(
                  key: Key('askodoxOrdersStepsAccept-${o['id']}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(150, 54)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final decisions = <String, bool>{
                      for (final i in askodoxPosList(o['items'])) '${i['product_id']}': true,
                    };
                    unawaited(_run(() => _repo.deskConfirm(widget.businessId, '${o['id']}', decisions)));
                  },
                  child: Text(te ? 'అంగీకరించు' : 'Accept', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                OutlinedButton(
                  key: Key('askodoxOrdersStepsReject-${o['id']}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(110, 54)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_run(() => _repo.deskReject(widget.businessId, '${o['id']}', '')));
                  },
                  child: Text(te ? 'వద్దు' : 'Reject'),
                ),
              ] else ...[
                if (next != null && !(next == 'done' && !billed))
                  FilledButton(
                    key: Key('askodoxOrdersStepsNext-${o['id']}'),
                    style: FilledButton.styleFrom(minimumSize: const Size(150, 54)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      var who = '';
                      var whoId = '';
                      if (next == 'out_for_delivery' && '${o['assignee'] ?? ''}'.isEmpty) {
                        final p = await _pickPerson();
                        if (p == null) return;
                        who = '${p['label']}';
                        whoId = '${p['id']}';
                      }
                      await _run(() => _repo.deskAdvance(widget.businessId, '${o['id']}', next, assignee: who, assigneeUser: whoId));
                    },
                    child: Text('→ ${_stage(next, te)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                if (!billed) ...[
                  OutlinedButton(
                    key: Key('askodoxOrdersStepsBillCash-${o['id']}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(110, 54)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_run(() => _repo.deskBill(widget.businessId, '${o['id']}',
                          estimate > 0 ? [{'method': 'cash', 'amount_paise': estimate}] : const [])));
                    },
                    child: Text(te ? 'బిల్లు · క్యాష్' : 'Bill · cash'),
                  ),
                  OutlinedButton(
                    key: Key('askodoxOrdersStepsBillUpi-${o['id']}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(110, 54)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_run(() => _repo.deskBill(widget.businessId, '${o['id']}',
                          estimate > 0 ? [{'method': 'upi', 'amount_paise': estimate}] : const [])));
                    },
                    child: const Text('Bill · UPI'),
                  ),
                  OutlinedButton(
                    key: Key('askodoxOrdersStepsBillLater-${o['id']}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(110, 54)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_run(() => _repo.deskBill(widget.businessId, '${o['id']}', const [])));
                    },
                    child: Text(te ? 'బిల్లు · తర్వాత' : 'Bill · later'),
                  ),
                ],
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  List<AskodoxStepMore> _more() => [
        AskodoxStepMore('askodoxOrdersStepsFull', _te ? 'పాత ఆర్డర్స్ డెస్క్' : 'Old orders desk', Icons.menu_book_rounded,
            () => context.push('/desk/${widget.businessId}?full=1')),
        AskodoxStepMore('askodoxOrdersStepsMenu', _te ? 'మెనూ' : 'Menu', Icons.restaurant_menu_rounded,
            () => context.push('/desk/${widget.businessId}/menu')),
        AskodoxStepMore('askodoxOrdersStepsSales', _te ? 'అమ్మకాలు' : 'Sales', Icons.insights_outlined,
            () => context.push('/desk/${widget.businessId}/sales')),
        AskodoxStepMore('askodoxOrdersStepsSettings', _te ? 'ఆర్డర్ అలర్ట్స్ & సిబ్బంది' : 'Order alerts & staff', Icons.tune_rounded,
            () => context.push('/desk/${widget.businessId}/settings')),
        AskodoxStepMore('askodoxOrdersStepsQr', 'QR', Icons.qr_code_2_rounded, () => context.push('/desk/${widget.businessId}/qr')),
      ];

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final all = askodoxPosList(_data?['orders'])
        .where((o) => !const ['done', 'rejected', 'cancelled'].contains('${o['stage']}'))
        .toList();
    final waiting = all.where((o) => o['stage'] == 'placed').length;
    final shown = [...all.where((o) => o['stage'] == 'placed'), ...all.where((o) => o['stage'] != 'placed')];
    return AskodoxStepScaffold(
      key: const Key('askodoxOrdersSteps'),
      title: te ? 'వచ్చిన ఆర్డర్లు' : 'Live orders',
      more: _more(),
      body: _error != null && _data == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('$waiting', label: te ? 'కొత్త ఆర్డర్లు మీ కోసం' : 'New orders waiting', size: 44),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఇప్పుడు ఆర్డర్లు లేవు.' : 'No orders right now.',
                            key: const Key('askodoxOrdersStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final o in shown)
                      AskodoxStepPersonRow(
                        key: Key('askodoxOrdersStepsRow-${o['id']}'),
                        name: '${_kindName(o, te)}${'${o['customer_name'] ?? ''}'.isEmpty ? '' : ' · ${o['customer_name']}'}',
                        sub: [
                          _stage('${o['stage']}', te),
                          askodoxPosList(o['items']).take(2).map((i) => '${i['name']}').join(', '),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        amount: askodoxPaise(askodoxPosInt(o['estimate_paise'])),
                        amountColor: o['stage'] == 'placed' ? askodoxStepWarn : askodoxStepInk,
                        onTap: () => unawaited(_tapOrder(o)),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxOrdersStepsNew'),
        label: te ? 'కొత్త ఆర్డర్' : 'New order',
        icon: Icons.add_rounded,
        onPressed: () => context.push('/my-shop/sale'),
      ),
    );
  }
}

// ============================================================================ kitchen
class AskodoxKitchenStepsScreen extends ConsumerStatefulWidget {
  const AskodoxKitchenStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxKitchenStepsScreen> createState() => _KitchenStepsState();
}

class _KitchenStepsState extends ConsumerState<AskodoxKitchenStepsScreen> {
  List<AskodoxJson>? _kots;
  Object? _error;
  Timer? _timer;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final k = await _repo.kitchen(widget.businessId);
      if (mounted) {
        setState(() {
          _kots = k;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _kots == null) setState(() => _error = e);
    }
  }

  Future<void> _set(AskodoxJson k, String status) async {
    try {
      await _repo.setKotStatus(widget.businessId, '${k['id']}', status);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
    await _load();
  }

  String _statusName(String s) => switch (s) {
        'new' => _te ? 'కొత్త' : 'New',
        'preparing' => _te ? 'తయారవుతోంది' : 'Preparing',
        'ready' => _te ? 'రెడీ' : 'Ready',
        'served' => _te ? 'వడ్డించాం' : 'Served',
        _ => s,
      };

  Future<void> _tapKot(AskodoxJson k) async {
    final te = _te;
    final status = '${k['status']}';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('KOT ${k['number']} · ${k['table_name'] ?? k['kind'] ?? ''}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final i in askodoxPosList(k['items']))
              Text('• ${askodoxQty(askodoxPosInt(i['qty_milli']), '')} × ${i['name']}'
                  '${'${i['note'] ?? ''}'.isEmpty ? '' : ' — ${i['note']}'}'
                  '${i['status'] == 'void' ? (te ? ' (రద్దు)' : ' (VOID)') : ''}',
                  style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              if (status == 'new')
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(140, 54)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_set(k, 'preparing'));
                  },
                  child: Text(te ? 'తయారవుతోంది' : 'Preparing'),
                ),
              if (status == 'new' || status == 'preparing')
                FilledButton(
                  key: Key('askodoxKitchenStepsReady-${k['number']}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 54)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_set(k, 'ready'));
                  },
                  child: Text(te ? 'రెడీ' : 'Ready', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              if (status == 'ready')
                FilledButton(
                  key: Key('askodoxKitchenStepsServed-${k['number']}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 54)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_set(k, 'served'));
                  },
                  child: Text(te ? 'వడ్డించాం' : 'Served', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
    final kots = _kots;
    final newOnes = kots?.where((k) => k['status'] == 'new').length ?? 0;
    return AskodoxStepScaffold(
      key: const Key('askodoxKitchenSteps'),
      title: te ? 'వంటగది KOT' : 'Kitchen (KOT)',
      more: [
        AskodoxStepMore('askodoxKitchenStepsFull', te ? 'పాత వంటగది పేజీ' : 'Old kitchen page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/kitchen?full=1')),
      ],
      body: _error != null && kots == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : kots == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('$newOnes', label: te ? 'కొత్త టికెట్లు' : 'New tickets', size: 44),
                    const SizedBox(height: 10),
                    if (kots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'పెండింగ్ ఆర్డర్లు లేవు.' : 'No pending tickets.',
                            key: const Key('askodoxKitchenStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final k in kots)
                      AskodoxStepPersonRow(
                        key: Key('askodoxKitchenStepsRow-${k['number']}'),
                        name: 'KOT ${k['number']} · ${k['table_name'] ?? k['kind'] ?? ''}',
                        sub: [
                          _statusName('${k['status']}'),
                          askodoxPosList(k['items']).take(2).map((i) => '${i['name']}').join(', '),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        amount: '${askodoxPosList(k['items']).length}',
                        amountColor: k['status'] == 'ready' ? askodoxStepDone : askodoxStepWarn,
                        onTap: () => unawaited(_tapKot(k)),
                      ),
                  ]),
                ),
    );
  }
}

// ============================================================================ tables
class AskodoxTablesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxTablesStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxTablesStepsScreen> createState() => _TablesStepsState();
}

class _TablesStepsState extends ConsumerState<AskodoxTablesStepsScreen> {
  List<AskodoxJson>? _tables;
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
      final t = await _repo.tables(widget.businessId);
      if (mounted) {
        setState(() {
          _tables = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _tables == null) setState(() => _error = e);
    }
  }

  Future<void> _open({String? tableId, String kind = 'dine_in'}) async {
    try {
      final order = await _repo.openOrder(widget.businessId, tableId: tableId, kind: kind);
      if (!mounted) return;
      await context.push('/pos/${widget.businessId}/order/${order['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    }
    if (mounted) await _load();
  }

  Future<void> _tapTable(AskodoxJson t) async {
    final order = t['order'];
    if (order is Map) {
      await context.push('/pos/${widget.businessId}/order/${order['id']}');
      if (mounted) await _load();
    } else {
      await _open(tableId: '${t['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final tables = _tables;
    final busy = tables?.where((t) => t['order'] is Map).length ?? 0;
    return AskodoxStepScaffold(
      key: const Key('askodoxTablesSteps'),
      title: te ? 'టేబుల్స్' : 'Tables',
      more: [
        AskodoxStepMore('askodoxTablesStepsFull', te ? 'పాత టేబుల్స్ పేజీ (టేబుల్ చేర్చు, రిజర్వేషన్లు)' : 'Old tables page (add table, reservations)',
            Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/tables?full=1')),
        AskodoxStepMore('askodoxTablesStepsWatch', te ? 'టేబుల్ వాచ్ (ఎవరు వేచి ఉన్నారు)' : 'Table watch (who is waiting)',
            Icons.visibility_outlined, () => context.push('/pos/${widget.businessId}/tables/watch')),
        AskodoxStepMore('askodoxTablesStepsKitchen', te ? 'వంటగది' : 'Kitchen', Icons.soup_kitchen_outlined,
            () => context.push('/pos/${widget.businessId}/kitchen')),
      ],
      body: _error != null && tables == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : tables == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('$busy', label: te ? 'నిండిన టేబుల్స్' : 'Busy tables', size: 44),
                    const SizedBox(height: 12),
                    if (tables.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'టేబుల్స్ లేవు. పైన ⋮ నుంచి చేర్చండి.' : 'No tables. Add them from ⋮ above.',
                            key: const Key('askodoxTablesStepsNone'), textAlign: TextAlign.center),
                      ),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final t in tables)
                        SizedBox(
                          width: 150,
                          height: 96,
                          child: InkWell(
                            key: Key('askodoxTablesStepsTable-${t['name']}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => unawaited(_tapTable(t)),
                            child: Ink(
                              decoration: BoxDecoration(
                                color: t['order'] is Map ? const Color(0xFF402804) : askodoxStepGreenSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: t['order'] is Map ? askodoxStepWarn : askodoxStepGreen),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('${t['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: askodoxStepInk)),
                                Text(
                                  t['order'] is Map
                                      ? askodoxPaise(askodoxPosInt(askodoxPosMap(t['order'])['estimate_paise']))
                                      : (te ? 'ఖాళీ' : 'Free'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxTablesStepsTakeaway'),
        label: te ? 'పార్సెల్' : 'Takeaway',
        icon: Icons.takeout_dining_outlined,
        onPressed: () => unawaited(_open(kind: 'takeaway')),
      ),
    );
  }
}

// ============================================================================ suppliers & purchases
class AskodoxSuppliersStepsScreen extends ConsumerStatefulWidget {
  const AskodoxSuppliersStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxSuppliersStepsScreen> createState() => _SuppliersStepsState();
}

class _SuppliersStepsState extends ConsumerState<AskodoxSuppliersStepsScreen> {
  List<AskodoxJson>? _list;
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
      final l = await _repo.suppliers(widget.businessId);
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
    final owed = list?.fold<int>(0, (s, x) => s + askodoxPosInt(x['owed_paise'])) ?? 0;
    return AskodoxStepScaffold(
      key: const Key('askodoxSuppliersSteps'),
      title: te ? 'కొనుగోళ్లు' : 'Purchases',
      more: [
        AskodoxStepMore('askodoxSuppliersStepsFull', te ? 'పాత సప్లయర్ల పేజీ (కొత్త సప్లయర్)' : 'Old suppliers page (new supplier)',
            Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/suppliers?full=1')),
        AskodoxStepMore('askodoxSuppliersStepsOrders', te ? 'కొనుగోలు ఆర్డర్లు' : 'Purchase orders', Icons.assignment_outlined,
            () => context.push('/pos/${widget.businessId}/purchase-orders')),
      ],
      body: _error != null && list == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(owed), label: te ? 'సప్లయర్లకు ఇవ్వాల్సింది' : 'You owe suppliers', size: 40),
                    const SizedBox(height: 10),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ముందు సప్లయర్‌ని చేర్చండి (⋮ → పాత పేజీ).' : 'Add a supplier first (⋮ → old page).',
                            key: const Key('askodoxSuppliersStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final s in list)
                      AskodoxStepPersonRow(
                        key: Key('askodoxSuppliersStepsRow-${s['id']}'),
                        name: '${s['name']}',
                        sub: '${s['gstin'] ?? (te ? 'GST లేదు' : 'no GSTIN')}',
                        amount: askodoxPosInt(s['owed_paise']) > 0 ? askodoxStepRupees(askodoxPosInt(s['owed_paise'])) : '✓',
                        amountColor: askodoxPosInt(s['owed_paise']) > 0 ? askodoxStepWarn : askodoxStepDone,
                        onTap: () async {
                          await context.push('/pos/${widget.businessId}/suppliers/${s['id']}');
                          if (mounted) await _load();
                        },
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxSuppliersStepsNew'),
        label: te ? 'కొనుగోలు బిల్లు' : 'Purchase bill',
        icon: Icons.add_shopping_cart,
        onPressed: () async {
          await context.push('/pos/${widget.businessId}/purchase/new');
          if (mounted) await _load();
        },
      ),
    );
  }
}
