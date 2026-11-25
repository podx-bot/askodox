import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/domain/pos_tax.dart';
import '../../pos/presentation/pos_bill_photo_screen.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 35): record a supplier's bill `/pos/:id/purchase/new`.
/// 1 which supplier? (or the bill photo, which fills everything by itself) -> 2 the bill number (+ the printed total to
/// check) -> 3 what came: ONE list of lines (tap = quantity, cost before GST, GST %, pack, batch / expiry, serials),
/// "+ Add item", and ONE big "Record bill". Same arithmetic and the same call as the old page (`?full=1`).
class AskodoxPurchaseStepsScreen extends ConsumerStatefulWidget {
  const AskodoxPurchaseStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPurchaseStepsScreen> createState() => _PurchaseStepsState();
}

const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

class _Line {
  _Line(this.product);
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

  void dispose() {
    for (final c in [qty, cost, batch, expiry, serials]) {
      c.dispose();
    }
  }
}

class _PurchaseStepsState extends ConsumerState<AskodoxPurchaseStepsScreen> {
  List<AskodoxJson>? _suppliers;
  List<AskodoxJson> _products = const [];
  Object? _error;
  int _step = 1;
  String? _supplierId;
  bool _busy = false;
  final _billNo = TextEditingController();
  final _total = TextEditingController();
  final List<_Line> _lines = [];
  final List<_Line> _made = [];
  final _txn = askodoxNewTxnId();

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_repo.products(widget.businessId).then((p) {
      if (mounted) setState(() => _products = p);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    _billNo.dispose();
    _total.dispose();
    for (final l in _made) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.suppliers(widget.businessId);
      if (mounted) {
        setState(() {
          _suppliers = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _suppliers == null) setState(() => _error = e);
    }
  }

  /// Same arithmetic as the server (cost before GST; GST only from a registered supplier).
  int? _computed(AskodoxJson? business) {
    final supplier = (_suppliers ?? const <AskodoxJson>[]).where((s) => s['id'] == _supplierId).firstOrNull;
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

  Future<void> _photo() async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(MaterialPageRoute(builder: (_) => AskodoxPosBillPhotoScreen(businessId: widget.businessId)));
    if (saved == true && mounted && navigator.canPop()) navigator.pop();
  }

  Future<void> _addLine() async {
    final te = _te;
    final picked = await showModalBottomSheet<AskodoxJson>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .75,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(te ? 'ఏ సరుకు వచ్చింది?' : 'Which item came?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final p in _products)
              AskodoxStepPersonRow(
                key: ValueKey('askodoxPurchaseStepsProduct-${p['id']}'),
                name: '${p['name']}',
                sub: '${p['unit'] ?? ''}${p['track_batches'] == true ? (te ? ' · బ్యాచ్' : ' · batch') : ''}',
                amount: '+',
                amountColor: askodoxStepGreen,
                onTap: () => Navigator.pop(ctx, p),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final line = _Line(picked);
    _made.add(line);
    setState(() => _lines.add(line));
    await _editLine(line);
  }

  Future<void> _editLine(_Line l) async {
    final te = _te;
    final packs = askodoxPosList(l.product['packs']);
    final i = _lines.indexOf(l);
    final out = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${l.product['name']} (${l.product['unit'] ?? ''})', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              TextField(
                  key: ValueKey('askodoxPurchaseStepsQty-$i'),
                  controller: l.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(labelText: te ? 'పరిమాణం' : 'Quantity', border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(
                  key: ValueKey('askodoxPurchaseStepsCost-$i'),
                  controller: l.cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(labelText: te ? 'ఒక్కదాని ధర (GST ముందు) ₹' : 'Cost of one, before GST ₹', border: const OutlineInputBorder())),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey('askodoxPurchaseStepsRate-$i'),
                initialValue: _rates.contains(l.rateBp) ? l.rateBp : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'GST %', border: OutlineInputBorder(), isDense: true),
                items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text(askodoxRate(r)))],
                onChanged: (v) => setSheet(() => l.rateBp = v ?? l.rateBp),
              ),
              if (packs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  ChoiceChip(label: Text('${l.product['unit']}'), selected: l.pack == null, onSelected: (_) => setSheet(() => l.pack = null)),
                  for (final k in packs)
                    ChoiceChip(label: Text('${k['name']}'), selected: l.pack == k['name'], onSelected: (_) => setSheet(() => l.pack = '${k['name']}')),
                ]),
              ],
              if (l.product['track_batches'] == true) ...[
                const SizedBox(height: 8),
                TextField(
                    controller: l.batch,
                    maxLength: 40,
                    decoration: InputDecoration(labelText: te ? 'బ్యాచ్ నంబర్' : 'Batch no.', border: const OutlineInputBorder())),
                TextField(
                    controller: l.expiry,
                    maxLength: 10,
                    decoration: InputDecoration(labelText: te ? 'ఎక్స్‌పైరీ (YYYY-MM-DD)' : 'Expiry (YYYY-MM-DD)', border: const OutlineInputBorder())),
              ],
              if (l.product['track_serials'] == true) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: l.serials,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l.product['serial_kind'] == 'imei'
                        ? (te ? 'IMEI లు (ఒక్కో లైన్‌కి ఒకటి)' : 'IMEIs (one per line)')
                        : (te ? 'సీరియల్స్ (ఒక్కో లైన్‌కి ఒకటి)' : 'Serials (one per line)'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                  key: ValueKey('askodoxPurchaseStepsLineOk-$i'),
                  style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, 'ok'),
                  child: Text(te ? 'సరే' : 'OK')),
              const SizedBox(height: 8),
              OutlinedButton(
                  key: ValueKey('askodoxPurchaseStepsLineRemove-$i'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: askodoxStepBad),
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  child: Text(te ? 'ఈ లైన్ తీసేయి' : 'Remove this line')),
            ]),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (out == 'remove') _lines.remove(l);
    });
  }

  Future<void> _save() async {
    final te = _te;
    if (_supplierId == null || _billNo.text.trim().isEmpty || _lines.isEmpty) {
      askodoxPosSnack(context, te ? 'సప్లయర్, బిల్లు నంబర్, కనీసం ఒక లైన్ కావాలి.' : 'Supplier, bill number and at least one line are needed.');
      return;
    }
    final lines = <AskodoxJson>[];
    for (final l in _lines) {
      final q = askodoxParseMilli(l.qty.text);
      final c = askodoxParsePaise(l.cost.text);
      if (q == null || q <= 0 || c == null) {
        askodoxPosSnack(context, te ? '${l.product['name']}: పరిమాణం, ధర నమోదు చేయండి.' : '${l.product['name']}: enter quantity and cost.');
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
    setState(() => _busy = true);
    try {
      await _repo.recordPurchase(widget.businessId, {
        'client_txn_id': _txn,
        'supplier_id': _supplierId,
        'supplier_bill_no': _billNo.text.trim(),
        'lines': lines,
        if (askodoxParsePaise(_total.text) != null) 'supplier_total_paise': askodoxParsePaise(_total.text),
      });
      if (!mounted) return;
      askodoxPosSnack(context, te ? '✓ బిల్లు నమోదు అయింది' : '✓ Bill recorded');
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop(true);
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'కొనుగోలు బిల్లు' : 'Purchase bill';
    final more = [
      AskodoxStepMore('askodoxPurchaseStepsPhoto', te ? 'బిల్లు ఫోటో' : 'Bill photo', Icons.photo_camera_outlined, _photo),
      AskodoxStepMore('askodoxPurchaseStepsSuppliers', te ? 'సప్లయర్లు' : 'Suppliers', Icons.local_shipping_outlined,
          () => context.push('/pos/${widget.businessId}/suppliers').then((_) => _load())),
      AskodoxStepMore('askodoxPurchaseStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push('/pos/${widget.businessId}/purchase/new?full=1')),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final suppliers = _suppliers;
    if (suppliers == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    return switch (_step) {
      2 => _bill(title, more, suppliers),
      3 => _linesStep(title, more),
      _ => _who(title, more, suppliers),
    };
  }

  Widget _who(String title, List<AskodoxStepMore> more, List<AskodoxJson> suppliers) {
    final te = _te;
    return AskodoxStepScaffold(
      key: const Key('askodoxPurchaseSteps'),
      title: title,
      step: 1,
      question: te ? 'ఏ సప్లయర్?' : 'Which supplier?',
      hint: te ? 'బిల్లు ఫోటో తీస్తే అన్నీ దానంతట అదే నిండుతాయి' : 'A photo of the bill fills everything by itself',
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepChoice(
          key: const Key('askodoxPurchaseStepsPhotoTile'),
          icon: Icons.photo_camera_outlined,
          color: askodoxStepGreen,
          title: te ? 'బిల్లు ఫోటో తీయండి' : 'Photograph the bill',
          sub: te ? 'అన్నీ దానంతట అదే నిండుతాయి' : 'Everything fills by itself',
          onTap: _photo,
        ),
        const SizedBox(height: 12),
        if (suppliers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(te ? 'ఇంకా సప్లయర్లు లేరు — ⋮ లో "సప్లయర్లు" లో చేర్చండి.' : 'No suppliers yet — add one from "Suppliers" in ⋮.'),
          ),
        for (final s in suppliers)
          AskodoxStepPersonRow(
            key: ValueKey('askodoxPurchaseStepsSupplier-${s['id']}'),
            name: '${s['name'] ?? ''}',
            sub: s['gstin'] != null ? 'GSTIN ${s['gstin']}' : (te ? 'GST లేదు' : 'No GST'),
            amount: _supplierId == '${s['id']}' ? '✓' : '›',
            amountColor: askodoxStepGreen,
            onTap: () => setState(() {
              _supplierId = '${s['id']}';
              _step = 2;
            }),
          ),
      ]),
    );
  }

  Widget _bill(String title, List<AskodoxStepMore> more, List<AskodoxJson> suppliers) {
    final te = _te;
    final supplier = suppliers.where((s) => '${s['id']}' == _supplierId).firstOrNull;
    return AskodoxStepScaffold(
      key: const Key('askodoxPurchaseSteps'),
      title: title,
      sub: '${supplier?['name'] ?? ''}',
      step: 2,
      question: te ? 'బిల్లు నంబర్?' : 'Bill number?',
      onBack: () => setState(() => _step = 1),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        TextField(
            key: const Key('askodoxPurchaseStepsBillNo'),
            controller: _billNo,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: te ? 'సప్లయర్ బిల్లు నంబర్' : 'Supplier bill number', border: const OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            key: const Key('askodoxPurchaseStepsPrinted'),
            controller: _total,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: te ? 'బిల్లుపై ఉన్న మొత్తం ₹ (సరిచూడటానికి, ఉంటే)' : 'Total printed on the bill ₹ (to check, optional)',
                border: const OutlineInputBorder())),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxPurchaseStepsNext'),
        label: te ? 'తర్వాత: ఏం వచ్చింది?' : 'Next: what came?',
        icon: Icons.arrow_forward_rounded,
        onPressed: _billNo.text.trim().isEmpty ? null : () => setState(() => _step = 3),
      ),
    );
  }

  Widget _linesStep(String title, List<AskodoxStepMore> more) {
    final te = _te;
    final computed = _computed(ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull);
    final printed = askodoxParsePaise(_total.text);
    return AskodoxStepScaffold(
      key: const Key('askodoxPurchaseSteps'),
      title: title,
      sub: _billNo.text.trim(),
      step: 3,
      question: _lines.isEmpty ? (te ? 'ఏం వచ్చింది?' : 'What came?') : null,
      onBack: () => setState(() => _step = 2),
      more: more,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        if (_lines.isNotEmpty)
          AskodoxStepBigNumber(computed == null ? '—' : askodoxPaise(computed),
              key: const Key('askodoxPurchaseStepsComputed'),
              label: printed == null || computed == null
                  ? (te ? 'లెక్క' : 'Computed')
                  : (printed == computed
                      ? (te ? 'బిల్లుతో సరిపోయింది ✓' : 'Matches the bill ✓')
                      : (te ? 'బిల్లుపై ${askodoxPaise(printed)} — సరిచూడండి' : 'Bill says ${askodoxPaise(printed)} — check')),
              color: printed != null && computed != null && printed != computed ? askodoxStepWarn : askodoxStepInk),
        for (final l in _lines)
          AskodoxStepPersonRow(
            key: ValueKey('askodoxPurchaseStepsLine-${_lines.indexOf(l)}'),
            name: '${l.product['name']}',
            sub: '${l.qty.text.isEmpty ? '?' : l.qty.text} ${l.pack ?? l.product['unit'] ?? ''} × ₹${l.cost.text.isEmpty ? '?' : l.cost.text} · ${askodoxRate(l.rateBp)}',
            amount: askodoxParseMilli(l.qty.text) != null && askodoxParsePaise(l.cost.text) != null ? '✓' : '!',
            amountColor: askodoxParseMilli(l.qty.text) != null && askodoxParsePaise(l.cost.text) != null ? askodoxStepDone : askodoxStepWarn,
            onTap: () => _editLine(l),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('askodoxPurchaseStepsAddLine'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _products.isEmpty ? null : _addLine,
          icon: const Icon(Icons.add_rounded),
          label: Text(te ? 'సరుకు చేర్చు' : 'Add item', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        Text(
          te
              ? 'GST నమోదైన సప్లయర్ బిల్లుకే GST లెక్కిస్తాం. ఇన్‌పుట్ ట్యాక్స్ క్రెడిట్ అర్హత మీ అకౌంటెంట్ నిర్ణయం.'
              : 'GST is counted only for a registered supplier. Input tax credit eligibility is your accountant\'s call.',
          style: const TextStyle(fontSize: 12, color: askodoxStepMuted),
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxPurchaseStepsSave'),
        label: te ? 'బిల్లు నమోదు చేయి' : 'Record bill',
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: _busy || _lines.isEmpty ? null : _save,
      ),
    );
  }
}
