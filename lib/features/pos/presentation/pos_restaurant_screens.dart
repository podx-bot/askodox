import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import '../domain/pos_tax.dart';
import 'pos_common.dart';
import 'pos_sale_screen.dart' show AskodoxPosPaymentSheet;

/// Floor view: tables with their open orders; takeaway / delivery orders below.
class AskodoxPosTablesScreen extends ConsumerStatefulWidget {
  const AskodoxPosTablesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosTablesScreen> createState() => _AskodoxPosTablesScreenState();
}

class _AskodoxPosTablesScreenState extends ConsumerState<AskodoxPosTablesScreen> {
  late Future<(List<AskodoxJson>, List<AskodoxJson>)> _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(askodoxPosRepositoryProvider);
    _data = () async {
      final tables = await repo.tables(widget.businessId);
      final orders = await repo.openOrders(widget.businessId);
      return (tables, orders.where((o) => o['table_id'] == null).toList());
    }();
  }

  Future<void> _open({String? tableId, String kind = 'dine_in'}) async {
    final te = askodoxPosTe(context);
    try {
      final order = await ref.read(askodoxPosRepositoryProvider).openOrder(widget.businessId, tableId: tableId, kind: kind);
      if (!mounted) return;
      await context.push('/pos/${widget.businessId}/order/${order['id']}');
      if (mounted) setState(_load);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _addTable() async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త టేబుల్' : 'New table'),
        content: AskodoxPosField(controller: name, label: te ? 'పేరు (T1, Family 2…)' : 'Name (T1, Family 2…)', maxLength: 30),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).addTable(widget.businessId, name.text.trim());
      if (mounted) setState(_load);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'టేబుల్స్ & ఆర్డర్లు' : 'Tables & orders'),
        actions: [
          IconButton(key: const Key('askodoxPosKitchenOpen'), onPressed: () => context.push('/pos/${widget.businessId}/kitchen'),
              icon: const Icon(Icons.soup_kitchen_outlined)),
          IconButton(key: const Key('askodoxPosAddTable'), onPressed: _addTable, icon: const Icon(Icons.table_restaurant_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxPosTakeaway'),
        onPressed: () => _open(kind: 'takeaway'),
        icon: const Icon(Icons.takeout_dining_outlined),
        label: Text(te ? 'పార్సెల్' : 'Takeaway'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_load),
        child: FutureBuilder<(List<AskodoxJson>, List<AskodoxJson>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final (tables, others) = snap.data!;
            return ListView(key: const Key('askodoxPosTables'), padding: const EdgeInsets.all(12), children: [
              if (tables.isEmpty)
                Text(te ? 'పైన టేబుల్ గుర్తుతో టేబుల్స్ జోడించండి.' : 'Add tables with the table icon above.'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in tables)
                  SizedBox(
                    width: 104,
                    height: 84,
                    child: Card(
                      color: t['order'] == null ? null : const Color(0xFFFFEDD5),
                      child: InkWell(
                        key: ValueKey('askodoxPosTable-${t['name']}'),
                        onTap: () {
                          final order = t['order'];
                          if (order is Map) {
                            context.push('/pos/${widget.businessId}/order/${order['id']}').then((_) {
                              if (mounted) setState(_load);
                            });
                          } else {
                            _open(tableId: '${t['id']}');
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                            if (t['order'] is Map) ...[
                              Text(askodoxPaise(askodoxPosInt(askodoxPosMap(t['order'])['estimate_paise'])), style: const TextStyle(fontSize: 12)),
                              if (askodoxPosInt(askodoxPosMap(t['order'])['pending']) > 0)
                                Text(te ? 'KOT పంపాలి' : 'KOT not sent', style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
                            ] else
                              Text(te ? 'ఖాళీ' : 'Free', style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(te ? 'పార్సెల్ / డెలివరీ' : 'Takeaway / delivery', style: const TextStyle(fontWeight: FontWeight.w800)),
                for (final o in others)
                  ListTile(
                    key: ValueKey('askodoxPosOrderRow-${o['id']}'),
                    title: Text('${o['kind']} · ${askodoxPosInt(o['item_count'])} ${te ? 'ఐటమ్స్' : 'items'}'),
                    trailing: Text(askodoxPaise(askodoxPosInt(o['estimate_paise']))),
                    onTap: () => context.push('/pos/${widget.businessId}/order/${o['id']}').then((_) {
                      if (mounted) setState(_load);
                    }),
                  ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

/// One open order: add menu items with notes, send KOT, move / merge table,
/// void (manager), bill all or chosen items (split bill).
class AskodoxPosOrderScreen extends ConsumerStatefulWidget {
  const AskodoxPosOrderScreen({super.key, required this.businessId, required this.orderId});
  final String businessId;
  final String orderId;

  @override
  ConsumerState<AskodoxPosOrderScreen> createState() => _AskodoxPosOrderScreenState();
}

class _AskodoxPosOrderScreenState extends ConsumerState<AskodoxPosOrderScreen> {
  AskodoxJson? _order;
  List<AskodoxJson> _menu = const [];
  final Set<String> _chosen = {};
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    ref.read(askodoxPosRepositoryProvider).products(widget.businessId).then((m) {
      if (mounted) setState(() => _menu = m);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final o = await ref.read(askodoxPosRepositoryProvider).order(widget.businessId, widget.orderId);
      if (mounted) setState(() => _order = o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  Future<void> _run(Future<AskodoxJson> Function(AskodoxPosRepository repo) action) async {
    final te = askodoxPosTe(context);
    setState(() => _busy = true);
    try {
      final o = await action(ref.read(askodoxPosRepositoryProvider));
      if (mounted) setState(() => _order = o['order'] is Map ? askodoxPosMap(o['order']) : o);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addItem(AskodoxJson product) async {
    final te = askodoxPosTe(context);
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${product['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AskodoxPosField(controller: qty, number: true, label: te ? 'సంఖ్య' : 'Quantity'),
          AskodoxPosField(controller: note, label: te ? 'నోట్ (తక్కువ కారం…)' : 'Note (less spicy…)', maxLength: 120),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxPosOrderAddOk'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'జోడించు' : 'Add')),
        ],
      ),
    );
    final milli = askodoxParseMilli(qty.text);
    if (ok != true || milli == null || milli <= 0 || !mounted) return;
    await _run((repo) => repo.addOrderItems(widget.businessId, widget.orderId, [
          {'product_id': product['id'], 'qty_milli': milli, 'note': note.text.trim(), 'client_txn_id': askodoxNewTxnId()},
        ]));
  }

  Future<String?> _ask(String title) async {
    final te = askodoxPosTe(context);
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: AskodoxPosField(controller: c, label: te ? 'కారణం' : 'Reason'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
        ],
      ),
    );
    return ok == true ? c.text.trim() : null;
  }

  Future<void> _remove(AskodoxJson item) async {
    final te = askodoxPosTe(context);
    var reason = '';
    if (item['status'] == 'sent') {
      final r = await _ask(te ? 'వంటగదికి పంపిన ఐటమ్ రద్దు (మేనేజర్)' : 'Void an item already sent (manager)');
      if (r == null || r.isEmpty) return;
      reason = r;
    }
    await _run((repo) => repo.removeOrderItem(widget.businessId, widget.orderId, '${item['id']}', reason: reason));
  }

  Future<void> _move() async {
    final te = askodoxPosTe(context);
    List<AskodoxJson> tables;
    try {
      tables = await ref.read(askodoxPosRepositoryProvider).tables(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(children: [
        for (final t in tables)
          ListTile(
            title: Text('${t['name']}'),
            subtitle: Text(t['order'] == null ? (te ? 'ఖాళీ' : 'Free') : (te ? 'కలిపేస్తాం (merge)' : 'Has an order — will merge')),
            onTap: () => Navigator.pop(ctx, '${t['id']}'),
          ),
      ]),
    );
    if (picked == null) return;
    await _run((repo) => repo.moveOrder(widget.businessId, widget.orderId, picked));
  }

  Future<void> _bill(AskodoxJson order, {required bool includeUnsent}) async {
    final te = askodoxPosTe(context);
    final items = askodoxPosList(order['items']).where((i) => i['status'] == 'pending' || i['status'] == 'sent').toList();
    final chosen = _chosen.isEmpty ? items : items.where((i) => _chosen.contains(i['id'])).toList();
    final business = ref.read(askodoxPosBusinessProvider(widget.businessId)).valueOrNull;
    final byProduct = {for (final p in _menu) '${p['id']}': p};
    final merged = <String, int>{};
    for (final i in chosen) {
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
    final estimate = preview.totalPaise;
    final payments = await showModalBottomSheet<List<AskodoxJson>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AskodoxPosPaymentSheet(total: estimate, allowCredit: false, te: te),
    );
    if (payments == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final invoice = await ref.read(askodoxPosRepositoryProvider).billOrder(widget.businessId, widget.orderId, {
        'client_txn_id': askodoxNewTxnId(),
        if (_chosen.isNotEmpty) 'item_ids': _chosen.toList(),
        'payments': payments,
        'include_unsent': includeUnsent,
      });
      if (!mounted) return;
      _chosen.clear();
      setState(() => _order = askodoxPosMap(invoice['order']));
      context.push('/pos/${widget.businessId}/invoice/${invoice['id']}');
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
    final te = askodoxPosTe(context);
    final order = _order;
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final q = _search.text.trim().toLowerCase();
    final menu = q.isEmpty ? _menu : _menu.where((p) => '${p['name']}'.toLowerCase().contains(q) || '${p['name_te']}'.contains(q)).toList();
    final open = order != null && order['status'] == 'open';
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null
            ? (te ? 'ఆర్డర్' : 'Order')
            : '${order['table_name'] ?? order['kind']}${order['status'] == 'open' ? '' : ' · ${order['status']}'}'),
        actions: [
          if (open) IconButton(key: const Key('askodoxPosMoveOrder'), onPressed: _busy ? null : _move, icon: const Icon(Icons.swap_horiz)),
          if (open && askodoxPosCan(business, 'cancel'))
            IconButton(
              key: const Key('askodoxPosVoidOrder'),
              onPressed: _busy
                  ? null
                  : () async {
                      final r = await _ask(te ? 'బిల్లు లేకుండా ఆర్డర్ మూసేయాలా?' : 'Close this order without a bill?');
                      if (r != null && r.isNotEmpty) await _run((repo) => repo.voidOrder(widget.businessId, widget.orderId, r));
                    },
              icon: const Icon(Icons.block),
            ),
        ],
      ),
      body: order == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                flex: 4,
                child: ListView(key: const Key('askodoxPosOrderItems'), children: [
                  for (final item in askodoxPosList(order['items']))
                    ListTile(
                      key: ValueKey('askodoxPosOrderItem-${item['id']}'),
                      dense: true,
                      leading: open && (item['status'] == 'pending' || item['status'] == 'sent')
                          ? Checkbox(
                              value: _chosen.contains(item['id']),
                              onChanged: (v) => setState(() => v == true ? _chosen.add('${item['id']}') : _chosen.remove(item['id'])),
                            )
                          : null,
                      title: Text('${item['name']} × ${askodoxQty(askodoxPosInt(item['qty_milli']), '')}',
                          style: TextStyle(decoration: item['status'] == 'void' ? TextDecoration.lineThrough : null)),
                      subtitle: Text([
                        switch ('${item['status']}') {
                          'pending' => te ? 'ఇంకా పంపలేదు' : 'not sent',
                          'sent' => te ? 'వంటగదిలో' : 'in kitchen',
                          'billed' => te ? 'బిల్లు అయింది' : 'billed',
                          _ => te ? 'రద్దు: ${item['void_reason']}' : 'void: ${item['void_reason']}',
                        },
                        if ('${item['note'] ?? ''}'.isNotEmpty) '${item['note']}',
                      ].join(' · ')),
                      trailing: open && (item['status'] == 'pending' || item['status'] == 'sent')
                          ? IconButton(onPressed: _busy ? null : () => _remove(item), icon: const Icon(Icons.close, size: 18))
                          : null,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('${te ? 'అంచనా' : 'Estimate'} ${askodoxPaise(askodoxPosInt(order['estimate_paise']))} · ${order['note']}',
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ]),
              ),
              if (open) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.search),
                        hintText: te ? 'మెనూలో వెతకండి' : 'Search the menu'),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ListView(key: const Key('askodoxPosMenu'), children: [
                    for (final p in menu)
                      ListTile(
                        key: ValueKey('askodoxPosMenuItem-${p['id']}'),
                        dense: true,
                        title: Text(te && '${p['name_te'] ?? ''}'.isNotEmpty ? '${p['name_te']}' : '${p['name']}'),
                        trailing: Text(askodoxPaise(askodoxPosInt(p['price_paise']))),
                        onTap: _busy ? null : () => _addItem(p),
                      ),
                  ]),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('askodoxPosSendKot'),
                          onPressed: _busy || askodoxPosInt(order['pending']) == 0
                              ? null
                              : () => _run((repo) => repo.sendKot(widget.businessId, widget.orderId)),
                          icon: const Icon(Icons.soup_kitchen_outlined),
                          label: Text(te ? 'KOT పంపు (${askodoxPosInt(order['pending'])})' : 'Send KOT (${askodoxPosInt(order['pending'])})'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (askodoxPosCan(business, 'sell'))
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('askodoxPosBillOrder'),
                            onPressed: _busy || askodoxPosInt(order['item_count']) == 0 ? null : () => _bill(order, includeUnsent: false),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(_chosen.isEmpty ? (te ? 'బిల్లు' : 'Bill') : (te ? 'ఎంచినవి బిల్లు' : 'Bill chosen')),
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ]),
    );
  }
}

/// Kitchen display: tickets oldest first; refreshes every 10 s.
class AskodoxPosKitchenScreen extends ConsumerStatefulWidget {
  const AskodoxPosKitchenScreen({super.key, required this.businessId, this.refreshEvery = const Duration(seconds: 10)});
  final String businessId;
  final Duration refreshEvery;

  @override
  ConsumerState<AskodoxPosKitchenScreen> createState() => _AskodoxPosKitchenScreenState();
}

class _AskodoxPosKitchenScreenState extends ConsumerState<AskodoxPosKitchenScreen> {
  List<AskodoxJson>? _kots;
  String? _error;
  Timer? _timer;
  late final AskodoxPosRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(askodoxPosRepositoryProvider);
    _load();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _load());
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
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(askodoxPosTe(context)));
    }
  }

  Future<void> _set(AskodoxJson kot, String status) async {
    try {
      await _repo.setKotStatus(widget.businessId, '${kot['id']}', status);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(askodoxPosTe(context)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final kots = _kots;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'వంటగది (KOT)' : 'Kitchen (KOT)')),
      body: kots == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : Center(child: Text(_error!)))
          : kots.isEmpty
              ? Center(child: Text(te ? 'పెండింగ్ ఆర్డర్లు లేవు.' : 'No pending tickets.', key: const Key('askodoxPosKitchenEmpty')))
              : ListView(key: const Key('askodoxPosKitchen'), padding: const EdgeInsets.all(12), children: [
                  for (final k in kots)
                    Card(
                      key: ValueKey('askodoxPosKot-${k['number']}'),
                      color: switch ('${k['status']}') {
                        'ready' => const Color(0xFFDCFCE7),
                        'preparing' => const Color(0xFFFEF9C3),
                        _ => null,
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('KOT ${k['number']} · ${k['table_name'] ?? k['kind']} · ${k['status']}',
                              style: const TextStyle(fontWeight: FontWeight.w900)),
                          for (final i in askodoxPosList(k['items']))
                            Text('• ${askodoxQty(askodoxPosInt(i['qty_milli']), '')} × ${i['name']}'
                                '${'${i['note'] ?? ''}'.isEmpty ? '' : ' — ${i['note']}'}'
                                '${i['status'] == 'void' ? (te ? ' (రద్దు)' : ' (VOID)') : ''}'),
                          Wrap(spacing: 8, children: [
                            if (k['status'] == 'new')
                              OutlinedButton(onPressed: () => _set(k, 'preparing'), child: Text(te ? 'తయారవుతోంది' : 'Preparing')),
                            if (k['status'] == 'new' || k['status'] == 'preparing')
                              FilledButton(
                                  key: ValueKey('askodoxPosKotReady-${k['number']}'),
                                  onPressed: () => _set(k, 'ready'),
                                  child: Text(te ? 'రెడీ' : 'Ready')),
                            if (k['status'] == 'ready')
                              FilledButton(onPressed: () => _set(k, 'served'), child: Text(te ? 'వడ్డించాం' : 'Served')),
                          ]),
                        ]),
                      ),
                    ),
                ]),
    );
  }
}

/// Held bills and quotations (drafts -- not financial records).
class AskodoxPosDraftsScreen extends ConsumerStatefulWidget {
  const AskodoxPosDraftsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosDraftsScreen> createState() => _AskodoxPosDraftsScreenState();
}

class _AskodoxPosDraftsScreenState extends ConsumerState<AskodoxPosDraftsScreen> {
  late Future<List<AskodoxJson>> _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(askodoxPosRepositoryProvider).drafts(widget.businessId);
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఆపిన బిల్లులు / కొటేషన్లు' : 'Held bills / quotations')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _drafts,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) return Center(child: Text(te ? 'ఏమీ లేవు.' : 'Nothing held.'));
          return ListView(key: const Key('askodoxPosDrafts'), children: [
            for (final d in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosDraft-${d['id']}'),
                leading: Icon(d['kind'] == 'quotation' ? Icons.request_quote_outlined : Icons.pause_circle_outline),
                title: Text('${d['title']}'),
                subtitle: Text('${d['updated_at']}'.split('.').first.replaceFirst('T', ' ')),
                onTap: () => Navigator.of(context).pop(d),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(askodoxPosRepositoryProvider).deleteDraft(widget.businessId, '${d['id']}');
                    if (mounted) {
                      setState(() {
                        _drafts = ref.read(askodoxPosRepositoryProvider).drafts(widget.businessId);
                      });
                    }
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
