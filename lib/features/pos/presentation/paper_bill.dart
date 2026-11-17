import 'package:flutter/material.dart';

import '../data/pos_repository.dart';

/// A bill drawn like the shop's printed paper bill (owner 2026-11-17): shop name, what it sells, address, phone,
/// GSTIN or "no GST"; the title from how it was paid (cash / online / credit / part paid); items with quantity, rate and
/// amount; discount, GST, round-off; the cash / online / baaki box. No signature line. [paper] = `/bills/{id}/paper`.
class AskodoxPaperBill extends StatelessWidget {
  const AskodoxPaperBill({super.key, required this.paper, required this.te});
  final AskodoxJson paper;
  final bool te;

  static const _ink = Color(0xFF9D1D5A);

  static String rupees(int paise) {
    final neg = paise < 0;
    final p = paise.abs();
    final s = p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2);
    return '${neg ? '−' : ''}₹$s';
  }

  static String qty(int milli) => milli % 1000 == 0 ? '${milli ~/ 1000}' : (milli / 1000).toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');

  String get _title => switch ('${paper['bill_kind']}') {
        'credit' => te ? 'క్రెడిట్ బిల్ (బాకీ)' : 'CREDIT BILL',
        'part' => te ? 'బిల్ — కొంత బాకీ' : 'BILL — PART PAID',
        'online' => te ? 'ఆన్‌లైన్ బిల్' : 'ONLINE BILL',
        'mixed' => te ? 'క్యాష్ + ఆన్‌లైన్ బిల్' : 'CASH + ONLINE BILL',
        _ => te ? 'క్యాష్ బిల్' : 'CASH BILL',
      };

  @override
  Widget build(BuildContext context) {
    final lines = askodoxPosList(paper['paper_lines']);
    final gst = paper['gst'] == true;
    final cancelled = paper['status'] == 'cancelled';
    final date = DateTime.tryParse('${paper['issued_at'] ?? ''}')?.toLocal();
    const head = TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _ink);
    const cell = TextStyle(fontSize: 12.5);
    Widget row(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontSize: 12.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w500, color: color))),
            Text(b, style: TextStyle(fontSize: bold ? 15 : 12.5, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: color)),
          ]),
        );
    return Container(
      key: const Key('askodoxPaperBill'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF7),
        border: Border.all(color: _ink, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${paper['shop'] ?? ''}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
        if ('${paper['shop_category'] ?? ''}'.isNotEmpty)
          Text('${paper['shop_category']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _ink)),
        if ('${paper['shop_address'] ?? ''}'.isNotEmpty)
          Text('${paper['shop_address']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
        Text(
            [
              if ('${paper['shop_phone'] ?? ''}'.isNotEmpty) '📞 ${paper['shop_phone']}',
              gst && '${paper['shop_gstin'] ?? ''}'.isNotEmpty ? 'GSTIN ${paper['shop_gstin']}' : (te ? 'GST లేదు' : 'No GST'),
            ].join('  ·  '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5)),
        const Divider(color: _ink, height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4)),
            child: Text(cancelled ? (te ? 'రద్దైన బిల్' : 'CANCELLED') : _title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('${te ? 'నం.' : 'No.'} ${paper['number'] ?? ''}', style: cell)),
          if (date != null)
            Text('${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}  '
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}', style: cell),
        ]),
        if ('${paper['customer_name'] ?? ''}'.isNotEmpty || '${paper['customer_phone_last4'] ?? ''}'.isNotEmpty)
          Text(
              '${te ? 'పేరు' : 'Name'}: ${paper['customer_name'] ?? ''}'
              '${'${paper['customer_phone_last4'] ?? ''}'.isNotEmpty ? '  (…${paper['customer_phone_last4']})' : ''}',
              style: cell),
        const SizedBox(height: 6),
        Table(
          columnWidths: const {0: FixedColumnWidth(22), 1: FlexColumnWidth(), 2: IntrinsicColumnWidth(), 3: IntrinsicColumnWidth(), 4: IntrinsicColumnWidth()},
          border: const TableBorder(
              top: BorderSide(color: _ink), bottom: BorderSide(color: _ink), horizontalInside: BorderSide(color: Color(0x339D1D5A))),
          children: [
            TableRow(children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('#', style: head)),
              Text(te ? 'వివరాలు' : 'Item', style: head),
              Padding(padding: const EdgeInsets.only(left: 6), child: Text(te ? 'పరిమాణం' : 'Qty', style: head)),
              Padding(padding: const EdgeInsets.only(left: 6), child: Text(te ? 'రేటు' : 'Rate', style: head)),
              Padding(padding: const EdgeInsets.only(left: 6), child: Text(te ? 'మొత్తం' : 'Amount', style: head, textAlign: TextAlign.right)),
            ]),
            for (final (i, l) in lines.indexed)
              TableRow(children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${i + 1}', style: cell)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                      '${l['name']}${askodoxPosInt(l['discount_paise']) > 0 ? '\n${te ? 'తగ్గింపు' : 'less'} ${rupees(askodoxPosInt(l['discount_paise']))}' : ''}',
                      style: cell),
                ),
                Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text('${qty(askodoxPosInt(l['qty_milli']))} ${l['unit'] ?? ''}', style: cell)),
                Padding(padding: const EdgeInsets.only(left: 6, top: 4), child: Text(rupees(askodoxPosInt(l['rate_paise'])), style: cell)),
                Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text(rupees(askodoxPosInt(l['amount_paise'])), style: cell.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
              ]),
          ],
        ),
        const SizedBox(height: 6),
        if (askodoxPosInt(paper['discount_paise']) > 0) row(te ? 'తగ్గింపు' : 'Discount', rupees(-askodoxPosInt(paper['discount_paise']))),
        if (gst && askodoxPosInt(paper['tax_paise']) > 0) ...[
          if (askodoxPosInt(paper['cgst_paise']) > 0) row('CGST', rupees(askodoxPosInt(paper['cgst_paise']))),
          if (askodoxPosInt(paper['sgst_paise']) > 0) row('SGST', rupees(askodoxPosInt(paper['sgst_paise']))),
          if (askodoxPosInt(paper['igst_paise']) > 0) row('IGST', rupees(askodoxPosInt(paper['igst_paise']))),
        ],
        if (askodoxPosInt(paper['round_off_paise']) != 0) row(te ? 'రౌండ్ ఆఫ్' : 'Round off', rupees(askodoxPosInt(paper['round_off_paise']))),
        row(te ? 'మొత్తం' : 'Total', rupees(askodoxPosInt(paper['total_paise'])), bold: true, color: _ink),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: const Color(0x669D1D5A)), borderRadius: BorderRadius.circular(6)),
          child: Column(children: [
            if (askodoxPosInt(paper['cash_paise']) > 0) row('💵 ${te ? 'క్యాష్' : 'Cash'}', rupees(askodoxPosInt(paper['cash_paise']))),
            if (askodoxPosInt(paper['online_paise']) > 0)
              row(
                  '📱 ${te ? 'ఆన్‌లైన్' : 'Online'}${(paper['online_apps'] as List? ?? const []).isEmpty ? '' : ' (${(paper['online_apps'] as List).join(', ')})'}',
                  rupees(askodoxPosInt(paper['online_paise']))),
            if (askodoxPosInt(paper['due_paise']) > 0)
              row('📒 ${te ? 'బాకీ' : 'Baaki (due)'}', rupees(askodoxPosInt(paper['due_paise'])), bold: true, color: const Color(0xFFB45309)),
            if (askodoxPosInt(paper['due_paise']) == 0 && !cancelled) row(te ? 'పూర్తిగా కట్టారు ✓' : 'Fully paid ✓', '', color: const Color(0xFF17784C)),
          ]),
        ),
        const SizedBox(height: 6),
        Text(te ? 'ధన్యవాదాలు 🙏 మళ్ళీ రండి' : 'Thank you 🙏 visit again',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _ink, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
