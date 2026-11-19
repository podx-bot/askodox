import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';
import 'pos_sale_screen.dart' show askodoxPrintInvoice;
import '../../../shared/widgets/qr_poster.dart';

/// Bills after the counter (owner 2026-11-16): the shop's bill history (how each bill was paid, what is pending,
/// remind / mark paid) and the customer's own "My bills" (pay the shop's UPI straight from the bill).

String askodoxBillRupees(int paise) {
  final whole = paise ~/ 100;
  final rest = paise % 100;
  return rest == 0 ? '₹$whole' : '₹$whole.${rest.toString().padLeft(2, '0')}';
}

/// (English, Telugu) name of a way of paying as the history stores it.
(String, String) askodoxBillModeLabel(String mode) => switch (mode) {
      'cash' => ('Cash', 'క్యాష్'),
      'phonepe' => ('PhonePe', 'PhonePe'),
      'gpay' => ('Google Pay', 'Google Pay'),
      'paytm' => ('Paytm', 'Paytm'),
      'bhim' => ('BHIM', 'BHIM'),
      'other_upi' => ('Other UPI', 'ఇతర UPI'),
      'card' => ('Card', 'కార్డ్'),
      'bank_transfer' => ('Bank', 'బ్యాంక్'),
      'cheque' => ('Cheque', 'చెక్'),
      _ => (mode, mode),
    };

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _clock(Object? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// =============================================================== shop: bill history
class AskodoxBillHistoryScreen extends ConsumerStatefulWidget {
  const AskodoxBillHistoryScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBillHistoryScreen> createState() => _AskodoxBillHistoryScreenState();
}

class _AskodoxBillHistoryScreenState extends ConsumerState<AskodoxBillHistoryScreen> {
  final _search = TextEditingController();
  String _range = 'today'; // today | week | month | due
  AskodoxJson? _data;
  Object? _error;
  bool _busy = false;

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
    final now = DateTime.now();
    final from = switch (_range) {
      'today' => _ymd(now),
      'week' => _ymd(now.subtract(const Duration(days: 6))),
      'month' => _ymd(DateTime(now.year, now.month, 1)),
      _ => '',
    };
    try {
      final out = await ref
          .read(askodoxPosRepositoryProvider)
          .billHistory(widget.businessId, from: from, due: _range == 'due', q: _search.text.trim());
      if (mounted) {
        setState(() {
          _data = out;
          _error = null;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Money came for a pending bill: the cashier says how, the bill closes.
  Future<void> _markPaid(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    final pay = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    title: Text(
                        '${te ? 'బిల్లు' : 'Bill'} ${bill['number']} · ${askodoxBillRupees(askodoxPosInt(bill['due_paise']))} ${te ? 'ఎలా వచ్చింది?' : '— how did it come?'}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                for (final m in const ['cash', 'phonepe', 'gpay', 'paytm', 'other_upi', 'card'])
                  ListTile(
                    key: Key('askodoxBillSettle-$m'),
                    title: Text(te ? askodoxBillModeLabel(m).$2 : askodoxBillModeLabel(m).$1),
                    onTap: () => Navigator.of(sheet).pop(m),
                  ),
              ]),
            ));
    if (pay == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).billSettle(widget.businessId, '${bill['id']}', pay, askodoxNewTxnId());
      messenger.showSnackBar(SnackBar(content: Text(te ? 'కట్టారు అని రాశాం ✓' : 'Marked paid ✓')));
      await _load();
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the bill (again) to a number: the customer's ASKODOX app, or WhatsApp opened on that number.
  Future<void> _send(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    final phone = TextEditingController();
    final digits = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(te ? 'ఏ నంబర్‌కి పంపాలి?' : 'Send to which number?'),
              content: TextField(
                key: const Key('askodoxBillSendPhone'),
                controller: phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                    labelText: te ? 'కస్టమర్ మొబైల్ నంబర్' : 'Customer mobile number', border: const OutlineInputBorder()),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'వద్దు' : 'Cancel')),
                FilledButton(
                    key: const Key('askodoxBillSendGo'),
                    onPressed: () => Navigator.of(dialog).pop(phone.text.replaceAll(RegExp(r'[^0-9]'), '')),
                    child: Text(te ? 'పంపు' : 'Send')),
              ],
            ));
    phone.dispose();
    if (digits == null) return;
    if (digits.length < 10) {
      messenger.showSnackBar(SnackBar(content: Text(te ? '10 అంకెల నంబర్ రాయండి.' : 'Type a 10-digit number.')));
      return;
    }
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).billSend(widget.businessId, '${bill['id']}', digits);
      if ('${out['channel']}' == 'askodox') {
        messenger.showSnackBar(SnackBar(
            content: Text(te ? 'కస్టమర్ ASKODOX యాప్‌లోకి వెళ్ళింది ✓' : "Sent to the customer's ASKODOX app ✓")));
      } else {
        final text = '${out['text'] ?? ''}';
        final uri = Uri.parse('https://wa.me/${out['whatsapp_to']}?text=${Uri.encodeComponent(text)}');
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
        if (!ok) {
          await Clipboard.setData(ClipboardData(text: text));
          messenger.showSnackBar(SnackBar(
              content: Text(te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.')));
        }
      }
      await _load();
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    }
  }

  /// Prints a bill the counter skipped with "Next bill"; the server marks it printed, the row loses its flag.
  Future<void> _print(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final inv = await ref.read(askodoxPosRepositoryProvider).invoice(widget.businessId, '${bill['id']}');
      if (!mounted) return;
      final ok = await askodoxPrintInvoice(context, ref, inv);
      if (ok) {
        await ref.read(askodoxPosRepositoryProvider).billPrinted(widget.businessId, '${bill['id']}');
        await _load();
      }
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _totals(bool te, AskodoxJson totals) {
    Widget tile(String label, int paise, {bool due = false}) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: due ? const Color(0xFFFFF1E3) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: due ? const Color(0xFFF3D3B2) : const Color(0xFFE2E5EA))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: due ? const Color(0xFFB4530A) : const Color(0xFF5B6475))),
            Text(askodoxBillRupees(paise),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: due ? const Color(0xFFB4530A) : null)),
          ]),
        );
    final shown = [
      for (final m in const ['cash', 'phonepe', 'gpay', 'paytm', 'other_upi', 'card'])
        if (askodoxPosInt(totals[m]) > 0 || m == 'cash') m,
    ];
    return GridView.count(
      key: const Key('askodoxBillHistoryTotals'),
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.9,
      children: [
        for (final m in shown) tile(te ? askodoxBillModeLabel(m).$2 : askodoxBillModeLabel(m).$1, askodoxPosInt(totals[m])),
        tile(te ? 'బాకీ' : 'Pending', askodoxPosInt(totals['due']), due: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final data = _data;
    final bills = askodoxPosList(data?['bills']);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'బిల్లుల హిస్టరీ' : 'Bill history')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    TextField(
                      key: const Key('askodoxBillHistorySearch'),
                      controller: _search,
                      keyboardType: TextInputType.text,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: te ? 'బిల్లు నంబర్ / కస్టమర్ నంబర్' : 'Bill number / customer number',
                          border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final r in const [
                        ('today', 'Today', 'ఈరోజు'),
                        ('week', 'This week', 'ఈ వారం'),
                        ('month', 'This month', 'ఈ నెల'),
                        ('due', 'Pending only', 'బాకీ మాత్రమే'),
                      ])
                        ChoiceChip(
                          key: Key('askodoxBillHistoryRange-${r.$1}'),
                          label: Text(te ? r.$3 : r.$2),
                          selected: _range == r.$1,
                          onSelected: (_) {
                            setState(() => _range = r.$1);
                            unawaited(_load());
                          },
                        ),
                    ]),
                    const SizedBox(height: 10),
                    _totals(te, askodoxPosMap(data['totals'])),
                    const SizedBox(height: 10),
                    if (bills.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(te ? 'ఈ సమయంలో బిల్లులు లేవు.' : 'No bills in this period.', textAlign: TextAlign.center)),
                    for (final b in bills)
                      Card(
                        key: ValueKey('askodoxBillRow-${b['id']}'),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${b['number']} · ${askodoxBillRupees(askodoxPosInt(b['total_paise']))}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                              if ('${b['status']}' != 'issued')
                                Text(te ? 'రద్దు' : 'Cancelled', style: const TextStyle(color: Color(0xFF5B6475)))
                              else if (askodoxPosInt(b['due_paise']) > 0)
                                Text('${te ? 'బాకీ' : 'Pending'} ${askodoxBillRupees(askodoxPosInt(b['due_paise']))}',
                                    style: const TextStyle(color: Color(0xFFB4530A), fontWeight: FontWeight.w700))
                              else
                                Text(
                                    '${[for (final m in (b['modes'] as List? ?? const [])) te ? askodoxBillModeLabel('$m').$2 : askodoxBillModeLabel('$m').$1].join(' + ')} ✓',
                                    style: const TextStyle(color: Color(0xFF1F7A4A), fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                                [
                                  _clock(b['issued_at']),
                                  if ('${b['customer_phone_last4']}'.isNotEmpty) '…${b['customer_phone_last4']}',
                                  if ('${b['sent']}' == 'askodox') te ? 'ASKODOX లోకి పంపాం' : 'sent to ASKODOX',
                                  if ('${b['sent']}' == 'whatsapp') te ? 'WhatsApp పంపాం' : 'sent on WhatsApp',
                                  if (b['seen'] == true) te ? 'చూశారు' : 'seen',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                            if ('${b['status']}' == 'issued' && b['printed'] == false)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(te ? '🖨 ప్రింట్ చేయాలి' : '🖨 Not printed yet',
                                    key: Key('askodoxBillNotPrinted-${b['id']}'),
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                              ),
                            if (b['customer_says_paid'] == true && askodoxPosInt(b['due_paise']) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                    te
                                        ? 'కస్టమర్ "కట్టాను" అన్నారు — మీ UPI లో చూసి "కట్టారు" నొక్కండి.'
                                        : 'The customer says they paid — check your UPI, then tap "Paid".',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4530A))),
                              ),
                            if ('${b['status']}' == 'issued')
                              Row(children: [
                                if (askodoxPosInt(b['due_paise']) > 0)
                                  TextButton(
                                      key: Key('askodoxBillPaid-${b['id']}'),
                                      onPressed: _busy ? null : () => _markPaid(b),
                                      child: Text(te ? 'కట్టారు' : 'Paid')),
                                if (b['printed'] == false)
                                  TextButton(
                                      key: Key('askodoxBillPrint-${b['id']}'),
                                      onPressed: _busy ? null : () => _print(b),
                                      child: Text(te ? 'ప్రింట్' : 'Print')),
                                TextButton(
                                    key: Key('askodoxBillSend-${b['id']}'),
                                    onPressed: () => _send(b),
                                    child: Text(askodoxPosInt(b['due_paise']) > 0
                                        ? (te ? 'గుర్తు చేయి / పంపు' : 'Remind / send')
                                        : (te ? 'మళ్ళీ పంపు' : 'Send again'))),
                              ]),
                          ]),
                        ),
                      ),
                  ]),
                ),
    );
  }
}

