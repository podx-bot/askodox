import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/media_picker.dart';
import '../../../shared/widgets/estimate_note.dart';
import '../data/pos_repository.dart';
import '../domain/pos_money.dart';
import 'pos_common.dart';

/// Supplier bill PHOTO -> one review screen -> saved (owner 2026-11-19): the photo fills the supplier, the bill number
/// and every line; items the shop does not have yet are marked NEW and are added with the bill. Only what the photo
/// did not show is asked (highlighted). Nothing is saved until "Save bill".
class AskodoxPosBillPhotoScreen extends ConsumerStatefulWidget {
  const AskodoxPosBillPhotoScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosBillPhotoScreen> createState() => _AskodoxPosBillPhotoScreenState();
}

class _BillLine {
  _BillLine(AskodoxJson m)
      : productId = m['product_id'] == null ? null : '${m['product_id']}',
        isNew = m['new'] == true,
        unit = '${m['unit'] ?? 'pcs'}',
        rateBp = askodoxPosInt(m['rate_bp']),
        batch = '${m['batch_no'] ?? ''}',
        name = TextEditingController(text: '${m['name'] ?? ''}'),
        qty = TextEditingController(text: _milli(m['qty_milli'])),
        cost = TextEditingController(text: _rupees(m['cost_paise'])),
        price = TextEditingController(text: _rupees(m['price_paise'])),
        expiry = TextEditingController(text: '${m['expiry_date'] ?? ''}');

  final String? productId;
  final bool isNew;
  final String unit;
  final String batch;
  int rateBp;
  final TextEditingController name, qty, cost, price, expiry;

  static String _rupees(Object? paise) {
    if (paise is! num) return '';
    return paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2);
  }

  static String _milli(Object? milli) {
    if (milli is! num) return '';
    return milli % 1000 == 0 ? '${milli ~/ 1000}' : (milli / 1000).toString();
  }

  void dispose() {
    for (final c in [name, qty, cost, price, expiry]) {
      c.dispose();
    }
  }
}

class _AskodoxPosBillPhotoScreenState extends ConsumerState<AskodoxPosBillPhotoScreen> {
  static const _rates = [0, 10, 25, 100, 150, 300, 500, 600, 1200, 1800, 2800, 4000];

  bool _reading = false;
  bool _saving = false;
  bool _read = false;
  String? _error;
  String? _supplierId;
  AskodoxJson _supplier = const {};
  final _supplierName = TextEditingController();
  final _billNo = TextEditingController();
  String _billDate = '';
  int? _totalPaise;
  int? _totalQtyMilli; // the total QUANTITY written on the bill ("Total 130 kg"), when one is written
  bool _skipPrintedTotal = false; // the person chose to save although the lines do not add up to the printed total
  final List<_BillLine> _lines = [];
  final List<_BillLine> _removed = []; // disposed with the screen (their boxes may still be on screen this frame)
  String _txn = askodoxNewTxnId();
  bool _gstBill = true; // false = a hand slip / a bill with no GST (owner 2026-11-28, design "Purchase")

