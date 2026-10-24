import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/pdf/askodox_pdf_share.dart';
import '../../../services/chat_attachment_service.dart';
import '../../../services/media_picker.dart';
import '../data/phone_meters.dart';
import '../data/vehicle_report_pdf.dart';
import '../data/vision_inspection_repository.dart';
import '../domain/meter_math.dart';
import '../domain/photo_measure.dart' show AskodoxPoint;
import 'inspection_screen.dart' show AskodoxInspectionReportView;
import 'smart_tool_widgets.dart';

/// Picks one photo and its pixel size (null when cancelled / unreadable).
Future<(ChatAttachment, Size)?> _pickPhoto(WidgetRef ref, String source) async {
  final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
  final photo = picked.where((p) => p.isImage).firstOrNull;
  if (photo == null) return null;
  final codec = await ui.instantiateImageCodec(photo.bytes);
  final frame = await codec.getNextFrame();
  final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  return (photo, size);
}

Widget _photoButtons(BuildContext context, String keyPrefix, void Function(String source) pick) {
  final te = askodoxToolsTe(context);
  return Row(children: [
    Expanded(
      child: OutlinedButton.icon(
        key: Key('${keyPrefix}Camera'),
        onPressed: () => pick('camera'),
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(te ? 'కెమెరా' : 'Camera'),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: OutlinedButton.icon(
        key: Key('${keyPrefix}Gallery'),
        onPressed: () => pick('photos'),
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(te ? 'గ్యాలరీ' : 'Gallery'),
      ),
    ),
  ]);
}

Widget _note(String text, {Key? key}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, key: key, style: const TextStyle(fontSize: 12.5)),
    );

// ------------------------------------------------------------- protractor
/// Protractor from a photo: tap the corner, then one point on each arm.
class AskodoxProtractorScreen extends ConsumerStatefulWidget {
  const AskodoxProtractorScreen({super.key});

  @override
  ConsumerState<AskodoxProtractorScreen> createState() => _AskodoxProtractorScreenState();
}

class _AskodoxProtractorScreenState extends ConsumerState<AskodoxProtractorScreen> {
  ChatAttachment? _photo;
  Size? _size;
  final _points = <AskodoxPoint>[]; // vertex, arm A, arm B (image pixels)
  String? _error;

