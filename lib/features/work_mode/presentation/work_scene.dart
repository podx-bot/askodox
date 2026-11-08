import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/work_mode_plan.dart';

/// The live picture of the job. What is drawn follows the REAL progress of the
/// current stage (rows ploughed, seedlings planted, bricks laid, doors served,
/// seam welded ...). While the person is walking ([active]) the worker does the
/// stage's work -- the plough moves, the shovel throws soil, the paper flies to
/// the door -- and when they stop, the worker stops too. Each new count of
/// steps floats as "+N" over the scene ([gain] changes).
class AskodoxWorkSceneView extends StatefulWidget {
  const AskodoxWorkSceneView({
    required this.job,
    required this.stageIndex,
    required this.stageFraction,
    this.active = true,
    this.gain = 0,
    this.gainId = 0,
    this.height = 240,
    super.key,
  });

  final AskodoxWorkJob job;
  final int stageIndex;

  /// 0..1 inside the current stage.
  final double stageFraction;

  /// The person is walking now: the worker works.
  final bool active;

  /// Steps added by the latest count, floated as "+N" whenever [gainId] changes.
  final int gain;
  final int gainId;
  final double height;

  @override
  State<AskodoxWorkSceneView> createState() => _AskodoxWorkSceneViewState();
}

class _AskodoxWorkSceneViewState extends State<AskodoxWorkSceneView> with TickerProviderStateMixin {
  // One slow clock (60 s); every motion uses a period that divides 60 s, so
  // the loop never jumps.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))
    ..repeat();
  late final AnimationController _bubble =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  int _shownGain = 0;

  @override
  void didUpdateWidget(covariant AskodoxWorkSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gain > 0 && widget.gainId != oldWidget.gainId) {
      _shownGain = widget.gain;
      _bubble.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _bubble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        key: const Key('askodoxWorkScene'),
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: Listenable.merge([_clock, _bubble]),
            builder: (context, _) => CustomPaint(
              painter: AskodoxWorkScenePainter(
                job: widget.job,
                stageIndex: _ci(widget.stageIndex, 0, widget.job.stages.length - 1),
                fraction: widget.stageFraction.clamp(0.0, 1.0),
                seconds: _clock.value * 60,
                active: widget.active,
                bubble: _bubble.isAnimating ? _bubble.value : -1,
                gain: _shownGain,
              ),
            ),
          ),
        ),
      );
}

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// A body pose: angles in radians from straight down (positive = forward).
class _Pose {
  const _Pose({this.lean = 0, this.armF = 0, this.armB = 0, this.legF = 0, this.legB = 0, this.crouch = 0, this.bob = 0});
  final double lean;
  final double armF;
  final double armB;
  final double legF;
  final double legB;
  final double crouch;
  final double bob;
}

const _skin = Color(0xFFC68B59);
const _skinBack = Color(0xFFA9744A);
const _pants = Color(0xFF2D3E50);
const _pantsBack = Color(0xFF223040);

class AskodoxWorkScenePainter extends CustomPainter {
  AskodoxWorkScenePainter({
    required this.job,
    required this.stageIndex,
    required this.fraction,
    required this.seconds,
    required this.active,
    this.bubble = -1,
    this.gain = 0,
  });

  final AskodoxWorkJob job;
  final int stageIndex;
  final double fraction;
  final double seconds;
  final bool active;
  final double bubble;
  final int gain;

  late double _w;
  late double _h;
  late double _s;

  String get _stage => job.stages[stageIndex].id;
  int _idx(String id) => job.stages.indexWhere((s) => s.id == id);
  bool get _lastStageDone => stageIndex == job.stages.length - 1 && fraction >= 0.999;

  /// sin wave with a period that divides 60 s.
  double _wave(double period, [double shift = 0]) => math.sin(2 * math.pi * (seconds / period + shift));

  /// 0..1 saw with a period that divides 60 s.
  double _saw(double period, [double shift = 0]) => (seconds / period + shift) % 1;

