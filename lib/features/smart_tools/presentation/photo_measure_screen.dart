import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/chat_attachment_service.dart';
import '../../../services/media_picker.dart';
import '../domain/construction_calculators.dart' show AskodoxCalcException;
import '../domain/photo_measure.dart';
import 'smart_tool_widgets.dart';

/// Measure from one photo with a reference object (A4 sheet / bank card /
/// typed size): tap the reference's two ends, then the object's two ends.
/// Approximate; the range and the same-plane condition are always shown.
class AskodoxPhotoMeasureScreen extends ConsumerStatefulWidget {
  const AskodoxPhotoMeasureScreen({super.key});

  @override
  ConsumerState<AskodoxPhotoMeasureScreen> createState() => _AskodoxPhotoMeasureScreenState();
}

class _AskodoxPhotoMeasureScreenState extends ConsumerState<AskodoxPhotoMeasureScreen> {
  ChatAttachment? _photo;
  Size? _imageSize;
  final _points = <AskodoxPoint>[]; // image-pixel coordinates: refA, refB, targetA, targetB
  String _reference = askodoxReferenceObjects.first.id;
  final _custom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _pick(String source) async {
    final te = askodoxToolsTe(context);
    try {
      final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
      final photo = picked.where((p) => p.isImage).firstOrNull;
      if (photo == null) return;
      final codec = await ui.instantiateImageCodec(photo.bytes);
      final frame = await codec.getNextFrame();
      final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _imageSize = size;
        _points.clear();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
    }
  }

  double? get _referenceMm {
    if (_reference == 'custom') return askodoxParseNumber(_custom.text);
    return askodoxReferenceObjects.firstWhere((r) => r.id == _reference).lengthMm;
  }

  void _tap(TapDownDetails details, Size box) {
    final image = _imageSize;
    if (image == null || _points.length >= 4) return;
    setState(() => _points.add(AskodoxPoint(
        details.localPosition.dx / box.width * image.width, details.localPosition.dy / box.height * image.height)));
  }

  String _prompt(bool te) => switch (_points.length) {
        0 => te ? '1. రిఫరెన్స్ వస్తువు ఒక చివర నొక్కండి' : '1. Tap one end of the reference object',
        1 => te ? '2. రిఫరెన్స్ రెండో చివర నొక్కండి' : '2. Tap the other end of the reference',
        2 => te ? '3. కొలవాల్సిన దాని ఒక చివర నొక్కండి' : '3. Tap one end of what you want to measure',
        3 => te ? '4. దాని రెండో చివర నొక్కండి' : '4. Tap its other end',
        _ => te ? 'ఫలితం క్రింద ఉంది' : 'Result below',
      };

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final photo = _photo;
    final image = _imageSize;
    AskodoxPhotoMeasurement? result;
    String? calcError;
    if (_points.length == 4 && image != null) {
      final refMm = _referenceMm;
      if (refMm == null) {
        calcError = te ? 'రిఫరెన్స్ పొడవు నమోదు చేయండి.' : 'Enter the reference length.';
      } else {
        try {
          // Tap error scales with how much the photo is shrunk on screen.
          result = askodoxMeasureFromPhoto(
              referenceA: _points[0], referenceB: _points[1], referenceMm: refMm, targetA: _points[2], targetB: _points[3],
              tapErrorPx: 6 * image.width / (MediaQuery.of(context).size.width - 32).clamp(1, double.infinity));
        } on AskodoxCalcException catch (e) {
          calcError = e.message(te);
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఫోటోతో కొలత' : 'Measure from a photo')),
      body: ListView(
        key: const Key('askodoxPhotoMeasure'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            te
                ? 'తెలిసిన సైజు వస్తువు (A4 పేపర్ / బ్యాంక్ కార్డు) కొలవాల్సిన దాని పక్కనే, అదే సమతలంపై ఉంచి నేరుగా ఫోటో తీయండి. అంచనా మాత్రమే.'
                : 'Put a known-size object (A4 sheet / bank card) flat beside what you measure, on the same surface, and shoot straight on. Approximate only.',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('askodoxMeasureReference'),
            initialValue: _reference,
            isExpanded: true,
            decoration: InputDecoration(labelText: te ? 'రిఫరెన్స్ వస్తువు' : 'Reference object', border: const OutlineInputBorder(), isDense: true),
            items: [
              for (final r in askodoxReferenceObjects) DropdownMenuItem(value: r.id, child: Text(te ? r.nameTe : r.nameEn)),
              DropdownMenuItem(value: 'custom', child: Text(te ? 'ఇతర (మి.మీ.లో టైప్ చేయండి)' : 'Other (type length in mm)')),
            ],
            onChanged: (v) => setState(() => _reference = v ?? _reference),
          ),
          if (_reference == 'custom')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AskodoxNumberField(controller: _custom, label: te ? 'రిఫరెన్స్ పొడవు' : 'Reference length', suffix: 'mm',
                  onChanged: (_) => setState(() {})),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('askodoxMeasureCamera'),
                onPressed: () => _pick('camera'),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(te ? 'కెమెరా' : 'Camera'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick('photos'),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(te ? 'గ్యాలరీ' : 'Gallery'),
              ),
            ),
          ]),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (photo != null && image != null) ...[
            const SizedBox(height: 10),
            Text(_prompt(te), key: const Key('askodoxMeasurePrompt'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            AspectRatio(
              aspectRatio: image.width / image.height,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  key: const Key('askodoxMeasureImage'),
                  onTapDown: (d) => _tap(d, Size(box.maxWidth, box.maxHeight)),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(photo.bytes, fit: BoxFit.fill,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE5E7EB))),
                    CustomPaint(painter: _MarksPainter(points: List.of(_points), image: image)),
                  ]),
                ),
              ),
            ),
            Row(children: [
              TextButton(
                key: const Key('askodoxMeasureUndo'),
                onPressed: _points.isEmpty ? null : () => setState(() => _points.removeLast()),
                child: Text(te ? 'వెనక్కి' : 'Undo'),
              ),
              TextButton(
                onPressed: _points.isEmpty ? null : () => setState(_points.clear),
                child: Text(te ? 'మళ్ళీ' : 'Start over'),
              ),
            ]),
          ],
          if (calcError != null) Text(calcError, key: const Key('askodoxMeasureError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (result != null)
            Card(
              key: const Key('askodoxMeasureResult'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(result.formatted(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  Text('${te ? 'నాణ్యత' : 'Quality'}: ${result.quality.name}'),
                  for (final w in result.warnings) Text('• $w', style: const TextStyle(fontSize: 12)),
                  Text(te ? 'సర్వే / ఇంజనీరింగ్ కొలత కాదు.' : 'Not a survey-grade or engineering measurement.',
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({required this.points, required this.image});
  final List<AskodoxPoint> points;
  final Size image;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(AskodoxPoint p) => Offset(p.x / image.width * size.width, p.y / image.height * size.height);
    for (var i = 0; i < points.length; i++) {
      final paint = Paint()
        ..color = i < 2 ? const Color(0xFF1769FF) : const Color(0xFFDC2626)
        ..strokeWidth = 3;
      canvas.drawCircle(at(points[i]), 6, paint);
      if (i.isOdd) canvas.drawLine(at(points[i - 1]), at(points[i]), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarksPainter old) => old.points.length != points.length;
}
