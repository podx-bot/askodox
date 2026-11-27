import '../../../config/theme/askodox_look.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_commands.dart';
import '../../pos/domain/pos_item_icons.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_dues_screen.dart' show askodoxDueDateChoices, askodoxIsoDay;
import '../../pos/presentation/pos_sale_screen.dart' show askodoxPrintInvoice;
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// `/me/business/:id/bill` (owner 2026-11-22, "3 steps"): ① what did they take? (item tiles: tap = 1, tap again =
/// more, hold = type the weight; a shop with no items types the amount) ② how did they pay? (cash / online / due,
/// three big cards) ③ ✓ with WhatsApp / print. The mic takes "12 number 2, UPI": the items appear on the tiles and the
/// way of paying is pre-selected -- the cashier still sees and taps it (nothing is billed silently).
/// The old full page (GST, advance, revise) stays at `?full=1`, in "⋮".
class AskodoxBillStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBillStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBillStepsScreen> createState() => _AskodoxBillStepsScreenState();
}

class _Extra {
  const _Extra(this.name, this.paise, {this.qtyMilli = 0, this.ratePaise = 0});
  final String name;
  final int paise;

  /// Only calculator rows (quantity x rate) carry these; "Other" lines are a name + one amount.
  final int qtyMilli;
  final int ratePaise;
}

class _CalcRow {
  final name = TextEditingController();
  final qty = TextEditingController();
  final rate = TextEditingController();
  void dispose() {
    name.dispose();
    qty.dispose();
    rate.dispose();
  }
}

const _tileColors = [
  Color(0xFF123624), Color(0xFF402804), Color(0xFF222C4A), Color(0xFF332842), Color(0xFF402623), Color(0xFF0F3433),
];

class _AskodoxBillStepsScreenState extends ConsumerState<AskodoxBillStepsScreen> {
  int _step = 1;
  List<AskodoxJson>? _menu;
  Object? _menuError;
  final Map<String, int> _qty = {};
  final List<_Extra> _extras = [];
  String _typed = '';
  final _search = TextEditingController();
  String _q = '';
  String? _said;
  bool _busy = false;
  String _txn = askodoxNewTxnId();
  AskodoxJson? _saved;
  String _paidHow = '';
  String _dueOn = '';
  String _shopName = '';
  String _upi = '';
  String _payee = '';
  String _phone = '';
  int _onlinePart = 0;

  bool get _te => askodoxPosTe(context);

  List<AskodoxJson> get _items => [
        for (final m in _menu ?? const <AskodoxJson>[])
          if (m['available'] != false) m,
      ];

  AskodoxJson? _item(String id) => _items.where((m) => '${m['id']}' == id).firstOrNull;

  int get _totalPaise {
    var sum = 0;
    for (final e in _qty.entries) {
      final m = _item(e.key);
      if (m != null) sum += askodoxLinePaise(askodoxPosInt(m['price_paise']), e.value);
    }
    for (final x in _extras) {
      sum += x.paise;
    }
    if (_items.isEmpty) sum += askodoxKeypadPaise(_typed);
    return sum;
  }

