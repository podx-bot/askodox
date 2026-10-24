import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color, Offset, TextPainter, TextSpan, TextStyle;
import 'package:pdf/widgets.dart' as pw;

/// Text the built-in PDF font cannot draw (Telugu and other Indic scripts, the ₹
/// sign — dart_pdf has no Indic shaping) is drawn by the phone's own text engine
/// (system fonts, correct shaping) into an image and placed in the PDF. Such text
/// is a picture: it cannot be selected or searched. Plain ASCII stays real text.

final _nonAscii = RegExp(r'[^\x20-\x7E\n]');

/// True when [text] needs the image path (anything outside printable ASCII).
bool askodoxPdfNeedsImage(String text) => _nonAscii.hasMatch(text);

/// [text] with every character the PDF font lacks replaced by "?" (last resort only).
String askodoxPdfAscii(Object? text) => '${text ?? ''}'.replaceAll(RegExp(r'[^\x20-\x7E\n]'), '?');

class _TextImage {
  const _TextImage(this.png, this.width, this.height);
  final Uint8List png;
  final double width;
  final double height;
}

const _scale = 4.0;

Future<_TextImage?> _render(String text, double fontSize, bool bold, double? maxWidth) async {
  try {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize * _scale,
          color: const Color(0xFF000000),
          fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: maxWidth == null ? double.infinity : maxWidth * _scale);
    final w = painter.width.ceil().clamp(1, 8000);
    final h = painter.height.ceil().clamp(1, 8000);
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), Offset.zero);
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return _TextImage(data.buffer.asUint8List(), w / _scale, h / _scale);
  } catch (_) {
    return null;
  }
}

/// Collects the strings a PDF will show (await [want] for each BEFORE building the
/// document — rendering is asynchronous), then [text] returns a widget for each.
class AskodoxPdfText {
  final Map<String, _TextImage?> _images = {};

  static String _key(String text, double size, bool bold, double? maxWidth) =>
      '$size|${bold ? 1 : 0}|${maxWidth ?? 0}|$text';

  Future<void> want(Object? value, double size, {bool bold = false, double? maxWidth}) async {
    final text = '${value ?? ''}';
    if (!askodoxPdfNeedsImage(text)) return;
    final key = _key(text, size, bold, maxWidth);
    if (_images.containsKey(key)) return;
    _images[key] = await _render(text, size, bold, maxWidth);
  }

  /// Images actually rendered.
  int get count => _images.values.whereType<_TextImage>().length;

  /// ASCII -> PDF text; otherwise its image (shrunk to fit narrow cells). Falls back
  /// to "?" only if rendering failed.
  pw.Widget text(Object? value, pw.TextStyle style, {bool bold = false, String prefix = '', double? maxWidth}) {
    final text = '${value ?? ''}';
    final size = style.fontSize ?? 12;
    final image = askodoxPdfNeedsImage(text) ? _images[_key(text, size, bold, maxWidth)] : null;
    if (image == null) return pw.Text('$prefix${askodoxPdfAscii(text)}', style: style);
    final picture = pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: pw.Alignment.centerLeft,
      child: pw.Image(pw.MemoryImage(image.png), width: image.width, height: image.height),
    );
    if (prefix.isEmpty) return picture;
    return pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Text(prefix, style: style),
      pw.Flexible(child: picture),
    ]);
  }
}