// =============================================================== customer: my bills
class AskodoxMyBillsScreen extends ConsumerStatefulWidget {
  const AskodoxMyBillsScreen({super.key});

  @override
  ConsumerState<AskodoxMyBillsScreen> createState() => _AskodoxMyBillsScreenState();
}

class _AskodoxMyBillsScreenState extends ConsumerState<AskodoxMyBillsScreen> {
  List<AskodoxJson>? _bills;
  Object? _error;
  bool _dueTab = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(askodoxPosRepositoryProvider).myBills();
      if (mounted) {
        setState(() {
          _bills = rows;
          _error = null;
          if (!rows.any((b) => '${b['status']}' == 'due')) _dueTab = false;
        });
      }
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _upi(AskodoxJson bill) {
    for (final p in askodoxPosList(bill['pay'])) {
      if ('${p['upi_link'] ?? ''}'.isNotEmpty) return '${p['upi_link']}';
    }
    return '';
  }

  /// Opens the phone's UPI app with the shop's UPI + the balance filled in. Money goes straight to the shop.
  Future<void> _pay(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri.parse(_upi(bill)), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok) {
      messenger.showSnackBar(SnackBar(
          content: Text(te ? 'UPI యాప్ తెరుచుకోలేదు — QR చూపించి వేరే ఫోన్‌తో కట్టండి.' : 'No UPI app opened — show the QR and pay from another phone.')));
    }
  }

  void _qr(AskodoxJson bill) {
    final te = askodoxPosTe(context);
    showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text('${bill['shop']} · ${askodoxBillRupees(askodoxPosInt(bill['due_paise']))}'),
              content: SizedBox(
                  width: 260,
                  child: AskodoxQrPoster(
                    qrKey: const Key('askodoxMyBillQr'),
                    data: _upi(bill),
                    te: te,
                    title: '${bill['shop']}',
                    size: 190,
                    actions: false,
                    fileName: 'askodox-bill-qr',
                    footnoteEn: "Shop's own UPI · ASKODOX never holds your money",
                    footnoteTe: 'షాప్ సొంత UPI · ASKODOX మీ డబ్బు ఉంచుకోదు',
                  )),
              actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(te ? 'సరే' : 'OK'))],
            ));
  }

  Future<void> _saidPaid(AskodoxJson bill) async {
    final te = askodoxPosTe(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(askodoxPosRepositoryProvider).myBillPaid('${bill['token']}', '');
      messenger.showSnackBar(SnackBar(
          content: Text(te ? 'షాప్‌కి చెప్పాం. వాళ్ళు చూసి "కట్టారు" అని మారుస్తారు.' : 'The shop has been told. They confirm and close the bill.')));
      await _load();
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    }
  }

  Widget _card(bool te, AskodoxJson b) {
    final due = askodoxPosInt(b['due_paise']);
    final upi = _upi(b);
    return Card(
      key: ValueKey('askodoxMyBill-${b['token']}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${b['shop']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text('${b['number']} · ${_clock(b['issued_at'])}', style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
          ]),
          const SizedBox(height: 6),
          for (final l in askodoxPosList(b['lines']))
            Row(children: [
              Expanded(child: Text('${l['name']} × ${(askodoxPosInt(l['qty_milli']) / 1000).toString().replaceAll(RegExp(r'\.0$'), '')}')),
              Text(askodoxBillRupees(askodoxPosInt(l['amount_paise']))),
            ]),
          const Divider(),
          Row(children: [
            Expanded(
                child: Text(due > 0 ? (te ? 'కట్టాల్సింది' : 'To pay') : (te ? 'మొత్తం' : 'Total'),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(askodoxBillRupees(due > 0 ? due : askodoxPosInt(b['total_paise'])),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          if ('${b['status']}' == 'cancelled')
            Text(te ? 'ఈ బిల్లు రద్దు అయింది.' : 'This bill was cancelled.')
          else if (due <= 0)
            Text(
                '${te ? 'కట్టారు' : 'Paid'} ✓ ${(b['paid_with'] as List? ?? const []).join(', ')}',
                style: const TextStyle(color: Color(0xFF1F7A4A), fontWeight: FontWeight.w700))
          else ...[
            const SizedBox(height: 8),
            if (upi.isNotEmpty) ...[
              FilledButton.icon(
                  key: Key('askodoxMyBillPay-${b['token']}'),
                  onPressed: () => _pay(b),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(te ? 'UPI లో ${askodoxBillRupees(due)} కట్టు' : 'Pay ${askodoxBillRupees(due)} by UPI')),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        key: Key('askodoxMyBillShowQr-${b['token']}'),
                        onPressed: () => _qr(b),
                        child: Text(te ? 'QR చూపించు' : 'Show QR'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton(
                        key: Key('askodoxMyBillSaidPaid-${b['token']}'),
                        onPressed: b['customer_says_paid'] == true ? null : () => _saidPaid(b),
                        child: Text(b['customer_says_paid'] == true
                            ? (te ? 'షాప్‌కి చెప్పాం' : 'Shop told')
                            : (te ? 'కట్టేశాను' : 'I have paid')))),
              ]),
              const SizedBox(height: 6),
              Text(
                  te
                      ? 'డబ్బు నేరుగా షాప్ UPI కి వెళ్తుంది. ASKODOX డబ్బు పట్టుకోదు.'
                      : "Money goes straight to the shop's UPI. ASKODOX never holds it.",
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
            ] else
              Text(te ? 'షాప్‌లో కట్టండి (షాప్ UPI ఇంకా జోడించలేదు).' : 'Pay at the shop (the shop has not added its UPI yet).'),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final bills = _bills;
    final dueBills = [for (final b in bills ?? const <AskodoxJson>[]) if ('${b['status']}' == 'due') b];
    final rest = [for (final b in bills ?? const <AskodoxJson>[]) if ('${b['status']}' != 'due') b];
    final shown = _dueTab ? dueBills : rest;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా బిల్లులు' : 'My bills')),
      body: _error != null
          ? AskodoxPosError(error: _error!, onRetry: _load)
          : bills == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Wrap(spacing: 8, children: [
                      ChoiceChip(
                          key: const Key('askodoxMyBillsDue'),
                          label: Text('${te ? 'కట్టాలి' : 'To pay'} ${dueBills.length}'),
                          selected: _dueTab,
                          onSelected: (_) => setState(() => _dueTab = true)),
                      ChoiceChip(
                          key: const Key('askodoxMyBillsPaid'),
                          label: Text(te ? 'కట్టినవి' : 'Paid'),
                          selected: !_dueTab,
                          onSelected: (_) => setState(() => _dueTab = false)),
                    ]),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              te
                                  ? 'ఇక్కడ బిల్లులు లేవు. షాప్ మీ నంబర్‌కి బిల్లు పంపితే ఇక్కడ కనిపిస్తుంది.'
                                  : 'No bills here. A bill a shop sends to your number shows up here.',
                              textAlign: TextAlign.center)),
                    for (final b in shown) _card(te, b),
                  ]),
                ),
    );
  }
}
