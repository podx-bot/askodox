import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import '../domain/pos_tax.dart';
import 'pos_common.dart';

/// Suppliers with what the shop owes them; add supplier; record a purchase bill.
class AskodoxPosSuppliersScreen extends ConsumerStatefulWidget {
  const AskodoxPosSuppliersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosSuppliersScreen> createState() => _AskodoxPosSuppliersScreenState();
}

class _AskodoxPosSuppliersScreenState extends ConsumerState<AskodoxPosSuppliersScreen> {
  late Future<List<AskodoxJson>> _list;

  @override
  void initState() {
    super.initState();
    _list = ref.read(askodoxPosRepositoryProvider).suppliers(widget.businessId);
  }

  void _reload() => setState(() => _list = ref.read(askodoxPosRepositoryProvider).suppliers(widget.businessId));

  Future<void> _add() async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final phone = TextEditingController();
    final gstin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త సప్లయర్' : 'New supplier'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(controller: name, label: te ? 'పేరు' : 'Name'),
            AskodoxPosField(controller: phone, number: true, decimal: false, label: te ? 'ఫోన్' : 'Phone'),
            AskodoxPosField(controller: gstin, label: 'GSTIN', maxLength: 15),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).addSupplier(widget.businessId, {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        if (gstin.text.trim().isNotEmpty) 'gstin': gstin.text.trim().toUpperCase(),
      });
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'సప్లయర్లు & కొనుగోళ్లు' : 'Suppliers & purchases'),
        actions: [
          IconButton(
              key: const Key('askodoxPosOpenPos'),
              tooltip: te ? 'కొనుగోలు ఆర్డర్లు' : 'Purchase orders',
              onPressed: () => context.push('/pos/${widget.businessId}/purchase-orders'),
              icon: const Icon(Icons.assignment_outlined)),
          IconButton(key: const Key('askodoxPosAddSupplier'), onPressed: _add, icon: const Icon(Icons.person_add_alt)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxPosNewPurchase'),
        onPressed: () async {
          await context.push('/pos/${widget.businessId}/purchase/new');
          if (mounted) _reload();
        },
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(te ? 'కొనుగోలు బిల్లు' : 'Purchase bill'),
      ),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) return Center(child: Text(te ? 'ముందు సప్లయర్‌ని జోడించండి.' : 'Add a supplier first.'));
          return ListView(key: const Key('askodoxPosSuppliers'), children: [
            for (final s in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosSupplier-${s['id']}'),
                title: Text('${s['name']}'),
                subtitle: Text('${s['gstin'] ?? (te ? 'GST లేదు' : 'no GSTIN')}'),
                trailing: Text('${te ? 'ఇవ్వాలి' : 'owe'} ${askodoxPaise(askodoxPosInt(s['owed_paise']))}'),
                onTap: () async {
                  await context.push('/pos/${widget.businessId}/suppliers/${s['id']}');
                  if (mounted) _reload();
                },
              ),
          ]);
        },
      ),
    );
  }
}

/// One supplier: monthly statement, purchase bills, record a payment.
class AskodoxPosSupplierScreen extends ConsumerStatefulWidget {
  const AskodoxPosSupplierScreen({super.key, required this.businessId, required this.supplierId});
  final String businessId;
  final String supplierId;

  @override
  ConsumerState<AskodoxPosSupplierScreen> createState() => _AskodoxPosSupplierScreenState();
}

class _AskodoxPosSupplierScreenState extends ConsumerState<AskodoxPosSupplierScreen> {
  late String _month;
  late Future<(AskodoxJson, List<AskodoxJson>)> _data;

  @override
  void initState() {
    super.initState();
    _month = askodoxPosToday().substring(0, 7);
    _load();
  }

  void _load() {
    final repo = ref.read(askodoxPosRepositoryProvider);
    _data = () async {
      final st = await repo.supplierStatement(widget.businessId, widget.supplierId, _month);
      final bills = await repo.purchases(widget.businessId, supplierId: widget.supplierId);
      return (st, bills);
    }();
  }

