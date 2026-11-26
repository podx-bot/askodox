import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/domain/pos_tax.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_sale_screen.dart' show AskodoxPosPaymentSheet, askodoxDefaultUpi;
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 33): one running table / parcel order `/pos/:id/order/:oid`.
/// The job in 3 steps: 1 add items (menu sheet with search) -> 2 send to the kitchen -> 3 bill. Top = the estimate,
/// middle = ONE list of the order's items (tap = take it out; an item already in the kitchen needs a reason),
/// bottom = ONE big button that is always the next step (Add items / Send to kitchen (n) / Bill).
/// Move table, close without a bill (cancel permission), bill only some items, and the old page live in ⋮.
/// Same calls and the same bill arithmetic as the old page (`?full=1`).
class AskodoxTableOrderStepsScreen extends ConsumerStatefulWidget {
  const AskodoxTableOrderStepsScreen({super.key, required this.businessId, required this.orderId});
  final String businessId;
  final String orderId;

  @override
  ConsumerState<AskodoxTableOrderStepsScreen> createState() => _TableOrderStepsState();
}

class _TableOrderStepsState extends ConsumerState<AskodoxTableOrderStepsScreen> {
  AskodoxJson? _order;
  Object? _error;
  List<AskodoxJson> _menu = const [];
  bool _busy = false;
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  final _reason = TextEditingController();
  final _search = TextEditingController();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    unawaited(_repo.sellableProducts(widget.businessId).then((m) {
      if (mounted) setState(() => _menu = m);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final c in [_qty, _note, _reason, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final o = await _repo.order(widget.businessId, widget.orderId);
      if (mounted) {
        setState(() {
          _order = o;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _order == null) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<AskodoxJson> Function() action) async {
    setState(() => _busy = true);
    try {
      final o = await action();
      if (mounted) setState(() => _order = o['order'] is Map ? askodoxPosMap(o['order']) : o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(AskodoxJson p) => _te && '${p['name_te'] ?? ''}'.isNotEmpty ? '${p['name_te']}' : '${p['name'] ?? ''}';

  // ------------------------------------------------------------------ 1 add items
  Future<void> _menuSheet() async {
    final te = _te;
    _search.clear();
    final picked = await showModalBottomSheet<AskodoxJson>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .8,
          child: StatefulBuilder(builder: (ctx, setSheet) {
            final q = _search.text.trim().toLowerCase();
            final rows = q.isEmpty
                ? _menu
                : _menu.where((p) => '${p['name']}'.toLowerCase().contains(q) || '${p['name_te'] ?? ''}'.contains(q)).toList();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(children: [
                AskodoxStepSearch(
                  fieldKey: const Key('askodoxTableOrderStepsSearch'),
                  controller: _search,
                  hint: te ? 'మెనూలో వెతకండి' : 'Search the menu',
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: rows.isEmpty
                      ? Center(child: Text(_menu.isEmpty ? (te ? 'మెనూ లోడ్ అవుతోంది…' : 'Loading the menu…') : (te ? 'దొరకలేదు' : 'Not found')))
                      : ListView(children: [
                          for (final p in rows)
                            AskodoxStepPersonRow(
                              key: ValueKey('askodoxTableOrderStepsMenu-${p['id']}'),
                              name: _name(p),
                              sub: '',
                              amount: askodoxPaise(askodoxPosInt(p['price_paise'])),
                              amountColor: askodoxStepGreen,
                              onTap: () => Navigator.pop(ctx, p),
                            ),
                        ]),
                ),
              ]),
            );
          }),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _addItem(picked);
  }

  Future<void> _addItem(AskodoxJson product) async {
    final te = _te;
    _qty.text = '1';
    _note.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_name(product)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('askodoxTableOrderStepsQty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              decoration: InputDecoration(labelText: te ? 'సంఖ్య' : 'Quantity', border: const OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: _note,
              maxLength: 120,
              decoration: InputDecoration(labelText: te ? 'నోట్ (తక్కువ కారం…)' : 'Note (less spicy…)', border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(
              key: const Key('askodoxTableOrderStepsAddOk'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'జోడించు' : 'Add')),
        ],
      ),
    );
    final milli = askodoxParseMilli(_qty.text);
    if (ok != true || milli == null || milli <= 0 || !mounted) return;
    final note = _note.text.trim();
    await _run(() => _repo.addOrderItems(widget.businessId, widget.orderId, [
          {'product_id': product['id'], 'qty_milli': milli, 'note': note, 'client_txn_id': askodoxNewTxnId()},
        ]));
  }

  Future<String?> _askReason(String title) async {
    final te = _te;
    _reason.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            key: const Key('askodoxTableOrderStepsReason'),
            controller: _reason,
            decoration: InputDecoration(labelText: te ? 'కారణం' : 'Reason', border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(
              key: const Key('askodoxTableOrderStepsReasonYes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(te ? 'అవును' : 'Yes')),
        ],
      ),
    );
    return ok == true ? _reason.text.trim() : null;
  }

  Future<void> _item(AskodoxJson item) async {
    final te = _te;
    final status = '${item['status']}';
    if (status != 'pending' && status != 'sent') return;
    var reason = '';
    if (status == 'sent') {
      final r = await _askReason(te ? 'వంటగదికి పంపిన ఐటమ్ రద్దు (మేనేజర్)' : 'Void an item already sent (manager)');
      if (r == null || r.isEmpty) return;
      reason = r;
    } else {
      final sure = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(te ? '${item['name']} తీసేయాలా?' : 'Take out ${item['name']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(te ? 'వద్దు' : 'No')),
            FilledButton(
                key: const Key('askodoxTableOrderStepsRemoveYes'),
                onPressed: () => Navigator.pop(d, true),
                child: Text(te ? 'తీసేయి' : 'Take out')),
          ],
        ),
      );
      if (sure != true) return;
    }
    if (!mounted) return;
    await _run(() => _repo.removeOrderItem(widget.businessId, widget.orderId, '${item['id']}', reason: reason));
  }

  // ------------------------------------------------------------------ ⋮
  Future<void> _move() async {
    final te = _te;
    List<AskodoxJson> tables;
    try {
      tables = await _repo.tables(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          for (final t in tables)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxTableOrderStepsMoveTo-${t['id']}'),
              name: '${t['name']}',
              sub: t['order'] == null ? (te ? 'ఖాళీ' : 'Free') : (te ? 'కలిపేస్తాం (merge)' : 'Has an order — will merge'),
              amount: '›',
              amountColor: askodoxStepGreen,
              onTap: () => Navigator.pop(ctx, '${t['id']}'),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    await _run(() => _repo.moveOrder(widget.businessId, widget.orderId, picked));
  }

  Future<void> _close() async {
    final te = _te;
    final r = await _askReason(te ? 'బిల్లు లేకుండా ఆర్డర్ మూసేయాలా?' : 'Close this order without a bill?');
    if (r == null || r.isEmpty || !mounted) return;
    await _run(() => _repo.voidOrder(widget.businessId, widget.orderId, r));
  }

  // ------------------------------------------------------------------ 3 bill
  Future<void> _bill(AskodoxJson order, {required bool includeUnsent}) async {
    final te = _te;
    final items = askodoxPosList(order['items']).where((i) => i['status'] == 'pending' || i['status'] == 'sent').toList();
    final business = ref.read(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final byProduct = {for (final p in _menu) '${p['id']}': p};
    final merged = <String, int>{};
    for (final i in items) {
      merged['${i['product_id']}'] = (merged['${i['product_id']}'] ?? 0) + askodoxPosInt(i['qty_milli']);
    }
    if (business == null || merged.keys.any((id) => !byProduct.containsKey(id))) {
      askodoxPosSnack(context, te ? 'మెనూ ఇంకా లోడ్ కాలేదు.' : 'The menu is still loading.');
      return;
    }
    // Same arithmetic as the server (shared vectors); the issued bill is the final one.
    final preview = askodoxInvoicePreview([
      for (final e in merged.entries)
        AskodoxLineInput(
          qtyMilli: e.value,
          unitPricePaise: askodoxPosInt(byProduct[e.key]!['price_paise']),
          rateBp: askodoxPosInt(byProduct[e.key]!['rate_bp']),
          cessBp: askodoxPosInt(byProduct[e.key]!['cess_bp']),
          priceIncludesTax: byProduct[e.key]!['price_includes_tax'] == true,
          category: '${byProduct[e.key]!['category'] ?? 'taxable'}',
        ),
    ], registrationType: '${business['registration_type']}', businessState: '${business['state_code']}');
    final payments = await showModalBottomSheet<List<AskodoxJson>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosPaymentSheet(
        total: preview.totalPaise,
        allowCredit: false,
        te: te,
        // Owner 2026-11-24: table / parcel / delivery bills show the OWNER's own UPI QR too.
        shopUpi: () => _repo.myPaymentMethods().then(askodoxDefaultUpi, onError: (_) => null),
      ),
    );
    if (payments == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final invoice = await _repo.billOrder(widget.businessId, widget.orderId, {
        'client_txn_id': askodoxNewTxnId(),
        'payments': payments,
        'include_unsent': includeUnsent,
      });
      if (!mounted) return;
      setState(() => _order = askodoxPosMap(invoice['order']));
      context.push('/pos/${widget.businessId}/invoice/${invoice['id']}?fresh=1');
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (e.code == 'unsent') {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(te ? 'కొన్ని ఐటమ్స్ వంటగదికి పంపలేదు. అయినా బిల్లు చేయాలా?' : 'Some items were never sent to the kitchen. Bill them anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
            ],
          ),
        );
        if (go == true && mounted) await _bill(order, includeUnsent: true);
      } else {
        askodoxPosSnack(context, e.message(te));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final order = _order;
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final open = order != null && order['status'] == 'open';
    final full = AskodoxStepMore('askodoxTableOrderStepsFull', te ? 'పాత పేజీ (కొన్ని ఐటమ్స్ మాత్రమే బిల్లు)' : 'Old page (bill only some items)',
        Icons.menu_book_rounded, () => context.push('/pos/${widget.businessId}/order/${widget.orderId}?full=1').then((_) => _refresh()));
    final title = order == null ? (te ? 'ఆర్డర్' : 'Order') : '${order['table_name'] ?? order['kind'] ?? ''}';
    if (_error != null) return AskodoxStepScaffold(title: title, more: [full], body: AskodoxPosError(error: _error!, onRetry: _refresh));
    if (order == null) return AskodoxStepScaffold(title: title, more: [full], body: const Center(child: CircularProgressIndicator()));
    final pending = askodoxPosInt(order['pending']);
    final count = askodoxPosInt(order['item_count']);
    final canSell = askodoxPosCan(business, 'sell');
    final step = !open ? 0 : (pending > 0 ? 2 : (count > 0 ? 3 : 1));
    final more = [
      if (open) AskodoxStepMore('askodoxTableOrderStepsMove', te ? 'టేబుల్ మార్చు' : 'Move table', Icons.swap_horiz_rounded, _move),
      if (open && askodoxPosCan(business, 'cancel'))
        AskodoxStepMore('askodoxTableOrderStepsClose', te ? 'బిల్లు లేకుండా మూసేయి' : 'Close without a bill', Icons.block_rounded, _close),
      full,
    ];
    Widget? bottom;
    if (open && !_busy) {
      if (pending > 0) {
        bottom = AskodoxStepBottom(
          buttonKey: const Key('askodoxTableOrderStepsKot'),
          label: te ? 'వంటగదికి పంపు ($pending)' : 'Send to kitchen ($pending)',
          icon: Icons.soup_kitchen_outlined,
          onPressed: () => _run(() => _repo.sendKot(widget.businessId, widget.orderId)),
        );
      } else if (count > 0 && canSell) {
        bottom = AskodoxStepBottom(
          buttonKey: const Key('askodoxTableOrderStepsBill'),
          label: te ? 'బిల్లు' : 'Bill',
          icon: Icons.receipt_long_outlined,
          onPressed: () => _bill(order, includeUnsent: false),
        );
      } else {
        bottom = AskodoxStepBottom(
          buttonKey: const Key('askodoxTableOrderStepsAdd'),
          label: te ? 'ఐటమ్స్ జోడించు' : 'Add items',
          icon: Icons.add_rounded,
          onPressed: _menuSheet,
        );
      }
    } else if (open) {
      bottom = const AskodoxStepBottom(label: '…', busy: true);
    }
    return AskodoxStepScaffold(
      key: const Key('askodoxTableOrderSteps'),
      title: title,
      sub: open ? '' : '${order['status']}',
      step: step,
      more: more,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          AskodoxStepBigNumber(askodoxPaise(askodoxPosInt(order['estimate_paise'])),
              key: const Key('askodoxTableOrderStepsTotal'), label: te ? 'అంచనా' : 'Estimate'),
          if ('${order['note'] ?? ''}'.isNotEmpty)
            Text('${order['note']}', textAlign: TextAlign.center, style: const TextStyle(color: askodoxStepMuted)),
          const SizedBox(height: 8),
          if (open)
            OutlinedButton.icon(
              key: const Key('askodoxTableOrderStepsAddMore'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _menuSheet,
              icon: const Icon(Icons.add_rounded),
              label: Text(te ? 'ఐటమ్స్ జోడించు' : 'Add items', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          const SizedBox(height: 6),
          for (final item in askodoxPosList(order['items']))
            AskodoxStepPersonRow(
              key: ValueKey('askodoxTableOrderStepsItem-${item['id']}'),
              name: '${item['name']} × ${askodoxQty(askodoxPosInt(item['qty_milli']), '')}',
              sub: [
                switch ('${item['status']}') {
                  'pending' => te ? 'ఇంకా పంపలేదు' : 'not sent',
                  'sent' => te ? 'వంటగదిలో' : 'in kitchen',
                  'billed' => te ? 'బిల్లు అయింది' : 'billed',
                  _ => te ? 'రద్దు: ${item['void_reason'] ?? ''}' : 'void: ${item['void_reason'] ?? ''}',
                },
                if ('${item['note'] ?? ''}'.isNotEmpty) '${item['note']}',
              ].join(' · '),
              amount: switch ('${item['status']}') { 'pending' => '•', 'sent' => '🍳', 'billed' => '✓', _ => '✕' },
              amountColor: '${item['status']}' == 'pending' ? askodoxStepWarn : askodoxStepDone,
              onTap: () => open && !_busy ? _item(item) : null,
            ),
        ]),
      ),
      bottom: bottom,
    );
  }
}
