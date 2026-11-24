import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_purchase_screens.dart' show AskodoxPosPurchaseOrderScreen, askodoxCreatePurchaseOrder;
import '../domain/step_logic.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 5): GST summary `/pos/:id/gst`, Purchase orders `/pos/:id/purchase-orders`,
/// Bill history `/biz/:id/money/history`, Sales `/desk/:id/sales`. One number on top, one list in the middle, ONE big
/// button at the bottom; the rest in the header ⋮. The old pages stay at `?full=1`.

/// A bottom sheet of big choices; returns the picked key.
Future<String?> _pick(BuildContext context, String prefix, List<(String, String)> choices) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (k, label) in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  key: Key('$prefix-$k'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, k),
                  child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ),
      ),
    );

// ============================================================================ GST summary
class AskodoxGstStepsScreen extends ConsumerStatefulWidget {
  const AskodoxGstStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxGstStepsScreen> createState() => _GstState();
}

class _GstState extends ConsumerState<AskodoxGstStepsScreen> {
  late String _month = _ym(DateTime.now());
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  static String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5));
    final last = DateTime(y, m + 1, 0).day;
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).gstReport(widget.businessId, '$_month-01', '$_month-${last.toString().padLeft(2, '0')}');
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

  int _tax(AskodoxJson r) =>
      askodoxPosInt(r['cgst_paise']) + askodoxPosInt(r['sgst_paise']) + askodoxPosInt(r['igst_paise']) + askodoxPosInt(r['cess_paise']);

  Future<void> _change() async {
    final now = DateTime.now();
    final months = [for (var i = 0; i < 6; i++) _ym(DateTime(now.year, now.month - i))];
    final p = await _pick(context, 'askodoxGstStepsMonth', [for (final m in months) (m, m)]);
    if (p == null || !mounted || p == _month) return;
    setState(() {
      _month = p;
      _data = null;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final r = _data;
    final rows = askodoxPosList(r?['by_rate']);
    final tax = rows.fold<int>(0, (s, x) => s + _tax(x));
    final taxable = rows.fold<int>(0, (s, x) => s + askodoxPosInt(x['taxable_paise']));
    return AskodoxStepScaffold(
      key: const Key('askodoxGstSteps'),
      title: te ? 'GST సారాంశం' : 'GST summary',
      sub: _month,
      more: [
        AskodoxStepMore('askodoxGstStepsFull', te ? 'పాత GST పేజీ (HSN, B2B / B2C)' : 'Old GST page (HSN, B2B / B2C)', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/gst?full=1')),
      ],
      body: _error != null && r == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(tax), label: te ? 'ఈ నెల GST' : 'GST this month', size: 40),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${te ? 'పన్ను విధించదగిన విలువ' : 'Taxable value'} ${askodoxStepRupees(taxable)}',
                          key: const Key('askodoxGstStepsTaxable'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఈ నెల బిల్లులు లేవు.' : 'No bills this month.',
                            key: const Key('askodoxGstStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (var i = 0; i < rows.length; i++)
                      AskodoxStepPersonRow(
                        key: Key('askodoxGstStepsRow-$i'),
                        name: '${askodoxRate(askodoxPosInt(rows[i]['rate_bp']))} · ${rows[i]['category']}',
                        sub: '${te ? 'విలువ' : 'Taxable'} ${askodoxStepRupees(askodoxPosInt(rows[i]['taxable_paise']))}',
                        amount: askodoxStepRupees(_tax(rows[i])),
                        amountColor: askodoxStepInk,
                        onTap: () {},
                      ),
                    if ('${r['disclaimer'] ?? ''}'.isNotEmpty && '${r['disclaimer']}' != 'null')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('${r['disclaimer']}',
                            key: const Key('askodoxGstStepsDisclaimer'), style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxGstStepsChange'),
        label: te ? 'నెల మార్చు' : 'Change month',
        icon: Icons.calendar_month,
        onPressed: _change,
      ),
    );
  }
}

// ============================================================================ purchase orders
class AskodoxPurchaseOrdersStepsScreen extends ConsumerStatefulWidget {
  const AskodoxPurchaseOrdersStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPurchaseOrdersStepsScreen> createState() => _PoState();
}

class _PoState extends ConsumerState<AskodoxPurchaseOrdersStepsScreen> {
  List<AskodoxJson>? _list;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final l = await ref.read(askodoxPosRepositoryProvider).purchaseOrders(widget.businessId);
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

  bool _open(AskodoxJson o) => !const {'received', 'closed', 'cancelled', 'completed'}.contains('${o['status']}');

  String _status(String s, bool te) => switch (s) {
        'draft' => te ? 'డ్రాఫ్ట్' : 'Draft',
        'sent' => te ? 'పంపాం' : 'Sent',
        'partial' => te ? 'కొంత వచ్చింది' : 'Part received',
        'received' => te ? 'వచ్చింది' : 'Received',
        'closed' => te ? 'ముగిసింది' : 'Closed',
        'cancelled' => te ? 'రద్దు' : 'Cancelled',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final list = _list;
    final open = list?.where(_open).length ?? 0;
    return AskodoxStepScaffold(
      key: const Key('askodoxPurchaseOrdersSteps'),
      title: te ? 'కొనుగోలు ఆర్డర్లు' : 'Purchase orders',
      more: [
        AskodoxStepMore('askodoxPurchaseOrdersStepsFull', te ? 'పాత ఆర్డర్ల పేజీ' : 'Old orders page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/purchase-orders?full=1')),
      ],
      body: _error != null && list == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber('$open', label: te ? 'సరుకు రావాల్సిన ఆర్డర్లు' : 'Orders waiting for goods', size: 44),
                    const SizedBox(height: 10),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఆర్డర్లు లేవు.' : 'No orders yet.', key: const Key('askodoxPurchaseOrdersStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final o in list)
                      AskodoxStepPersonRow(
                        key: Key('askodoxPurchaseOrdersStepsRow-${o['id']}'),
                        name: '${o['supplier_name']}',
                        sub: '${o['number']}${o['expected_date'] == null ? '' : ' · ${o['expected_date']}'}',
                        amount: _status('${o['status']}', te),
                        amountColor: _open(o) ? askodoxStepWarn : askodoxStepDone,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => AskodoxPosPurchaseOrderScreen(businessId: widget.businessId, poId: '${o['id']}')));
                          if (mounted) await _load();
                        },
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxPurchaseOrdersStepsNew'),
        label: te ? 'కొత్త ఆర్డర్' : 'New order',
        icon: Icons.add_shopping_cart,
        onPressed: () async {
          if (await askodoxCreatePurchaseOrder(context, ref, widget.businessId) && mounted) await _load();
        },
      ),
    );
  }
}