  void _shift(int delta) {
    final d = DateTime(int.parse(_month.substring(0, 4)), int.parse(_month.substring(5)) + delta);
    setState(() {
      _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      _load();
    });
  }

  Future<void> _pay() async {
    final te = askodoxPosTe(context);
    final amount = TextEditingController();
    final reference = TextEditingController();
    var method = 'bank_transfer';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(te ? 'సప్లయర్‌కి చెల్లింపు' : 'Paid to supplier'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              for (final m in ['cash', 'upi', 'bank_transfer', 'cheque'])
                ChoiceChip(label: Text(m), selected: method == m, onSelected: (_) => setLocal(() => method = m)),
            ]),
            AskodoxPosField(controller: amount, number: true, label: te ? 'మొత్తం (₹)' : 'Amount (₹)'),
            AskodoxPosField(controller: reference, label: te ? 'రిఫరెన్స్' : 'Reference'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final paise = askodoxParsePaise(amount.text);
    if (ok != true || paise == null || paise <= 0 || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).paySupplier(widget.businessId, widget.supplierId,
          {'client_txn_id': askodoxNewTxnId(), 'method': method, 'amount_paise': paise, 'reference': reference.text.trim()});
      setState(_load);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సప్లయర్ ఖాతా' : 'Supplier account')),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('askodoxPosPaySupplier'), onPressed: _pay, icon: const Icon(Icons.currency_rupee), label: Text(te ? 'చెల్లించాం' : 'Paid')),
      body: FutureBuilder<(AskodoxJson, List<AskodoxJson>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (st, bills) = snap.data!;
          return ListView(key: const Key('askodoxPosSupplierStatement'), padding: const EdgeInsets.all(12), children: [
            Text('${askodoxPosMap(st['supplier'])['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Text(_month, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ]),
            ListTile(dense: true, title: Text(te ? 'మొదటి బాకీ' : 'Opening'), trailing: Text(askodoxPaise(askodoxPosInt(st['opening_paise'])))),
            for (final e in askodoxPosList(st['entries']))
              ListTile(
                dense: true,
                title: Text('${e['local_date']} · ${e['note']}'),
                trailing: Text(askodoxPosInt(e['owed_paise']) != 0
                    ? '+${askodoxPaise(askodoxPosInt(e['owed_paise']))}'
                    : '−${askodoxPaise(askodoxPosInt(e['paid_paise']))}'),
              ),
            ListTile(
              title: Text(te ? 'ఇవ్వాల్సింది' : 'You owe', style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Text(askodoxPaise(askodoxPosInt(st['closing_paise'])), key: const Key('askodoxPosSupplierOwed'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const Divider(),
            Text(te ? 'కొనుగోలు బిల్లులు' : 'Purchase bills', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final b in bills)
              ListTile(
                dense: true,
                title: Text('${b['supplier_bill_no']} · ${b['bill_date']}'),
                subtitle: b['status'] == 'cancelled' ? Text(te ? 'రద్దు' : 'cancelled') : null,
                trailing: Text(askodoxPaise(askodoxPosInt(b['total_paise']))),
              ),
          ]);
        },
      ),
    );
  }
}

class _PurchaseLine {
  _PurchaseLine(this.product);
  final AskodoxJson product;
  final qty = TextEditingController();
  final cost = TextEditingController();
  final batch = TextEditingController();
  final expiry = TextEditingController();
  final serials = TextEditingController();
  late int rateBp = askodoxPosInt(product['rate_bp']);
  String? pack;

  List<String> get serialList =>
      [for (final s in serials.text.split(RegExp(r'[\s,]+'))) if (s.trim().isNotEmpty) s.trim().toUpperCase()];
}

/// Record a supplier's bill: lines with cost BEFORE GST, batch / expiry for batch items,
/// and the supplier's printed total to catch typing mistakes.
class AskodoxPosPurchaseScreen extends ConsumerStatefulWidget {
  const AskodoxPosPurchaseScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosPurchaseScreen> createState() => _AskodoxPosPurchaseScreenState();
}

class _AskodoxPosPurchaseScreenState extends ConsumerState<AskodoxPosPurchaseScreen> {
  List<AskodoxJson> _suppliers = const [];
  List<AskodoxJson> _products = const [];
  String? _supplierId;
  final _billNo = TextEditingController();
  final _total = TextEditingController();
  final List<_PurchaseLine> _lines = [];
  final List<_PurchaseLine> _created = [];
  bool _busy = false;
  String? _error;
  final _txn = askodoxNewTxnId();

  static const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

  @override
  void initState() {
    super.initState();
    final repo = ref.read(askodoxPosRepositoryProvider);
    repo.suppliers(widget.businessId).then((s) {
      if (mounted) setState(() => _suppliers = s);
    }).catchError((_) {});
    repo.products(widget.businessId).then((p) {
      if (mounted) setState(() => _products = p);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _billNo.dispose();
    _total.dispose();
    for (final l in _created) {
      for (final c in [l.qty, l.cost, l.batch, l.expiry, l.serials]) {
        c.dispose();
      }
    }
    super.dispose();
  }

  /// Same arithmetic as the server (cost before GST; GST only from a registered supplier).
  int? _computed(AskodoxJson? business) {
    final supplier = _suppliers.where((s) => s['id'] == _supplierId).firstOrNull;
    if (supplier == null || business == null || _lines.isEmpty) return null;
    final registered = supplier['gstin'] != null;
    final inter = (supplier['state_code'] ?? business['state_code']) != business['state_code'];
    var total = 0;
    for (final l in _lines) {
      final q = askodoxParseMilli(l.qty.text);
      final c = askodoxParsePaise(l.cost.text);
      if (q == null || q <= 0 || c == null) return null;
      total += askodoxLineTax(AskodoxLineInput(qtyMilli: q, unitPricePaise: c, rateBp: l.rateBp), interState: inter, collectTax: registered)
          .totalPaise;
    }
    return total;
  }

  Future<void> _addLine() async {
    final te = askodoxPosTe(context);
    final picked = await showModalBottomSheet<AskodoxJson>(
      context: context,
      builder: (ctx) => ListView(children: [
        for (final p in _products)
          ListTile(title: Text('${p['name']}'), subtitle: Text('${p['unit']}${p['track_batches'] == true ? (te ? ' · బ్యాచ్' : ' · batch') : ''}'),
              onTap: () => Navigator.pop(ctx, p)),
      ]),
    );
    if (picked == null) return;
    final line = _PurchaseLine(picked);
    _created.add(line);
    setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    if (_supplierId == null || _billNo.text.trim().isEmpty || _lines.isEmpty) {
      setState(() => _error = te ? 'సప్లయర్, బిల్లు నంబర్, కనీసం ఒక లైన్ కావాలి.' : 'Supplier, bill number and at least one line are needed.');
      return;
    }
    final lines = <AskodoxJson>[];
    for (final l in _lines) {
      final q = askodoxParseMilli(l.qty.text);
      final c = askodoxParsePaise(l.cost.text);
      if (q == null || q <= 0 || c == null) {
        setState(() => _error = te ? '${l.product['name']}: పరిమాణం, ధర నమోదు చేయండి.' : '${l.product['name']}: enter quantity and cost.');
        return;
      }
      lines.add({
        'product_id': l.product['id'],
        'qty_milli': q,
        'cost_paise': c,
        'rate_bp': l.rateBp,
        if (l.batch.text.trim().isNotEmpty) 'batch_no': l.batch.text.trim(),
        if (l.expiry.text.trim().isNotEmpty) 'expiry_date': l.expiry.text.trim(),
        if (l.pack != null) 'pack': l.pack,
        if (l.product['track_serials'] == true) 'serials': l.serialList,
      });
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(askodoxPosRepositoryProvider).recordPurchase(widget.businessId, {
        'client_txn_id': _txn,
        'supplier_id': _supplierId,
        'supplier_bill_no': _billNo.text.trim(),
        'lines': lines,
        if (askodoxParsePaise(_total.text) != null) 'supplier_total_paise': askodoxParsePaise(_total.text),
      });
      if (mounted) Navigator.of(context).pop();
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final computed = _computed(ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కొనుగోలు బిల్లు నమోదు' : 'Record purchase bill')),
      body: ListView(key: const Key('askodoxPosPurchaseForm'), padding: const EdgeInsets.all(12), children: [
        DropdownButtonFormField<String>(
          key: const Key('askodoxPosPurchaseSupplier'),
          initialValue: _supplierId,
          isExpanded: true,
          decoration: InputDecoration(labelText: te ? 'సప్లయర్' : 'Supplier', border: const OutlineInputBorder(), isDense: true),
          items: [for (final s in _suppliers) DropdownMenuItem(value: '${s['id']}', child: Text('${s['name']}'))],
          onChanged: (v) => setState(() => _supplierId = v),
        ),
        const SizedBox(height: 10),
        AskodoxPosField(controller: _billNo, label: te ? 'సప్లయర్ బిల్లు నంబర్' : 'Supplier bill number', maxLength: 40),
        for (var i = 0; i < _lines.length; i++)
          Card(
            key: ValueKey('askodoxPosPurchaseLine-$i'),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${_lines[i].product['name']} (${_lines[i].product['unit']})', style: const TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => setState(() => _lines.removeAt(i)), icon: const Icon(Icons.close, size: 18)),
                ]),
                Row(children: [
                  Expanded(child: AskodoxPosField(controller: _lines[i].qty, number: true, label: te ? 'పరిమాణం' : 'Qty', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: AskodoxPosField(
                          controller: _lines[i].cost, number: true, label: te ? 'ధర (GST ముందు)' : 'Cost before GST', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 6),
                  DropdownButton<int>(
                    value: _lines[i].rateBp,
                    items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
                    onChanged: (v) => setState(() => _lines[i].rateBp = v ?? _lines[i].rateBp),
                  ),
                ]),
                if (askodoxPosList(_lines[i].product['packs']).isNotEmpty)
                  Wrap(spacing: 6, children: [
                    ChoiceChip(
                        label: Text('${_lines[i].product['unit']}'),
                        selected: _lines[i].pack == null,
                        onSelected: (_) => setState(() => _lines[i].pack = null)),
                    for (final k in askodoxPosList(_lines[i].product['packs']))
                      ChoiceChip(
                          label: Text('${k['name']}'),
                          selected: _lines[i].pack == k['name'],
                          onSelected: (_) => setState(() => _lines[i].pack = '${k['name']}')),
                  ]),
                if (_lines[i].product['track_serials'] == true)
                  TextField(
                    key: ValueKey('askodoxPosPurchaseSerials-$i'),
                    controller: _lines[i].serials,
                    minLines: 2,
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      labelText: _lines[i].product['serial_kind'] == 'imei'
                          ? (te ? 'IMEI లు (ఒక్కో లైన్‌కి ఒకటి) — ${_lines[i].serialList.length}' : 'IMEIs (one per line) — ${_lines[i].serialList.length}')
                          : (te ? 'సీరియల్స్ (ఒక్కో లైన్‌కి ఒకటి) — ${_lines[i].serialList.length}' : 'Serials (one per line) — ${_lines[i].serialList.length}'),
                    ),
                  ),
                if (_lines[i].product['track_batches'] == true)
                  Row(children: [
                    Expanded(child: AskodoxPosField(controller: _lines[i].batch, label: te ? 'బ్యాచ్ నంబర్' : 'Batch no.', maxLength: 40)),
                    const SizedBox(width: 6),
                    Expanded(child: AskodoxPosField(controller: _lines[i].expiry, label: te ? 'ఎక్స్‌పైరీ (YYYY-MM-DD)' : 'Expiry (YYYY-MM-DD)', maxLength: 10)),
                  ]),
              ]),
            ),
          ),
        TextButton.icon(
          key: const Key('askodoxPosPurchaseAddLine'),
          onPressed: _products.isEmpty ? null : _addLine,
          icon: const Icon(Icons.add),
          label: Text(te ? 'లైన్ జోడించు' : 'Add line'),
        ),
        AskodoxPosField(controller: _total, number: true, label: te ? 'బిల్లుపై ఉన్న మొత్తం (₹) — సరిచూడటానికి' : 'Total printed on the bill (₹) — to check'),
        if (computed != null)
          Text('${te ? 'లెక్క' : 'Computed'}: ${askodoxPaise(computed)}', key: const Key('askodoxPosPurchaseComputed'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          te
              ? 'GST నమోదైన సప్లయర్ బిల్లుకే GST లెక్కిస్తాం. ఇన్‌పుట్ ట్యాక్స్ క్రెడిట్ అర్హత మీ అకౌంటెంట్ నిర్ణయం.'
              : 'GST is counted only for a registered supplier. Input tax credit eligibility is your accountant\'s call.',
          style: const TextStyle(fontSize: 11.5),
        ),
        if (_error != null) Text(_error!, key: const Key('askodoxPosPurchaseError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(key: const Key('askodoxPosPurchaseSave'), onPressed: _busy ? null : _save, child: Text(te ? 'నమోదు చేయి' : 'Record bill')),
      ]),
    );
  }
}

/// Batches expiring soon (or already expired) and stock value at average purchase cost.
class AskodoxPosStockReportScreen extends ConsumerWidget {
  const AskodoxPosStockReportScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఎక్స్‌పైరీ & స్టాక్ విలువ' : 'Expiry & stock value'), actions: [
        IconButton(
          key: const Key('askodoxPosSerialLookup'),
          tooltip: te ? 'సీరియల్ / IMEI వెతుకు' : 'Find serial / IMEI',
          onPressed: () => askodoxSerialLookup(context, ref, businessId),
          icon: const Icon(Icons.manage_search),
        ),
      ]),
      body: FutureBuilder<(AskodoxJson, AskodoxJson?)>(
        future: () async {
          final expiry = await repo.expiryReport(businessId, days: 60);
          AskodoxJson? value;
          try {
            value = await repo.valuation(businessId);
          } on AskodoxPosException {
            value = null; // the role may not see reports
          }
          return (expiry, value);
        }(),
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (expiry, value) = snap.data!;
          final items = askodoxPosList(expiry['items']);
          return ListView(key: const Key('askodoxPosStockReport'), padding: const EdgeInsets.all(12), children: [
            Text(te ? '60 రోజుల్లో ఎక్స్‌పైర్ అయ్యేవి' : 'Expiring within 60 days', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (items.isEmpty) Text(te ? 'ఏమీ లేవు.' : 'None.'),
            for (final i in items)
              ListTile(
                key: ValueKey('askodoxPosExpiry-${i['batch_no']}'),
                dense: true,
                leading: Icon(i['expired'] == true ? Icons.dangerous_outlined : Icons.schedule, color: i['expired'] == true ? const Color(0xFFB91C1C) : null),
                title: Text('${i['name']} · ${te ? 'బ్యాచ్' : 'batch'} ${i['batch_no']}'),
                subtitle: Text('${i['expiry_date']}${i['expired'] == true ? (te ? ' · ఎక్స్‌పైర్ అయింది — అమ్మకానికి రాదు' : ' · EXPIRED — cannot be sold') : ''}'),
                trailing: Text(askodoxQty(askodoxPosInt(i['qty_milli']), '${i['unit']}')),
              ),
            if (value != null) ...[
              const Divider(),
              Text('${te ? 'స్టాక్ విలువ' : 'Stock value'}: ${askodoxPaise(askodoxPosInt(value['total_value_paise']))}',
                  key: const Key('askodoxPosStockValue'), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${value['method']}${askodoxPosInt(value['items_without_cost']) > 0 ? ' · ${value['items_without_cost']} ${te ? 'సరుకులకు ధర తెలియదు' : 'items without a recorded cost'}' : ''}',
                  style: const TextStyle(fontSize: 11.5)),
            ],
          ]);
        },
      ),
    );
  }
}


