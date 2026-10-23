import 'pos_money.dart';

/// Offline preview of the server's GST arithmetic (backend `pos_tax.py`).
/// The SERVER is authoritative: the issued invoice always shows the server's
/// numbers. Both sides are checked against `test/fixtures/pos_tax_vectors.json`.
class AskodoxLineInput {
  const AskodoxLineInput({
    required this.qtyMilli,
    required this.unitPricePaise,
    this.discountPaise = 0,
    this.rateBp = 0,
    this.cessBp = 0,
    this.priceIncludesTax = false,
    this.category = 'taxable',
  });

  final int qtyMilli;
  final int unitPricePaise;
  final int discountPaise;
  final int rateBp;
  final int cessBp;
  final bool priceIncludesTax;
  final String category;

  factory AskodoxLineInput.fromJson(Map<String, Object?> j) => AskodoxLineInput(
        qtyMilli: (j['qty_milli'] as num).toInt(),
        unitPricePaise: (j['unit_price_paise'] as num).toInt(),
        discountPaise: (j['discount_paise'] as num?)?.toInt() ?? 0,
        rateBp: (j['rate_bp'] as num?)?.toInt() ?? 0,
        cessBp: (j['cess_bp'] as num?)?.toInt() ?? 0,
        priceIncludesTax: j['price_includes_tax'] == true,
        category: '${j['category'] ?? 'taxable'}',
      );
}

class AskodoxLineTax {
  const AskodoxLineTax({
    required this.grossPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.cessPaise,
  });

  final int grossPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int cessPaise;

  int get taxPaise => cgstPaise + sgstPaise + igstPaise + cessPaise;
  int get totalPaise => taxablePaise + taxPaise;
}

class AskodoxTaxException implements Exception {
  const AskodoxTaxException(this.code);
  final String code;
  @override
  String toString() => 'AskodoxTaxException($code)';
}

/// UTs without a legislature levy UTGST instead of SGST.
const askodoxUtgstCodes = {'04', '26', '31', '35', '38', '97'};

AskodoxLineTax askodoxLineTax(AskodoxLineInput line, {required bool interState, required bool collectTax}) {
  if (line.qtyMilli <= 0) throw const AskodoxTaxException('qty');
  if (line.unitPricePaise < 0 || line.discountPaise < 0) throw const AskodoxTaxException('amount');
  final gross = askodoxRoundDiv(line.qtyMilli * line.unitPricePaise, 1000);
  if (line.discountPaise > gross) throw const AskodoxTaxException('discount');
  final value = gross - line.discountPaise;
  final taxed = collectTax && line.category == 'taxable' && (line.rateBp > 0 || line.cessBp > 0);
  if (!taxed) {
    return AskodoxLineTax(grossPaise: gross, taxablePaise: value, cgstPaise: 0, sgstPaise: 0, igstPaise: 0, cessPaise: 0);
  }
  var taxable = line.priceIncludesTax ? askodoxRoundDiv(value * 10000, 10000 + line.rateBp + line.cessBp) : value;
  final half = interState ? 0 : askodoxRoundDiv(taxable * line.rateBp, 20000);
  final igst = interState ? askodoxRoundDiv(taxable * line.rateBp, 10000) : 0;
  final cess = askodoxRoundDiv(taxable * line.cessBp, 10000);
  if (line.priceIncludesTax) taxable = value - (half * 2 + igst + cess);
  return AskodoxLineTax(grossPaise: gross, taxablePaise: taxable, cgstPaise: half, sgstPaise: half, igstPaise: igst, cessPaise: cess);
}

class AskodoxInvoicePreview {
  const AskodoxInvoicePreview({required this.lines, required this.documentType, required this.interState, required this.stateTaxLabel});
  final List<AskodoxLineTax> lines;
  final String documentType;
  final bool interState;
  final String stateTaxLabel;

  int _sum(int Function(AskodoxLineTax) f) => lines.fold(0, (a, l) => a + f(l));
  int get taxablePaise => _sum((l) => l.taxablePaise);
  int get cgstPaise => _sum((l) => l.cgstPaise);
  int get sgstPaise => _sum((l) => l.sgstPaise);
  int get igstPaise => _sum((l) => l.igstPaise);
  int get cessPaise => _sum((l) => l.cessPaise);
  int get taxPaise => _sum((l) => l.taxPaise);
  int get totalPaise => _sum((l) => l.totalPaise);
}

/// tax_invoice | bill_of_supply | bill
String askodoxDocumentType(String registrationType, Iterable<AskodoxLineInput> lines) {
  if (registrationType == 'unregistered') return 'bill';
  if (registrationType == 'composition') return 'bill_of_supply';
  return lines.any((l) => l.category == 'taxable' || l.category == 'zero_rated_lut') ? 'tax_invoice' : 'bill_of_supply';
}

AskodoxInvoicePreview askodoxInvoicePreview(
  List<AskodoxLineInput> lines, {
  required String registrationType,
  required String businessState,
  String? placeOfSupply,
}) {
  if (lines.isEmpty) throw const AskodoxTaxException('empty');
  final place = placeOfSupply ?? businessState;
  final inter = place != businessState;
  final collect = registrationType == 'regular';
  return AskodoxInvoicePreview(
    lines: [for (final l in lines) askodoxLineTax(l, interState: inter, collectTax: collect)],
    documentType: askodoxDocumentType(registrationType, lines),
    interState: inter,
    stateTaxLabel: askodoxUtgstCodes.contains(place) ? 'utgst' : 'sgst',
  );
}