  Future<void> _pick(String source) async {
    final te = askodoxToolsTe(context);
    try {
      final got = await _pickPhoto(ref, source);
      if (got == null || !mounted) return;
      setState(() {
        _photo = got.$1;
        _size = got.$2;
        _points.clear();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
    }
  }

  void _tap(TapDownDetails d, Size box) {
    final image = _size;
    if (image == null || _points.length >= 3) return;
    setState(() => _points.add(
        AskodoxPoint(d.localPosition.dx / box.width * image.width, d.localPosition.dy / box.height * image.height)));
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final photo = _photo;
    final image = _size;
    double? angle;
    double? error;
    if (_points.length == 3 && image != null) {
      angle = askodoxAngleAt(_points[1], _points[0], _points[2]);
      final shown = (MediaQuery.of(context).size.width - 32).clamp(1, double.infinity);
      if (angle != null) error = askodoxAngleError(_points[1], _points[0], _points[2], tapErrorPx: 6 * image.width / shown);
    }
    final prompt = switch (_points.length) {
      0 => te ? '1. కోణం మూల (శీర్షం) నొక్కండి' : '1. Tap the corner (vertex)',
      1 => te ? '2. మొదటి భుజం మీద ఒక చోట నొక్కండి' : '2. Tap a point on the first arm',
      2 => te ? '3. రెండో భుజం మీద ఒక చోట నొక్కండి' : '3. Tap a point on the second arm',
      _ => te ? 'ఫలితం క్రింద ఉంది' : 'Result below',
    };
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ప్రొట్రాక్టర్' : 'Protractor')),
      body: ListView(key: const Key('askodoxProtractor'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _note(te
            ? 'కోణాన్ని నేరుగా ఎదురుగా నిలబడి ఫోటో తీయండి (వాలుగా తీస్తే కోణం మారుతుంది). అంచనా మాత్రమే — సర్టిఫైడ్ కొలత కాదు.'
            : 'Shoot the angle straight on (a slanted photo changes the angle). Approximate — not a certified measurement.'),
        _photoButtons(context, 'askodoxProtractor', _pick),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (photo != null && image != null) ...[
          const SizedBox(height: 10),
          Text(prompt, key: const Key('askodoxProtractorPrompt'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: image.width / image.height,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                key: const Key('askodoxProtractorImage'),
                onTapDown: (d) => _tap(d, Size(box.maxWidth, box.maxHeight)),
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(photo.bytes, fit: BoxFit.fill, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE5E7EB))),
                  CustomPaint(painter: _AnglePainter(List.of(_points), image)),
                ]),
              ),
            ),
          ),
          Row(children: [
            TextButton(
              key: const Key('askodoxProtractorUndo'),
              onPressed: _points.isEmpty ? null : () => setState(() => _points.removeLast()),
              child: Text(te ? 'వెనక్కి' : 'Undo'),
            ),
            TextButton(onPressed: _points.isEmpty ? null : () => setState(_points.clear), child: Text(te ? 'మళ్ళీ' : 'Start over')),
          ]),
        ],
        if (_points.length == 3 && angle == null)
          Text(te ? 'రెండు చోట్ల ఒకే చోట నొక్కారు — మళ్ళీ ప్రయత్నించండి.' : 'Two taps landed on the same spot — try again.'),
        if (angle != null)
          Card(
            key: const Key('askodoxProtractorResult'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${angle.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text('${te ? 'ఇతర వైపు' : 'Other side'}: ${(360 - angle).toStringAsFixed(1)}° · '
                    '${te ? 'పూరక కోణం' : 'Supplement'}: ${(180 - angle).toStringAsFixed(1)}°'),
                Text('± ${error!.toStringAsFixed(1)}° ${te ? '(నొక్కే తేడా వల్ల)' : '(from tap accuracy)'}', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _AnglePainter extends CustomPainter {
  _AnglePainter(this.points, this.image);
  final List<AskodoxPoint> points;
  final Size image;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(AskodoxPoint p) => Offset(p.x / image.width * size.width, p.y / image.height * size.height);
    final paint = Paint()
      ..color = const Color(0xFF1769FF)
      ..strokeWidth = 3;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(at(points[i]), 6, paint);
      if (i > 0) canvas.drawLine(at(points[0]), at(points[i]), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnglePainter old) => old.points.length != points.length;
}

// -------------------------------------------------------------- magnifier
/// Magnifier: a photo at full resolution with pinch zoom up to 10x (there is no
/// live camera preview in this app build).
class AskodoxMagnifierScreen extends ConsumerStatefulWidget {
  const AskodoxMagnifierScreen({super.key});

  @override
  ConsumerState<AskodoxMagnifierScreen> createState() => _AskodoxMagnifierScreenState();
}

class _AskodoxMagnifierScreenState extends ConsumerState<AskodoxMagnifierScreen> {
  ChatAttachment? _photo;
  final _zoom = TransformationController();
  bool _contrast = false;
  String? _error;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _pick(String source) async {
    final te = askodoxToolsTe(context);
    try {
      final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
      final photo = picked.where((p) => p.isImage).firstOrNull;
      if (photo == null || !mounted) return;
      setState(() {
        _photo = photo;
        _zoom.value = Matrix4.identity();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = te ? 'ఫోటో తెరవలేకపోయాను.' : 'Could not open the photo.');
    }
  }

  void _zoomTo(double scale) => setState(() => _zoom.value = Matrix4.diagonal3Values(scale, scale, 1));

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final photo = _photo;
    Widget image = photo == null
        ? const SizedBox.shrink()
        : Image.memory(photo.bytes, fit: BoxFit.contain, filterQuality: FilterQuality.high);
    if (_contrast) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          1.6, 0, 0, 0, -60, //
          0, 1.6, 0, 0, -60,
          0, 0, 1.6, 0, -60,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'మాగ్నిఫైయర్' : 'Magnifier')),
      body: Padding(
        key: const Key('askodoxMagnifier'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _note(te
              ? 'చిన్న అక్షరాలు / లేబుల్‌కి దగ్గరగా ఫోటో తీసి, వేళ్లతో పెద్దది చేయండి (10x వరకు). లైవ్ కెమెరా జూమ్ ఇంకా లేదు.'
              : 'Take a close photo of the small print / label, then pinch to zoom (up to 10x). Live camera zoom is not available yet.'),
          _photoButtons(context, 'askodoxMagnifier', _pick),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (photo != null) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final s in const [1.0, 2.0, 4.0, 8.0])
                ActionChip(key: Key('askodoxMagnifierZoom-${s.toInt()}'), label: Text('${s.toInt()}x'), onPressed: () => _zoomTo(s)),
              FilterChip(
                key: const Key('askodoxMagnifierContrast'),
                label: Text(te ? 'కాంట్రాస్ట్' : 'Contrast'),
                selected: _contrast,
                onSelected: (v) => setState(() => _contrast = v),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRect(
                child: InteractiveViewer(
                  key: const Key('askodoxMagnifierView'),
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 10,
                  child: image,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ light meter
class AskodoxLightMeterScreen extends ConsumerStatefulWidget {
  const AskodoxLightMeterScreen({super.key});

  @override
  ConsumerState<AskodoxLightMeterScreen> createState() => _AskodoxLightMeterScreenState();
}

class _AskodoxLightMeterScreenState extends ConsumerState<AskodoxLightMeterScreen> {
  double? _lux;
  Timer? _live;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (_busy) return;
    final te = askodoxToolsTe(context);
    _busy = true;
    try {
      final lux = await ref.read(askodoxPhoneMetersProvider).lux();
      if (mounted) {
        setState(() {
          _lux = lux;
          _error = null;
        });
      }
    } on AskodoxMeterException catch (e) {
      _live?.cancel();
      _live = null;
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      _busy = false;
    }
  }

  void _toggleLive() {
    setState(() {
      if (_live != null) {
        _live!.cancel();
        _live = null;
      } else {
        _live = Timer.periodic(const Duration(seconds: 1), (_) => _read());
        _read();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final lux = _lux;
    final band = lux == null ? null : askodoxLuxBand(lux);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'వెలుతురు కొలత' : 'Light meter')),
      body: ListView(key: const Key('askodoxLightMeter'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _note(te
            ? 'ఫోన్ ముందు భాగం పైన ఉండే సెన్సార్ (సాధారణంగా ముందు కెమెరా దగ్గర) వెలుతురు వైపు ఉంచండి. ఫోన్ సెన్సార్లు కాలిబ్రేట్ కావు — అంచనా మాత్రమే.'
            : 'Point the sensor on the front of the phone (usually near the front camera) at the light. Phone sensors are not calibrated — approximate only.'),
        Row(children: [
          Expanded(
            child: FilledButton(
              key: const Key('askodoxLightRead'),
              onPressed: _read,
              child: Text(te ? 'కొలువు' : 'Measure'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('askodoxLightLive'),
              onPressed: _toggleLive,
              child: Text(_live == null ? (te ? 'లైవ్' : 'Live') : (te ? 'ఆపు' : 'Stop')),
            ),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const Key('askodoxLightError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (lux != null && band != null)
          Card(
            key: const Key('askodoxLightResult'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${lux.round()} lux', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                Text(te ? band.te : band.en, key: const Key('askodoxLightBand')),
                const SizedBox(height: 4),
                Text(te ? '≈ 300–500 lux: చదువు / ఆఫీస్; 500+ : సన్నని పని.' : '≈ 300–500 lux: reading / office; 500+: fine detailed work.',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ sound meter
const askodoxSoundOffsetKey = 'askodox.tools.sound_offset.v1';

class AskodoxSoundMeterScreen extends ConsumerStatefulWidget {
  const AskodoxSoundMeterScreen({super.key});

  @override
  ConsumerState<AskodoxSoundMeterScreen> createState() => _AskodoxSoundMeterScreenState();
}

class _AskodoxSoundMeterScreenState extends ConsumerState<AskodoxSoundMeterScreen> {
  AskodoxSoundReading? _reading;
  double? _offset;
  bool _live = false;
  bool _busy = false;
  String? _error;
  final _meter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOffset();
  }

  Future<void> _loadOffset() async {
    try {
      final v = (await SharedPreferences.getInstance()).getDouble(askodoxSoundOffsetKey);
      if (mounted && v != null) setState(() => _offset = v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _live = false;
    _meter.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (_busy) return;
    final te = askodoxToolsTe(context);
    setState(() => _busy = true);
    try {
      final r = await ref.read(askodoxPhoneMetersProvider).sound();
      if (mounted) {
        setState(() {
          _reading = r;
          _error = null;
        });
      }
    } on AskodoxMeterException catch (e) {
      _live = false;
      if (mounted) setState(() => _error = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runLive() async {
    setState(() => _live = !_live);
    while (_live && mounted) {
      await _read();
    }
  }

  Future<void> _calibrate() async {
    final r = _reading;
    final meterDb = askodoxParseNumber(_meter.text);
    if (r == null || meterDb == null) return;
    final offset = askodoxSoundOffset(r.dbfs, meterDb);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(askodoxSoundOffsetKey, offset);
    } catch (_) {}
    if (mounted) setState(() => _offset = offset);
  }

  Future<void> _clearCalibration() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(askodoxSoundOffsetKey);
    } catch (_) {}
    if (mounted) setState(() => _offset = null);
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final r = _reading;
    final db = r?.calibrated(_offset);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'శబ్ద స్థాయి' : 'Sound level')),
      body: ListView(key: const Key('askodoxSoundMeter'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _note(te
            ? 'ఫోన్ మైక్ స్థాయి (dBFS) మాత్రమే — ఫోన్‌కి ఫోన్ తేడా ఉంటుంది. నిజమైన సౌండ్ మీటర్‌తో ఒకసారి సరిచేస్తే అంచనా dB చూపిస్తాం. చట్టపరమైన / వృత్తిపరమైన శబ్ద కొలతకు ఉపయోగించవద్దు. ఆడియో రికార్డ్ చేయదు, ఎక్కడికీ పంపదు.'
            : 'Phone microphone level (dBFS) only — it differs from phone to phone. Calibrate once against a real sound-level meter to see an approximate dB. Not for legal or occupational noise measurement. Nothing is recorded or sent.'),
        Row(children: [
          Expanded(
            child: FilledButton(
              key: const Key('askodoxSoundRead'),
              onPressed: _busy || _live ? null : _read,
              child: Text(te ? 'కొలువు' : 'Measure'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const Key('askodoxSoundLive'),
              onPressed: _runLive,
              child: Text(_live ? (te ? 'ఆపు' : 'Stop') : (te ? 'లైవ్' : 'Live')),
            ),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const Key('askodoxSoundError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (r != null)
          Card(
            key: const Key('askodoxSoundResult'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  db == null ? '${r.dbfs.toStringAsFixed(1)} dBFS' : '≈ ${db.toStringAsFixed(0)} dB',
                  key: const Key('askodoxSoundValue'),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: r.relative / 90),
                const SizedBox(height: 4),
                Text(db == null
                    ? (te ? 'సరిచేయని రీడింగ్ (0 = మైక్ గరిష్టం). ' : 'Uncalibrated (0 = the mic\'s maximum). ')
                    : (te ? 'మీ సౌండ్ మీటర్‌తో సరిచేసిన అంచనా. ' : 'Approximate, from your calibration. ')),
                Text('Peak ${r.peakDbfs.toStringAsFixed(1)} dBFS', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const Key('askodoxSoundCalibration'),
          title: Text(te ? 'సౌండ్ మీటర్‌తో సరిచేయి' : 'Calibrate with a sound-level meter'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            _note(te
                ? 'ఒక స్థిర శబ్దం దగ్గర నిజమైన మీటర్ పక్కన ఫోన్ పెట్టి "కొలువు" నొక్కండి, మీటర్ చూపిన dB ఇక్కడ రాయండి.'
                : 'Hold the phone next to a real meter on a steady sound, tap Measure, then type the dB the meter shows.'),
            AskodoxNumberField(controller: _meter, label: te ? 'మీటర్ రీడింగ్' : 'Meter reading', suffix: 'dB'),
            Row(children: [
              FilledButton(
                key: const Key('askodoxSoundCalibrate'),
                onPressed: r == null ? null : _calibrate,
                child: Text(te ? 'సేవ్' : 'Save'),
              ),
              const SizedBox(width: 8),
              if (_offset != null) TextButton(onPressed: _clearCalibration, child: Text(te ? 'తొలగించు' : 'Remove')),
            ]),
          ],
        ),
      ]),
    );
  }
}

// ----------------------------------------------------- vehicle report
/// Guided 4-side walk-around: one photo per side -> one Expert inspection
/// (backend `/api/vision/inspect`, domain vehicle, 4 images) -> PDF report.
class AskodoxVehicleReportScreen extends ConsumerStatefulWidget {
  const AskodoxVehicleReportScreen({super.key});

  @override
  ConsumerState<AskodoxVehicleReportScreen> createState() => _AskodoxVehicleReportScreenState();
}

class _AskodoxVehicleReportScreenState extends ConsumerState<AskodoxVehicleReportScreen> {
  final _photos = <String, ChatAttachment>{};
  final _vehicle = TextEditingController();
  final _odometer = TextEditingController();
  bool _busy = false;
  AskodoxInspectionReport? _report;
  String? _error;
  String? _shareNote;

  @override
  void dispose() {
    _vehicle.dispose();
    _odometer.dispose();
    super.dispose();
  }

  Future<void> _shoot(AskodoxVehicleSide side, String source) async {
    final te = askodoxToolsTe(context);
    try {
      final picked = await ref.read(askodoxMediaPickerProvider).pick(source);
      final photo = picked.where((p) => p.isImage).firstOrNull;
      if (photo == null || !mounted) return;
      setState(() {
        _photos[side.id] = photo;
        _report = null;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = te ? 'ఫోటో తీసుకోలేకపోయాను.' : 'Could not get the photo.');
    }
  }

  Future<void> _inspect() async {
    final te = askodoxToolsTe(context);
    setState(() {
      _busy = true;
      _error = null;
      _shareNote = null;
    });
    try {
      final report = await ref.read(askodoxVisionInspectionRepositoryProvider).inspect(
            [for (final s in askodoxVehicleSides) _photos[s.id]!],
            domain: 'vehicle',
            mode: 'expert',
            language: te ? 'te' : 'en',
            userText: askodoxVehicleInspectionNote(vehicle: _vehicle.text, odometer: _odometer.text),
          );
      if (mounted) setState(() => _report = report);
    } on AskodoxInspectionException catch (e) {
      if (mounted) setState(() => _error = e.message(te));
    } catch (_) {
      if (mounted) setState(() => _error = const AskodoxInspectionException('failed').message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() async {
    final te = askodoxToolsTe(context);
    final report = _report;
    if (report == null) return;
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final bytes = await askodoxVehicleReportPdf(
      report: report,
      photos: {for (final e in _photos.entries) e.key: e.value.bytes},
      date: date,
      vehicle: _vehicle.text,
      odometer: _odometer.text,
      te: te,
    );
    final ok = await askodoxSharePdf(bytes, name: 'vehicle-report-$date');
    if (mounted && !ok) {
      setState(() => _shareNote = te ? 'ఈ యాప్ వెర్షన్ ఫైల్ షేర్ చేయలేదు — యాప్ అప్‌డేట్ చేయండి.' : 'This app version cannot share files — please update the app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final ready = askodoxVehicleSides.every((s) => _photos.containsKey(s.id));
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'వాహన పరిశీలన రిపోర్ట్' : 'Vehicle walk-around report')),
      body: ListView(key: const Key('askodoxVehicleReport'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _note(te
            ? 'నాలుగు వైపుల ఫోటోలు తీయండి. AI కనిపించినది, అవకాశం ఉన్నది, ఫోటో నుండి చెప్పలేనిది వేరుగా చెబుతుంది. ఇది రోడ్ యోగ్యత / ఫిట్‌నెస్ సర్టిఫికెట్ కాదు. ఇంజన్, బ్రేకులు, OBD పరీక్షించదు.'
            : 'Take one photo of each side. The AI separates what it saw, what is likely and what a photo cannot tell. Not a roadworthiness / fitness certificate. Engine, brakes and OBD are not checked.'),
        TextField(
          key: const Key('askodoxVehicleName'),
          controller: _vehicle,
          decoration: InputDecoration(
            labelText: te ? 'వాహనం (ఉదా: Maruti Swift 2019) — ఐచ్ఛికం' : 'Vehicle (e.g. Maruti Swift 2019) — optional',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        AskodoxNumberField(controller: _odometer, label: te ? 'ఓడోమీటర్ — ఐచ్ఛికం' : 'Odometer — optional', suffix: 'km'),
        for (final side in askodoxVehicleSides)
          Card(
            key: ValueKey('askodoxVehicleSide-${side.id}'),
            child: ListTile(
              leading: _photos[side.id] == null
                  ? const Icon(Icons.directions_car_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(_photos[side.id]!.bytes, width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.check_circle, color: Color(0xFF16A34A))),
                    ),
              title: Text(te ? side.te : side.en),
              subtitle: Text(te ? side.tipTe : side.tipEn, style: const TextStyle(fontSize: 12)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('askodoxVehicleShoot-${side.id}'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: () => _shoot(side, 'camera'),
                ),
                IconButton(icon: const Icon(Icons.photo_library_outlined), onPressed: () => _shoot(side, 'photos')),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('askodoxVehicleInspect'),
          onPressed: ready && !_busy ? _inspect : null,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.fact_check_outlined),
          label: Text(ready
              ? (te ? 'పరిశీలించు (Expert)' : 'Inspect (Expert)')
              : (te ? '${_photos.length}/4 ఫోటోలు' : '${_photos.length}/4 photos')),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const Key('askodoxVehicleError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (report != null) ...[
          const SizedBox(height: 12),
          AskodoxInspectionReportView(report: report, te: te),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('askodoxVehiclePdf'),
            onPressed: _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(te ? 'PDF రిపోర్ట్ షేర్ చేయి' : 'Share PDF report'),
          ),
          if (_shareNote != null) Text(_shareNote!),
        ],
      ]),
    );
  }
}