/// Purchase orders: what the shop asks a supplier for. Not stock and not money owed
/// until the supplier's bill is recorded against the order.
class AskodoxPosPurchaseOrdersScreen extends ConsumerStatefulWidget {
  const AskodoxPosPurchaseOrdersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosPurchaseOrdersScreen> createState() => _AskodoxPosPurchaseOrdersScreenState();
}

class _AskodoxPosPurchaseOrdersScreenState extends ConsumerState<AskodoxPosPurchaseOrdersScreen> {
  late Future<List<AskodoxJson>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = ref.read(askodoxPosRepositoryProvider).purchaseOrders(widget.businessId);
  }

  void _reload() => setState(() => _orders = ref.read(askodoxPosRepositoryProvider).purchaseOrders(widget.businessId));

  Future<void> _create() async {
    final te = askodoxPosTe(context);
    final repo = ref.read(askodoxPosRepositoryProvider);
    List<AskodoxJson> suppliers;
    List<AskodoxJson> products;
    try {
      suppliers = await repo.suppliers(widget.businessId);
      products = await repo.products(widget.businessId);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
      return;
    }
    if (!mounted) return;
    if (suppliers.isEmpty || products.isEmpty) {
      askodoxPosSnack(context, te ? 'ముందు సప్లయర్, సరుకులు జోడించండి.' : 'Add a supplier and items first.');
      return;
    }
    String supplierId = '${suppliers.first['id']}';
    final lines = <(AskodoxJson, TextEditingController, String?)>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(te ? 'కొత్త కొనుగోలు ఆర్డర్' : 'New purchase order'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: supplierId,
                  isExpanded: true,
                  items: [for (final s in suppliers) DropdownMenuItem(value: '${s['id']}', child: Text('${s['name']}'))],
                  onChanged: (v) => setLocal(() => supplierId = v ?? supplierId),
                ),
                for (var i = 0; i < lines.length; i++)
                  Row(children: [
                    Expanded(child: Text('${lines[i].$1['name']}')),
                    SizedBox(width: 90, child: AskodoxPosField(controller: lines[i].$2, number: true, label: lines[i].$3 ?? '${lines[i].$1['unit']}')),
                  ]),
                DropdownButton<String>(
                  key: const Key('askodoxPosPoAddItem'),
                  hint: Text(te ? 'సరుకు జోడించు' : 'Add item'),
                  isExpanded: true,
                  items: [
                    for (final p in products) ...[
                      DropdownMenuItem(value: '${p['id']}|', child: Text('${p['name']} (${p['unit']})')),
                      for (final k in askodoxPosList(p['packs']))
                        DropdownMenuItem(value: '${p['id']}|${k['name']}', child: Text('${p['name']} (${k['name']})')),
                    ],
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    final parts = v.split('|');
                    final product = products.firstWhere((p) => p['id'] == parts[0]);
                    setLocal(() => lines.add((product, TextEditingController(text: '1'), parts[1].isEmpty ? null : parts[1])));
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(key: const Key('askodoxPosPoSave'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true || lines.isEmpty || !mounted) return;
    try {
      await repo.createPurchaseOrder(widget.businessId, {
        'supplier_id': supplierId,
        'lines': [
          for (final l in lines)
            if ((askodoxParseMilli(l.$2.text) ?? 0) > 0)
              {'product_id': l.$1['id'], 'qty_milli': askodoxParseMilli(l.$2.text), if (l.$3 != null) 'pack': l.$3},
        ],
      });
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కొనుగోలు ఆర్డర్లు' : 'Purchase orders')),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('askodoxPosNewPo'), onPressed: _create, icon: const Icon(Icons.add), label: Text(te ? 'ఆర్డర్' : 'Order')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _orders,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.isEmpty) return Center(child: Text(te ? 'ఆర్డర్లు లేవు.' : 'No orders yet.'));
          return ListView(key: const Key('askodoxPosPurchaseOrders'), children: [
            for (final o in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosPo-${o['id']}'),
                title: Text('${o['number']} · ${o['supplier_name']}'),
                subtitle: Text('${o['status']}${o['expected_date'] == null ? '' : ' · ${o['expected_date']}'}'),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => AskodoxPosPurchaseOrderScreen(businessId: widget.businessId, poId: '${o['id']}')));
                  if (mounted) _reload();
                },
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosPurchaseOrderScreen extends ConsumerStatefulWidget {
  const AskodoxPosPurchaseOrderScreen({super.key, required this.businessId, required this.poId});
  final String businessId;
  final String poId;

  @override
  ConsumerState<AskodoxPosPurchaseOrderScreen> createState() => _AskodoxPosPurchaseOrderScreenState();
}

class _AskodoxPosPurchaseOrderScreenState extends ConsumerState<AskodoxPosPurchaseOrderScreen> {
  late Future<AskodoxJson> _po;

  @override
  void initState() {
    super.initState();
    _po = ref.read(askodoxPosRepositoryProvider).purchaseOrder(widget.businessId, widget.poId);
  }

  Future<void> _status(String status) async {
    final te = askodoxPosTe(context);
    try {
      final po = await ref.read(askodoxPosRepositoryProvider).setPurchaseOrderStatus(widget.businessId, widget.poId, status);
      if (mounted) setState(() => _po = Future.value(po));
      if (status == 'sent') {
        try {
          await const MethodChannel('com.askodox.app/device')
              .invokeMethod<bool>('shareText', <String, Object?>{'text': '${po['text']}', 'title': '${po['number']}'});
        } catch (_) {}
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _receive(AskodoxJson po) async {
    final te = askodoxPosTe(context);
    final billNo = TextEditingController();
    final open = [for (final l in askodoxPosList(po['lines'])) if (askodoxPosInt(l['received_milli']) < askodoxPosInt(l['qty_milli'])) l];
    final qty = {for (final l in open) l['line_no']: TextEditingController(text: askodoxQty(askodoxPosInt(l['qty_milli']) - askodoxPosInt(l['received_milli']), ''))};
    final cost = {for (final l in open) l['line_no']: TextEditingController(text: l['cost_paise'] == null ? '' : askodoxPaise(askodoxPosInt(l['cost_paise']), symbol: false).replaceAll(',', ''))};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'సరుకు వచ్చింది — బిల్లు నమోదు' : 'Goods arrived — record the bill'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(controller: billNo, label: te ? 'సప్లయర్ బిల్లు నంబర్' : 'Supplier bill number'),
            for (final l in open)
              Row(children: [
                Expanded(child: Text('${l['name']} (${l['unit']})')),
                SizedBox(width: 70, child: AskodoxPosField(controller: qty[l['line_no']]!, number: true, label: te ? 'వచ్చింది' : 'Got')),
                const SizedBox(width: 6),
                SizedBox(width: 90, child: AskodoxPosField(controller: cost[l['line_no']]!, number: true, label: te ? 'ధర (GST ముందు)' : 'Cost ex-GST')),
              ]),
            Text(te ? 'బ్యాచ్ / సీరియల్ ఉన్న సరుకులకు కొనుగోలు బిల్లు స్క్రీన్ వాడండి.' : 'For batch / serial items use the purchase bill screen.',
                style: const TextStyle(fontSize: 11.5)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(key: const Key('askodoxPosPoReceiveOk'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'నమోదు' : 'Record')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).receivePurchaseOrder(widget.businessId, widget.poId, {
        'client_txn_id': askodoxNewTxnId(),
        'supplier_bill_no': billNo.text.trim(),
        'lines': [
          for (final l in open)
            if ((askodoxParseMilli(qty[l['line_no']]!.text) ?? 0) > 0)
              {
                'line_no': l['line_no'],
                'qty_milli': askodoxParseMilli(qty[l['line_no']]!.text),
                if (askodoxParsePaise(cost[l['line_no']]!.text) != null) 'cost_paise': askodoxParsePaise(cost[l['line_no']]!.text),
              },
        ],
      });
      if (mounted) setState(() => _po = Future.value(askodoxPosMap(out['order'])));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కొనుగోలు ఆర్డర్' : 'Purchase order')),
      body: FutureBuilder<AskodoxJson>(
        future: _po,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final po = snap.data!;
          final status = '${po['status']}';
          return ListView(key: const Key('askodoxPosPurchaseOrder'), padding: const EdgeInsets.all(12), children: [
            Text('${po['number']} · ${po['supplier_name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${te ? 'స్థితి' : 'Status'}: $status'),
            for (final l in askodoxPosList(po['lines']))
              ListTile(
                dense: true,
                title: Text('${l['name']}'),
                trailing: Text('${askodoxQty(askodoxPosInt(l['received_milli']), '')} / ${askodoxQty(askodoxPosInt(l['qty_milli']), '${l['unit']}')}'),
              ),
            for (final b in askodoxPosList(po['bills'])) Text('${te ? 'బిల్లు' : 'Bill'} ${b['supplier_bill_no']} · ${b['bill_date']}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (status == 'draft')
                FilledButton.icon(
                    key: const Key('askodoxPosPoSend'),
                    onPressed: () => _status('sent'),
                    icon: const Icon(Icons.send),
                    label: Text(te ? 'సప్లయర్‌కి పంపు' : 'Send to supplier')),
              if (status == 'draft' || status == 'sent' || status == 'partially_received')
                OutlinedButton(key: const Key('askodoxPosPoReceive'), onPressed: () => _receive(po), child: Text(te ? 'సరుకు వచ్చింది' : 'Goods arrived')),
              if (status == 'draft' || status == 'sent' || status == 'partially_received')
                TextButton(onPressed: () => _status('cancelled'), child: Text(te ? 'రద్దు' : 'Cancel order')),
            ]),
          ]);
        },
      ),
    );
  }
}


/// Warranty / theft check: where a serial or IMEI appears in this shop's records.
Future<void> askodoxSerialLookup(BuildContext context, WidgetRef ref, String businessId) async {
  final te = askodoxPosTe(context);
  final c = TextEditingController();
  final query = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(te ? 'సీరియల్ / IMEI' : 'Serial / IMEI'),
      content: AskodoxPosField(controller: c, label: te ? 'నంబర్' : 'Number', maxLength: 40),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(te ? 'రద్దు' : 'Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(te ? 'వెతుకు' : 'Find')),
      ],
    ),
  );
  if (query == null || query.isEmpty || !context.mounted) return;
  String text;
  try {
    final r = await ref.read(askodoxPosRepositoryProvider).serialLookup(businessId, query);
    text = [
      for (final rec in askodoxPosList(r['records']))
        '${rec['name']}: ${rec['status']}${rec['invoice'] is Map ? ' · ${askodoxPosMap(rec['invoice'])['number']} (${askodoxPosMap(rec['invoice'])['date']})' : ''}',
    ].join('\n');
  } on AskodoxPosException catch (e) {
    text = e.message(te);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('askodoxPosSerialResult'),
      title: Text(query),
      content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
