import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../domain/escpos.dart';

/// Dots across the paper for common thermal heads (203 dpi): 58 mm -> 384, 80 mm -> 576.
int askodoxPaperDots(int paperMm) => paperMm >= 80 ? 576 : 384;

/// Draws receipt [lines] (any script: Telugu, ₹) as a black-on-white image and
/// returns ESC/POS raster bytes. Untested on real printers.
Future<Uint8List> askodoxRasterReceipt(List<String> lines, {int paperMm = 58, double fontSize = 20}) async {
  final width = askodoxPaperDots(paperMm);
  final painters = [
    for (final line in lines)
      TextPainter(
        text: TextSpan(text: line.isEmpty ? ' ' : line, style: TextStyle(fontSize: fontSize, color: const Color(0xFF000000), fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: width.toDouble()),
  ];
  final height = painters.fold<double>(0, (h, p) => h + p.height).ceil() + 8;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
  var y = 0.0;
  for (final p in painters) {
    p.paint(canvas, Offset(0, y));
    y += p.height;
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  final mono = askodoxMonochrome(data!.buffer.asUint8List(), width, height);
  // Send in bands of 255 rows: some printers cannot buffer a tall single image.
  final p = AskodoxEscPos().init();
  for (var row = 0; row < mono.height; row += 255) {
    final rows = (mono.height - row).clamp(0, 255);
    p.raster(Uint8List.sublistView(mono.bytes, row * mono.widthBytes, (row + rows) * mono.widthBytes),
        widthBytes: mono.widthBytes, height: rows);
  }
  return p.feed(3).cut().bytes();
}

/// Telugu / ₹ in names need the raster path; plain English names print as text.
bool askodoxInvoiceNeedsRaster(Map<String, Object?> invoice) =>
    askodoxReceiptLines(invoice, asciiOnly: false).any(askodoxNeedsRaster);
