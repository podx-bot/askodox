import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_invoice_pdf.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/escpos.dart';
import '../../pos/domain/pos_money.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_sale_screen.dart' show askodoxPrintInvoice;
import 'step_kit.dart';

const _device = MethodChannel('com.askodox.app/device');

/// Owner 2026-11-24 (3-step design, batch 9): one bill `/pos/:id/invoice/:iid`. Top = the total, middle = the bill,
/// bottom = ONE big button (Next bill right after billing, else Share PDF). Print / text share / return / cancel are in the
/// header menu; the old page stays at `?full=1`. Returns and cancels keep the record (credit note), money is only recorded.
class AskodoxInvoiceStepsScreen extends ConsumerStatefulWidget {
  const AskodoxInvoiceStepsScreen({super.key, required this.businessId, required this.invoiceId, this.fresh = false});
  final String businessId;
  final String invoiceId;
  final bool fresh;

  @override
  ConsumerState<AskodoxInvoiceStepsScreen> createState() => _InvoiceState();
}

class _InvoiceState extends ConsumerState<AskodoxInvoiceStepsScreen> {
  AskodoxJson? _inv;
  Object? _error;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final i = await _repo.invoice(widget.businessId, widget.invoiceId);
      if (mounted) {
        setState(() {
          _inv = i;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _inv == null) setState(() => _error = e);
    }
  }

  /// One reason box, shown for a return or a cancel (the record always stays).
  Future<String?> _reason(String title) async {
    final te = _te;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
            key: const Key('askodoxInvoiceStepsReason'),
            controller: c,
            autofocus: true,
            decoration: InputDecoration(labelText: te ? 'కారణం' : 'Reason', border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'No')),
          FilledButton(key: const Key('askodoxInvoiceStepsReasonYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'అవును' : 'Yes')),
        ],
      ),
    );
    final text = c.text.trim();
    return ok == true && text.isNotEmpty ? text : null;
  }

  Future<void> _creditAll(AskodoxJson inv) async {
    final te = _te;
    final reason = await _reason(te ? 'మొత్తం బిల్లు రిటర్న్ (క్రెడిట్ నోట్)' : 'Return the whole bill (credit note)');
    if (reason == null || !mounted) return;
    final lines = [
      for (final l in askodoxPosList(inv['lines'])) {'line_no': l['line_no'], 'qty_milli': l['qty_milli']},
    ];
    final total = askodoxPosInt(askodoxPosMap(inv['totals'])['grand_total_paise']);
    final refund = inv['customer_id'] == null ? {'method': 'cash', 'amount_paise': total} : null;
    try {
      final note = await _repo.creditNote(widget.businessId, widget.invoiceId, {
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
    final te = _te;
    final reason = await _reason(te ? 'ఈ బిల్లు రద్దు చేయాలా? (రికార్డు ఉంటుంది)' : 'Cancel this bill? (the record stays)');
    if (reason == null || !mounted) return;
    try {
      await _repo.cancel(widget.businessId, widget.invoiceId, reason);
      await _load();
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(te));
    }
  }

  void _nextBill() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/pos/${widget.businessId}/sale');
    }
  }

  Future<void> _sharePdf(AskodoxJson inv) async {
    final te = _te;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await askodoxShareInvoicePdf(inv);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(te ? 'PDF పంపలేకపోయాను (యాప్ అప్‌డేట్ చేయండి).' : 'Could not share the PDF (update the app).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'బిల్లు' : 'Bill';
    final inv = _inv;
    if (inv == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxInvoiceSteps'),
          title: title,
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final business = ref.watch(askodoxPosBusinessProvider(widget.businessId)).valueOrNull ?? const <String, Object?>{};
    final receipt = askodoxReceiptLines(inv, columns: 32, asciiOnly: false);
    final issued = inv['status'] == 'issued';
    final isInvoice = inv['doc_kind'] == 'invoice' && issued;
    final cancelled = inv['status'] == 'cancelled';
    final total = askodoxPosInt(askodoxPosMap(inv['totals'])['grand_total_paise']);
    return AskodoxStepScaffold(
      key: const Key('askodoxInvoiceSteps'),
      title: title,
      sub: '${inv['number'] ?? ''}',
      more: [
        AskodoxStepMore('askodoxInvoiceStepsPrint', te ? 'ప్రింట్' : 'Print', Icons.print_outlined,
            () => askodoxPrintInvoice(context, ref, inv, businessId: widget.businessId)),
        if (!widget.fresh || !issued)
          AskodoxStepMore('askodoxInvoiceStepsPdf', 'PDF', Icons.picture_as_pdf_outlined, () => _sharePdf(inv)),
        AskodoxStepMore('askodoxInvoiceStepsText', te ? 'టెక్స్ట్‌గా షేర్' : 'Share as text', Icons.share_outlined, () async {
          try {
            await _device.invokeMethod<bool>('shareText', <String, Object?>{'text': receipt.join('\n'), 'title': '${inv['number']}'});
          } catch (_) {}
        }),
        if (isInvoice && askodoxPosCan(business, 'return'))
          AskodoxStepMore('askodoxInvoiceStepsReturn', te ? 'రిటర్న్ / క్రెడిట్ నోట్' : 'Return / credit note', Icons.undo, () => _creditAll(inv)),
        if (isInvoice && askodoxPosCan(business, 'cancel'))
          AskodoxStepMore('askodoxInvoiceStepsCancel', te ? 'బిల్లు రద్దు' : 'Cancel bill', Icons.cancel_outlined, _cancel),
        AskodoxStepMore('askodoxInvoiceStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/pos/${widget.businessId}/invoice/${widget.invoiceId}?full=1')),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        AskodoxStepBigNumber(askodoxPaise(total),
            label: cancelled ? (te ? 'రద్దు' : 'Cancelled') : (te ? 'మొత్తం' : 'Total'), color: cancelled ? askodoxStepBad : askodoxStepInk, size: 44),
        if (cancelled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${inv['cancel_reason'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: askodoxStepBad, fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(receipt.join('\n'), key: const Key('askodoxInvoiceStepsReceipt'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        for (final p in askodoxPosList(inv['payments']))
          if (p['verification'] == 'cashier_confirmed')
            Text(te ? '${p['method']}: క్యాషియర్ నమోదు చేశారు' : '${p['method']}: entered by the cashier', style: const TextStyle(fontSize: 11.5)),
      ]),
      bottom: widget.fresh && issued
          ? AskodoxStepBottom(
              buttonKey: const Key('askodoxInvoiceStepsNext'),
              label: te ? 'తర్వాతి బిల్లు' : 'Next bill',
              icon: Icons.add_circle_outline,
              onPressed: _nextBill)
          : AskodoxStepBottom(
              buttonKey: const Key('askodoxInvoiceStepsShare'),
              label: te ? 'PDF షేర్ చేయి' : 'Share PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => _sharePdf(inv)),
    );
  }
}
