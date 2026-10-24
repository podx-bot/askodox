import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_invoice_pdf.dart';

void main() {
  test('amount in words uses the Indian system', () {
    expect(askodoxAmountInWords(0), 'Rupees Zero Only');
    expect(askodoxAmountInWords(29640), 'Rupees Two Hundred Ninety Six and Forty Paise Only');
    expect(askodoxAmountInWords(123456789), 'Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven and Eighty Nine Paise Only');
    expect(askodoxAmountInWords(1000000000000), 'Rupees One Thousand Crore Only');
    expect(askodoxAmountInWords(10000000), 'Rupees One Lakh Only');
  });

  testWidgets('the PDF is built from the issued record only; Telugu text goes in as an image', (tester) async {
    final invoice = <String, Object?>{
      'number': 'SL/2627/000001',
      'local_date': '2026-10-24',
      'title': 'Tax Invoice',
      'mode': 'intra',
      'place_of_supply': '36',
      'business_snapshot': {'name': 'Sri Lakshmi Stores', 'gstin': '36AAPFU0939F1ZV', 'state': 'Telangana', 'state_code': '36'},
      'customer_snapshot': {'name': 'చికెన్ హోటల్'},
      'lines': [
        {'line_no': 1, 'name': 'Biscuits', 'hsn_sac': '1905', 'unit': 'pcs', 'qty_milli': 2000, 'unit_price_paise': 11800,
          'discount_paise': 0, 'taxable_paise': 20000, 'rate_bp': 1800, 'category': 'taxable', 'total_paise': 23600},
      ],
      'rate_summary': [
        {'rate_bp': 1800, 'category': 'taxable', 'taxable_paise': 20000, 'cgst_paise': 1800, 'sgst_paise': 1800, 'igst_paise': 0, 'cess_paise': 0},
      ],
      'totals': {'taxable_paise': 20000, 'cgst_paise': 1800, 'sgst_paise': 1800, 'grand_total_paise': 23600, 'state_tax_label': 'sgst'},
      'payments': [
        {'method': 'upi', 'amount_paise': 23600, 'verification': 'cashier_confirmed'},
      ],
    };
    final bytes = (await tester.runAsync(() => askodoxInvoicePdf(invoice, compress: false)))!;
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1500));
    final text = String.fromCharCodes(bytes);
    expect(text.contains('/Subtype /Image') || text.contains('/Subtype/Image'), isTrue, reason: 'the Telugu buyer name is an image');
    expect(await tester.runAsync(() => askodoxInvoicePdfImageCount(invoice)), 1);
    expect(askodoxPdfNeedsImage('Biscuits'), isFalse);
    expect(askodoxPdfNeedsImage('చికెన్'), isTrue);
    expect(askodoxPdfNeedsImage('₹ 10'), isTrue);
  });
}