// ============================================================================ bill history
class AskodoxBillHistoryStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBillHistoryStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBillHistoryStepsScreen> createState() => _BillHistoryState();
}

class _BillHistoryState extends ConsumerState<AskodoxBillHistoryStepsScreen> {
  String _range = 'today';
  String _q = '';
  AskodoxJson? _data;
  Object? _error;
  Timer? _debounce;
  final _search = TextEditingController();

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  (String, String) _dates() {
    final now = DateTime.now();
    String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return switch (_range) {
      'today' => (d(now), d(now)),
      'yesterday' => (d(now.subtract(const Duration(days: 1))), d(now.subtract(const Duration(days: 1)))),
      'week' => (d(now.subtract(const Duration(days: 6))), d(now)),
      _ => (d(DateTime(now.year, now.month)), d(now)),
    };
  }

  Future<void> _load() async {
    final (from, to) = _dates();
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).billHistory(widget.businessId, from: from, to: to, q: _q);
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

  String _label(String k, bool te) => switch (k) {
        'yesterday' => te ? 'నిన్న' : 'Yesterday',
        'week' => te ? '7 రోజులు' : '7 days',
        'month' => te ? 'ఈ నెల' : 'This month',
        _ => te ? 'ఈ రోజు' : 'Today',
      };

  Future<void> _change() async {
    final te = _te;
    final p = await _pick(context, 'askodoxBillHistoryStepsRange', [for (final k in const ['today', 'yesterday', 'week', 'month']) (k, _label(k, te))]);
    if (p == null || !mounted || p == _range) return;
    setState(() {
      _range = p;
      _data = null;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final bills = askodoxPosList(d?['bills']);
    final total = bills.where((b) => b['status'] != 'cancelled').fold<int>(0, (s, b) => s + askodoxPosInt(b['total_paise']));
    return AskodoxStepScaffold(
      key: const Key('askodoxBillHistorySteps'),
      title: te ? 'బిల్లుల చరిత్ర' : 'Bill history',
      sub: _label(_range, te),
      more: [
        AskodoxStepMore('askodoxBillHistoryStepsFull', te ? 'పాత చరిత్ర పేజీ (క్యాష్ / ఆన్‌లైన్ / బాకీ ఫిల్టర్)' : 'Old history page (cash / online / baaki filters)',
            Icons.menu_book_rounded, () => context.push('/biz/${widget.businessId}/money/history?full=1')),
      ],
      body: _error != null && d == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
              AskodoxStepBigNumber(d == null ? '…' : askodoxStepRupees(total),
                  label: te ? '${bills.length} బిల్లులు' : '${bills.length} bills', size: 40),
              const SizedBox(height: 10),
              AskodoxStepSearch(
                controller: _search,
                hint: te ? 'బిల్ నంబర్ / ఫోన్ నంబర్' : 'Bill number / phone number',
                fieldKey: const Key('askodoxBillHistoryStepsSearch'),
                onChanged: (v) {
                  _q = v.trim();
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _load);
                },
              ),
              if (d == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              if (d != null && bills.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(te ? 'బిల్లులు లేవు.' : 'No bills.', key: const Key('askodoxBillHistoryStepsNone'), textAlign: TextAlign.center),
                ),
              for (final b in bills)
                AskodoxStepPersonRow(
                  key: Key('askodoxBillHistoryStepsRow-${b['id']}'),
                  name: '${'${b['customer_name'] ?? ''}'.isEmpty ? (te ? 'కస్టమర్' : 'Walk-in') : b['customer_name']}',
                  sub: '${b['number']} · ${b['local_date']}${b['status'] == 'cancelled' ? (te ? ' · రద్దు' : ' · cancelled') : ''}'
                      '${askodoxPosInt(b['due_paise']) > 0 ? (te ? ' · బాకీ' : ' · baaki') : ''}',
                  amount: askodoxStepRupees(askodoxPosInt(b['total_paise'])),
                  amountColor: b['status'] == 'cancelled' ? askodoxStepMuted : (askodoxPosInt(b['due_paise']) > 0 ? askodoxStepWarn : askodoxStepInk),
                  onTap: () => context.push('/bills/${widget.businessId}'),
                ),
            ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBillHistoryStepsChange'),
        label: te ? 'రోజు మార్చు' : 'Change day',
        icon: Icons.calendar_today,
        onPressed: _change,
      ),
    );
  }
}

// ============================================================================ sales (front desk)
class AskodoxSalesStepsScreen extends ConsumerStatefulWidget {
  const AskodoxSalesStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxSalesStepsScreen> createState() => _SalesState();
}

class _SalesState extends ConsumerState<AskodoxSalesStepsScreen> {
  String _period = 'day';
  AskodoxJson? _data;
  Object? _error;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).shopSales(widget.businessId, period: _period);
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

