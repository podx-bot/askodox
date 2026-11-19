import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/data/pos_invoice_pdf.dart' show askodoxShareInvoicePdf;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/escpos.dart' show askodoxReceiptLines;
import '../../pos/presentation/pos_sale_screen.dart' show askodoxPrintInvoice;

const _device = MethodChannel('com.askodox.app/device');

/// True when typed / spoken words may be a bill by item NUMBERS ("bill 1 2, 3 1", "బిల్ 4 x3", or just "1 2, 3 1").
/// Only a quick pre-check: the server (`/api/pos/chat-bill`) decides, and answers "no card" for everything else.
bool askodoxLooksLikeNumberBill(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t.length > 400 || !RegExp(r'\d').hasMatch(t)) return false;
  if (RegExp(r'\bbill\b|\bbilling\b|బిల్|बिल').hasMatch(t)) return true;
  // numbers only (with item marks / "x" / quantity words): "1 2, 3 1", "#4 x3"
  final rest = t
      .replaceAll(RegExp(r'#|\bno\.?|\bnumber\b|\bitem\b|నంబర్|నెంబర్|నంబరు|नंबर|\bplates?\b|ప్లేట్లు|ప్లేట్|\bqty\b'), ' ')
      .replaceAll(RegExp(r'(?<![a-z])[x×*](?![a-z])'), ' ')
      .replaceAll(RegExp(r'[\d\s,;+.\-]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_qtyWords.contains(w));
  if (rest.isNotEmpty) return false;
  // a lone number ("5") answers something else
  return RegExp(r'[,;#+]|\d\s+\d|\d\s*[x×*]\s*\d').hasMatch(t);
}

const _qtyWords = {
  'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'ఒకటి', 'ఒక', 'రెండు', 'మూడు', 'నాలుగు', 'ఐదు', 'ఆరు', 'ఏడు', 'ఎనిమిది', 'తొమ్మిది', 'పది', //
  'एक', 'दो', 'तीन', 'चार', 'पांच', 'पाँच', 'छह', 'सात', 'आठ', 'नौ', 'दस', 'और', 'and', 'మరియు',
};

/// A bill INSIDE the chat (owner 2026-11-19): the lines come from the shop's own item numbers (server card, never a
/// guess); the cashier picks how it was paid and taps once -> the same real bill as the Bill screen (quick-bill API),
/// then Print / PDF / Share right here. Unknown numbers are named, never matched to another item.
class AskodoxChatBillCard extends ConsumerStatefulWidget {
  const AskodoxChatBillCard({super.key, required this.card, required this.te});

  /// Backend `/api/pos/chat-bill` card: {business_id, shop_name, lines[{item_no, name, unit, price_paise, count,
  /// amount_paise}], unknown[], total_paise}.
  final Map<String, Object?> card;
  final bool te;

  @override
  ConsumerState<AskodoxChatBillCard> createState() => _AskodoxChatBillCardState();
}

class _AskodoxChatBillCardState extends ConsumerState<AskodoxChatBillCard> {
  final _phone = TextEditingController();
  final String _txn = askodoxNewTxnId();
  String _pay = 'cash';
  bool _busy = false;
  AskodoxJson? _bill;

  String get _biz => '${widget.card['business_id'] ?? ''}';
  List<AskodoxJson> get _lines => askodoxPosList(widget.card['lines']);
  int get _total => askodoxPosInt(widget.card['total_paise']);

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _rupees(int paise) => paise % 100 == 0 ? '₹${paise ~/ 100}' : '₹${(paise / 100).toStringAsFixed(2)}';

  static const _ways = [
    ('cash', 'Cash', 'క్యాష్'),
    ('phonepe', 'PhonePe', 'PhonePe'),
    ('gpay', 'Google Pay', 'Google Pay'),
    ('paytm', 'Paytm', 'Paytm'),
    ('other_upi', 'Other UPI', 'ఇతర UPI'),
    ('due', 'Pending', 'బాకీ'),
  ];

  Future<void> _make() async {
    final te = widget.te;
    final messenger = ScaffoldMessenger.of(context);
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_pay == 'due' && digits.length < 10) {
      messenger.showSnackBar(SnackBar(content: Text(te ? 'బాకీకి కస్టమర్ నంబర్ రాయండి.' : 'For pending, type the customer number.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).quickBill(_biz, {
        'lines': [
          for (final l in _lines) {'item_no': askodoxPosInt(l['item_no']), 'count': askodoxPosInt(l['count'])},
        ],
        'advance_paise': _pay == 'due' ? 0 : _total,
        'method': _pay == 'due' ? 'cash' : _pay,
        if (digits.isNotEmpty) 'phone': digits,
        'client_txn_id': _txn, // the same tap twice = the same bill
      });
      if (mounted) setState(() => _bill = out);
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText() async {
    final bill = _bill;
    if (bill == null) return;
    try {
      await _device.invokeMethod<bool>('shareText', <String, Object?>{
        'text': askodoxReceiptLines(bill, columns: 32, asciiOnly: false).join('\n'),
        'title': '${bill['number'] ?? ''}',
      });
    } catch (_) {}
  }

  Future<void> _sendToNumber() async {
    final te = widget.te;
    final bill = _bill;
    final messenger = ScaffoldMessenger.of(context);
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (bill == null || digits.length < 10) return;
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).billSend(_biz, '${bill['id']}', digits);
      if ('${out['channel']}' == 'askodox') {
        messenger.showSnackBar(SnackBar(content: Text(te ? 'కస్టమర్ ASKODOX యాప్‌లోకి వెళ్ళింది ✓' : "Sent to the customer's ASKODOX app ✓")));
      } else {
        await Clipboard.setData(ClipboardData(text: '${out['text'] ?? ''}'));
        try {
          await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': '${out['text'] ?? ''}', 'title': '${bill['number']}'});
        } catch (_) {}
      }
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final unknown = [for (final n in (widget.card['unknown'] as List? ?? const [])) '#$n'];
    final bill = _bill;
    return Container(
      key: ValueKey('askodoxChatBill-$_txn'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE1E8F2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${widget.card['shop_name'] ?? ''} · ${te ? 'బిల్లు' : 'Bill'}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        for (final l in _lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text('#${l['item_no']} ${l['name']} × ${l['count']}')),
              Text(_rupees(askodoxPosInt(l['amount_paise']))),
            ]),
          ),
        if (unknown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(te ? '${unknown.join(', ')} మెనూలో లేదు' : '${unknown.join(', ')} not on the menu',
                key: const Key('askodoxChatBillUnknown'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4530A), fontWeight: FontWeight.w700)),
          ),
        const Divider(),
        Row(children: [
          Expanded(child: Text(te ? 'మొత్తం' : 'Total', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text(_rupees(_total), key: const Key('askodoxChatBillTotal'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        if (bill == null && _lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final w in _ways)
              ChoiceChip(
                key: Key('askodoxChatBillPay-${w.$1}'),
                label: Text(te ? w.$3 : w.$2),
                selected: _pay == w.$1,
                onSelected: (_) => setState(() => _pay = w.$1),
              ),
          ]),
          const SizedBox(height: 6),
          TextField(
            key: const Key('askodoxChatBillPhone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                isDense: true,
                labelText: _pay == 'due'
                    ? (te ? 'కస్టమర్ నంబర్ (బాకీకి తప్పనిసరి)' : 'Customer number (needed for pending)')
                    : (te ? 'కస్టమర్ నంబర్ (ఐచ్ఛికం)' : 'Customer number (optional)'),
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('askodoxChatBillMake'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _make,
            icon: const Icon(Icons.receipt_long),
            label: Text(te ? 'బిల్లు చేయి' : 'Make bill', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
        if (bill != null) ...[
          const SizedBox(height: 8),
          Text('${te ? 'బిల్లు' : 'Bill'} ${bill['number'] ?? ''} ✓',
              key: const Key('askodoxChatBillDone'), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1F7A4A))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxChatBillPrint'),
                onPressed: () => askodoxPrintInvoice(context, ref, bill, businessId: _biz),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: Text(te ? 'ప్రింట్' : 'Print'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxChatBillPdf'),
                onPressed: () => askodoxShareInvoicePdf(bill),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxChatBillShare'),
                onPressed: _shareText,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(te ? 'షేర్' : 'Share'),
              ),
            ),
          ]),
          if (_phone.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 10) ...[
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              key: const Key('askodoxChatBillSend'),
              onPressed: () => unawaited(_sendToNumber()),
              icon: const Icon(Icons.send_rounded),
              label: Text(te ? 'ఈ నంబర్‌కి బిల్లు పంపు' : 'Send the bill to this number'),
            ),
          ],
          const SizedBox(height: 4),
          Text(te ? 'తర్వాతి బిల్లుకు నంబర్లు చెప్పండి / టైప్ చేయండి.' : 'Say / type the numbers for the next bill.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
        ],
      ]),
    );
  }
}
