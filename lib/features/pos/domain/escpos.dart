import 'dart:typed_data';

import 'pos_money.dart';

/// ESC/POS command builder for thermal receipt printers.
///
/// Uses only the widely shared basic commands (ESC @, ESC a, ESC E, GS !,
/// GS V, GS v 0 raster). Printers differ: nothing here is "verified" with a
/// real printer until one is tested and recorded in the compatibility matrix.
/// Text that is not plain ASCII (Telugu, ₹) must be printed as a RASTER
/// image -- [askodoxNeedsRaster] tells the caller.
class AskodoxEscPos {
  final _bytes = BytesBuilder(copy: false);

  Uint8List bytes() => _bytes.toBytes();

  AskodoxEscPos init() => _add([0x1B, 0x40]);

  /// 0 left, 1 centre, 2 right.
  AskodoxEscPos align(int value) => _add([0x1B, 0x61, value.clamp(0, 2)]);

  AskodoxEscPos bold(bool on) => _add([0x1B, 0x45, on ? 1 : 0]);

  /// width / height multipliers 1..8 (GS ! n).
  AskodoxEscPos size({int width = 1, int height = 1}) =>
      _add([0x1D, 0x21, ((width.clamp(1, 8) - 1) << 4) | (height.clamp(1, 8) - 1)]);

  AskodoxEscPos text(String value) {
    if (askodoxNeedsRaster(value)) throw ArgumentError('Text needs raster printing: $value');
    return _add([...value.codeUnits, 0x0A]);
  }

  AskodoxEscPos feed(int lines) => _add([0x1B, 0x64, lines.clamp(0, 255)]);

  /// Partial cut after feeding (GS V 66 n). Printers without a cutter ignore it.
  AskodoxEscPos cut() => _add([0x1D, 0x56, 0x42, 0x03]);

  /// GS v 0: [packed] is 1 bit per pixel, MSB first, rows of [widthBytes].
  AskodoxEscPos raster(Uint8List packed, {required int widthBytes, required int height}) {
    if (packed.length != widthBytes * height) throw ArgumentError('raster size');
    return _add([0x1D, 0x76, 0x30, 0x00, widthBytes & 0xFF, widthBytes >> 8, height & 0xFF, height >> 8, ...packed]);
  }

  AskodoxEscPos _add(List<int> data) {
    _bytes.add(data);
    return this;
  }
}

bool askodoxNeedsRaster(String text) => text.codeUnits.any((c) => c > 0x7E || (c < 0x20 && c != 0x0A));

/// RGBA pixels -> packed 1-bit rows (dark pixel = printed dot). Width is padded
/// to whole bytes. Transparent pixels count as paper.
({Uint8List bytes, int widthBytes, int height}) askodoxMonochrome(Uint8List rgba, int width, int height,
    {int threshold = 160}) {
  if (rgba.length < width * height * 4) throw ArgumentError('rgba size');
  final widthBytes = (width + 7) ~/ 8;
  final out = Uint8List(widthBytes * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final alpha = rgba[i + 3];
      final luminance = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
      final dark = alpha > 127 && luminance < threshold;
      if (dark) out[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return (bytes: out, widthBytes: widthBytes, height: height);
}

/// Printable characters per line for common paper widths (Font A).
int askodoxReceiptColumns(int paperMm) => paperMm >= 80 ? 48 : 32;

/// A plain-ASCII receipt (English names) for printers without raster support;
/// "Rs" replaces the rupee sign. Telugu receipts use the raster path.
List<String> askodoxReceiptLines(Map<String, Object?> invoice, {int columns = 32, bool asciiOnly = true}) {
  String money(Object? paise) => askodoxPaise((paise as num? ?? 0).toInt(), symbol: false);
  String pair(String left, String right) {
    final space = columns - left.length - right.length;
    if (space >= 1) return '$left${' ' * space}$right';
    return '${left.substring(0, (columns - right.length - 1).clamp(0, left.length))} $right';
  }

  String ascii(Object? v) => asciiOnly ? '${v ?? ''}'.replaceAll(RegExp(r'[^\x20-\x7E]'), '?') : '${v ?? ''}';
  final business = (invoice['business_snapshot'] as Map?) ?? const {};
  final customer = (invoice['customer_snapshot'] as Map?) ?? const {};
  final totals = (invoice['totals'] as Map?) ?? const {};
  final rule = '-' * columns;
  final lines = <String>[
    ascii(business['name']),
    if ('${business['address'] ?? ''}'.isNotEmpty) ascii(business['address']),
    if (business['gstin'] != null) 'GSTIN: ${business['gstin']}',
    if ('${business['heading'] ?? ''}'.isNotEmpty) ascii(business['heading']),
    ascii(invoice['title']),
    pair('No: ${invoice['number']}', '${invoice['local_date'] ?? ''}'),
    'To: ${ascii(customer['name'])}',
    if (customer['gstin'] != null) 'GSTIN: ${customer['gstin']}',
    rule,
  ];
  for (final raw in (invoice['lines'] as List? ?? const [])) {
    final line = Map<String, Object?>.from(raw as Map);
    lines.add(ascii(line['name']));
    final qty = askodoxQty((line['qty_milli'] as num).toInt(), '${line['unit']}');
    lines.add(pair('  $qty x ${money(line['unit_price_paise'])}', money(line['total_paise'])));
    if ('${line['hsn_sac'] ?? ''}'.isNotEmpty) lines.add('  HSN ${line['hsn_sac']}');
  }
  lines.add(rule);
  lines.add(pair('Taxable', money(totals['taxable_paise'])));
  final stateLabel = '${totals['state_tax_label'] ?? 'sgst'}'.toUpperCase();
  if ((totals['cgst_paise'] as num? ?? 0) != 0) lines.add(pair('CGST', money(totals['cgst_paise'])));
  if ((totals['sgst_paise'] as num? ?? 0) != 0) lines.add(pair(stateLabel, money(totals['sgst_paise'])));
  if ((totals['igst_paise'] as num? ?? 0) != 0) lines.add(pair('IGST', money(totals['igst_paise'])));
  if ((totals['cess_paise'] as num? ?? 0) != 0) lines.add(pair('Cess', money(totals['cess_paise'])));
  if ((totals['round_off_paise'] as num? ?? 0) != 0) lines.add(pair('Round off', money(totals['round_off_paise'])));
  lines.add(pair('TOTAL Rs', money(totals['grand_total_paise'])));
  for (final raw in (invoice['payments'] as List? ?? const [])) {
    final p = Map<String, Object?>.from(raw as Map);
    lines.add(pair('Paid ${p['method']}', money(p['amount_paise'])));
  }
  if ((invoice['balance_paise'] as num? ?? 0) > 0) lines.add(pair('Balance due', money(invoice['balance_paise'])));
  lines.add(rule);
  lines.add('Thank you');
  return lines;
}

/// Full ESC/POS bytes for [askodoxReceiptLines].
Uint8List askodoxReceiptBytes(Map<String, Object?> invoice, {int paperMm = 58}) {
  final columns = askodoxReceiptColumns(paperMm);
  final lines = askodoxReceiptLines(invoice, columns: columns);
  final p = AskodoxEscPos().init().align(1).bold(true).text(lines.first).bold(false).align(0);
  for (final line in lines.skip(1)) {
    p.text(line);
  }
  return p.feed(3).cut().bytes();
}