  String _label(String k, bool te) => switch (k) {
        'week' => te ? 'ఈ వారం' : 'This week',
        'month' => te ? 'ఈ నెల' : 'This month',
        _ => te ? 'ఈరోజు' : 'Today',
      };

  String _method(String m, bool te) => switch (m) {
        'cash' => te ? 'క్యాష్' : 'Cash',
        'upi' => 'UPI',
        'card' => te ? 'కార్డ్' : 'Card',
        'bank_transfer' => te ? 'బ్యాంక్' : 'Bank',
        'advance' => te ? 'అడ్వాన్స్' : 'Advance',
        _ => m,
      };

  Future<void> _change() async {
    final te = _te;
    final p = await _pick(context, 'askodoxSalesStepsPeriod', [for (final k in const ['day', 'week', 'month']) (k, _label(k, te))]);
    if (p == null || !mounted || p == _period) return;
    setState(() {
      _period = p;
      _data = null;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final d = _data;
    final pays = askodoxPosList(d?['payments']);
    final tops = askodoxPosList(d?['top_items']);
    return AskodoxStepScaffold(
      key: const Key('askodoxSalesSteps'),
      title: te ? 'అమ్మకాలు' : 'Sales',
      sub: _label(_period, te),
      more: [
        AskodoxStepMore('askodoxSalesStepsFull', te ? 'పాత అమ్మకాల పేజీ (రోజు వారీ, ఇటీవలి బిల్లులు)' : 'Old sales page (day by day, latest bills)',
            Icons.menu_book_rounded, () => context.push('/desk/${widget.businessId}/sales?full=1')),
      ],
      body: _error != null && d == null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    AskodoxStepBigNumber(askodoxStepRupees(askodoxPosInt(d['net_paise'])), label: te ? 'అమ్మకం' : 'Sales', size: 40),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${d['bills']} ${te ? 'బిల్లులు' : 'bills'} · ${te ? 'బాకీ' : 'Baaki'} ${askodoxStepRupees(askodoxPosInt(d['dues_paise']))}',
                          key: const Key('askodoxSalesStepsSplit'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: askodoxStepMuted, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    if (pays.isEmpty && tops.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(te ? 'ఇంకా అమ్మకాలు లేవు.' : 'No sales yet.', key: const Key('askodoxSalesStepsNone'), textAlign: TextAlign.center),
                      ),
                    for (final p in pays)
                      AskodoxStepPersonRow(
                        key: Key('askodoxSalesStepsPay-${p['method']}'),
                        name: _method('${p['method']}', te),
                        sub: te ? 'ఎలా చెల్లించారు' : 'How it was paid',
                        amount: askodoxStepRupees(askodoxPosInt(p['amount_paise'])),
                        amountColor: askodoxStepInk,
                        onTap: () {},
                      ),
                    for (final i in tops)
                      AskodoxStepPersonRow(
                        key: Key('askodoxSalesStepsTop-${i['name']}'),
                        name: '${i['name']}',
                        sub: te ? 'ఎక్కువ అమ్మినవి' : 'Best seller',
                        amount: askodoxStepRupees(askodoxPosInt(i['total_paise'])),
                        amountColor: askodoxStepDone,
                        onTap: () {},
                      ),
                  ]),
                ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxSalesStepsChange'),
        label: te ? 'కాలం మార్చు' : 'Change period',
        icon: Icons.calendar_today,
        onPressed: _change,
      ),
    );
  }
}
