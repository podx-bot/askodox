import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/pos_money.dart';
import 'pos_repository.dart';

/// A4 PDF of an issued invoice / bill of supply / credit note, built ONLY from
/// the server's issued record (numbers, taxes and names as stored). The built-in
/// PDF font has no Telugu glyphs, so non-Latin text prints as "?" -- the item's
/// English name is used. Signature is left as a blank "Authorised signatory" line.

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

Future<Uint8List> askodoxInvoicePdf(AskodoxJson invoice, {bool compress = true}) async {
  final doc = pw.Document(compress: compress);
  final seller = askodoxPosMap(invoice['business_snapshot']);
  final buyer = askodoxPosMap(invoice['customer_snapshot']);
  final totals = askodoxPosMap(invoice['totals']);
  final lines = askodoxPosList(invoice['lines']);
  final rates = askodoxPosList(invoice['rate_summary']);
  final payments = askodoxPosList(invoice['payments']);
  final original = invoice['original_invoice'] is Map ? askodoxPosMap(invoice['original_invoice']) : null;
  final stateLabel = '${totals['state_tax_label'] ?? 'sgst'}'.toUpperCase();
  final inter = invoice['mode'] == 'inter';
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  const small = pw.TextStyle(fontSize: 8.5);

  pw.Widget kv(String k, String v) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 92, child: pw.Text(k, style: small.copyWith(fontWeight: pw.FontWeight.bold))),
        pw.Expanded(child: pw.Text(v, style: small)),
      ]);

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
            pw.Text(_a(seller['name']), style: bold),
            if ('${seller['address'] ?? ''}'.isNotEmpty) pw.Text(_a(seller['address']), style: small),
            if (seller['gstin'] != null) pw.Text('GSTIN: ${seller['gstin']}', style: small),
            pw.Text('State: ${_a(seller['state'])} (${seller['state_code'] ?? ''})', style: small),
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
            if (invoice['status'] == 'cancelled') kv('Status', 'CANCELLED: ${_a(invoice['cancel_reason'])}'),
          ]),
        ),
      ]),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Bill to', style: small.copyWith(fontWeight: pw.FontWeight.bold)),
          pw.Text(_a(buyer['name']), style: bold),
          if ('${buyer['address'] ?? ''}'.isNotEmpty) pw.Text(_a(buyer['address']), style: small),
          if (buyer['gstin'] != null) pw.Text('GSTIN: ${buyer['gstin']}', style: small),
          if ('${buyer['state_code'] ?? ''}'.isNotEmpty) pw.Text('State: ${_a(buyer['state'])} (${buyer['state_code']})', style: small),
        ]),
      ),
      if (invoice['reason'] != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('Reason: ${_a(invoice['reason'])}', style: small)),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        cellStyle: small,
        headerStyle: small.copyWith(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignments: {for (var i = 3; i < 9; i++) i: pw.Alignment.centerRight},
        headers: ['#', 'Item', 'HSN/SAC', 'Qty', 'Rate', 'Disc.', 'Taxable', 'GST %', 'Amount'],
        data: [
          for (final l in lines)
            [
              '${l['line_no']}',
              _a(l['name']),
              _a(l['hsn_sac']),
              askodoxQty(askodoxPosInt(l['qty_milli']), _a(l['unit'])),
              _m(l['unit_price_paise']),
              _m(l['discount_paise']),
              _m(l['taxable_paise']),
              l['category'] == 'taxable' ? askodoxRate(askodoxPosInt(l['rate_bp'])) : _a(l['category']),
              _m(l['total_paise']),
            ],
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
          pw.Text('For ${_a(seller['name'])}', style: small),
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
