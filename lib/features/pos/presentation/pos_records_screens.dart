import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../devices/data/ble_gateway.dart';
import '../data/pos_printer.dart';
import '../data/pos_repository.dart';
import '../domain/escpos.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';
import 'pos_sale_screen.dart' show askodoxPrintInvoice;

const _device = MethodChannel('com.askodox.app/device');

// ------------------------------------------------------------------ items
class AskodoxPosItemsScreen extends ConsumerStatefulWidget {
  const AskodoxPosItemsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosItemsScreen> createState() => _AskodoxPosItemsScreenState();
}

class _AskodoxPosItemsScreenState extends ConsumerState<AskodoxPosItemsScreen> {
  late Future<List<AskodoxJson>> _items;

  @override
  void initState() {
    super.initState();
    _items = ref.read(askodoxPosRepositoryProvider).products(widget.businessId);
  }

  void _reload() => setState(() => _items = ref.read(askodoxPosRepositoryProvider).products(widget.businessId));

  Future<void> _stock(AskodoxJson p) async {
    final te = askodoxPosTe(context);
    final qty = TextEditingController();
    final reason = TextEditingController();
    var kind = 'purchase';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${p['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              items: [
                DropdownMenuItem(value: 'purchase', child: Text(te ? 'కొనుగోలు (+)' : 'Purchase (+)')),
                DropdownMenuItem(value: 'wastage', child: Text(te ? 'పాడైనది (−)' : 'Wastage (−)')),
                DropdownMenuItem(value: 'count', child: Text(te ? 'లెక్కించిన స్టాక్' : 'Counted stock')),
              ],
              onChanged: (v) => setLocal(() => kind = v ?? kind),
            ),
            AskodoxPosField(controller: qty, number: true, label: '${te ? 'పరిమాణం' : 'Quantity'} (${p['unit']})'),
            AskodoxPosField(controller: reason, label: te ? 'కారణం' : 'Reason'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
          ],
        ),
      ),
    );
    final milli = askodoxParseMilli(qty.text);
    final why = reason.text.trim();
    if (ok != true || milli == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).stock(widget.businessId,
          {'product_id': p['id'], 'kind': kind, 'qty_milli': milli, 'reason': why, 'client_txn_id': askodoxNewTxnId()});
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సరుకులు' : 'Items')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxPosAddItem'),
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => AskodoxPosItemForm(businessId: widget.businessId)));
          if (added == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: Text(te ? 'సరుకు' : 'Item'),
      ),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _items,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return Center(child: Text(te ? 'ఇంకా సరుకులు లేవు.' : 'No items yet.'));
          return ListView(key: const Key('askodoxPosItems'), children: [
            for (final p in items)
              ListTile(
                key: ValueKey('askodoxPosItem-${p['id']}'),
                title: Text('${p['name']}${'${p['name_te'] ?? ''}'.isEmpty ? '' : ' · ${p['name_te']}'}'),
                subtitle: Text([
                  '${askodoxPaise(askodoxPosInt(p['price_paise']))}/${p['unit']}',
                  '${te ? 'GST' : 'GST'} ${askodoxRate(askodoxPosInt(p['rate_bp']))}${p['price_includes_tax'] == true ? (te ? ' కలిపి' : ' incl.') : ''}',
                  if ('${p['hsn_sac'] ?? ''}'.isNotEmpty) 'HSN ${p['hsn_sac']}',
                  if (p['stock_milli'] != null) '${te ? 'స్టాక్' : 'stock'} ${askodoxQty(askodoxPosInt(p['stock_milli']), '${p['unit']}')}',
                  if (p['low_stock'] == true) (te ? 'తక్కువ స్టాక్' : 'LOW'),
                ].join(' · ')),
                trailing: p['track_stock'] == true
                    ? IconButton(onPressed: () => _stock(p), icon: const Icon(Icons.inventory_outlined))
                    : null,
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosItemForm extends ConsumerStatefulWidget {
  const AskodoxPosItemForm({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosItemForm> createState() => _AskodoxPosItemFormState();
}

class _AskodoxPosItemFormState extends ConsumerState<AskodoxPosItemForm> {
  final _name = TextEditingController();
  final _nameTe = TextEditingController();
  final _price = TextEditingController();
  final _hsn = TextEditingController();
  final _barcode = TextEditingController();
  final _opening = TextEditingController();
  String _unit = 'pcs';
  int _rate = 0;
  String _category = 'taxable';
  bool _inclusive = true;
  bool _track = false;
  bool _busy = false;
  String? _error;

  static const _units = ['pcs', 'kg', 'g', 'l', 'ml', 'm', 'dozen', 'box', 'plate', 'hour', 'service', 'pack'];
  static const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

  @override
  void dispose() {
    for (final c in [_name, _nameTe, _price, _hsn, _barcode, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    final price = askodoxParsePaise(_price.text);
    if (_name.text.trim().isEmpty || price == null) {
      setState(() => _error = te ? 'పేరు, ధర తప్పనిసరి.' : 'Name and price are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(askodoxPosRepositoryProvider).addProduct(widget.businessId, {
        'name': _name.text.trim(),
        'name_te': _nameTe.text.trim(),
        'unit': _unit,
        'price_paise': price,
        'price_includes_tax': _inclusive,
        'rate_bp': _rate,
        'category': _category,
        'hsn_sac': _hsn.text.trim(),
        'barcode': _barcode.text.trim(),
        'track_stock': _track,
        if (_track) 'opening_stock_milli': askodoxParseMilli(_opening.text) ?? 0,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final categories = {
      'taxable': te ? 'పన్ను వర్తించేది' : 'Taxable',
      'exempt': te ? 'మినహాయింపు (exempt)' : 'Exempt',
      'nil_rated': te ? 'నిల్ రేటు' : 'Nil rated',
      'non_gst': te ? 'GST కాదు' : 'Non-GST',
      'zero_rated_lut': te ? 'ఎగుమతి (LUT)' : 'Zero-rated export (LUT)',
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కొత్త సరుకు' : 'New item')),
      body: ListView(key: const Key('askodoxPosItemForm'), padding: const EdgeInsets.all(16), children: [
        AskodoxPosField(controller: _name, label: te ? 'పేరు (ఇంగ్లీష్)' : 'Name', maxLength: 80),
        AskodoxPosField(controller: _nameTe, label: te ? 'తెలుగు పేరు' : 'Telugu name (optional)', maxLength: 80),
        Row(children: [
          Expanded(child: AskodoxPosField(controller: _price, number: true, label: te ? 'అమ్మకం ధర (₹)' : 'Selling price (₹)')),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _unit,
              decoration: InputDecoration(labelText: te ? 'యూనిట్' : 'Unit', border: const OutlineInputBorder(), isDense: true),
              items: [for (final u in _units) DropdownMenuItem(value: u, child: Text(u))],
              onChanged: (v) => setState(() => _unit = v ?? _unit),
            ),
          ),
        ]),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: InputDecoration(labelText: te ? 'పన్ను రకం' : 'Tax type', border: const OutlineInputBorder(), isDense: true),
          items: [for (final e in categories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 10),
        if (_category == 'taxable')
          DropdownButtonFormField<int>(
            key: const Key('askodoxPosRate'),
            initialValue: _rate,
            decoration: InputDecoration(labelText: te ? 'GST రేటు (మీ వర్గీకరణ)' : 'GST rate (your classification)', border: const OutlineInputBorder(), isDense: true),
            items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
            onChanged: (v) => setState(() => _rate = v ?? _rate),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _inclusive,
          onChanged: (v) => setState(() => _inclusive = v),
          title: Text(te ? 'ధరలో GST కలిసి ఉంది' : 'Price includes GST'),
        ),
        AskodoxPosField(controller: _hsn, number: true, decimal: false, label: 'HSN / SAC', maxLength: 8,
            hint: te ? 'మీ అకౌంటెంట్ ఇచ్చిన కోడ్' : 'Code from your own classification'),
        AskodoxPosField(controller: _barcode, label: te ? 'బార్‌కోడ్ (ఐచ్ఛికం)' : 'Barcode (optional)', maxLength: 64),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _track,
          onChanged: (v) => setState(() => _track = v),
          title: Text(te ? 'స్టాక్ లెక్క పెట్టు' : 'Track stock'),
        ),
        if (_track) AskodoxPosField(controller: _opening, number: true, label: te ? 'ప్రస్తుత స్టాక్' : 'Opening stock ($_unit)'),
        if (_error != null) Text(_error!, key: const Key('askodoxPosItemError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FilledButton(key: const Key('askodoxPosSaveItem'), onPressed: _busy ? null : _save, child: Text(te ? 'సేవ్' : 'Save')),
      ]),
    );
  }
}

// -------------------------------------------------------------- customers
class AskodoxPosCustomersScreen extends ConsumerStatefulWidget {
  const AskodoxPosCustomersScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosCustomersScreen> createState() => _AskodoxPosCustomersScreenState();
}

class _AskodoxPosCustomersScreenState extends ConsumerState<AskodoxPosCustomersScreen> {
  late Future<List<AskodoxJson>> _list;

  @override
  void initState() {
    super.initState();
    _list = ref.read(askodoxPosRepositoryProvider).customers(widget.businessId);
  }

  void _reload() => setState(() => _list = ref.read(askodoxPosRepositoryProvider).customers(widget.businessId));

  Future<void> _add() async {
    final te = askodoxPosTe(context);
    final name = TextEditingController();
    final phone = TextEditingController();
    final gstin = TextEditingController();
    final address = TextEditingController();
    final limit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(te ? 'కొత్త కస్టమర్' : 'New customer'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AskodoxPosField(controller: name, label: te ? 'పేరు' : 'Name'),
            AskodoxPosField(controller: phone, number: true, decimal: false, label: te ? 'ఫోన్' : 'Phone'),
            AskodoxPosField(controller: gstin, label: 'GSTIN (B2B)', maxLength: 15),
            AskodoxPosField(controller: address, label: te ? 'చిరునామా' : 'Address'),
            AskodoxPosField(controller: limit, number: true, label: te ? 'బాకీ పరిమితి ₹ (ఐచ్ఛికం)' : 'Credit limit ₹ (optional)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'సేవ్' : 'Save')),
        ],
      ),
    );
    final body = {
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      if (gstin.text.trim().isNotEmpty) 'gstin': gstin.text.trim().toUpperCase(),
      'address': address.text.trim(),
      'credit_limit_paise': askodoxParsePaise(limit.text) ?? 0,
    };
    if (ok != true || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).addCustomer(widget.businessId, body);
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కస్టమర్లు & ఖాతా' : 'Customers & credit')),
      floatingActionButton: FloatingActionButton(key: const Key('askodoxPosAddCustomer'), onPressed: _add, child: const Icon(Icons.person_add_alt)),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _list,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(key: const Key('askodoxPosCustomers'), children: [
            for (final c in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosCustomerRow-${c['id']}'),
                title: Text('${c['name']}'),
                subtitle: Text('${c['gstin'] ?? 'B2C'}'),
                trailing: Text(askodoxPaise(askodoxPosInt(c['balance_paise'])),
                    style: TextStyle(fontWeight: FontWeight.w800, color: askodoxPosInt(c['balance_paise']) > 0 ? const Color(0xFFB91C1C) : null)),
                onTap: () async {
                  await context.push('/pos/${widget.businessId}/customers/${c['id']}');
                  if (mounted) _reload();
                },
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosCustomerScreen extends ConsumerStatefulWidget {
  const AskodoxPosCustomerScreen({super.key, required this.businessId, required this.customerId});
  final String businessId;
  final String customerId;

  @override
  ConsumerState<AskodoxPosCustomerScreen> createState() => _AskodoxPosCustomerScreenState();
}

class _AskodoxPosCustomerScreenState extends ConsumerState<AskodoxPosCustomerScreen> {
  late String _month;
  late Future<AskodoxJson> _statement;

  @override
  void initState() {
    super.initState();
    _month = askodoxPosToday().substring(0, 7);
    _load();
  }

  void _load() => _statement = ref.read(askodoxPosRepositoryProvider).statement(widget.businessId, widget.customerId, _month);

  void _shiftMonth(int delta) {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5)) + delta;
    final d = DateTime(y, m);
    setState(() {
      _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      _load();
    });
  }

  Future<void> _collect() async {
    final te = askodoxPosTe(context);
    final amount = TextEditingController();
    final reference = TextEditingController();
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(te ? 'డబ్బు వచ్చింది' : 'Money received'),
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
    final ref0 = reference.text.trim();
    if (ok != true || paise == null || paise <= 0 || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).collect(widget.businessId, widget.customerId,
          {'client_txn_id': askodoxNewTxnId(), 'method': method, 'amount_paise': paise, 'reference': ref0});
      setState(_load);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _share(AskodoxJson st) async {
    final lines = <String>[
      '${askodoxPosMap(st['customer'])['name']} — ${st['month']}',
      'Opening: ${askodoxPaise(askodoxPosInt(st['opening_paise']))}',
      for (final e in askodoxPosList(st['entries']))
        '${e['local_date']} ${e['kind']} ${e['note']}  ${askodoxPosInt(e['debit_paise']) > 0 ? '+${askodoxPaise(askodoxPosInt(e['debit_paise']))}' : '-${askodoxPaise(askodoxPosInt(e['credit_paise']))}'}  = ${askodoxPaise(askodoxPosInt(e['balance_paise']))}',
      'Closing balance: ${askodoxPaise(askodoxPosInt(st['closing_paise']))}',
    ];
    try {
      await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': lines.join('\n'), 'title': 'Statement'});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఖాతా స్టేట్‌మెంట్' : 'Account statement')),
      floatingActionButton: FloatingActionButton.extended(
          key: const Key('askodoxPosCollect'), onPressed: _collect, icon: const Icon(Icons.currency_rupee), label: Text(te ? 'జమ' : 'Received')),
      body: FutureBuilder<AskodoxJson>(
        future: _statement,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final st = snap.data!;
          return ListView(key: const Key('askodoxPosStatement'), padding: const EdgeInsets.all(12), children: [
            Text('${askodoxPosMap(st['customer'])['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Row(children: [
              IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
              Text(_month, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
              const Spacer(),
              IconButton(onPressed: () => _share(st), icon: const Icon(Icons.share_outlined)),
            ]),
            ListTile(dense: true, title: Text(te ? 'మొదటి బాకీ' : 'Opening balance'), trailing: Text(askodoxPaise(askodoxPosInt(st['opening_paise'])))),
            for (final e in askodoxPosList(st['entries']))
              ListTile(
                dense: true,
                title: Text('${e['local_date']} · ${e['kind']}'),
                subtitle: Text('${e['note']}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(askodoxPosInt(e['debit_paise']) > 0
                      ? '+${askodoxPaise(askodoxPosInt(e['debit_paise']))}'
                      : '−${askodoxPaise(askodoxPosInt(e['credit_paise']))}'),
                  Text(askodoxPaise(askodoxPosInt(e['balance_paise'])), style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ListTile(
              key: const Key('askodoxPosClosing'),
              title: Text(te ? 'చివరి బాకీ' : 'Closing balance', style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Text(askodoxPaise(askodoxPosInt(st['closing_paise'])), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ bills
class AskodoxPosInvoicesScreen extends ConsumerWidget {
  const AskodoxPosInvoicesScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లులు' : 'Bills')),
      body: FutureBuilder<List<AskodoxJson>>(
        future: ref.read(askodoxPosRepositoryProvider).invoices(businessId),
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(key: const Key('askodoxPosInvoices'), children: [
            for (final i in snap.data!)
              ListTile(
                key: ValueKey('askodoxPosInvoiceRow-${i['id']}'),
                title: Text('${i['number']} · ${i['customer_name']}'),
                subtitle: Text('${i['local_date']} · ${i['document_type']}${i['status'] == 'cancelled' ? (te ? ' · రద్దు' : ' · CANCELLED') : ''}'),
                trailing: Text(askodoxPaise(askodoxPosInt(i['grand_total_paise']))),
                onTap: () => context.push('/pos/$businessId/invoice/${i['id']}'),
              ),
          ]);
        },
      ),
    );
  }
}

class AskodoxPosInvoiceScreen extends ConsumerStatefulWidget {
  const AskodoxPosInvoiceScreen({super.key, required this.businessId, required this.invoiceId});
  final String businessId;
  final String invoiceId;

  @override
  ConsumerState<AskodoxPosInvoiceScreen> createState() => _AskodoxPosInvoiceScreenState();
}

class _AskodoxPosInvoiceScreenState extends ConsumerState<AskodoxPosInvoiceScreen> {
  late Future<AskodoxJson> _invoice;

  @override
  void initState() {
    super.initState();
    _invoice = ref.read(askodoxPosRepositoryProvider).invoice(widget.businessId, widget.invoiceId);
  }

  void _reload() => setState(() => _invoice = ref.read(askodoxPosRepositoryProvider).invoice(widget.businessId, widget.invoiceId));

  Future<String?> _reason(String title) async {
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
    final text = c.text.trim();
    return ok == true && text.isNotEmpty ? text : null;
  }

  Future<void> _creditAll(AskodoxJson invoice) async {
    final te = askodoxPosTe(context);
    final reason = await _reason(te ? 'మొత్తం బిల్లు రిటర్న్ (క్రెడిట్ నోట్)' : 'Return the whole bill (credit note)');
    if (reason == null || !mounted) return;
    final lines = [
      for (final l in askodoxPosList(invoice['lines'])) {'line_no': l['line_no'], 'qty_milli': l['qty_milli']},
    ];
    final total = askodoxPosInt(askodoxPosMap(invoice['totals'])['grand_total_paise']);
    final refund = invoice['customer_id'] == null ? {'method': 'cash', 'amount_paise': total} : null;
    try {
      final note = await ref.read(askodoxPosRepositoryProvider).creditNote(widget.businessId, widget.invoiceId, {
        'client_txn_id': askodoxNewTxnId(),
        'reason': reason,
        'lines': lines,
        if (refund != null) 'refund': refund,
      });
      if (mounted) context.pushReplacement('/pos/${widget.businessId}/invoice/${note['id']}');
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  Future<void> _cancel() async {
    final te = askodoxPosTe(context);
    final reason = await _reason(te ? 'ఈ బిల్లు రద్దు చేయాలా? (రికార్డు ఉంటుంది)' : 'Cancel this bill? (the record stays)');
    if (reason == null || !mounted) return;
    try {
      await ref.read(askodoxPosRepositoryProvider).cancel(widget.businessId, widget.invoiceId, reason);
      _reload();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లు' : 'Bill')),
      body: FutureBuilder<AskodoxJson>(
        future: _invoice,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final inv = snap.data!;
          final receipt = askodoxReceiptLines(inv, columns: 32, asciiOnly: false);
          final isInvoice = inv['doc_kind'] == 'invoice' && inv['status'] == 'issued';
          return ListView(key: const Key('askodoxPosInvoice'), padding: const EdgeInsets.all(12), children: [
            if (inv['status'] == 'cancelled')
              Text('${te ? 'రద్దు' : 'CANCELLED'}: ${inv['cancel_reason']}', style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w800)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(receipt.join('\n'), key: const Key('askodoxPosReceipt'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
            for (final p in askodoxPosList(inv['payments']))
              if (p['verification'] == 'cashier_confirmed')
                Text(te ? '${p['method']}: క్యాషియర్ నిర్ధారించారు (బ్యాంక్ నిర్ధారణ కాదు)' : '${p['method']}: confirmed by the cashier (not bank-verified)',
                    style: const TextStyle(fontSize: 11.5)),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                key: const Key('askodoxPosPrint'),
                onPressed: () => askodoxPrintInvoice(context, ref, inv),
                icon: const Icon(Icons.print_outlined),
                label: Text(te ? 'ప్రింట్' : 'Print'),
              ),
              OutlinedButton.icon(
                key: const Key('askodoxPosShare'),
                onPressed: () async {
                  try {
                    await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': receipt.join('\n'), 'title': '${inv['number']}'});
                  } catch (_) {}
                },
                icon: const Icon(Icons.share_outlined),
                label: Text(te ? 'షేర్ (WhatsApp మొ.)' : 'Share (WhatsApp etc.)'),
              ),
              if (isInvoice && askodoxPosCan(business, 'return'))
                OutlinedButton(key: const Key('askodoxPosReturn'), onPressed: () => _creditAll(inv), child: Text(te ? 'రిటర్న్ / క్రెడిట్ నోట్' : 'Return / credit note')),
              if (isInvoice && askodoxPosCan(business, 'cancel'))
                TextButton(key: const Key('askodoxPosCancel'), onPressed: _cancel, child: Text(te ? 'రద్దు' : 'Cancel bill')),
            ]),
          ]);
        },
      ),
    );
  }
}

// -------------------------------------------------------------- day close
class AskodoxPosDayScreen extends ConsumerStatefulWidget {
  const AskodoxPosDayScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosDayScreen> createState() => _AskodoxPosDayScreenState();
}

class _AskodoxPosDayScreenState extends ConsumerState<AskodoxPosDayScreen> {
  final _float = TextEditingController();
  final _counted = TextEditingController();
  late Future<AskodoxJson> _day;
  final _date = askodoxPosToday();

  @override
  void initState() {
    super.initState();
    _day = ref.read(askodoxPosRepositoryProvider).day(widget.businessId, _date);
  }

  @override
  void dispose() {
    _float.dispose();
    _counted.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final te = askodoxPosTe(context);
    final counted = askodoxParsePaise(_counted.text);
    if (counted == null) {
      askodoxPosSnack(context, te ? 'డ్రాలో ఉన్న నగదు నమోదు చేయండి.' : 'Enter the cash counted in the drawer.');
      return;
    }
    try {
      final day = await ref.read(askodoxPosRepositoryProvider).closeDay(widget.businessId,
          {'local_date': _date, 'opening_float_paise': askodoxParsePaise(_float.text) ?? 0, 'counted_cash_paise': counted});
      if (mounted) setState(() => _day = Future.value(day));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text('${te ? 'రోజు ముగింపు' : 'Day close'} · $_date')),
      body: FutureBuilder<AskodoxJson>(
        future: _day,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final d = snap.data!;
          final closed = d['closed'] == null ? null : askodoxPosMap(d['closed']);
          return ListView(key: const Key('askodoxPosDay'), padding: const EdgeInsets.all(12), children: [
            ListTile(title: Text(te ? 'బిల్లులు' : 'Bills'), trailing: Text('${d['invoices']}')),
            ListTile(title: Text(te ? 'అమ్మకాలు' : 'Sales'), trailing: Text(askodoxPaise(askodoxPosInt(d['sales_paise'])))),
            ListTile(title: Text(te ? 'పన్ను' : 'Tax'), trailing: Text(askodoxPaise(askodoxPosInt(d['tax_paise'])))),
            ListTile(title: Text(te ? 'క్రెడిట్ నోట్లు' : 'Credit notes'), trailing: Text(askodoxPaise(askodoxPosInt(d['credit_notes_paise'])))),
            for (final e in askodoxPosMap(d['payments']).entries)
              ListTile(dense: true, title: Text(e.key), trailing: Text(askodoxPaise(askodoxPosInt(askodoxPosMap(e.value)['net_paise'])))),
            Text('${d['note']}', style: const TextStyle(fontSize: 11.5)),
            const Divider(),
            if (closed != null) ...[
              Text(te ? 'ఈ రోజు ముగిసింది (మార్చలేం).' : 'This day is closed (final).', key: const Key('askodoxPosDayClosed'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              ListTile(title: Text(te ? 'ఉండాల్సిన నగదు' : 'Expected cash'), trailing: Text(askodoxPaise(askodoxPosInt(closed['expected_cash_paise'])))),
              ListTile(title: Text(te ? 'లెక్కించిన నగదు' : 'Counted cash'), trailing: Text(askodoxPaise(askodoxPosInt(closed['counted_cash_paise'])))),
              ListTile(title: Text(te ? 'తేడా' : 'Difference'), trailing: Text(askodoxPaise(askodoxPosInt(closed['difference_paise'])))),
            ] else ...[
              AskodoxPosField(controller: _float, number: true, label: te ? 'ఉదయం డ్రాలో పెట్టిన నగదు (₹)' : 'Opening cash in drawer (₹)'),
              AskodoxPosField(controller: _counted, number: true, label: te ? 'ఇప్పుడు లెక్కించిన నగదు (₹)' : 'Cash counted now (₹)'),
              FilledButton(key: const Key('askodoxPosCloseDay'), onPressed: _close, child: Text(te ? 'రోజు ముగించు' : 'Close the day')),
            ],
          ]);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- GST
class AskodoxPosGstScreen extends ConsumerStatefulWidget {
  const AskodoxPosGstScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosGstScreen> createState() => _AskodoxPosGstScreenState();
}

class _AskodoxPosGstScreenState extends ConsumerState<AskodoxPosGstScreen> {
  late String _month;
  late Future<AskodoxJson> _report;

  @override
  void initState() {
    super.initState();
    _month = askodoxPosToday().substring(0, 7);
    _load();
  }

  void _load() {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5));
    final last = DateTime(y, m + 1, 0).day;
    _report = ref.read(askodoxPosRepositoryProvider).gstReport(widget.businessId, '$_month-01', '$_month-${last.toString().padLeft(2, '0')}');
  }

  void _shift(int delta) {
    final d = DateTime(int.parse(_month.substring(0, 4)), int.parse(_month.substring(5)) + delta);
    setState(() {
      _month = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      _load();
    });
  }

  Widget _row(String label, AskodoxJson r) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text('CGST ${askodoxPaise(askodoxPosInt(r['cgst_paise']))} · SGST/UTGST ${askodoxPaise(askodoxPosInt(r['sgst_paise']))} · '
            'IGST ${askodoxPaise(askodoxPosInt(r['igst_paise']))} · Cess ${askodoxPaise(askodoxPosInt(r['cess_paise']))}'),
        trailing: Text(askodoxPaise(askodoxPosInt(r['taxable_paise']))),
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'GST సారాంశం' : 'GST summary')),
      body: FutureBuilder<AskodoxJson>(
        future: _report,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!, onRetry: () => setState(_load));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final r = snap.data!;
          return ListView(key: const Key('askodoxPosGst'), padding: const EdgeInsets.all(12), children: [
            Row(children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Text(_month, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ]),
            Text('${r['disclaimer']}', key: const Key('askodoxPosGstDisclaimer'), style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
            Text(te ? 'రేటు వారీగా (పన్ను విధించదగిన విలువ)' : 'By rate (taxable value)', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final row in askodoxPosList(r['by_rate'])) _row('${askodoxRate(askodoxPosInt(row['rate_bp']))} · ${row['category']}', row),
            _row('B2B', askodoxPosMap(r['b2b'])),
            _row('B2C', askodoxPosMap(r['b2c'])),
            Text('HSN', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final row in askodoxPosList(r['hsn'])) _row('${row['hsn_sac']} · ${askodoxQty(askodoxPosInt(row['qty_milli']), '${row['unit']}')}', row),
            Text('${te ? 'రద్దైన బిల్లులు' : 'Cancelled bills'}: ${r['cancelled_count']}'),
          ]);
        },
      ),
    );
  }
}

// ----------------------------------------------------------------- staff
class AskodoxPosStaffScreen extends ConsumerStatefulWidget {
  const AskodoxPosStaffScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosStaffScreen> createState() => _AskodoxPosStaffScreenState();
}

class _AskodoxPosStaffScreenState extends ConsumerState<AskodoxPosStaffScreen> {
  final _phone = TextEditingController();
  String _role = 'cashier';
  late Future<List<AskodoxJson>> _members;

  @override
  void initState() {
    super.initState();
    _members = ref.read(askodoxPosRepositoryProvider).members(widget.businessId);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final te = askodoxPosTe(context);
    try {
      await ref.read(askodoxPosRepositoryProvider).setMember(widget.businessId, _phone.text.trim(), _role);
      _phone.clear();
      if (mounted) setState(() => _members = ref.read(askodoxPosRepositoryProvider).members(widget.businessId));
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final roles = {
      'manager': te ? 'మేనేజర్ (ధర మార్పు, రిటర్న్, రద్దు)' : 'Manager (price change, returns, cancel)',
      'cashier': te ? 'క్యాషియర్ (బిల్లింగ్ మాత్రమే)' : 'Cashier (billing only)',
      'accountant': te ? 'అకౌంటెంట్ (నివేదికలు మాత్రమే)' : 'Accountant (reports only)',
      'removed': te ? 'తొలగించు' : 'Remove access',
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'సిబ్బంది & పాత్రలు' : 'Staff & roles')),
      body: ListView(key: const Key('askodoxPosStaff'), padding: const EdgeInsets.all(12), children: [
        AskodoxPosField(controller: _phone, number: true, decimal: false, label: te ? 'సిబ్బంది మొబైల్ నంబర్' : 'Staff mobile number', maxLength: 13),
        DropdownButtonFormField<String>(
          initialValue: _role,
          isExpanded: true,
          items: [for (final e in roles.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        const SizedBox(height: 8),
        FilledButton(key: const Key('askodoxPosSaveMember'), onPressed: _save, child: Text(te ? 'సేవ్' : 'Save')),
        Text(te ? 'వారు అదే నంబర్‌తో ASKODOX లో సైన్ ఇన్ చేస్తే ఈ షాపు కనిపిస్తుంది.' : 'They see this shop after signing in to ASKODOX with that number.',
            style: const TextStyle(fontSize: 12)),
        const Divider(),
        FutureBuilder<List<AskodoxJson>>(
          future: _members,
          builder: (context, snap) => Column(children: [
            for (final m in snap.data ?? const <AskodoxJson>[])
              ListTile(
                dense: true,
                title: Text('…${m['phone_last4']}'),
                subtitle: Text('${m['role']}${m['active'] == true ? '' : (te ? ' (తొలగించారు)' : ' (removed)')}'),
              ),
          ]),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------- printer
class AskodoxPosPrinterScreen extends ConsumerStatefulWidget {
  const AskodoxPosPrinterScreen({super.key});

  @override
  ConsumerState<AskodoxPosPrinterScreen> createState() => _AskodoxPosPrinterScreenState();
}

class _AskodoxPosPrinterScreenState extends ConsumerState<AskodoxPosPrinterScreen> {
  AskodoxSavedPrinter? _saved;
  List<AskodoxBleDevice> _found = const [];
  bool _scanning = false;
  int _paper = 58;
  String? _message;

  @override
  void initState() {
    super.initState();
    AskodoxSavedPrinter.load().then((p) {
      if (mounted && p != null) {
        setState(() {
          _saved = p;
          _paper = p.paperMm;
        });
      }
    });
  }

  Future<void> _scan() async {
    final te = askodoxPosTe(context);
    final ble = ref.read(askodoxBleGatewayProvider);
    setState(() {
      _scanning = true;
      _message = null;
    });
    try {
      if (!await ble.isOn()) await ble.requestTurnOn();
      final found = await ble.scan(const Duration(seconds: 8));
      if (mounted) setState(() => _found = found);
    } on AskodoxBleException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'permission_denied'
            ? (te ? 'బ్లూటూత్ అనుమతి ఇవ్వలేదు.' : 'Bluetooth permission was not given.')
            : (te ? 'స్కాన్ విఫలమైంది.' : 'The scan failed.'));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _choose(AskodoxBleDevice d) async {
    final p = AskodoxSavedPrinter(id: d.id, name: d.name.isEmpty ? d.id : d.name, paperMm: _paper);
    await p.save();
    if (mounted) setState(() => _saved = p);
  }

  Future<void> _test() async {
    final te = askodoxPosTe(context);
    final p = _saved;
    if (p == null) return;
    final bytes = (AskodoxEscPos().init().align(1).bold(true).text('ASKODOX test print').bold(false).text('Paper ${p.paperMm} mm')
          ..text('-' * askodoxReceiptColumns(p.paperMm))
          ..feed(3)
          ..cut())
        .bytes();
    try {
      await ref.read(askodoxPrinterTransportProvider).write(p.id, bytes);
      if (mounted) setState(() => _message = te ? 'పంపాం — పేపర్ మీద వచ్చిందా చూడండి.' : 'Sent — check that it printed.');
    } on AskodoxPrinterException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'రసీదు ప్రింటర్' : 'Receipt printer')),
      body: ListView(key: const Key('askodoxPosPrinter'), padding: const EdgeInsets.all(12), children: [
        Text(
          te
              ? 'బ్లూటూత్ LE థర్మల్ ప్రింటర్లు (ESC/POS) మాత్రమే. క్లాసిక్ బ్లూటూత్, USB, Wi-Fi ప్రింటర్లు ఇంకా లేవు. ఏ మోడల్ ఇంకా నిజంగా పరీక్షించలేదు. తెలుగు పేర్లు చిత్రంగా ప్రింట్ అవుతాయి (ఇంకా ప్రింటర్‌పై పరీక్షించలేదు).'
              : 'Bluetooth LE thermal printers (ESC/POS) only. Classic Bluetooth, USB and Wi-Fi printers are not supported yet. No model has been tested yet. Telugu names print as an image (not tested on a printer yet).',
          key: const Key('askodoxPosPrinterLimits'),
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
          selected: {_paper},
          onSelectionChanged: (s) async {
            setState(() => _paper = s.first);
            final p = _saved;
            if (p != null) {
              final updated = AskodoxSavedPrinter(id: p.id, name: p.name, paperMm: s.first);
              await updated.save();
              if (mounted) setState(() => _saved = updated);
            }
          },
        ),
        if (_saved != null)
          ListTile(
            key: const Key('askodoxPosSavedPrinter'),
            leading: const Icon(Icons.print),
            title: Text(_saved!.name),
            subtitle: Text('${_saved!.paperMm} mm'),
            trailing: TextButton(onPressed: _test, child: Text(te ? 'టెస్ట్ ప్రింట్' : 'Test print')),
          ),
        FilledButton.icon(
          key: const Key('askodoxPosPrinterScan'),
          onPressed: _scanning ? null : _scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(_scanning ? (te ? 'వెతుకుతోంది…' : 'Scanning…') : (te ? 'ప్రింటర్ వెతుకు' : 'Find printer')),
        ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!)),
        for (final d in _found)
          ListTile(
            key: ValueKey('askodoxPosPrinterFound-${d.id}'),
            title: Text(d.name.isEmpty ? (te ? 'పేరు లేని పరికరం' : 'Unnamed device') : d.name),
            subtitle: Text('RSSI ${d.rssi}'),
            onTap: () => _choose(d),
          ),
      ]),
    );
  }
}
