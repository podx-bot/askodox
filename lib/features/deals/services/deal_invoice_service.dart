import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DealInvoiceData {
  const DealInvoiceData({
    required this.orderId,
    required this.shopName,
    required this.buyerName,
    required this.sellerName,
    required this.amount,
    required this.paymentMode,
    required this.paymentStatus,
    required this.createdAt,
  });

  final String orderId;
  final String shopName;
  final String buyerName;
  final String sellerName;
  final double? amount;
  final String paymentMode;
  final String paymentStatus;
  final DateTime createdAt;
}

class DealInvoiceService {
  const DealInvoiceService();

  Future<File> generate(DealInvoiceData data) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ASKODOX DEAL INVOICE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 18),
            _row('Order ID', data.orderId),
            _row('Shop', _ascii(data.shopName)),
            _row('Buyer', _ascii(data.buyerName)),
            _row('Seller', _ascii(data.sellerName)),
            _row('Date', data.createdAt.toLocal().toString()),
            _row('Amount', data.amount == null ? 'To be confirmed' : 'INR ${data.amount!.toStringAsFixed(2)}'),
            _row('Payment mode', data.paymentMode),
            _row('Payment status', data.paymentStatus),
            pw.SizedBox(height: 24),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('Requirement details, seller clarifications and deal history remain available inside ASKODOX.'),
            pw.SizedBox(height: 12),
            pw.Text('This document is a deal confirmation record, not a tax invoice unless the seller issues a compliant tax invoice.'),
          ],
        ),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final safeId = data.orderId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/ASKODOX_$safeId.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  pw.Widget _row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 120, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );

  String _ascii(String value) {
    final cleaned = value.runes.where((r) => r >= 32 && r <= 126).map(String.fromCharCode).join();
    return cleaned.trim().isEmpty ? 'ASKODOX user' : cleaned;
  }
}