  int get _lineCount => _qty.values.where((q) => q > 0).length + _extras.length + (_items.isEmpty && _typed.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    for (final r in _calcRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(askodoxPosRepositoryProvider);
    try {
      final menu = [
        for (final m in askodoxPosList((await repo.deskMenu(widget.businessId))['items']))
          if (m['buy_only'] != true) m, // a bought item with no selling price is never billed
      ];
      if (mounted) {
        setState(() {
          _menu = menu;
          _menuError = null;
        });
      }
    } catch (e) {
      // Staff who may bill but not open the menu, or no network: the amount pad still works (as the old page did).
      if (mounted) {
        setState(() {
          _menu = const [];
          _menuError = e;
        });
      }
    }
    unawaited(repo.shopState(widget.businessId).then((shop) {
      if (mounted) setState(() => _shopName = '${shop['name'] ?? ''}');
    }, onError: (_) {}));
    unawaited(repo.myPaymentMethods().then((methods) {
      final upis = [for (final m in methods) if ('${m['upi_id'] ?? ''}'.isNotEmpty) m];
      if (upis.isEmpty || !mounted) return;
      final m = upis.firstWhere((u) => u['is_default'] == true, orElse: () => upis.first);
      setState(() {
        _upi = '${m['upi_id']}';
        _payee = '${m['payee_name'] ?? ''}';
      });
    }, onError: (_) {}));
  }

  String _unitTe(String unit) => switch (unit.toLowerCase()) {
        'kg' => 'kg',
        'pcs' || 'pc' || 'piece' => _te ? 'ఒకటి' : 'each',
        'plate' => _te ? 'ప్లేట్' : 'plate',
        'dozen' => _te ? 'డజను' : 'dozen',
        'l' || 'litre' => _te ? 'లీటర్' : 'litre',
        'pack' => _te ? 'ప్యాకెట్' : 'pack',
        _ => unit,
      };

  String _name(AskodoxJson m) => _te && '${m['name_te'] ?? ''}'.isNotEmpty ? '${m['name_te']}' : '${m['name']}';

  void _tap(AskodoxJson m) {
    HapticFeedback.selectionClick();
    final id = '${m['id']}';
    setState(() {
      _qty[id] = askodoxBillTapQty(_qty[id] ?? 0, '${m['unit'] ?? 'pcs'}');
      _txn = askodoxNewTxnId();
    });
  }

  /// Hold a tile: the exact weight / count (quick ¼ ½ ¾ 1 1½ 2), or take it off the bill.
  Future<void> _hold(AskodoxJson m) async {
    final id = '${m['id']}';
    final unit = '${m['unit'] ?? 'pcs'}';
    final weighed = askodoxWeighable(unit);
    final box = TextEditingController(text: askodoxQtyShort(_qty[id] ?? 0));
    final quick = weighed ? const [250, 500, 750, 1000, 1500, 2000] : const [1000, 2000, 3000, 4000, 5000, 6000];
    final te = _te;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? '${_name(m)} — ఎంత?' : '${_name(m)} — how much?',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: askodoxStepInk)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in quick)
              ActionChip(
                key: Key('askodoxBillQty-$q'),
                label: Text('${askodoxQtyShort(q)} ${_unitTe(unit)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                onPressed: () => Navigator.of(sheet).pop(q),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            key: const Key('askodoxBillQtyBox'),
            controller: box,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                border: const OutlineInputBorder(), labelText: te ? 'లేదా టైప్ చేయండి (${_unitTe(unit)})' : 'Or type (${_unitTe(unit)})'),
            onSubmitted: (v) => Navigator.of(sheet).pop(askodoxParseQtyMilli(v)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('askodoxBillQtyRemove'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: askodoxStepBad),
                onPressed: () => Navigator.of(sheet).pop(0),
                child: Text(te ? 'తీసేయి' : 'Remove'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('askodoxBillQtyOk'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: askodoxStepGreen),
                onPressed: () => Navigator.of(sheet).pop(askodoxParseQtyMilli(box.text)),
                child: Text(te ? 'సరే' : 'OK'),
              ),
            ),
          ]),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked <= 0) {
        _qty.remove(id);
      } else {
        _qty[id] = picked;
      }
      _txn = askodoxNewTxnId();
    });
  }

  /// "Something else": a name + an amount for a thing not on the menu.
  Future<void> _other() async {
    final te = _te;
    final name = TextEditingController();
    var typed = '';
    final out = await showModalBottomSheet<_Extra>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: const Key('askodoxBillOtherName'),
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ఏం ఇచ్చారు?' : 'What was it?'),
            ),
            AskodoxStepAmountPad(value: typed, onChanged: (v) => setInner(() => typed = v), label: te ? 'ఎంత?' : 'How much?'),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('askodoxBillOtherOk'),
                style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen),
                onPressed: () {
                  final paise = askodoxKeypadPaise(typed);
                  if (paise <= 0 || name.text.trim().isEmpty) return;
                  Navigator.of(sheet).pop(_Extra(name.text.trim(), paise));
                },
                child: Text(te ? 'చేర్చు' : 'Add', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (out == null || !mounted) return;
    setState(() {
      _extras.add(out);
      _txn = askodoxNewTxnId();
    });
  }

  /// The mic: items said by number / name go onto the tiles; a way of paying said with them pre-selects it and
  /// opens step 2 (the cashier still taps it).
  void _heard(String words) {
    final te = _te;
    if (words.trim().isEmpty) return;
    var added = 0;
    if (_items.isEmpty) {
      final paise = askodoxSpokenRupees(words);
      if (paise != null && paise > 0) {
        _typed = '${paise ~/ 100}';
        added = 1;
      }
    } else {
      final refs = [
        for (final m in _items)
          AskodoxPosItemRef(
              id: '${m['id']}',
              name: '${m['name']}',
              nameTe: '${m['name_te'] ?? ''}',
              unit: '${m['unit'] ?? 'pcs'}',
              itemNo: askodoxPosInt(m['item_no'])),
      ];
      for (final p in askodoxParsePosOrder(words, refs)) {
        final c = p.command;
        final item = c.item;
        if (item == null) continue;
        if (c.kind == AskodoxPosCommandKind.add) {
          _qty[item.id] = (c.qtyMilli ?? 1000) > 0 ? (c.qtyMilli ?? 1000) : 1000;
          added++;
        } else if (c.kind == AskodoxPosCommandKind.remove) {
          _qty.remove(item.id);
          added++;
        }
      }
    }
    final said = askodoxSpokenPayMethod(words);
    setState(() {
      if (said != null) _said = said;
      _txn = askodoxNewTxnId();
      if (added > 0 && said != null && _totalPaise > 0) _step = 2;
    });
    askodoxPosSnack(
        context,
        added == 0
            ? (te ? 'అర్థం కాలేదు: "$words" — బొమ్మలు నొక్కండి.' : 'Not understood: "$words" — tap the tiles.')
            : (te ? '$added చేర్చాను — చూసుకోండి.' : 'Added $added — please check.'));
  }

  AskodoxJson _lineFor(AskodoxJson m, int milli) {
    final price = askodoxPosInt(m['price_paise']);
    final no = askodoxPosInt(m['item_no']);
    return {
      if (no > 0) 'item_no': no,
      'name': '${m['name']}',
      'amount_paise': askodoxLinePaise(price, milli),
      'rate_paise': price,
      'qty_milli': milli,
    };
  }

  List<AskodoxJson> _lines() => [
        for (final e in _qty.entries)
          if (e.value > 0 && _item(e.key) != null) _lineFor(_item(e.key)!, e.value),
        for (final x in _extras)
          {
            'name': x.name,
            'amount_paise': x.paise,
            if (x.qtyMilli > 0 && x.ratePaise > 0) ...{'qty_milli': x.qtyMilli, 'rate_paise': x.ratePaise},
          },
        if (_items.isEmpty && askodoxKeypadPaise(_typed) > 0) {'name': '', 'amount_paise': askodoxKeypadPaise(_typed)},
      ];

  String _summary() {
    final parts = <String>[
      for (final e in _qty.entries)
        if (e.value > 0 && _item(e.key) != null)
          '${_name(_item(e.key)!)} ${askodoxQtyShort(e.value)}${askodoxWeighable('${_item(e.key)!['unit']}') ? ' kg' : ''}',
      for (final x in _extras) x.name,
    ];
    return parts.join(', ');
  }

  /// Makes the real bill (one tap on a way of paying). The same tap twice is the same bill (txn id).
  Future<void> _make(String how, {int advance = -1, int cash = 0, int online = 0, String name = '', String phone = '', String dueDate = ''}) async {
    final te = _te;
    final total = _totalPaise;
    if (total <= 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).quickBill(widget.businessId, {
        'lines': _lines(),
        'advance_paise': how == 'split' ? 0 : (advance < 0 ? total : advance),
        'method': how == 'online' ? 'online' : 'cash',
        if (how == 'split') ...{'cash_paise': cash, 'online_paise': online},
        'name': name,
        'phone': phone,
        'rate_bp': 0,
        'client_txn_id': _txn,
      });
      if (!mounted) return;
      setState(() {
        _saved = out;
        _paidHow = how;
        _phone = phone;
        _dueOn = dueDate;
        _onlinePart = how == 'split' ? online : (how == 'online' ? askodoxPosInt(askodoxPosMap(out['totals'])['grand_total_paise']) : 0);
        _step = 3;
      });
      if (dueDate.isNotEmpty && askodoxPosInt(out['pending_paise']) > 0) {
        unawaited(ref
            .read(askodoxPosRepositoryProvider)
            .setDueDate(widget.businessId, '${out['id']}', dueDate)
            .then((_) => null, onError: (_) => null));
      }
    } on AskodoxPosException catch (e) {
      if (mounted) {
        askodoxPosSnack(
            context,
            e.code == 'balance' || e.code == 'payment'
                ? (te ? 'బాకీ ఉంటే కస్టమర్ పేరు లేదా ఫోన్ రాయండి.' : 'For a due bill give the customer name or phone.')
                : e.message(te));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Due: who (name / number), when they will pay, and anything paid now.
  Future<void> _due() async {
    final te = _te;
    final name = TextEditingController();
    final phone = TextEditingController();
    final paid = TextEditingController();
    final choices = askodoxDueDateChoices(DateTime.now());
    var pick = choices[2];
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'బాకీ ఎవరిది?' : 'Whose due?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: askodoxStepInk)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('askodoxBillDueName'),
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'పేరు' : 'Name'),
            ),
            TextField(
              key: const Key('askodoxBillDuePhone'),
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  border: const OutlineInputBorder(), labelText: te ? 'ఫోన్ నంబర్ (గుర్తు పంపడానికి)' : 'Phone (for reminders)'),
            ),
            const SizedBox(height: 10),
            Text(te ? 'ఎప్పుడు కడతారు?' : 'When will they pay?', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in choices)
                ChoiceChip(
                  key: Key('askodoxBillDueWhen-${c.$1}'),
                  label: Text(te ? c.$2 : c.$1),
                  selected: pick == c,
                  onSelected: (_) => setInner(() => pick = c),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              key: const Key('askodoxBillDuePaid'),
              controller: paid,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  border: const OutlineInputBorder(), labelText: te ? 'ఇప్పుడు కొంత ఇచ్చారా? (₹, లేకపోతే ఖాళీ)' : 'Paid anything now? (₹, else empty)'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('askodoxBillDueOk'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF9A79)),
                onPressed: () {
                  if (name.text.trim().isEmpty && askodoxTenDigits(phone.text).isEmpty) return;
                  Navigator.of(sheet).pop(true);
                },
                child: Text(te ? 'బాకీగా బిల్లు వేయి' : 'Bill as due', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
    final n = name.text.trim();
    final p = askodoxTenDigits(phone.text);
    final paidNow = askodoxSpokenRupees(paid.text) ?? 0;
    // The sheet's boxes are still drawn while it slides away, so the controllers are left to the garbage collector.
    if (go != true || !mounted) return;
    await _make('due', advance: paidNow.clamp(0, _totalPaise), name: n, phone: p, dueDate: askodoxIsoDay(pick.$3));
  }

  /// Part cash, part online: the cash typed, the rest online.
  Future<void> _split() async {
    final te = _te;
    final total = _totalPaise;
    final cash = await askodoxAskAmount(context,
        title: te ? 'క్యాష్ ఎంత ఇచ్చారు? మిగతాది ఆన్‌లైన్' : 'How much in cash? The rest online');
    if (cash == null || !mounted) return;
    if (cash <= 0 || cash >= total) {
      askodoxPosSnack(context, te ? 'క్యాష్ బిల్లు కంటే తక్కువ ఉండాలి.' : 'Cash must be less than the bill.');
      return;
    }
    await _make('split', cash: cash, online: total - cash);
  }

  Future<void> _send() async {
    final te = _te;
    var digits = _phone;
    if (digits.isEmpty) {
      final box = TextEditingController();
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(te ? 'కస్టమర్ నంబర్' : "Customer's number",
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: askodoxStepInk)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('askodoxBillSendPhone'),
              controller: box,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: '+91 '),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('askodoxBillSendOk'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF75D48B)),
                onPressed: () => Navigator.of(sheet).pop(true),
                child: Text(te ? 'పంపు' : 'Send'),
              ),
            ),
          ]),
        ),
      );
      digits = askodoxTenDigits(box.text);
      if (ok != true || !mounted) return;
      if (digits.isEmpty) {
        askodoxPosSnack(context, te ? '10 అంకెల నంబర్ రాయండి.' : 'Type a 10-digit number.');
        return;
      }
      _phone = digits;
    }
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).billSend(widget.businessId, '${_saved!['id']}', digits);
      if (!mounted) return;
      if ('${out['channel']}' == 'askodox') {
        askodoxPosSnack(context, te ? 'బిల్లు కస్టమర్ ASKODOX యాప్‌లోకి వెళ్ళింది ✓' : "Sent to the customer's ASKODOX app ✓");
        return;
      }
      final text = '${out['text'] ?? ''}';
      final uri = Uri.parse('https://wa.me/${out['whatsapp_to']}?text=${Uri.encodeComponent(text)}');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) askodoxPosSnack(context, te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  /// Calculator bill (owner 2026-11-26): rows of name + quantity x rate with a running total, added to THIS bill; the
  /// way of paying, WhatsApp share and print are the same steps 2-3 as every other bill.
  final List<_CalcRow> _calcRows = [];

  Future<void> _calculator() async {
    final rows = <_CalcRow>[_CalcRow()];
    final out = await showModalBottomSheet<List<_Extra>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setInner) {
          final te = _te;
          final total = rows.fold<int>(0, (sum, r) => sum + askodoxCalcRowPaise(r.qty.text, r.rate.text));
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(te ? 'కాలిక్యులేటర్ బిల్లు' : 'Calculator bill',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: askodoxStepInk)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          flex: 5,
                          child: TextField(
                            key: Key('askodoxBillCalcName-$i'),
                            controller: rows[i].name,
                            decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: te ? 'పేరు' : 'Name'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: Key('askodoxBillCalcQty-$i'),
                            controller: rows[i].qty,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setInner(() {}),
                            decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: te ? 'సంఖ్య' : 'Qty'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: Key('askodoxBillCalcRate-$i'),
                            controller: rows[i].rate,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setInner(() {}),
                            decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: te ? 'రేటు ₹' : 'Rate ₹'),
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(askodoxStepRupees(askodoxCalcRowPaise(rows[i].qty.text, rows[i].rate.text)),
                              key: Key('askodoxBillCalcAmount-$i'),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: askodoxStepGreenDark)),
                        ),
                      ]),
                    ),
                ]),
              ),
              Row(children: [
                TextButton.icon(
                  key: const Key('askodoxBillCalcAddRow'),
                  onPressed: () => setInner(() => rows.add(_CalcRow())),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(te ? 'వరుస చేర్చు' : 'Add a row'),
                ),
                const Spacer(),
                Text(askodoxStepRupees(total),
                    key: const Key('askodoxBillCalcTotal'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: askodoxStepInk)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  key: const Key('askodoxBillCalcOk'),
                  style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen),
                  onPressed: total <= 0
                      ? null
                      : () {
                          final lines = <_Extra>[];
                          for (final r in rows) {
                            final paise = askodoxCalcRowPaise(r.qty.text, r.rate.text);
                            if (paise <= 0) continue;
                            final name = r.name.text.trim();
                            lines.add(_Extra(name.isEmpty ? (te ? 'ఐటమ్' : 'Item') : name, paise,
                                qtyMilli: askodoxParseQtyMilli(r.qty.text) ?? 0,
                                ratePaise: askodoxCalcRatePaise(r.rate.text)));
                          }
                          Navigator.of(sheet).pop(lines);
                        },
                  child: Text(te ? 'బిల్లులో చేర్చు' : 'Add to the bill', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          );
        },
      ),
    );
    // The sheet is still animating out here: disposing now breaks its last frame.
    // The controllers are disposed with the page instead.
    _calcRows.addAll(rows);
    if (out == null || out.isEmpty || !mounted) return;
    setState(() {
      _extras.addAll(out);
      _txn = askodoxNewTxnId();
    });
  }

  void _newBill() {
    setState(() {
      _qty.clear();
      _extras.clear();
      _typed = '';
      _said = null;
      _saved = null;
      _paidHow = '';
      _dueOn = '';
      _phone = '';
      _onlinePart = 0;
      _q = '';
      _search.clear();
      _txn = askodoxNewTxnId();
      _step = 1;
    });
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final id = widget.businessId;
    return [
      AskodoxStepMore('askodoxBillStepsFull', te ? 'పూర్తి బిల్లు పేజీ (GST, అడ్వాన్స్, మార్పు)' : 'Full bill page (GST, advance, edit)',
          Icons.receipt_long_rounded, () => context.push('/me/business/$id/bill?full=1')),
      AskodoxStepMore('askodoxBillStepsCalc', te ? 'కాలిక్యులేటర్ బిల్లు (సంఖ్య × రేటు)' : 'Calculator bill (qty × rate)',
          Icons.calculate_rounded, _calculator),
      AskodoxStepMore('askodoxBillStepsHistory', te ? 'బిల్లుల చరిత్ర' : 'Bill history', Icons.history_rounded,
          () => context.push('/biz/$id/money/history')),
      AskodoxStepMore('askodoxBillStepsItems', te ? 'ఐటమ్స్ చేర్చు / మార్చు' : 'Add / change items', Icons.list_alt_rounded,
          () => context.push('/desk/$id/menu')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'బిల్లు చేయి' : 'Make a bill';
    return switch (_step) {
      2 => AskodoxStepScaffold(
          key: const Key('askodoxBillSteps2'),
          title: title,
          sub: _shopName,
          step: 2,
          question: te ? 'ఎలా కట్టారు?' : 'How did they pay?',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: _payStep(te),
        ),
      3 => AskodoxStepScaffold(
          key: const Key('askodoxBillSteps3'),
          title: title,
          sub: _shopName,
          step: 3,
          more: _more(),
          body: _doneStep(te),
          bottom: AskodoxStepBottom(
              buttonKey: const Key('askodoxBillStepsNew'), label: te ? 'తర్వాతి బిల్లు' : 'Next bill', icon: Icons.add_rounded, onPressed: _newBill),
        ),
      _ => AskodoxStepScaffold(
          key: const Key('askodoxBillSteps1'),
          title: title,
          sub: _shopName,
          step: 1,
          question: _items.isEmpty && _menu != null ? (te ? 'ఎంత?' : 'How much?') : (te ? 'ఏం ఇచ్చారు?' : 'What did they take?'),
          hint: _items.isEmpty
              ? null
              : (te ? 'నొక్కితే 1 · మళ్ళీ నొక్కితే ఇంకా · పట్టుకుంటే బరువు టైప్' : 'Tap = 1 · tap again = more · hold = type the weight'),
          more: _more(),
          body: _itemsStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxBillStepsNext'),
            label: _totalPaise > 0
                ? (te ? 'తర్వాత · ${askodoxStepRupees(_totalPaise)}' : 'Next · ${askodoxStepRupees(_totalPaise)}')
                : (te ? 'తర్వాత' : 'Next'),
            icon: Icons.arrow_forward_rounded,
            onPressed: _totalPaise > 0 ? () => setState(() => _step = 2) : null,
            onSpoken: _heard,
          ),
        ),
    };
  }

  Widget _itemsStep(bool te) {
    if (_menu == null) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        if (_menuError != null)
          TextButton.icon(
            key: const Key('askodoxBillStepsRetry'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(te ? 'ఐటమ్స్ రాలేదు — మళ్ళీ ప్రయత్నించు' : 'Items did not load — try again'),
          )
        else
          TextButton.icon(
            key: const Key('askodoxBillStepsAddItems'),
            onPressed: () => context.push('/desk/${widget.businessId}/menu'),
            icon: const Icon(Icons.add_box_rounded),
            // Items exist but every one is out of stock / switched off: say that, not "add items".
            label: Text((_menu ?? const []).isNotEmpty
                ? (te
                    ? '${_menu!.length} ఐటమ్స్ స్టాక్ అయిపోయాయి / ఆఫ్‌లో ఉన్నాయి — ఇక్కడ సరిచేయి'
                    : '${_menu!.length} items are out of stock / switched off — fix here')
                : (te ? 'ఐటమ్స్ చేర్చితే ఇక్కడ బొమ్మలుగా వస్తాయి' : 'Add items and they show here as tiles')),
          ),
        if (_extras.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (var i = 0; i < _extras.length; i++)
              InputChip(
                key: Key('askodoxBillExtraChip-$i'),
                label: Text('${_extras[i].name} ${askodoxStepRupees(_extras[i].paise)}'),
                onDeleted: () => setState(() {
                  _extras.removeAt(i);
                  _txn = askodoxNewTxnId();
                }),
              ),
          ]),
        AskodoxStepAmountPad(value: _typed, onChanged: (v) => setState(() {
              _typed = v;
              _txn = askodoxNewTxnId();
            })),
      ]);
    }
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? _items
        : _items
            .where((m) =>
                '${m['name']} ${m['name_te'] ?? ''}'.toLowerCase().contains(q) || '${m['item_no'] ?? ''}' == q)
            .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Row(children: [
          Expanded(
            child: Container(
              key: const Key('askodoxBillStepsTotal'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(16)),
              child: Text(
                  _totalPaise > 0
                      ? (te ? '${askodoxStepRupees(_totalPaise)} · $_lineCount ఐటమ్స్' : '${askodoxStepRupees(_totalPaise)} · $_lineCount items')
                      : (te ? 'ఇంకా ఏమీ లేదు' : 'Nothing yet'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: askodoxStepGreenDark)),
            ),
          ),
          if (_totalPaise > 0)
            IconButton(
              key: const Key('askodoxBillStepsClear'),
              tooltip: te ? 'ఖాళీ చేయి' : 'Clear',
              onPressed: () => setState(() {
                _qty.clear();
                _extras.clear();
                _txn = askodoxNewTxnId();
              }),
              icon: const Icon(Icons.delete_sweep_outlined, color: askodoxStepMuted),
            ),
        ]),
      ),
      if (_items.length > 12)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: AskodoxStepSearch(
            fieldKey: const Key('askodoxBillStepsSearch'),
            controller: _search,
            hint: te ? 'నంబర్ / పేరు' : 'Number / name',
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
          itemCount: shown.length + 1 + _extras.length,
          itemBuilder: (context, i) {
            if (i < shown.length) return _tile(shown[i], te);
            final x = i - shown.length;
            if (x < _extras.length) return _extraTile(x, te);
            return _otherTile(te);
          },
        ),
      ),
    ]);
  }

  Widget _tile(AskodoxJson m, bool te) {
    final id = '${m['id']}';
    final qty = _qty[id] ?? 0;
    final unit = '${m['unit'] ?? 'pcs'}';
    final no = askodoxPosInt(m['item_no']);
    final bg = _tileColors[(no > 0 ? no : id.hashCode.abs()) % _tileColors.length];
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: Material(
          color: AskodoxLook.sheet,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: Key('askodoxBillTile-$id'),
            borderRadius: BorderRadius.circular(20),
            onTap: () => _tap(m),
            onLongPress: () => _hold(m),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: qty > 0 ? askodoxStepDone : askodoxStepLine, width: qty > 0 ? 2.5 : 1.5),
              ),
              child: Column(children: [
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(17)),
                  child: Text(askodoxItemIcon('${m['name']}', nameTe: '${m['name_te'] ?? ''}'), style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(_name(m),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w800, color: askodoxStepInk)),
                ),
                Text('${no > 0 ? '#$no · ' : ''}${askodoxStepRupees(askodoxPosInt(m['price_paise']))}/${_unitTe(unit)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: askodoxStepMuted)),
              ]),
            ),
          ),
        ),
      ),
      if (qty > 0)
        Positioned(
          top: -7,
          right: -5,
          child: Container(
            key: Key('askodoxBillTileQty-$id'),
            constraints: const BoxConstraints(minWidth: 28),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: askodoxStepDone, borderRadius: BorderRadius.circular(14), border: Border.all(color: AskodoxLook.sheet, width: 2.5)),
            child: Text(askodoxQtyShort(qty), style: const TextStyle(color: AskodoxLook.sheet, fontSize: 12.5, fontWeight: FontWeight.w900)),
          ),
        ),
    ]);
  }

  Widget _extraTile(int index, bool te) {
    final x = _extras[index];
    return Material(
      color: askodoxStepGreenSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('askodoxBillExtra-$index'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _extras.removeAt(index);
          _txn = askodoxNewTxnId();
        }),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.close_rounded, size: 18, color: askodoxStepMuted),
            const SizedBox(height: 4),
            Text(x.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: askodoxStepInk)),
            Text(askodoxStepRupees(x.paise), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: askodoxStepGreenDark)),
          ]),
        ),
      ),
    );
  }

  Widget _otherTile(bool te) => Material(
        color: AskodoxLook.sheet,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('askodoxBillOther'),
          borderRadius: BorderRadius.circular(20),
          onTap: _other,
          child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF9299A4), width: 1.5)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_rounded, size: 32, color: Color(0xFFC0CDE0)),
              const SizedBox(height: 4),
              Text(te ? 'వేరేది' : 'Other', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFC0CDE0))),
            ]),
          ),
        ),
      );

  Widget _payStep(bool te) {
    final total = _totalPaise;
    final said = te ? 'మీరు చెప్పింది' : 'You said';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
      AskodoxStepBigNumber(askodoxStepRupees(total), label: _summary().isEmpty ? null : _summary(), size: 46),
      const SizedBox(height: 14),
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator()),
      AskodoxStepChoice(
        key: const Key('askodoxBillPayCash'),
        icon: Icons.payments_rounded,
        color: const Color(0xFF75D48B),
        title: te ? 'క్యాష్' : 'Cash',
        sub: te ? 'చేతికి డబ్బు ఇచ్చారు' : 'Paid in cash',
        selected: _said == 'cash',
        badge: _said == 'cash' ? said : null,
        onTap: _busy ? null : () => _make('cash'),
      ),
      const SizedBox(height: 12),
      AskodoxStepChoice(
        key: const Key('askodoxBillPayOnline'),
        icon: Icons.qr_code_2_rounded,
        color: const Color(0xFFA0BFFF),
        title: te ? 'ఆన్‌లైన్ / UPI' : 'Online / UPI',
        sub: te ? 'QR చూపిస్తాం · వచ్చినప్పుడు ఫోన్ చెప్తుంది' : 'We show the QR · the phone speaks when it lands',
        selected: _said == 'online',
        badge: _said == 'online' ? said : null,
        onTap: _busy ? null : () => _make('online'),
      ),
      const SizedBox(height: 12),
      AskodoxStepChoice(
        key: const Key('askodoxBillPayDue'),
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFFF9A79),
        title: te ? 'బాకీ' : 'Due',
        sub: te ? 'తర్వాత కడతారు — పేరు అడుగుతాం' : 'They pay later — we ask the name',
        selected: _said == 'due',
        badge: _said == 'due' ? said : null,
        onTap: _busy ? null : _due,
      ),
      const SizedBox(height: 6),
      TextButton(
        key: const Key('askodoxBillPaySplit'),
        onPressed: _busy ? null : _split,
        child: Text(te ? 'కొంత క్యాష్, కొంత ఆన్‌లైన్?' : 'Part cash, part online?'),
      ),
    ]);
  }

  Widget _doneStep(bool te) {
    final saved = _saved ?? const <String, Object?>{};
    final total = askodoxPosInt(askodoxPosMap(saved['totals'])['grand_total_paise']);
    final shown = total > 0 ? total : _totalPaise;
    final pending = askodoxPosInt(saved['pending_paise']);
    final how = switch (_paidHow) {
      'online' => te ? 'ఆన్‌లైన్' : 'online',
      'due' => te ? 'బాకీ' : 'due',
      'split' => te ? 'క్యాష్ + ఆన్‌లైన్' : 'cash + online',
      _ => te ? 'క్యాష్' : 'cash',
    };
    final number = '${saved['number'] ?? ''}';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), children: [
      const Center(child: AskodoxStepDoneMark()),
      const SizedBox(height: 26),
      AskodoxStepBigNumber(askodoxStepRupees(shown),
          label: [if (number.isNotEmpty) (te ? 'బిల్లు నం. $number' : 'Bill $number'), how].join(' · '), size: 40),
      const SizedBox(height: 8),
      if (_paidHow == 'online' || _paidHow == 'split')
        Center(
          child: AskodoxStepPill(te ? 'డబ్బు వచ్చినప్పుడు ఫోన్ చెప్తుంది' : 'The phone speaks when the money lands'),
        ),
      if (pending > 0)
        Center(
          child: AskodoxStepPill(
              te
                  ? 'బాకీ ${askodoxStepRupees(pending)}${_dueOn.isEmpty ? '' : ' · ${_dueOn.substring(8)}/${_dueOn.substring(5, 7)} కి గుర్తు'}'
                  : 'Due ${askodoxStepRupees(pending)}${_dueOn.isEmpty ? '' : ' · reminder for ${_dueOn.substring(8)}/${_dueOn.substring(5, 7)}'}',
              kind: 'warn'),
        ),
      if ((_paidHow == 'online' || _paidHow == 'split') && _upi.isNotEmpty) ...[
        const SizedBox(height: 14),
        Center(
          child: AskodoxQrPoster(
            qrKey: const Key('askodoxBillStepsQr'),
            data: 'upi://pay?pa=${Uri.encodeComponent(_upi)}${_payee.isEmpty ? '' : '&pn=${Uri.encodeComponent(_payee)}'}'
                '&am=${((_onlinePart > 0 ? _onlinePart : shown) / 100).toStringAsFixed(2)}&cu=INR',
            te: te,
            title: _payee,
            size: 170,
            actions: false,
            fileName: 'askodox-bill-qr',
            footnoteEn: "Shop's own UPI · ASKODOX never holds your money",
            footnoteTe: 'షాప్ సొంత UPI · ASKODOX మీ డబ్బు ఉంచుకోదు',
          ),
        ),
      ],
      if ((_paidHow == 'online' || _paidHow == 'split') && _upi.isEmpty)
        TextButton(
          key: const Key('askodoxBillStepsAddUpi'),
          onPressed: () => context.push('/me/payment-methods'),
          child: Text(te ? 'QR చూపడానికి మీ UPI జోడించండి' : 'Add your UPI to show a QR'),
        ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        AskodoxStepRoundAction(
            key: const Key('askodoxBillStepsSend'),
            icon: Icons.send_rounded,
            label: te ? 'WhatsApp కి' : 'WhatsApp',
            color: const Color(0xFF75D48B),
            onTap: _saved == null ? null : _send),
        const SizedBox(width: 22),
        AskodoxStepRoundAction(
            key: const Key('askodoxBillStepsPrint'),
            icon: Icons.print_rounded,
            label: te ? 'ప్రింట్' : 'Print',
            color: const Color(0xFFBCCDE6),
            onTap: _saved == null ? null : () => askodoxPrintInvoice(context, ref, _saved!, businessId: widget.businessId)),
      ]),
    ]);
  }
}