  // ------------------------------------------------------------------ paint

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    _s = _h / 240;
    _backdrop(canvas);
    switch (job.scene) {
      case AskodoxWorkScene.field:
        _field(canvas);
      case AskodoxWorkScene.houses:
        _houses(canvas);
      case AskodoxWorkScene.building:
        if (job.id == 'digging') {
          _digging(canvas);
        } else {
          _house(canvas);
        }
      case AskodoxWorkScene.workshop:
        if (job.id == 'chicken_shop') {
          _shop(canvas);
        } else {
          _welding(canvas);
        }
    }
    _gainBubble(canvas);
  }

  void _backdrop(Canvas c) {
    final evening = _lastStageDone;
    final sky = Rect.fromLTWH(0, 0, _w, _h);
    c.drawRect(
        sky,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: evening ? const [Color(0xFFF2A65A), Color(0xFFFCE3C0)] : const [Color(0xFF8CCBEB), Color(0xFFE6F5FB)],
          ).createShader(sky));
    final sun = Offset(_w * 0.82, _h * (evening ? 0.34 : 0.16));
    c.drawCircle(sun, 26 * _s, Paint()..color = (evening ? const Color(0xFFF08A24) : const Color(0xFFFFE9A6)).withValues(alpha: 0.35));
    c.drawCircle(sun, 16 * _s, Paint()..color = evening ? const Color(0xFFF08A24) : const Color(0xFFFFE08A));
    // Clouds drift across in 60 s.
    for (var i = 0; i < 2; i++) {
      final x = ((_saw(60, i * 0.5)) * (_w + 160 * _s)) - 80 * _s;
      final y = _h * (0.12 + 0.08 * i);
      final p = Paint()..color = Colors.white.withValues(alpha: 0.9);
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 54 * _s, height: 18 * _s), p);
      c.drawOval(Rect.fromCenter(center: Offset(x + 16 * _s, y - 7 * _s), width: 34 * _s, height: 18 * _s), p);
    }
    // Birds.
    final bird = Paint()
      ..color = const Color(0xFF4A5560)
      ..strokeWidth = 1.4 * _s
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 3; i++) {
      final x = _w * (0.15 + 0.08 * i) + _saw(30, i * 0.2) * _w * 0.3;
      final y = _h * (0.22 + 0.03 * (i % 2)) + _wave(5, i * 0.3) * 3 * _s;
      final flap = 3 * _s + _wave(0.5, i * 0.3) * 2 * _s;
      c.drawPath(
          Path()
            ..moveTo(x - 5 * _s, y)
            ..quadraticBezierTo(x - 2.5 * _s, y - flap, x, y)
            ..quadraticBezierTo(x + 2.5 * _s, y - flap, x + 5 * _s, y),
          bird);
    }
    // Hills and trees.
    c.drawPath(
        Path()
          ..moveTo(0, _h * 0.5)
          ..quadraticBezierTo(_w * 0.22, _h * 0.33, _w * 0.45, _h * 0.47)
          ..quadraticBezierTo(_w * 0.72, _h * 0.32, _w, _h * 0.46)
          ..lineTo(_w, _h * 0.62)
          ..lineTo(0, _h * 0.62)
          ..close(),
        Paint()..color = const Color(0xFFB3C9A3));
    for (final x in [0.06, 0.93]) {
      _palm(c, Offset(_w * x, _h * 0.6), 1.0);
    }
    c.drawRect(
        Rect.fromLTWH(0, _h * 0.58, _w, _h * 0.42),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CC97A), Color(0xFF6E9E4F)],
          ).createShader(Rect.fromLTWH(0, _h * 0.58, _w, _h * 0.42)));
  }

  void _palm(Canvas c, Offset base, double k) {
    final s = _s * k;
    final sway = _wave(4) * 2 * s;
    final top = base + Offset(6 * s + sway, -62 * s);
    c.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(base.dx + 8 * s, base.dy - 30 * s, top.dx, top.dy),
        Paint()
          ..color = const Color(0xFF8B6B4A)
          ..strokeWidth = 4 * s
          ..style = PaintingStyle.stroke);
    final leaf = Paint()
      ..color = const Color(0xFF3F7D3A)
      ..strokeWidth = 3 * s
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = -math.pi + i * math.pi / 5;
      final end = top + Offset(math.cos(a) * 20 * s, math.sin(a).abs() * -4 * s + 8 * s);
      c.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo((top.dx + end.dx) / 2, top.dy - 8 * s, end.dx, end.dy),
          leaf);
    }
  }

  // ----------------------------------------------------------------- people

  /// Draws a worker standing on [foot], facing right. Returns the front hand.
  Offset _person(Canvas c, Offset foot, _Pose p,
      {Color shirt = const Color(0xFF2F6FEB), Color cap = const Color(0xFFE8C87A), bool mask = false, double k = 1}) {
    final s = _s * k;
    final down = 1 - 0.38 * p.crouch;
    final hip = foot + Offset(0, -31 * s * down + p.bob * s);
    void leg(double a, Color col) {
      final knee = hip + Offset(math.sin(a) * 15 * s + p.crouch * 8 * s, math.cos(a) * 15 * s * down);
      final ankle = knee + Offset(math.sin(a) * 14 * s - p.crouch * 6 * s, 15 * s * down);
      c.drawPath(
          Path()
            ..moveTo(hip.dx, hip.dy)
            ..lineTo(knee.dx, knee.dy)
            ..lineTo(ankle.dx, ankle.dy),
          Paint()
            ..color = col
            ..strokeWidth = 5.5 * s
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke);
      c.drawLine(
          ankle,
          ankle + Offset(5 * s, 0),
          Paint()
            ..color = const Color(0xFF3B2A20)
            ..strokeWidth = 4 * s
            ..strokeCap = StrokeCap.round);
    }

    final shoulder = hip + Offset(math.sin(p.lean) * 24 * s, -math.cos(p.lean) * 24 * s);
    Offset arm(double a, Color col) {
      final elbow = shoulder + Offset(math.sin(a) * 11 * s, math.cos(a) * 11 * s);
      final hand = elbow + Offset(math.sin(a + 0.35) * 11 * s, math.cos(a + 0.35) * 11 * s);
      c.drawPath(
          Path()
            ..moveTo(shoulder.dx, shoulder.dy)
            ..lineTo(elbow.dx, elbow.dy)
            ..lineTo(hand.dx, hand.dy),
          Paint()
            ..color = col
            ..strokeWidth = 4 * s
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke);
      return hand;
    }

    c.drawOval(Rect.fromCenter(center: foot + Offset(2 * s, 2 * s), width: 30 * s, height: 6 * s),
        Paint()..color = Colors.black.withValues(alpha: 0.16));
    leg(p.legB, _pantsBack);
    arm(p.armB, _skinBack);
    c.drawLine(
        hip,
        shoulder,
        Paint()
          ..color = shirt
          ..strokeWidth = 11 * s
          ..strokeCap = StrokeCap.round);
    final head = shoulder + Offset(math.sin(p.lean) * 9 * s, -math.cos(p.lean) * 9 * s);
    c.drawCircle(head, 6.8 * s, Paint()..color = _skin);
    if (mask) {
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: head + Offset(3 * s, 0), width: 10 * s, height: 13 * s),
              Radius.circular(2 * s)),
          Paint()..color = const Color(0xFF263238));
      c.drawRect(Rect.fromCenter(center: head + Offset(5 * s, -1 * s), width: 5 * s, height: 2.4 * s),
          Paint()..color = const Color(0xFF7CB342));
    } else {
      c.drawPath(
          Path()
            ..moveTo(head.dx - 7.5 * s, head.dy - 1 * s)
            ..quadraticBezierTo(head.dx, head.dy - 14 * s, head.dx + 8 * s, head.dy - 1 * s)
            ..close(),
          Paint()..color = cap);
    }
    leg(p.legF, _pants);
    return arm(p.armF, _skin);
  }

  _Pose _walk([double speed = 0.75]) {
    if (!active) return const _Pose();
    final a = _wave(speed);
    return _Pose(lean: 0.1, legF: a * 0.45, legB: -a * 0.45, armF: -a * 0.5, armB: a * 0.5, bob: _wave(speed / 2).abs() * -1.5);
  }

  _Pose _bend() {
    if (!active) return const _Pose(lean: 0.35, crouch: 0.2, armF: 0.2, armB: 0.1);
    final reach = (_wave(1.0) + 1) / 2;
    return _Pose(lean: 1.0, crouch: 0.45, armF: 0.1 + reach * 0.5, armB: 0.2, legF: 0.15, legB: -0.1);
  }

  _Pose _swing([double period = 1.0]) {
    if (!active) return const _Pose(lean: 0.15, armF: 0.4, armB: 0.3);
    final t = (_wave(period) + 1) / 2; // 0 = raised, 1 = struck
    return _Pose(lean: 0.25 + t * 0.35, crouch: 0.2, armF: -2.2 + t * 2.7, armB: -2.0 + t * 2.5, legF: 0.25, legB: -0.2);
  }

  _Pose _carryHead() {
    final w = _walk(0.75);
    return _Pose(lean: 0.02, legF: w.legF, legB: w.legB, armF: math.pi - 0.15, armB: math.pi - 0.05, bob: w.bob);
  }

  _Pose _crouch() {
    final jitter = active ? _wave(0.1) * 0.02 : 0.0;
    return _Pose(lean: 0.55, crouch: 0.85, armF: 1.0 + jitter, armB: 0.7, legF: 0.4, legB: 0.1);
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  // ------------------------------------------------------------------ field

  static const _rows = 5;
  static const _slots = 11;

  double _rowY(int i) => _h * (0.66 + 0.064 * i);
  double _rowLeft(int i) => _w * (0.12 - 0.018 * i);
  double _rowRight(int i) => _w * (0.84 + 0.018 * i);
  Offset _slot(int row, int slot) =>
      Offset(_rowLeft(row) + (_rowRight(row) - _rowLeft(row)) * (slot + 0.5) / _slots, _rowY(row));

  void _field(Canvas c) {
    final paddy = job.id == 'paddy';
    final plough = math.max(_idx('plough'), _idx('beds'));
    final plantAt = _idx('transplant') >= 0 ? _idx('transplant') : _idx('sow');
    final last = job.stages.length - 1;
    final tilledAll = stageIndex > plough;
    // Field plot with bunds.
    final plot = Path()
      ..moveTo(_rowLeft(0) - 10 * _s, _rowY(0) - 14 * _s)
      ..lineTo(_rowRight(0) + 10 * _s, _rowY(0) - 14 * _s)
      ..lineTo(_rowRight(_rows - 1) + 16 * _s, _h)
      ..lineTo(_rowLeft(_rows - 1) - 16 * _s, _h)
      ..close();
    c.drawPath(plot, Paint()..color = tilledAll ? const Color(0xFF8C6A45) : const Color(0xFF93A866));
    if (paddy && stageIndex > plough) {
      // Flooded paddy: a sky-coloured sheen that ripples.
      c.drawPath(plot, Paint()..color = const Color(0xFF9FD3F0).withValues(alpha: 0.35 + 0.05 * _wave(3)));
    }
    c.drawPath(plot, _stroke(const Color(0xFFB59A72), 4 * _s));

    // Nursery patch (left) during the first stages.
    if (_idx('nursery') >= 0 && stageIndex <= plantAt) {
      final patch = Rect.fromLTWH(_w * 0.02, _h * 0.6, _w * 0.13, _h * 0.07);
      c.drawRect(patch, Paint()..color = const Color(0xFF7E5B3A));
      final grown = stageIndex == 0 ? fraction : 1.0;
      final count = (8 + grown * 28).round();
      for (var i = 0; i < count; i++) {
        final x = patch.left + 3 * _s + (i % 9) * patch.width / 9;
        final y = patch.top + 4 * _s + (i ~/ 9) * patch.height / 4;
        c.drawLine(Offset(x, y + 4 * _s), Offset(x, y + 4 * _s - (2 + 4 * grown) * _s), _stroke(const Color(0xFF5DBB4C), 1.4 * _s));
      }
    }

    // Rows.
    final total = _rows * _slots;
    for (var r = 0; r < _rows; r++) {
      var tilledTo = tilledAll ? _rowRight(r) : _rowLeft(r);
      if (stageIndex == plough) {
        final pos = fraction * _rows;
        if (r < pos.floor()) tilledTo = _rowRight(r);
        if (r == pos.floor()) tilledTo = _rowLeft(r) + (_rowRight(r) - _rowLeft(r)) * (pos - r);
      }
      if (tilledTo > _rowLeft(r)) {
        c.drawLine(Offset(_rowLeft(r), _rowY(r)), Offset(tilledTo, _rowY(r)), _stroke(const Color(0xFF5E4127), 3.2 * _s));
      } else {
        c.drawLine(Offset(_rowLeft(r), _rowY(r)), Offset(_rowRight(r), _rowY(r)), _stroke(const Color(0xFF7F9658), 1.6 * _s));
      }
    }

    // Plants: none before planting; planted one by one; grow after; harvested one by one.
    var planted = 0;
    if (stageIndex > plantAt) planted = total;
    if (stageIndex == plantAt) planted = (fraction * total).floor();
    final afterPlant = math.max(1, last - plantAt - 1);
    var growth = stageIndex <= plantAt ? 0.3 : (0.3 + 0.7 * ((stageIndex - plantAt - 1 + fraction) / afterPlant)).clamp(0.3, 1.0);
    final harvesting = stageIndex == last && (_stage == 'harvest' || _stage == 'pick');
    if (harvesting) growth = 1.0;
    final cut = harvesting && _stage == 'harvest' ? (fraction * total).floor() : 0;
    final weeds = _stage == 'weed' ? ((1 - fraction) * 12).ceil() : 0;
    for (var i = 0; i < total; i++) {
      final r = i ~/ _slots;
      final k = r.isEven ? i % _slots : _slots - 1 - i % _slots; // planted back and forth
      final at = _slot(r, k);
      final scale = 0.75 + 0.12 * r;
      if (i < cut) {
        c.drawLine(at, at + Offset(0, -3 * _s), _stroke(const Color(0xFFB08A3E), 1.6 * _s));
        continue;
      }
      if (i < planted) _plant(c, at, scale, growth, harvesting);
      if (i % 5 == 2 && (i ~/ 5) < weeds) {
        c.drawCircle(at + Offset(6 * _s, 1 * _s), 2.6 * _s * scale, Paint()..color = const Color(0xFF3E6B2A));
      }
    }
    if (cut > 0) {
      // Sheaves stacked at the side.
      final sheaves = (cut / 6).ceil();
      for (var i = 0; i < sheaves; i++) {
        final base = Offset(_w * 0.9 + (i % 3) * 7 * _s, _h * 0.98 - (i ~/ 3) * 9 * _s);
        c.drawPath(
            Path()
              ..moveTo(base.dx - 4 * _s, base.dy)
              ..lineTo(base.dx, base.dy - 14 * _s)
              ..lineTo(base.dx + 4 * _s, base.dy)
              ..close(),
            Paint()..color = const Color(0xFFD9A441));
      }
    }

    // The worker and the live work of this stage.
    final cursor = _ci(stageIndex == plantAt ? planted : (_stage == 'harvest' ? cut : (fraction * total).floor()), 0, total - 1);
    final row = _ci(cursor ~/ _slots, 0, _rows - 1);
    final kk = row.isEven ? cursor % _slots : _slots - 1 - cursor % _slots;
    final spot = _slot(row, _ci(kk, 0, _slots - 1));
    switch (_stage) {
      case 'nursery':
      case 'beds':
      case 'sow': {
        if (_stage == 'beds') {
          _ploughTeam(c, withOxen: false);
          break;
        }
        final foot = _stage == 'sow' ? spot + Offset(-10 * _s, 0) : Offset(_w * 0.2, _h * 0.68);
        final hand = _person(c, foot, _bend());
        if (active) {
          for (var i = 0; i < 3; i++) {
            final t = _saw(1.0, i / 3);
            c.drawCircle(hand + Offset(2 * _s, t * 14 * _s), 1.4 * _s,
                Paint()..color = const Color(0xFF6B4A2B).withValues(alpha: 1 - t));
          }
        }
      }
      case 'plough':
        _ploughTeam(c, withOxen: true);
      case 'transplant': {
        final hand = _person(c, spot + Offset(-12 * _s, 6 * _s), _bend());
        c.drawLine(hand, hand + Offset(2 * _s, -7 * _s), _stroke(const Color(0xFF5DBB4C), 1.6 * _s));
      }
      case 'water': {
        // Channel with running water along the left bund.
        final top = Offset(_rowLeft(0) - 6 * _s, _rowY(0) - 10 * _s);
        final bottom = Offset(_rowLeft(_rows - 1) - 12 * _s, _h);
        c.drawLine(top, bottom, _stroke(const Color(0xFF4AA3E0), 6 * _s));
        for (var i = 0; i < 6; i++) {
          final t = active ? _saw(2, i / 6) : i / 6;
          final p = Offset.lerp(top, bottom, t)!;
          c.drawLine(p, p + Offset(-1 * _s, 5 * _s), _stroke(Colors.white.withValues(alpha: 0.8), 1.4 * _s));
        }
        // Water spreading into the rows that are done.
        final wet = (fraction * _rows).ceil();
        for (var r = 0; r < wet; r++) {
          c.drawLine(Offset(_rowLeft(r), _rowY(r) + 3 * _s), Offset(_rowRight(r), _rowY(r) + 3 * _s),
              _stroke(const Color(0xFF6EC1EA).withValues(alpha: 0.55 + 0.15 * _wave(2, r * 0.2)), 2.4 * _s));
        }
        final foot = Offset(_rowLeft(row) - 4 * _s, _rowY(row) + 4 * _s);
        final hand = _person(c, foot, _swing(1.5));
        c.drawLine(hand, hand + Offset(8 * _s, 14 * _s), _stroke(const Color(0xFF7A5232), 2.2 * _s));
      }
      case 'weed': {
        final hand = _person(c, spot + Offset(-12 * _s, 6 * _s), _bend());
        if (active) c.drawCircle(hand, 2.4 * _s, Paint()..color = const Color(0xFF3E6B2A));
      }
      case 'flower': {
        final x = _rowLeft(row) + (_rowRight(row) - _rowLeft(row)) * (_saw(12)).clamp(0.05, 0.95);
        _person(c, Offset(active ? x : spot.dx, _rowY(row) + 6 * _s), _walk(1.0));
      }
      case 'harvest': {
        final hand = _person(c, spot + Offset(-12 * _s, 6 * _s), _swing(1.0));
        // Sickle.
        c.drawArc(Rect.fromCircle(center: hand + Offset(4 * _s, 0), radius: 5 * _s), -math.pi / 2, math.pi,
            false, _stroke(const Color(0xFF9AA0A6), 1.8 * _s));
      }
      case 'pick': {
        final hand = _person(c, spot + Offset(-12 * _s, 6 * _s), _bend());
        c.drawCircle(hand, 2 * _s, Paint()..color = const Color(0xFFD32F2F));
        // Basket filling at the side.
        final basket = Rect.fromLTWH(_w * 0.88, _h * 0.88, 26 * _s, 16 * _s);
        c.drawRRect(RRect.fromRectAndRadius(basket, Radius.circular(4 * _s)), Paint()..color = const Color(0xFFB08850));
        c.drawOval(Rect.fromLTWH(basket.left + 2 * _s, basket.top - 4 * _s * fraction, basket.width - 4 * _s, 8 * _s),
            Paint()..color = const Color(0xFFD32F2F));
      }
      default:
        _person(c, spot, _walk());
    }
  }

  void _plant(Canvas c, Offset at, double scale, double growth, bool ripe) {
    final hgt = (6 + 18 * growth) * _s * scale;
    final sway = active ? _wave(3, at.dx / 300) * 1.5 * growth * _s : 0.0;
    final stem = ripe && job.id == 'paddy' ? const Color(0xFFC9962E) : const Color(0xFF2F7A32);
    for (final dx in [-2.5, 0.0, 2.5]) {
      c.drawLine(at + Offset(dx * _s * scale, 0), at + Offset(dx * 1.6 * _s * scale + sway, -hgt), _stroke(stem, 1.5 * _s));
    }
    if (ripe && job.id == 'paddy') {
      c.drawOval(Rect.fromCenter(center: at + Offset(sway + 2 * _s, -hgt), width: 5 * _s, height: 3 * _s),
          Paint()..color = const Color(0xFFE6B84F));
    }
    if (job.id == 'chilli' && (_stage == 'flower' || _stage == 'pick')) {
      final top = at + Offset(sway, -hgt);
      if (_stage == 'flower') {
        c.drawCircle(top + Offset(2 * _s, 2 * _s), 1.6 * _s, Paint()..color = Colors.white);
      } else {
        c.drawLine(top + Offset(2 * _s, 3 * _s), top + Offset(3 * _s, 9 * _s), _stroke(const Color(0xFFD32F2F), 2 * _s));
      }
    }
    if (job.id == 'vegetables' && ripe) {
      c.drawCircle(at + Offset(sway, -hgt * 0.6), 2.6 * _s, Paint()..color = const Color(0xFF8E24AA));
    }
  }

  void _ploughTeam(Canvas c, {required bool withOxen}) {
    final pos = fraction * _rows;
    final row = _ci(pos.floor(), 0, _rows - 1);
    final along = (pos - row).clamp(0.0, 1.0);
    final x = _rowLeft(row) + (_rowRight(row) - _rowLeft(row)) * along;
    final y = _rowY(row) + 4 * _s;
    if (withOxen) {
      _ox(c, Offset(x + 40 * _s, y - 2 * _s));
      _ox(c, Offset(x + 46 * _s, y + 4 * _s));
      // Yoke and plough.
      c.drawLine(Offset(x + 20 * _s, y - 14 * _s), Offset(x + 4 * _s, y - 2 * _s), _stroke(const Color(0xFF7A5232), 2.4 * _s));
      c.drawLine(Offset(x + 4 * _s, y - 2 * _s), Offset(x + 8 * _s, y + 3 * _s), _stroke(const Color(0xFF555555), 2.4 * _s));
    }
    // Soil kicked up behind the blade.
    if (active) {
      for (var i = 0; i < 4; i++) {
        final t = _saw(0.75, i / 4);
        c.drawCircle(Offset(x + 2 * _s - t * 10 * _s, y - math.sin(math.pi * t) * 8 * _s), 1.6 * _s,
            Paint()..color = const Color(0xFF6B4A2B).withValues(alpha: 1 - t));
      }
    }
    final hand = _person(c, Offset(x - 10 * _s, y + 2 * _s), _walk(0.75));
    c.drawLine(hand, Offset(x + 4 * _s, y - 4 * _s), _stroke(const Color(0xFF7A5232), 2 * _s));
  }

  void _ox(Canvas c, Offset foot) {
    final s = _s;
    final ph = active ? _wave(0.75) : 0.0;
    final body = Paint()..color = const Color(0xFFEDE6DA);
    final legP = _stroke(const Color(0xFFCFC6B6), 3.4 * s);
    for (final (dx, sign) in const [(-14.0, 1.0), (-8.0, -1.0), (10.0, -1.0), (16.0, 1.0)]) {
      c.drawLine(foot + Offset(dx * s, -18 * s), foot + Offset(dx * s + ph * sign * 4 * s, 0), legP);
    }
    c.drawOval(Rect.fromCenter(center: foot + Offset(0, -23 * s), width: 42 * s, height: 17 * s), body);
    c.drawOval(Rect.fromCenter(center: foot + Offset(9 * s, -31 * s), width: 12 * s, height: 9 * s), body);
    c.drawOval(Rect.fromCenter(center: foot + Offset(24 * s, -25 * s), width: 12 * s, height: 10 * s), body);
    final horn = _stroke(const Color(0xFF6B5B4B), 2 * s);
    c.drawLine(foot + Offset(22 * s, -30 * s), foot + Offset(19 * s, -37 * s), horn);
    c.drawLine(foot + Offset(26 * s, -30 * s), foot + Offset(29 * s, -37 * s), horn);
    c.drawLine(foot + Offset(-21 * s, -25 * s), foot + Offset(-24 * s - ph * 2 * s, -12 * s), horn);
  }

  // ----------------------------------------------------------------- houses

  static const _doors = 6;

  Offset _door(int i) => Offset(_w * (0.1 + 0.15 * i) + 18 * _s, _h * 0.8);

  void _houses(Canvas c) {
    // Lane.
    c.drawRect(Rect.fromLTWH(0, _h * 0.84, _w, _h * 0.16), Paint()..color = const Color(0xFF8A8F96));
    for (var i = 0; i < 8; i++) {
      final x = i * _w / 7;
      c.drawLine(Offset(x, _h * 0.93), Offset(x + 16 * _s, _h * 0.93), _stroke(Colors.white.withValues(alpha: 0.7), 2 * _s));
    }
    final delivering = _stage == 'rounds' || _stage == 'deliver';
    final collecting = _stage == 'collect';
    // A street walked three times during the stage (three rounds).
    final lap = delivering ? (fraction * 3) % 1 : fraction;
    final served = delivering || collecting ? (lap * _doors).floor() : 0;
    for (var i = 0; i < _doors; i++) {
      final x = _w * (0.1 + 0.15 * i);
      final body = Rect.fromLTWH(x, _h * 0.6, 36 * _s, 44 * _s);
      c.drawRect(body, Paint()..color = const [Color(0xFFF2D7B6), Color(0xFFE9C3C3), Color(0xFFCFE0F2)][i % 3]);
      c.drawPath(
          Path()
            ..moveTo(x - 4 * _s, _h * 0.6)
            ..lineTo(x + 18 * _s, _h * 0.6 - 16 * _s)
            ..lineTo(x + 40 * _s, _h * 0.6)
            ..close(),
          Paint()..color = const Color(0xFFB5523B));
      c.drawRect(Rect.fromLTWH(x + 13 * _s, _h * 0.6 + 22 * _s, 10 * _s, 22 * _s), Paint()..color = const Color(0xFF7A5232));
      c.drawRect(Rect.fromLTWH(x + 25 * _s, _h * 0.6 + 8 * _s, 8 * _s, 8 * _s), Paint()..color = const Color(0xFFFFF3C4));
      if (i < served) {
        c.drawCircle(Offset(x + 30 * _s, _h * 0.6 - 6 * _s), 5 * _s, Paint()..color = const Color(0xFF1F8A5B));
        c.drawPath(
            Path()
              ..moveTo(x + 27.5 * _s, _h * 0.6 - 6 * _s)
              ..lineTo(x + 29.5 * _s, _h * 0.6 - 4 * _s)
              ..lineTo(x + 32.5 * _s, _h * 0.6 - 8.5 * _s),
            _stroke(Colors.white, 1.4 * _s));
        if (job.id == 'paper') {
          c.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x + 8 * _s, _h * 0.6 + 40 * _s, 9 * _s, 4 * _s), Radius.circular(2 * _s)),
              Paint()..color = const Color(0xFFF5F0E6));
        } else {
          c.drawRect(Rect.fromLTWH(x + 6 * _s, _h * 0.6 + 36 * _s, 7 * _s, 7 * _s), Paint()..color = const Color(0xFFC49A6C));
        }
      }
    }

    if (delivering) {
      final next = _ci(served, 0, _doors - 1);
      final from = served == 0 ? Offset(0, _h * 0.9) : _door(served - 1) + Offset(0, _h * 0.1);
      final to = _door(next) + Offset(-12 * _s, _h * 0.1);
      final within = (lap * _doors) - served;
      final at = Offset.lerp(from, to, within.clamp(0.0, 1.0))!;
      if (job.id == 'paper') {
        _rider(c, at);
        if (active) {
          // The paper flies to the next door.
          final t = _saw(1.5);
          final start = at + Offset(10 * _s, -36 * _s);
          final end = _door(next) + Offset(-4 * _s, 0);
          final p = Offset.lerp(start, end, t)! + Offset(0, -math.sin(math.pi * t) * 24 * _s);
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(t * 2 * math.pi);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 10 * _s, height: 4 * _s), Radius.circular(2 * _s)),
              Paint()..color = const Color(0xFFF5F0E6));
          c.restore();
        }
      } else {
        final hand = _person(c, at, _walk(0.75));
        c.drawRect(Rect.fromCenter(center: hand + Offset(4 * _s, -2 * _s), width: 10 * _s, height: 9 * _s),
            Paint()..color = const Color(0xFFC49A6C));
      }
      return;
    }
    if (collecting) {
      final at = _door(_ci(served, 0, _doors - 1)) + Offset(-14 * _s, _h * 0.1);
      final hand = _person(c, at, active ? _Pose(armF: 1.2 + _wave(1) * 0.15, armB: 0.2) : const _Pose(armF: 0.6));
      c.drawRect(Rect.fromCenter(center: hand + Offset(3 * _s, 0), width: 8 * _s, height: 10 * _s), Paint()..color = Colors.white);
      return;
    }
    if (_stage == 'route') {
      final x = _w * (0.05 + 0.9 * fraction);
      _person(c, Offset(x, _h * 0.92), _walk());
      for (var i = 0; i < _doors; i++) {
        if (_w * (0.1 + 0.15 * i) < x) {
          c.drawCircle(_door(i) + Offset(0, -46 * _s), 3 * _s, Paint()..color = const Color(0xFFE8A317));
        }
      }
      return;
    }
    // Bundle / pickup / sort / returns: moving items from one pile to another.
    final pileA = Offset(_w * 0.12, _h * 0.98);
    final pileB = Offset(_w * 0.32, _h * 0.98);
    final left = _stage == 'returns' ? fraction : 1 - fraction;
    for (var i = 0; i < (left * 8).ceil(); i++) {
      c.drawRect(Rect.fromLTWH(pileA.dx - 8 * _s, pileA.dy - (i + 1) * 6 * _s, 16 * _s, 5.5 * _s),
          Paint()..color = job.id == 'paper' ? const Color(0xFFF5F0E6) : const Color(0xFFC49A6C));
    }
    for (var i = 0; i < ((1 - left) * 8).floor(); i++) {
      c.drawRect(Rect.fromLTWH(pileB.dx - 8 * _s, pileB.dy - (i + 1) * 6 * _s, 16 * _s, 5.5 * _s),
          Paint()..color = job.id == 'paper' ? const Color(0xFFF5F0E6) : const Color(0xFFC49A6C));
    }
    final t = active ? (_wave(3) + 1) / 2 : 0.5;
    final at = Offset.lerp(pileA + Offset(14 * _s, 0), pileB + Offset(-14 * _s, 0), t)!;
    final hand = _person(c, at, _walk(0.75));
    c.drawRect(Rect.fromCenter(center: hand + Offset(3 * _s, -2 * _s), width: 10 * _s, height: 7 * _s),
        Paint()..color = job.id == 'paper' ? const Color(0xFFF5F0E6) : const Color(0xFFC49A6C));
  }

  void _rider(Canvas c, Offset ground) {
    final s = _s;
    final r = 9 * s;
    final back = ground + Offset(-13 * s, -r);
    final front = ground + Offset(13 * s, -r);
    final rot = active ? 2 * math.pi * _saw(0.6) : 0.0;
    for (final ctr in [back, front]) {
      c.drawCircle(ctr, r, _stroke(const Color(0xFF2D3E50), 2 * s));
      for (var k = 0; k < 3; k++) {
        final a = rot + k * math.pi / 3;
        c.drawLine(ctr + Offset(math.cos(a) * r, math.sin(a) * r), ctr - Offset(math.cos(a) * r, math.sin(a) * r),
            _stroke(const Color(0xFF8A929A), 0.8 * s));
      }
    }
    final seat = ground + Offset(-4 * s, -24 * s);
    final bar = ground + Offset(10 * s, -27 * s);
    final crank = ground + Offset(0, -r);
    c.drawPath(
        Path()
          ..moveTo(back.dx, back.dy)
          ..lineTo(seat.dx, seat.dy)
          ..lineTo(bar.dx, bar.dy)
          ..lineTo(front.dx, front.dy)
          ..moveTo(back.dx, back.dy)
          ..lineTo(crank.dx, crank.dy)
          ..lineTo(seat.dx, seat.dy)
          ..moveTo(crank.dx, crank.dy)
          ..lineTo(bar.dx, bar.dy),
        _stroke(const Color(0xFFD9534F), 2.4 * s));
    c.drawRect(Rect.fromLTWH(bar.dx + 1 * s, bar.dy - 2 * s, 10 * s, 7 * s), Paint()..color = const Color(0xFFB08850));
    c.drawRect(Rect.fromLTWH(bar.dx + 2 * s, bar.dy - 5 * s, 8 * s, 3 * s), Paint()..color = const Color(0xFFF5F0E6));
    // Rider: hips on the seat, feet on the turning pedals.
    final hip = seat + Offset(0, -3 * s);
    for (final (shift, col) in [(math.pi, _pantsBack), (0.0, _pants)]) {
      final pedal = crank + Offset(math.cos(rot + shift) * 5 * s, math.sin(rot + shift) * 5 * s);
      final knee = Offset((hip.dx + pedal.dx) / 2 + 6 * s, math.min(hip.dy, pedal.dy) - 2 * s);
      c.drawPath(
          Path()
            ..moveTo(hip.dx, hip.dy)
            ..lineTo(knee.dx, knee.dy)
            ..lineTo(pedal.dx, pedal.dy),
          Paint()
            ..color = col
            ..strokeWidth = 5 * s
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke);
    }
    final shoulder = hip + Offset(9 * s, -20 * s);
    c.drawLine(hip, shoulder, _stroke(const Color(0xFF2F6FEB), 10 * s));
    c.drawLine(shoulder, bar + Offset(2 * s, -2 * s), _stroke(_skin, 3.6 * s));
    final head = shoulder + Offset(4 * s, -8 * s);
    c.drawCircle(head, 6.5 * s, Paint()..color = _skin);
    c.drawPath(
        Path()
          ..moveTo(head.dx - 7 * s, head.dy - 1 * s)
          ..quadraticBezierTo(head.dx, head.dy - 13 * s, head.dx + 7.5 * s, head.dy - 1 * s)
          ..close(),
        Paint()..color = const Color(0xFFE8C87A));
  }

  // ---------------------------------------------------------------- digging

  void _digging(Canvas c) {
    final ground = _h * 0.8;
    final pitL = _w * 0.25;
    final pitR = _w * 0.62;
    final markAt = _idx('mark');
    final digAt = _idx('dig');
    final depthFrac = stageIndex < digAt ? 0.0 : stageIndex == digAt ? fraction : 1.0;
    final depth = 8 * _s + depthFrac * 38 * _s;
    if (stageIndex == markAt) {
      final pegs = 2 + (fraction * 6).floor();
      for (var i = 0; i < pegs; i++) {
        final x = pitL + (pitR - pitL) * i / 7;
        c.drawLine(Offset(x, ground), Offset(x, ground - 10 * _s), _stroke(const Color(0xFF8B6B4A), 2.4 * _s));
      }
      c.drawLine(Offset(pitL, ground - 8 * _s), Offset(pitL + (pitR - pitL) * (pegs - 1) / 7, ground - 8 * _s),
          _stroke(Colors.white, 1 * _s));
      final hand = _person(c, Offset(pitL + (pitR - pitL) * pegs / 7 - 10 * _s, ground + 4 * _s), _bend());
      c.drawLine(hand, hand + Offset(0, 8 * _s), _stroke(const Color(0xFF8B6B4A), 2.4 * _s));
      return;
    }
    // Pit.
    final pit = Path()
      ..moveTo(pitL, ground)
      ..lineTo(pitR, ground)
      ..lineTo(pitR - 10 * _s, ground + depth)
      ..lineTo(pitL + 10 * _s, ground + depth)
      ..close();
    c.drawPath(pit, Paint()..color = const Color(0xFF5E4127));
    if (_stage == 'level') {
      // The floor gets smoother as the stage goes.
      final bump = (1 - fraction) * 4 * _s;
      final floor = Path()..moveTo(pitL + 10 * _s, ground + depth);
      for (var i = 1; i <= 8; i++) {
        floor.lineTo(pitL + 10 * _s + (pitR - pitL - 20 * _s) * i / 8, ground + depth - (i.isEven ? bump : 0));
      }
      c.drawPath(floor, _stroke(const Color(0xFF8C6A45), 2 * _s));
    }
    // Heap of dug soil.
    final heapSize = (stageIndex == digAt ? fraction : 1.0) * (_stage == 'clear' ? 1.0 - 0.5 * fraction : 1.0);
    final heapFar = _stage == 'clear' || stageIndex > _idx('clear') ? (stageIndex == _idx('clear') ? fraction : 1.0) : 0.0;
    c.drawPath(
        Path()
          ..moveTo(pitR + 8 * _s, ground)
          ..quadraticBezierTo(pitR + 26 * _s, ground - (6 + 26 * heapSize) * _s, pitR + 46 * _s, ground)
          ..close(),
        Paint()..color = const Color(0xFF9C6B43));
    if (heapFar > 0) {
      c.drawPath(
          Path()
            ..moveTo(_w * 0.8, ground)
            ..quadraticBezierTo(_w * 0.87, ground - (6 + 30 * heapFar) * _s, _w * 0.95, ground)
            ..close(),
          Paint()..color = const Color(0xFF9C6B43));
    }
    switch (_stage) {
      case 'dig': {
        final hand = _person(c, Offset(pitL + (pitR - pitL) * 0.55, ground + depth * 0.6), _swing(1.0));
        c.drawLine(hand, hand + Offset(6 * _s, 16 * _s), _stroke(const Color(0xFF7A5232), 2.4 * _s));
        c.drawLine(hand + Offset(6 * _s, 16 * _s), hand + Offset(10 * _s, 21 * _s), _stroke(const Color(0xFF9AA0A6), 4 * _s));
        if (active) {
          for (var i = 0; i < 5; i++) {
            final t = _saw(1.0, i / 5);
            final from = hand + Offset(8 * _s, 18 * _s);
            final to = Offset(pitR + 26 * _s, ground - 10 * _s);
            final p = Offset.lerp(from, to, t)! + Offset(0, -math.sin(math.pi * t) * 22 * _s);
            c.drawCircle(p, 2 * _s, Paint()..color = const Color(0xFF8C6A45).withValues(alpha: 1 - t * 0.6));
          }
        }
      }
      case 'clear': {
        final t = active ? (_wave(4) + 1) / 2 : 0.0;
        final at = Offset.lerp(Offset(pitR + 50 * _s, ground + 4 * _s), Offset(_w * 0.78, ground + 4 * _s), t)!;
        final hand = _person(c, at, _carryHead());
        c.drawOval(Rect.fromCenter(center: hand + Offset(0, -4 * _s), width: 18 * _s, height: 8 * _s),
            Paint()..color = const Color(0xFF8B6B4A));
      }
      case 'level': {
        final hand = _person(c, Offset(pitL + (pitR - pitL) * (0.2 + 0.6 * fraction), ground + depth), _swing(0.75));
        c.drawLine(hand, hand + Offset(0, 14 * _s), _stroke(const Color(0xFF7A5232), 2.2 * _s));
        c.drawRect(Rect.fromCenter(center: hand + Offset(0, 16 * _s), width: 10 * _s, height: 3 * _s),
            Paint()..color = const Color(0xFF555555));
      }
      default:
        _person(c, Offset(pitL - 14 * _s, ground + 4 * _s), _walk());
    }
  }

  // ------------------------------------------------------------ house build

  void _house(Canvas c) {
    final ground = _h * 0.86;
    final left = _w * 0.24;
    final right = _w * 0.68;
    const courses = 10;
    const perCourse = 7;
    final brickW = (right - left) / perCourse;
    final brickH = 7 * _s;
    final wallsAt = _idx('walls');
    final roofAt = _idx('roof');
    final plasterAt = _idx('plaster');
    final finishAt = _idx('finish');
    // Foundation trench and concrete.
    final found = stageIndex == 0 ? fraction : 1.0;
    c.drawRect(Rect.fromLTWH(left - 6 * _s, ground, right - left + 12 * _s, 8 * _s), Paint()..color = const Color(0xFF5E4127));
    c.drawRect(Rect.fromLTWH(left - 6 * _s, ground, (right - left + 12 * _s) * found, 8 * _s),
        Paint()..color = const Color(0xFF9AA0A6));
    // Brick pile.
    final pileLeft = stageIndex <= wallsAt ? (stageIndex == wallsAt ? 1 - fraction : 1.0) : 0.0;
    for (var i = 0; i < (pileLeft * 12).ceil(); i++) {
      c.drawRect(Rect.fromLTWH(_w * 0.82 + (i % 3) * 9 * _s, ground - (i ~/ 3 + 1) * brickH, 8 * _s, brickH - 1),
          Paint()..color = const Color(0xFFC0583A));
    }
    // Walls brick by brick.
    final laid = stageIndex < wallsAt ? 0.0 : stageIndex == wallsAt ? fraction * courses * perCourse : (courses * perCourse).toDouble();
    final whole = laid.floor();
    for (var i = 0; i <= whole && i < courses * perCourse; i++) {
      final row = i ~/ perCourse;
      final k = i % perCourse;
      final slide = i == whole ? (laid - whole) : 1.0;
      if (i == whole && slide <= 0.02) break;
      final x = left + k * brickW + (row.isOdd ? brickW / 2 : 0);
      if (x + brickW > right + brickW / 2) continue;
      final y = ground - (row + 1) * brickH;
      final dx = (1 - slide) * 24 * _s;
      final rect = Rect.fromLTWH(x + dx, y, math.min(brickW, right - x), brickH);
      c.drawRect(rect, Paint()..color = Color.lerp(const Color(0xFFC0583A), const Color(0xFFE07A55), i == whole ? 0.6 : 0.0)!);
      c.drawRect(rect, _stroke(const Color(0xFFEDE3D3), 0.8));
    }
    final wallTop = ground - courses * brickH;
    if (stageIndex >= roofAt) {
      final slab = stageIndex == roofAt ? fraction : 1.0;
      for (final x in [left + 6 * _s, (left + right) / 2, right - 6 * _s]) {
        if (stageIndex == roofAt) c.drawLine(Offset(x, ground), Offset(x, wallTop - 4 * _s), _stroke(const Color(0xFF8B6B4A), 2 * _s));
      }
      c.drawRect(Rect.fromLTWH(left - 8 * _s, wallTop - 8 * _s, (right - left + 16 * _s) * slab, 8 * _s),
          Paint()..color = const Color(0xFF9AA0A6));
    }
    if (stageIndex >= plasterAt) {
      final cover = stageIndex == plasterAt ? fraction : 1.0;
      c.drawRect(Rect.fromLTWH(left, wallTop, (right - left) * cover, ground - wallTop),
          Paint()..color = const Color(0xFFEDE3D3));
    }
    if (stageIndex >= finishAt) {
      final f = stageIndex == finishAt ? fraction : 1.0;
      c.drawRect(Rect.fromLTWH(left, wallTop, (right - left) * f, ground - wallTop),
          Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.8));
      final a = f.clamp(0.0, 1.0);
      c.drawRect(Rect.fromLTWH((left + right) / 2 - 8 * _s, ground - 34 * _s, 16 * _s, 34 * _s),
          Paint()..color = const Color(0xFF7A5232).withValues(alpha: a));
      for (final x in [left + 12 * _s, right - 30 * _s]) {
        c.drawRect(Rect.fromLTWH(x, wallTop + 12 * _s, 18 * _s, 16 * _s), Paint()..color = const Color(0xFF6FA8DC).withValues(alpha: a));
      }
    }
    // The worker.
    switch (_stage) {
      case 'walls': {
        final t = active ? (_wave(4) + 1) / 2 : 1.0;
        final at = Offset.lerp(Offset(_w * 0.8, ground + 6 * _s), Offset(right + 14 * _s, ground + 6 * _s), t)!;
        final hand = _person(c, at, _carryHead());
        for (var i = 0; i < 3; i++) {
          c.drawRect(Rect.fromLTWH(hand.dx - 9 * _s, hand.dy - 6 * _s - i * 4 * _s, 18 * _s, 3.6 * _s),
              Paint()..color = const Color(0xFFC0583A));
        }
      }
      case 'plaster':
      case 'finish': {
        final x = left + (right - left) * (stageIndex == plasterAt || stageIndex == finishAt ? fraction : 1.0);
        final hand = _person(c, Offset(math.min(x + 12 * _s, _w * 0.9), ground + 6 * _s), _swing(1.0));
        c.drawRect(Rect.fromCenter(center: hand + Offset(-3 * _s, 0), width: 8 * _s, height: 4 * _s),
            Paint()..color = const Color(0xFF9AA0A6));
      }
      default: {
        final t = active ? (_wave(4) + 1) / 2 : 0.0;
        final at = Offset.lerp(Offset(_w * 0.1, ground + 6 * _s), Offset(left - 10 * _s, ground + 6 * _s), t)!;
        final hand = _person(c, at, _carryHead());
        c.drawOval(Rect.fromCenter(center: hand + Offset(0, -3 * _s), width: 18 * _s, height: 7 * _s),
            Paint()..color = const Color(0xFF9AA0A6));
      }
    }
  }

  // ---------------------------------------------------------------- welding

  void _shed(Canvas c) {
    c.drawRect(Rect.fromLTWH(_w * 0.06, _h * 0.46, _w * 0.88, _h * 0.48), Paint()..color = const Color(0xFFE6E1D6));
    c.drawPath(
        Path()
          ..moveTo(_w * 0.02, _h * 0.47)
          ..lineTo(_w * 0.5, _h * 0.32)
          ..lineTo(_w * 0.98, _h * 0.47)
          ..close(),
        Paint()..color = const Color(0xFF5C6B7A));
    c.drawRect(Rect.fromLTWH(0, _h * 0.94, _w, _h * 0.06), Paint()..color = const Color(0xFF9E9E9E));
  }

  void _welding(Canvas c) {
    _shed(c);
    final bench = Rect.fromLTWH(_w * 0.36, _h * 0.78, _w * 0.42, 6 * _s);
    c.drawRect(bench, Paint()..color = const Color(0xFF7A5232));
    c.drawLine(Offset(bench.left + 6 * _s, bench.bottom), Offset(bench.left + 6 * _s, _h * 0.94), _stroke(const Color(0xFF5D4037), 3 * _s));
    c.drawLine(Offset(bench.right - 6 * _s, bench.bottom), Offset(bench.right - 6 * _s, _h * 0.94), _stroke(const Color(0xFF5D4037), 3 * _s));
    // The gate being made stands on the bench.
    final frame = Rect.fromLTWH(_w * 0.42, _h * 0.52, _w * 0.3, _h * 0.26);
    final steel = _stroke(const Color(0xFF6D7278), 3 * _s);
    final painted = _stage == 'paint' ? fraction : (_idx('paint') < stageIndex ? 1.0 : 0.0);
    if (_stage == 'measure') {
      final bars = (fraction * 6).ceil();
      for (var i = 0; i < bars; i++) {
        c.drawLine(Offset(bench.left + 8 * _s, bench.top - 3 * _s - i * 3.4 * _s),
            Offset(bench.left + 8 * _s + bench.width * 0.7, bench.top - 3 * _s - i * 3.4 * _s), steel);
      }
      final tape = bench.width * 0.7 * ((_wave(2) + 1) / 2);
      c.drawLine(Offset(bench.left + 8 * _s, bench.top - 26 * _s), Offset(bench.left + 8 * _s + tape, bench.top - 26 * _s),
          _stroke(const Color(0xFFFFC107), 2 * _s));
      final hand = _person(c, Offset(bench.left - 6 * _s, _h * 0.94), _bend());
      c.drawLine(hand, Offset(bench.left + 8 * _s, bench.top - 26 * _s), _stroke(const Color(0xFFFFC107), 1 * _s));
      return;
    }
    c.drawRect(frame, steel);
    for (var i = 1; i < 5; i++) {
      final x = frame.left + frame.width * i / 5;
      c.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), steel);
    }
    if (painted > 0) {
      final cover = Rect.fromLTWH(frame.left - 2 * _s, frame.top - 2 * _s, (frame.width + 4 * _s) * painted, frame.height + 4 * _s);
      c.save();
      c.clipRect(cover);
      final blue = _stroke(const Color(0xFF1F6FB2), 3.4 * _s);
      c.drawRect(frame, blue);
      for (var i = 1; i < 5; i++) {
        final x = frame.left + frame.width * i / 5;
        c.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), blue);
      }
      c.restore();
    }
    // Joints along the frame: 10 points (tack) / seam progress (weld) / grinding.
    final joints = <Offset>[
      for (var i = 0; i <= 5; i++) Offset(frame.left + frame.width * i / 5, frame.top),
      for (var i = 0; i <= 5; i++) Offset(frame.left + frame.width * i / 5, frame.bottom),
    ];
    final done = _stage == 'tack' ? (fraction * joints.length).floor() : joints.length;
    for (var i = 0; i < done; i++) {
      c.drawCircle(joints[i], 2.4 * _s, Paint()..color = const Color(0xFF9E9E9E));
    }
    Offset? work;
    if (_stage == 'tack') work = joints[_ci(done, 0, joints.length - 1)];
    if (_stage == 'weld' || _stage == 'grind') {
      final seam = math.min(fraction * joints.length, joints.length - 1.0);
      final i = _ci(seam.floor(), 0, joints.length - 2);
      work = Offset.lerp(joints[i], joints[i + 1], seam - i);
      final glow = _stroke(const Color(0xFFFF8F00).withValues(alpha: 0.75), 2.4 * _s);
      for (var j = 0; j < i; j++) {
        if (j == 5) continue; // no seam between the top and bottom rails' ends
        c.drawLine(joints[j], joints[j + 1], _stage == 'weld' ? _stroke(const Color(0xFF8D6E63), 2.6 * _s) : glow);
      }
    }
    final hand = _person(c, Offset(frame.left - 18 * _s, _h * 0.94), _crouch(), mask: _stage != 'paint', shirt: const Color(0xFF455A64));
    if (_stage == 'paint') {
      final x = frame.left + frame.width * fraction;
      c.drawLine(hand, Offset(x, frame.center.dy + _wave(1) * 10 * _s), _stroke(const Color(0xFF7A5232), 2 * _s));
      return;
    }
    if (work == null) return;
    c.drawLine(hand, work, _stroke(const Color(0xFF37474F), 2.2 * _s));
    if (!active) return;
    final rnd = math.Random((seconds * 12).floor());
    final flicker = 0.55 + rnd.nextDouble() * 0.45;
    c.drawCircle(
        work,
        22 * _s,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: flicker),
            const Color(0xFF80D8FF).withValues(alpha: 0.4 * flicker),
            Colors.transparent,
          ]).createShader(Rect.fromCircle(center: work, radius: 22 * _s)));
    final sparks = _stage == 'grind' ? 14 : 8;
    for (var i = 0; i < sparks; i++) {
      final a = _stage == 'grind' ? math.pi * (0.05 + rnd.nextDouble() * 0.25) : rnd.nextDouble() * math.pi;
      final r = (6 + rnd.nextDouble() * (_stage == 'grind' ? 30 : 16)) * _s;
      final end = work + Offset(math.cos(a) * r, -math.sin(a) * r * 0.6 + rnd.nextDouble() * 10 * _s);
      c.drawLine(work, end, _stroke(const Color(0xFFFFB84D), 1.3 * _s));
    }
  }

  // ------------------------------------------------------------ chicken shop

  void _shop(Canvas c) {
    _shed(c);
    // Awning.
    for (var i = 0; i < 8; i++) {
      c.drawRect(Rect.fromLTWH(_w * 0.06 + i * _w * 0.11, _h * 0.46, _w * 0.11, 12 * _s),
          Paint()..color = i.isEven ? const Color(0xFFD32F2F) : Colors.white);
    }
    final counter = Rect.fromLTWH(_w * 0.3, _h * 0.72, _w * 0.42, _h * 0.22);
    c.drawRect(counter, Paint()..color = const Color(0xFF8D6E63));
    // Scale with a moving needle.
    final scale = Offset(counter.left + 20 * _s, counter.top - 10 * _s);
    c.drawCircle(scale, 9 * _s, Paint()..color = Colors.white);
    c.drawCircle(scale, 9 * _s, _stroke(const Color(0xFF455A64), 1.4 * _s));
    final needle = -math.pi / 2 + (active && _stage == 'serve' ? 0.6 + _wave(2) * 0.4 : 0.0);
    c.drawLine(scale, scale + Offset(math.cos(needle) * 7 * _s, math.sin(needle) * 7 * _s), _stroke(const Color(0xFFD32F2F), 1.4 * _s));
    // Shopkeeper behind the counter.
    final keeper = Offset(counter.left + counter.width * 0.6, counter.top + 4 * _s);
    switch (_stage) {
      case 'market': {
        final crates = (fraction * 6).ceil();
        for (var i = 0; i < crates; i++) {
          c.drawRect(Rect.fromLTWH(_w * 0.78 + (i % 2) * 18 * _s, _h * 0.94 - (i ~/ 2 + 1) * 11 * _s, 16 * _s, 10 * _s),
              Paint()..color = const Color(0xFFFFB74D));
        }
        final t = active ? (_wave(4) + 1) / 2 : 1.0;
        final at = Offset.lerp(Offset(_w * 0.05, _h * 0.95), Offset(_w * 0.74, _h * 0.95), t)!;
        final hand = _person(c, at, _carryHead());
        c.drawRect(Rect.fromCenter(center: hand + Offset(0, -5 * _s), width: 18 * _s, height: 10 * _s),
            Paint()..color = const Color(0xFFFFB74D));
      }
      case 'clean': {
        final hand = _person(c, keeper, active ? _Pose(lean: 0.3, armF: 1.3 + _wave(0.75) * 0.5, armB: 0.3) : const _Pose(armF: 0.5));
        c.drawRect(Rect.fromCenter(center: hand, width: 8 * _s, height: 4 * _s), Paint()..color = const Color(0xFF4FC3F7));
        final shine = (fraction * 6).floor();
        for (var i = 0; i < shine; i++) {
          final p = Offset(counter.left + 10 * _s + i * counter.width / 6, counter.top + 4 * _s);
          c.drawLine(p + Offset(-3 * _s, 0), p + Offset(3 * _s, 0), _stroke(Colors.white, 1.2 * _s));
          c.drawLine(p + Offset(0, -3 * _s), p + Offset(0, 3 * _s), _stroke(Colors.white, 1.2 * _s));
        }
      }
      case 'serve': {
        _person(c, keeper, active ? _Pose(armF: 1.6 + _wave(1) * 0.3, armB: 0.6) : const _Pose(armF: 0.5));
        // Customers come to the counter and leave, one after another.
        final served = (fraction * 12).floor();
        for (var i = 0; i < 2; i++) {
          final t = active ? _saw(6, i * 0.5) : 0.5;
          final x = t < 0.4 ? _w * (0.02 + t * 0.6) : t < 0.6 ? _w * 0.26 : _w * (0.26 - (t - 0.6) * 0.6);
          _person(c, Offset(x, _h * 0.98), _walk(0.75), shirt: i == 0 ? const Color(0xFF8E24AA) : const Color(0xFF00897B), cap: const Color(0xFF3E2723));
        }
        for (var i = 0; i < served; i++) {
          c.drawCircle(Offset(_w * 0.1 + i * 7 * _s, _h * 0.52), 2.4 * _s, Paint()..color = const Color(0xFF1F8A5B));
        }
      }
      default: {
        // Closing: the shutter rolls down while the keeper writes the day's sales.
        final down = (_h * 0.46 + 12 * _s) + (counter.bottom - _h * 0.46 - 12 * _s) * fraction;
        _person(c, Offset(_w * 0.2, _h * 0.98), active ? _Pose(armF: 1.4 + _wave(0.5) * 0.08, armB: 1.2) : const _Pose(armF: 1.2, armB: 1.0));
        c.drawRect(Rect.fromLTWH(_w * 0.28, _h * 0.46 + 12 * _s, _w * 0.46, down - (_h * 0.46 + 12 * _s)),
            Paint()..color = const Color(0xFF90A4AE));
        for (var y = _h * 0.46 + 16 * _s; y < down; y += 5 * _s) {
          c.drawLine(Offset(_w * 0.28, y), Offset(_w * 0.74, y), _stroke(const Color(0xFF78909C), 1));
        }
      }
    }
  }

  // ------------------------------------------------------------------ bubble

  void _gainBubble(Canvas c) {
    if (bubble < 0 || gain <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '+$gain',
        style: TextStyle(
          color: const Color(0xFF1F8A5B).withValues(alpha: (1 - bubble).clamp(0.0, 1.0)),
          fontSize: 22 * _s,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.white, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(_w / 2 - tp.width / 2, _h * 0.42 - bubble * 40 * _s));
  }

  @override
  bool shouldRepaint(covariant AskodoxWorkScenePainter old) =>
      old.seconds != seconds ||
      old.fraction != fraction ||
      old.stageIndex != stageIndex ||
      old.job != job ||
      old.active != active ||
      old.bubble != bubble;
}