  @override
  void dispose() {
    _supplierName.dispose();
    _billNo.dispose();
    for (final l in [..._lines, ..._removed]) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _photo(String source) async {
    final te = askodoxPosTe(context);
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    if (picked.any((a) => a.bytes.length > 4400000)) {
      askodoxPosSnack(context, te ? 'ఫోటో చాలా పెద్దది. చిన్న ఫోటో వాడండి.' : 'That photo is too large. Use a smaller one.');
      return;
    }
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).purchaseBillPhoto(widget.businessId, [
        for (final a in picked.take(4)) {'data': base64Encode(a.bytes), 'mime': a.mimeType},
      ]);
      if (!mounted) return;
      final lines = askodoxPosList(out['lines']);
      setState(() {
        _removed.addAll(_lines);
        _lines
          ..clear()
          ..addAll([for (final m in lines) _BillLine(m)]);
        _read = out['read'] == true && lines.isNotEmpty;
        _supplierId = out['supplier_id'] == null ? null : '${out['supplier_id']}';
        _supplier = askodoxPosMap(out['supplier']);
        _supplierName.text = '${out['supplier_name'] ?? ''}';
        _billNo.text = '${out['bill_no'] ?? ''}';
        _billDate = '${out['bill_date'] ?? ''}';
        _totalPaise = out['total_paise'] is num ? (out['total_paise'] as num).round() : null;
        _totalQtyMilli = out['total_qty_milli'] is num ? (out['total_qty_milli'] as num).round() : null;
        _skipPrintedTotal = false;
        if (!_read) {
          _error = te
              ? 'ఫోటో నుంచి బిల్లు చదవలేకపోయాను. వెలుతురులో స్పష్టంగా మళ్ళీ తీయండి, లేదా కింద చేతితో రాయండి.'
              : 'Could not read the bill from that photo. Take it again, clear and well lit, or write it by hand below.';
        }
      });
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _save({bool another = false}) async {
    final te = askodoxPosTe(context);
    final lines = <AskodoxJson>[];
    for (final l in _lines) {
      final q = askodoxParseMilli(l.qty.text);
      final c = askodoxParsePaise(l.cost.text);
      final p = askodoxParsePaise(l.price.text);
      // Owner 2026-11-26: the selling price is the shop's own choice -- never demanded (birds bought, meat sold).
      if (q == null || q <= 0 || c == null) {
        setState(() => _error = te ? '${l.name.text}: పరిమాణం, కొన్న ధర నింపండి.' : '${l.name.text}: fill the quantity and the cost.');
        return;
      }
      lines.add({
        if (l.productId != null) 'product_id': l.productId,
        'name': l.name.text.trim(),
        'unit': l.unit,
        'qty_milli': q,
        'cost_paise': c,
        'rate_bp': l.rateBp,
        if (l.isNew && p != null && p > 0) 'price_paise': p,
        if (l.batch.isNotEmpty) 'batch_no': l.batch,
        if (l.expiry.text.trim().isNotEmpty) 'expiry_date': l.expiry.text.trim(),
      });
    }
    if (_billNo.text.trim().isEmpty || (_supplierId == null && _supplierName.text.trim().isEmpty)) {
      setState(() => _error = te ? 'సప్లయర్ పేరు, బిల్లు నంబర్ నింపండి.' : 'Fill the supplier name and the bill number.');
      return;
    }
    // Owner 2026-11-26: the total written on the bill ("130 kg") against what the rows add up to -- ask, then save.
    final written = _totalQtyMilli;
    final sum = _qtySum;
    if (written != null && sum != null && written != sum) {
      final unit = _lines.first.unit;
      final ok = await _confirm(
          te,
          te
              ? 'బిల్లు మీద మొత్తం ${_BillLine._milli(written)} $unit అని ఉంది. లైన్లు కలిపితే ${_BillLine._milli(sum)} $unit. ఇలాగే సేవ్ చేయాలా?'
              : 'The bill says ${_BillLine._milli(written)} $unit in total. The rows add up to ${_BillLine._milli(sum)} $unit. Save as it is?');
      if (!ok || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).purchaseFromPhoto(widget.businessId, {
        'client_txn_id': _txn,
        if (_supplierId != null) 'supplier_id': _supplierId,
        'supplier': {
          ..._supplier,
          'name': _supplierName.text.trim(),
          if (!_gstBill) 'gstin': '', // a hand slip has no GSTIN
        },
        'supplier_bill_no': _billNo.text.trim(),
        if (_billDate.isNotEmpty) 'bill_date': _billDate,
        if (_totalPaise != null && !_skipPrintedTotal) 'supplier_total_paise': _totalPaise,
        'lines': [for (final l in lines) _gstBill ? l : {...l, 'rate_bp': 0}],
      });
      if (!mounted) return;
      final created = askodoxPosInt(out['created_items']);
      askodoxPosSnack(
          context,
          te
              ? 'బిల్లు సేవ్ అయింది ✓ స్టాక్ పెరిగింది${created > 0 ? ' · $created కొత్త ఐటమ్స్ చేరాయి' : ''}'
              : 'Bill saved ✓ stock added${created > 0 ? ' · $created new items added' : ''}');
      if (another) {
        _startAnother();
      } else {
        Navigator.of(context).pop(true);
      }
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (e.code == 'total_mismatch' && !_skipPrintedTotal) {
        // the rows do not add up to the amount printed on the bill: the person decides (owner 2026-11-26)
        setState(() => _saving = false);
        final ok = await _confirm(
            te,
            te
                ? 'లైన్లు కలిపితే ₹${_BillLine._rupees(_amountSum)}. బిల్లు మీద ₹${_BillLine._rupees(_totalPaise)} అని ఉంది. లైన్ల మొత్తంతో సేవ్ చేయాలా?'
                : 'The rows add up to ₹${_BillLine._rupees(_amountSum)}. The bill says ₹${_BillLine._rupees(_totalPaise)}. Save with the rows\' total?');
        if (ok && mounted) {
          _skipPrintedTotal = true;
          return _save(another: another);
        }
        return;
      }
      setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "+ another bill": the saved one is done; the screen is ready for the next photo (a new transaction id).
  void _startAnother() {
    setState(() {
      _removed.addAll(_lines);
      _lines.clear();
      _read = false;
      _supplierId = null;
      _supplier = const {};
      _supplierName.clear();
      _billNo.clear();
      _billDate = '';
      _totalPaise = null;
      _totalQtyMilli = null;
      _skipPrintedTotal = false;
      _gstBill = true;
      _error = null;
      _txn = askodoxNewTxnId();
    });
  }

  /// GST on the rows (each row's own rate), rounded per row.
  int get _gstSum => _lines.fold(0, (sum, l) => sum + ((_lineAmount(l) ?? 0) * (_gstBill ? l.rateBp : 0) / 10000).round());

  /// The rows' quantity added up -- only when every row has one unit (kg + pcs are never added).
  int? get _qtySum {
    if (_lines.isEmpty || _lines.any((l) => l.unit != _lines.first.unit)) return null;
    var sum = 0;
    for (final l in _lines) {
      sum += askodoxParseMilli(l.qty.text) ?? 0;
    }
    return sum;
  }

  static int? _lineAmount(_BillLine l) {
    final q = askodoxParseMilli(l.qty.text);
    final c = askodoxParsePaise(l.cost.text);
    return q == null || c == null ? null : (q * c / 1000).round();
  }

  /// Quantity x cost of every row (before GST).
  int get _amountSum => _lines.fold(0, (sum, l) => sum + (_lineAmount(l) ?? 0));

  Future<bool> _confirm(bool te, String text) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                key: const Key('askodoxPosBillPhotoConfirm'),
                content: Text(text),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(te ? 'సరిచేస్తా' : 'Let me fix it')),
                  FilledButton(
                      key: const Key('askodoxPosBillPhotoConfirmYes'),
                      onPressed: () => Navigator.of(dialog).pop(true),
                      child: Text(te ? 'సేవ్ చేయి' : 'Save')),
                ],
              )) ??
      false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(_billDate) ?? now,
        firstDate: DateTime(now.year - 3),
        lastDate: now);
    if (picked != null && mounted) {
      setState(() => _billDate =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  /// 2026-11-24 -> 24-11-2026 (the way the bill writes it).
  static String _dayFirst(String iso) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    return m == null ? iso : '${m.group(3)}-${m.group(2)}-${m.group(1)}';
  }

  InputDecoration _box(String label, {bool warn = false}) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        filled: warn,
        fillColor: warn ? const Color(0xFF3C2A0D) : null,
      );

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లు ఫోటో' : 'Bill photo')),
      body: ListView(key: const Key('askodoxPosBillPhoto'), padding: const EdgeInsets.all(12), children: [
        Text(
            te
                ? 'సప్లయర్ ఇచ్చిన బిల్లు ఫోటో తీయండి. సప్లయర్, ఐటమ్స్, స్టాక్, GST అన్నీ దానంతట అదే నిండుతాయి. మీరు చూసి "సేవ్" నొక్కితే చాలు.'
                : 'Take a photo of the supplier\'s bill. Supplier, items, stock and GST fill by themselves. Check and tap Save.',
            style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('askodoxPosBillPhotoCamera'),
              onPressed: _reading || _saving ? null : () => _photo('camera'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(te ? 'ఫోటో తీయి' : 'Take photo'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('askodoxPosBillPhotoGallery'),
              onPressed: _reading || _saving ? null : () => _photo('photos'),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(te ? 'గ్యాలరీ' : 'Gallery'),
            ),
          ),
        ]),
        if (_reading)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(te ? 'బిల్లు చదువుతున్నాను…' : 'Reading the bill…'),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, key: const Key('askodoxPosBillPhotoError'), style: const TextStyle(color: Color(0xFFFEA293))),
          ),
        // Owner 2026-11-24: when a photo cannot be read the bill is still entered here -- by hand, any supplier.
        if (!_read && !_reading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              key: const Key('askodoxPosBillPhotoByHand'),
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _read = true;
                        _error = null;
                        if (_lines.isEmpty) _lines.add(_BillLine(const {'new': true}));
                      }),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(te ? 'ఫోటో లేకుండా చేతితో రాయి' : 'Write it by hand instead'),
            ),
          ),
        if (_read && !_reading) ...[
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            key: const Key('askodoxPosBillPhotoKind'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(te ? 'GST బిల్ (రిజిస్టర్డ్)' : 'GST bill (registered)', textAlign: TextAlign.center)),
              ButtonSegment(value: false, label: Text(te ? 'GST లేని / చేతి చీటీ' : 'No GST / hand slip', textAlign: TextAlign.center)),
            ],
            selected: {_gstBill},
            onSelectionChanged: (v) => setState(() {
              _gstBill = v.first;
              if (!_gstBill) {
                for (final l in _lines) {
                  l.rateBp = 0;
                }
              }
            }),
          ),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxPosBillPhotoSupplier'),
              controller: _supplierName,
              readOnly: _supplierId != null,
              onChanged: (_) => setState(() {}),
              decoration: _box(
                  _supplierId != null ? (te ? 'సప్లయర్ (మీ జాబితాలో ఉంది ✓)' : 'Supplier (already in your list ✓)') : (te ? 'సప్లయర్ పేరు (కొత్తది అయితే చేరుతుంది)' : 'Supplier name (a new one is added)'),
                  warn: _supplierName.text.trim().isEmpty).copyWith(
                suffixIcon: _supplierId == null
                    ? null
                    : IconButton(
                        key: const Key('askodoxPosBillPhotoSupplierChange'),
                        tooltip: te ? 'వేరే సప్లయర్' : 'Another supplier',
                        icon: const Icon(Icons.edit_rounded),
                        onPressed: () => setState(() {
                          _supplierId = null;
                          _supplier = const {};
                        }),
                      ),
              )),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxPosBillPhotoNumber'),
              controller: _billNo,
              onChanged: (_) => setState(() {}),
              decoration: _box(te ? 'బిల్లు నంబర్' : 'Bill number', warn: _billNo.text.trim().isEmpty)),
          const SizedBox(height: 8),
          // Owner 2026-11-26: the date written on the bill ("24/11") is shown and can be changed; empty = today.
          InkWell(
            key: const Key('askodoxPosBillPhotoDate'),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: _box(te ? 'బిల్లు తేదీ' : 'Bill date').copyWith(suffixIcon: const Icon(Icons.event_rounded)),
              child: Text(_billDate.isEmpty ? (te ? 'ఈ రోజు (మార్చడానికి నొక్కండి)' : 'Today (tap to change)') : _dayFirst(_billDate)),
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _lines.length; i++)
            Card(
              key: ValueKey('askodoxPosBillPhotoLine-$i'),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                          controller: _lines[i].name,
                          readOnly: !_lines[i].isNew,
                          decoration: _box(_lines[i].isNew ? (te ? 'కొత్త ఐటమ్' : 'New item') : (te ? 'మీ ఐటమ్ ✓' : 'Your item ✓'))),
                    ),
                    IconButton(
                      tooltip: te ? 'ఈ లైన్ తీసేయి' : 'Remove this line',
                      onPressed: () => setState(() => _removed.add(_lines.removeAt(i))),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                          controller: _lines[i].qty,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: _box('${te ? 'ఎన్ని' : 'Qty'} (${_lines[i].unit})', warn: _lines[i].qty.text.trim().isEmpty)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                          controller: _lines[i].cost,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: _box(te ? 'కొన్న ధర ₹' : 'Cost ₹', warn: _lines[i].cost.text.trim().isEmpty)),
                    ),
                    if (_lines[i].isNew) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                            controller: _lines[i].price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: _box(te ? 'అమ్మే ధర ₹ (ఉంటే)' : 'Sell ₹ (if any)')),
                      ),
                    ],
                  ]),
                  if (_lineAmount(_lines[i]) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          '${_lines[i].qty.text.trim()} × ₹${_lines[i].cost.text.trim()} = ₹${_BillLine._rupees(_lineAmount(_lines[i]))}',
                          key: ValueKey('askodoxPosBillPhotoLineAmount-$i'),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _rates.contains(_lines[i].rateBp) ? _lines[i].rateBp : 0,
                        isExpanded: true,
                        decoration: _box('GST %'),
                        items: [for (final r in _rates) DropdownMenuItem(value: r, child: Text('${r / 100}%'))],
                        onChanged: (v) => setState(() => _lines[i].rateBp = v ?? _lines[i].rateBp),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                          controller: _lines[i].expiry,
                          decoration: _box(te ? 'ఎక్స్‌పైరీ (YYYY-MM-DD)' : 'Expiry (YYYY-MM-DD)')),
                    ),
                  ]),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('askodoxPosBillPhotoAddLine'),
              onPressed: () => setState(() => _lines.add(_BillLine(const {'new': true}))),
              icon: const Icon(Icons.add_rounded),
              label: Text(te ? 'ఐటమ్ జోడించు' : 'Add an item'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              '${te ? 'లైన్ల మొత్తం' : 'Rows add up to'}: '
              '${_qtySum != null ? '${_BillLine._milli(_qtySum)} ${_lines.first.unit} · ' : ''}₹${_BillLine._rupees(_amountSum)}',
              key: const Key('askodoxPosBillPhotoSum'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (_totalQtyMilli != null && _qtySum != null)
            Text(
                '${te ? 'బిల్లు మీద రాసిన మొత్తం' : 'Total written on the bill'}: ${_BillLine._milli(_totalQtyMilli)} ${_lines.first.unit}'
                '${_totalQtyMilli == _qtySum ? ' ✓' : (te ? ' — సరిపోలేదు' : ' — does not match')}',
                key: const Key('askodoxPosBillPhotoWrittenQty'),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: _totalQtyMilli == _qtySum ? null : const Color(0xFFFB9F7A))),
          if (_gstBill && _gstSum > 0) ...[
            Text('${te ? 'GST' : 'GST'}: ₹${_BillLine._rupees(_gstSum)}', key: const Key('askodoxPosBillPhotoGst')),
            Text('${te ? 'మొత్తం (GST తో)' : 'Total with GST'}: ₹${_BillLine._rupees(_amountSum + _gstSum)}',
                key: const Key('askodoxPosBillPhotoTotalWithGst'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
          if (_totalPaise != null)
            Text('${te ? 'బిల్లు మీద మొత్తం' : 'Total printed on the bill'}: ₹${_BillLine._rupees(_totalPaise)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const AskodoxEstimateNote(),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('askodoxPosBillPhotoSaveNext'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: _saving || _lines.isEmpty ? null : () => _save(another: true),
            icon: const Icon(Icons.add_rounded),
            label: Text(te ? 'సేవ్ చేసి మరో బిల్' : 'Save and add another bill'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('askodoxPosBillPhotoSave'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _saving || _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? (te ? 'సేవ్ అవుతోంది…' : 'Saving…') : (te ? 'బిల్లు సేవ్ చేయి (స్టాక్ పెరుగుతుంది)' : 'Save bill (adds the stock)')),
          ),
        ],
      ]),
    );
  }
}
