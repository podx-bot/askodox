import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/share/askodox_image_share.dart';
import 'askodox_logo.dart';

/// The ONE branded QR poster (owner 2026-11-19): every QR the app shows or saves carries the ASKODOX logo,
/// the shop name, an instruction line and askodox.com. The QR itself stays plain black on white with a
/// quiet zone (a logo inside it can break scanning, UPI QRs above all); the brand lives in the frame.
/// [actions] adds Save to gallery + Share buttons that export the framed picture, not the bare square.
class AskodoxQrPoster extends StatefulWidget {
  const AskodoxQrPoster({
    super.key,
    required this.data,
    required this.te,
    this.title = '',
    this.label = '',
    this.instructionEn = '',
    this.instructionTe = '',
    this.footnoteEn = '',
    this.footnoteTe = '',
    this.size = 200,
    this.actions = true,
    this.fileName = 'askodox-qr',
    this.qrKey,
  });

  final String data;
  final bool te;

  /// Shop / payee name under the brand row.
  final String title;

  /// A short tag such as "Table 4" or the code in words.
  final String label;
  final String instructionEn;
  final String instructionTe;
  final String footnoteEn;
  final String footnoteTe;
  final double size;
  final bool actions;
  final String fileName;
  final Key? qrKey;

  @override
  State<AskodoxQrPoster> createState() => _AskodoxQrPosterState();
}

class _AskodoxQrPosterState extends State<AskodoxQrPoster> {
  final GlobalKey _boundary = GlobalKey();
  bool _busy = false;

  Future<Uint8List?> _png() async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final image = await object.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  void _say(String en, String te) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.te ? te : en)));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _png();
      if (bytes == null) return _say('Could not make the picture.', 'చిత్రం తయారు కాలేదు.');
      final ok = await askodoxSaveImageToGallery(bytes, name: widget.fileName);
      _say(ok ? 'Saved to your gallery.' : 'This phone could not save it. Use Share.',
          ok ? 'గ్యాలరీలో సేవ్ అయింది.' : 'ఈ ఫోన్‌లో సేవ్ కాలేదు. Share వాడండి.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _png();
      if (bytes == null) return _say('Could not make the picture.', 'చిత్రం తయారు కాలేదు.');
      final ok = await askodoxShareImage(bytes, name: widget.fileName, text: 'ASKODOX · askodox.com');
      if (!ok) _say('Sharing is not available on this build.', 'ఈ బిల్డ్‌లో షేర్ లేదు.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    final instruction = te ? widget.instructionTe : widget.instructionEn;
    final footnote = te ? widget.footnoteTe : widget.footnoteEn;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      RepaintBoundary(
        key: _boundary,
        child: Container(
          key: const Key('askodoxQrPoster'),
          width: widget.size + 64,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6C4DFF), width: 3),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              AskodoxLogo(size: 30),
              SizedBox(width: 8),
              Text('ASKODOX',
                  key: Key('askodoxQrPosterBrand'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFF151F45))),
            ]),
            if (widget.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF151F45))),
            ],
            if (widget.label.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFEDE9FF), borderRadius: BorderRadius.circular(20)),
                child: Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF4A32C8))),
              ),
            const SizedBox(height: 10),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(6),
              child: QrImageView(
                key: widget.qrKey,
                data: widget.data,
                size: widget.size,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            if (instruction.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF151F45))),
            ],
            if (footnote.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(footnote, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: Color(0xFF5A6078))),
            ],
            const SizedBox(height: 6),
            const Text('askodox.com', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C4DFF))),
          ]),
        ),
      ),
      if (widget.actions) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          OutlinedButton.icon(
            key: const Key('askodoxQrPosterSave'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.download),
            label: Text(te ? 'సేవ్ / డౌన్‌లోడ్' : 'Save / download'),
          ),
          FilledButton.icon(
            key: const Key('askodoxQrPosterShare'),
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share),
            label: Text(te ? 'షేర్ / ప్రింట్' : 'Share / print'),
          ),
        ]),
      ],
    ]);
  }
}
