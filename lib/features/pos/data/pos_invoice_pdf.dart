import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/askodox_pdf_text.dart';
import '../domain/pos_money.dart';
import 'pos_repository.dart';

export '../../../core/pdf/askodox_pdf_text.dart' show askodoxPdfNeedsImage;

/// A4 PDF of an issued invoice / bill of supply / credit note, built ONLY from
/// the server's issued record (numbers, taxes and names as stored). The built-in
/// PDF font has no Telugu glyphs and dart_pdf cannot shape Indic scripts, so any
/// text outside plain ASCII (Telugu names, addresses, the ₹ sign) is drawn by the
/// phone's own text engine (system fonts, correct shaping) into a small image and
/// placed in the PDF. That text is a picture: it cannot be selected or searched.
/// Signature is left as a blank "Authorised signatory" line.

const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
  'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${_ones[n % 10]}'}';

String _below1000(int n) {
  final h = n ~/ 100;
  final r = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _below100(r)].join(' ');
}

String _indian(int n) {
  final parts = <String>[];
  final crore = n ~/ 10000000;
  var rest = n % 10000000;
  final lakh = rest ~/ 100000;
  rest %= 100000;
  final thousand = rest ~/ 1000;
  rest %= 1000;
  if (crore > 0) parts.add('${_indian(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (rest > 0) parts.add(_below1000(rest));
  return parts.join(' ');
}

/// Indian-system words: 123456789 paise -> "Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven and Eighty Nine Paise Only".
String askodoxAmountInWords(int paise) {
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final p = abs % 100;
  final words = rupees == 0 ? 'Zero' : _indian(rupees);
  return '${paise < 0 ? 'Minus ' : ''}Rupees $words${p > 0 ? ' and ${_below100(p)} Paise' : ''} Only';
}

String _a(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
String _m(Object? paise) => askodoxPaise(askodoxPosInt(paise), symbol: false);

/// How many text images the PDF of [invoice] carries (for tests / diagnostics).
Future<int> askodoxInvoicePdfImageCount(AskodoxJson invoice) async => (await _collect(invoice)).count;

Future<AskodoxPdfText> _collect(AskodoxJson invoice) async {
  final g = AskodoxPdfText();
  final seller = askodoxPosMap(invoice['business_snapshot']);
  final buyer = askodoxPosMap(invoice['customer_snapshot']);
  await g.want(seller['name'], 12, bold: true);
  await g.want(seller['name'], 8.5);
  await g.want(seller['address'], 8.5);
  await g.want(seller['state'], 8.5);
  await g.want(buyer['name'], 12, bold: true);
  await g.want(buyer['address'], 8.5);
  await g.want(buyer['state'], 8.5);
  await g.want(invoice['reason'], 8.5);
  await g.want(invoice['cancel_reason'], 8.5);
  for (final l in askodoxPosList(invoice['lines'])) {
    await g.want(l['name'], 8.5);
    await g.want(l['unit'], 8.5);
  }
  return g;
}

Future<Uint8List> askodoxInvoicePdf(AskodoxJson invoice, {bool compress = true}) async {
  final doc = pw.Document(compress: compress);
  final g = await _collect(invoice);
  final seller = askodoxPosMap(invoice['business_snapshot']);
  final buyer = askodoxPosMap(invoice['customer_snapshot']);
  final totals = askodoxPosMap(invoice['totals']);
  final lines = askodoxPosList(invoice['lines']);
  final rates = askodoxPosList(invoice['rate_summary']);
  final payments = askodoxPosList(invoice['payments']);
  final original = invoice['original_invoice'] is Map ? askodoxPosMap(invoice['original_invoice']) : null;
  final stateLabel = '${totals['state_tax_label'] ?? 'sgst'}'.toUpperCase();
  final inter = invoice['mode'] == 'inter';
  const small = pw.TextStyle(fontSize: 8.5);

  const bold12 = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

  pw.Widget kvw(String k, pw.Widget v) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 92, child: pw.Text(k, style: small.copyWith(fontWeight: pw.FontWeight.bold))),
        pw.Expanded(child: v),
      ]);
  pw.Widget kv(String k, String v) => kvw(k, pw.Text(v, style: small));
  pw.Widget cell(pw.Widget child, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: right ? pw.Align(alignment: pw.Alignment.centerRight, child: child) : child,
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      if ('${seller['heading'] ?? ''}'.isNotEmpty)
        pw.Center(child: pw.Text(_a(seller['heading']).toUpperCase(), style: small.copyWith(fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text(_a(invoice['title']).toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            g.text(seller['name'], bold12, bold: true),
            if ('${seller['address'] ?? ''}'.isNotEmpty) g.text(seller['address'], small),
            if (seller['gstin'] != null) pw.Text('GSTIN: ${seller['gstin']}', style: small),
            pw.Row(children: [
              g.text(seller['state'], small, prefix: 'State: '),
              pw.Text(' (${seller['state_code'] ?? ''})', style: small),
            ]),
          ]),
        ),
        pw.SizedBox(
          width: 200,
          child: pw.Column(children: [
            kv('Number', _a(invoice['number'])),
            kv('Date', _a(invoice['local_date'])),
            kv('Place of supply', '${invoice['place_of_supply'] ?? ''}${inter ? ' (inter-State)' : ''}'),
            kv('Reverse charge', 'No'),
            if (original != null) kv('Against invoice', '${_a(original['number'])} dated ${'${original['issued_at'] ?? ''}'.split('T').first}'),
            if (invoice['status'] == 'cancelled') kvw('Status', g.text(invoice['cancel_reason'], small, prefix: 'CANCELLED: ')),
          ]),
        ),
      ]),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Bill to', style: small.copyWith(fontWeight: pw.FontWeight.bold)),
          g.text(buyer['name'], bold12, bold: true),
          if ('${buyer['address'] ?? ''}'.isNotEmpty) g.text(buyer['address'], small),
          if (buyer['gstin'] != null) pw.Text('GSTIN: ${buyer['gstin']}', style: small),
          if ('${buyer['state_code'] ?? ''}'.isNotEmpty)
            pw.Row(children: [
              g.text(buyer['state'], small, prefix: 'State: '),
              pw.Text(' (${buyer['state_code']})', style: small),
            ]),
        ]),
      ),
      if (invoice['reason'] != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: g.text(invoice['reason'], small, prefix: 'Reason: ')),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(width: 0.5),
        columnWidths: const {1: pw.FlexColumnWidth(3)},
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              for (final h in ['#', 'Item', 'HSN/SAC', 'Qty', 'Rate', 'Disc.', 'Taxable', 'GST %', 'Amount'])
                cell(pw.Text(h, style: small.copyWith(fontWeight: pw.FontWeight.bold))),
            ],
          ),
          for (final l in lines)
            pw.TableRow(children: [
              cell(pw.Text('${l['line_no']}', style: small)),
              cell(g.text(l['name'], small)),
              cell(pw.Text(_a(l['hsn_sac']), style: small)),
              cell(
                askodoxPdfNeedsImage('${l['unit'] ?? ''}')
                    ? pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                        pw.Text('${askodoxQty(askodoxPosInt(l['qty_milli']), '').trim()} ', style: small),
                        g.text(l['unit'], small),
                      ])
                    : pw.Text(askodoxQty(askodoxPosInt(l['qty_milli']), _a(l['unit'])), style: small),
                right: true,
              ),
              cell(pw.Text(_m(l['unit_price_paise']), style: small), right: true),
              cell(pw.Text(_m(l['discount_paise']), style: small), right: true),
              cell(pw.Text(_m(l['taxable_paise']), style: small), right: true),
              cell(
                pw.Text(l['category'] == 'taxable' ? askodoxRate(askodoxPosInt(l['rate_bp'])) : _a(l['category']), style: small),
                right: true,
              ),
              cell(pw.Text(_m(l['total_paise']), style: small), right: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 8),
      if (rates.isNotEmpty)
        pw.TableHelper.fromTextArray(
          cellStyle: small,
          headerStyle: small.copyWith(fontWeight: pw.FontWeight.bold),
          headers: ['Rate', 'Taxable', 'CGST', stateLabel, 'IGST', 'Cess'],
          data: [
            for (final r in rates)
              [
                r['category'] == 'taxable' ? askodoxRate(askodoxPosInt(r['rate_bp'])) : _a(r['category']),
                _m(r['taxable_paise']),
                _m(r['cgst_paise']),
                _m(r['sgst_paise']),
                _m(r['igst_paise']),
                _m(r['cess_paise']),
              ],
          ],
        ),
      pw.SizedBox(height: 8),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 220,
          child: pw.Column(children: [
            kv('Taxable value', _m(totals['taxable_paise'])),
            if (askodoxPosInt(totals['cgst_paise']) != 0) kv('CGST', _m(totals['cgst_paise'])),
            if (askodoxPosInt(totals['sgst_paise']) != 0) kv(stateLabel, _m(totals['sgst_paise'])),
            if (askodoxPosInt(totals['igst_paise']) != 0) kv('IGST', _m(totals['igst_paise'])),
            if (askodoxPosInt(totals['cess_paise']) != 0) kv('Cess', _m(totals['cess_paise'])),
            if (askodoxPosInt(totals['round_off_paise']) != 0) kv('Round off', _m(totals['round_off_paise'])),
            pw.Divider(thickness: 0.5),
            kv('TOTAL (Rs)', _m(totals['grand_total_paise'])),
            for (final p in payments) kv('Paid ${_a(p['method'])}', _m(p['amount_paise'])),
            if (askodoxPosInt(invoice['balance_paise']) > 0) kv('Balance due', _m(invoice['balance_paise'])),
          ]),
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(askodoxAmountInWords(askodoxPosInt(totals['grand_total_paise'])), style: small.copyWith(fontWeight: pw.FontWeight.bold)),
      if (payments.any((p) => p['verification'] == 'cashier_confirmed'))
        pw.Text('UPI / card / bank amounts were confirmed by the cashier, not verified with the bank.', style: small),
      pw.SizedBox(height: 28),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(children: [
          g.text(seller['name'], small, prefix: 'For '),
          pw.SizedBox(height: 24),
          pw.Text('Authorised signatory', style: small),
        ]),
      ),
    ],
  ));
  return doc.save();
}

const _device = MethodChannel('com.askodox.app/device');

/// Writes the PDF to the app cache (the only folder the share provider exposes)
/// and opens the Android share sheet; the person chooses where it goes.
/// Returns false on an older app build without file sharing.
Future<bool> askodoxShareInvoicePdf(AskodoxJson invoice) async {
  final bytes = await askodoxInvoicePdf(invoice);
  final dir = Directory('${(await getTemporaryDirectory()).path}/invoices');
  await dir.create(recursive: true);
  final safe = '${invoice['number'] ?? 'invoice'}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File('${dir.path}/$safe.pdf');
  await file.writeAsBytes(bytes, flush: true);
  try {
    return await _device.invokeMethod<bool>('shareFile', <String, Object?>{
          'path': file.path,
          'mime': 'application/pdf',
          'title': '${invoice['number'] ?? 'Invoice'}',
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
