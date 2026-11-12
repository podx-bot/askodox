import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/work_mode_plan.dart';
import 'work_scene_images.dart';

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
    this.te = false,
    this.crew,
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

  /// Telugu text in the scene (customers calling, people waiting ...).
  final bool te;

  /// The people working together (team); null = only you, moved by [active].
  final List<AskodoxWorkCrewMember>? crew;

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
  AskodoxWorkSceneImages? _images;

  @override
  void initState() {
    super.initState();
    AskodoxWorkSceneImages.load().then((loaded) {
      if (mounted && loaded != null) setState(() => _images = loaded);
    });
  }

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
                te: widget.te,
                crew: widget.crew,
                images: _images,
              ),
            ),
          ),
        ),
      );
}

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// One person in a team job: you or a friend / family member, each moved by
/// their own steps (a member who has not walked stands still).
class AskodoxWorkCrewMember {
  const AskodoxWorkCrewMember({required this.name, required this.active, this.wear = 'lungi'});
  final String name;
  final bool active;

  /// 'lungi', 'saree' or 'shirt'.
  final String wear;
}

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

/// What a worker wears: shirt and trousers, a lungi folded up to the knees
/// with a towel on the head (field / digging), or a saree tucked up for work.
enum _Outfit { shirt, lungi, saree }

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
    this.te = false,
    this.crew,
    this.images,
  });

  final AskodoxWorkJob job;
  final int stageIndex;
  final double fraction;
  final double seconds;
  final bool active;
  final double bubble;
  final int gain;
  final bool te;
  final List<AskodoxWorkCrewMember>? crew;

  /// Hand-made pictures; null until loaded (the code-made scene is used then).
  final AskodoxWorkSceneImages? images;

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
    // Everything is drawn in a 250-unit-high space, scaled to the real height.
    final k = size.height / 250;
    canvas.save();
    canvas.scale(k);
    _w = size.width / k;
    _h = 250;
    _s = 1;
    var ownProblems = false;
    if (_useImageScene) {
      _imageScene(canvas, images!);
    } else if (job.id == 'hotel') {
      _hotel(canvas);
      ownProblems = true;
    } else {
      _backdrop(canvas);
      switch (job.id) {
        case 'paper' || 'delivery':
          _paperOrParcels(canvas);
          ownProblems = true;
        case 'milk':
          _milk(canvas);
          ownProblems = true;
        case 'veg_cart':
          _vegCart(canvas);
          ownProblems = true;
        case 'cattle':
          _cattle(canvas);
          ownProblems = true;
        case 'fishing':
          _fishing(canvas);
          ownProblems = true;
        case 'digging':
          _digging(canvas);
        case 'house':
          _house(canvas);
        case 'chicken_shop':
          _shop(canvas);
        case 'welding':
          _welding(canvas);
        default:
          _field(canvas);
      }
    }
    if (!_anyActive && !_lastStageDone && !ownProblems) _waitingBubble(canvas);
    _gainBubble(canvas);
    canvas.restore();
  }

  // ----------------------------------------------------------- hand-made scene

  /// Paddy transplanting uses the hand-made picture while one person works
  /// (team jobs and the other paddy stages keep the code-made scene).
  bool get _useImageScene =>
      images != null &&
      job.id == 'paddy' &&
      _stage == 'transplant' &&
      (crew == null || crew!.length <= 1);

  /// Background (cover-fit) + the farmer. While walking, the six frames play
  /// (3 s loop, 0.5 s per frame); when still, the standing frame is shown.
  /// The farmer moves across the field as the stage progresses.
  void _imageScene(Canvas c, AskodoxWorkSceneImages pics) {
    final bg = pics.paddyBackground;
    final scale = math.max(_w / bg.width, 250 / bg.height);
    final dw = bg.width * scale;
    final dh = bg.height * scale;
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, _w, 250));
    c.drawImageRect(
      bg,
      Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
      Rect.fromLTWH((_w - dw) / 2, (250 - dh) / 2, dw, dh),
      Paint()..filterQuality = FilterQuality.medium,
    );
    c.restore();

    final frames = pics.paddyTransplantFrames;
    final index = active ? math.min(((seconds % 3) / 0.5).floor(), frames.length - 1) : 3;
    final sprite = frames[index];
    const spriteHeight = 200.0;
    final spriteScale = spriteHeight / sprite.height;
    final spriteWidth = sprite.width * spriteScale;
    final x = _w * 0.2 + fraction.clamp(0.0, 1.0) * _w * 0.5 - spriteWidth / 2;
    c.drawImageRect(
      sprite,
      Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()),
      Rect.fromLTWH(x, 228 - spriteHeight, spriteWidth, spriteHeight),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  // ------------------------------------------------------------------- crew

  static const _crewCloth = [null, Color(0xFF6A1B9A), Color(0xFFEF6C00), Color(0xFF00838F)];

  List<AskodoxWorkCrewMember> get _crew =>
      crew == null || crew!.isEmpty ? [AskodoxWorkCrewMember(name: '', active: active)] : crew!;
  bool get _team => _crew.length > 1;
  bool get _anyActive => _crew.any((m) => m.active);

  _Outfit _outfitOf(AskodoxWorkCrewMember m) => switch (m.wear) {
        'saree' => _Outfit.saree,
        'shirt' => _Outfit.shirt,
        _ => _Outfit.lungi,
      };

  /// A rounded label; with [tail] it is a speech bubble pointing down at [at].
  void _label(Canvas c, String text, Offset at,
      {required Color bg, required Color fg, Color? border, bool tail = false, double size = 8.5}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w700, height: 1.1)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: _w - 16);
    final w = tp.width + 12;
    final h = tp.height + 5;
    final double left = math.min(math.max(2.0, at.dx - w / 2), math.max(2.0, _w - w - 2));
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, at.dy - h - (tail ? 4 : 0), w, h), Radius.circular(h / 2));
    final fill = Paint()..color = bg;
    c.drawRRect(box, fill);
    if (tail) {
      c.drawPath(
          Path()
            ..moveTo(at.dx - 3, at.dy - 5)
            ..lineTo(at.dx, at.dy)
            ..lineTo(at.dx + 3, at.dy - 5)
            ..close(),
          fill);
    }
    if (border != null) c.drawRRect(box, _stroke(border, 1.1));
    tp.paint(c, Offset(left + 6, box.top + 2.5));
  }

  void _say(Canvas c, Offset at, String en, String teText, {bool angry = false}) => _label(c, te ? teText : en, at,
      bg: angry ? const Color(0xFFFFEBEE) : Colors.white,
      fg: angry ? const Color(0xFFC62828) : const Color(0xFF263238),
      border: angry ? const Color(0xFFE53935) : const Color(0x40000000),
      tail: true);

  void _nameTag(Canvas c, Offset at, AskodoxWorkCrewMember m) {
    if (!_team) return;
    _label(c, m.active ? m.name : '${m.name} · ${te ? 'ఆగారు' : 'stopped'}', at,
        bg: m.active ? const Color(0xEB1F8A5B) : const Color(0xD95A6064), fg: Colors.white);
  }

  void _backdrop(Canvas c) {
    final evening = _lastStageDone || _stage == 'harvest' || _stage == 'evening';
    final sky = Rect.fromLTWH(0, 0, _w, 136);
    c.drawRect(
        sky,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: evening ? const [Color(0xFFF3B26B), Color(0xFFFDE7C4)] : const [Color(0xFF79BFE6), Color(0xFFFBECCC)],
          ).createShader(sky));
    final sun = Offset(_w * 0.8, evening ? 70 : 46);
    c.drawCircle(
        sun,
        70,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xF2FFF0BE), Color(0x73FFE096), Color(0x00FFE096)], stops: [0, 0.25, 1])
              .createShader(Rect.fromCircle(center: sun, radius: 70)));
    c.drawCircle(sun, 13, Paint()..color = evening ? const Color(0xFFF5A142) : const Color(0xFFFFF3C4));
    // Clouds drift across in 60 s.
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final x = _saw(60, i / 3) * (_w + 120) - 60;
      final y = 22.0 + i * 13;
      for (final (dx, dy, r) in const [(-14.0, 2.0, 9.0), (0.0, -3.0, 12.0), (14.0, 2.0, 9.0), (26.0, 4.0, 6.0)]) {
        c.drawCircle(Offset(x + dx, y + dy), r, cloud);
      }
    }
    // Two layers of hills in the haze.
    c.drawPath(
        Path()
          ..moveTo(0, 112)
          ..cubicTo(_w * 0.15, 88, _w * 0.3, 96, _w * 0.42, 104)
          ..cubicTo(_w * 0.58, 82, _w * 0.75, 90, _w, 104)
          ..lineTo(_w, 130)
          ..lineTo(0, 130)
          ..close(),
        Paint()..color = const Color(0xFFA9C2C4));
    c.drawPath(
        Path()
          ..moveTo(0, 122)
          ..cubicTo(_w * 0.2, 108, _w * 0.38, 118, _w * 0.55, 116)
          ..cubicTo(_w * 0.72, 110, _w * 0.88, 118, _w, 114)
          ..lineTo(_w, 132)
          ..lineTo(0, 132)
          ..close(),
        Paint()..color = const Color(0xFF8FB092));
    // A row of palms and a village at the horizon.
    final rnd = math.Random(9);
    for (var x = 10.0; x < _w; x += 46) {
      _palm(c, Offset(x + rnd.nextDouble() * 20, 126), 0.55 + rnd.nextDouble() * 0.25);
    }
    for (final (fx, w) in const [(0.37, 18.0), (0.44, 14.0), (0.65, 16.0)]) {
      final x = _w * fx;
      c.drawRect(Rect.fromLTWH(x, 117, w, 8), Paint()..color = const Color(0xFFE9DCC6));
      c.drawPath(
          Path()
            ..moveTo(x - 2, 118)
            ..lineTo(x + w / 2, 111)
            ..lineTo(x + w + 2, 118)
            ..close(),
          Paint()..color = const Color(0xFF9C6B4A));
    }
    // Birds.
    final bird = _stroke(const Color(0xFF4A5560), 1);
    for (var i = 0; i < 3; i++) {
      final x = _saw(30, i * 0.2) * _w * 0.5 + 60 + i * 16;
      final y = 40 + i * 4 + _wave(5, i * 0.3) * 3;
      final flap = 3 + _wave(0.5, i * 0.3) * 2;
      c.drawPath(
          Path()
            ..moveTo(x - 5, y)
            ..quadraticBezierTo(x - 2.5, y - flap, x, y)
            ..quadraticBezierTo(x + 2.5, y - flap, x + 5, y),
          bird);
    }
    // Ground with grass tufts that bend when a gust passes.
    final ground = Rect.fromLTWH(0, 130, _w, _h - 130);
    c.drawRect(
        ground,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CC97A), Color(0xFF6E9E4F)],
          ).createShader(ground));
    final tuft = _stroke(const Color(0xFF5E8E43), 1.1);
    final grass = math.Random(3);
    for (var i = 0; i < 40; i++) {
      final x = grass.nextDouble() * _w;
      final y = 134 + grass.nextDouble() * (_h - 134);
      final bend = _gust(x) * 2;
      c.drawLine(Offset(x, y), Offset(x - 1.5 + bend, y - 4), tuft);
      c.drawLine(Offset(x, y), Offset(x + 1.5 + bend, y - 4.5), tuft);
    }
  }

  /// A palm in the distance (one hazy colour), swaying a little.
  void _palm(Canvas c, Offset base, double k, [Color col = const Color(0xFF5F8460)]) {
    final sway = _wave(4, base.dx / 97) * 1.5 * k;
    final trunk = _stroke(col, 2.6 * k);
    final top = base + Offset(4 * k + sway, -52 * k);
    c.drawPath(
        Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(base.dx + 6 * k, base.dy - 26 * k, top.dx, top.dy),
        trunk);
    final leaf = _stroke(col, 2.2 * k);
    for (var i = 0; i < 7; i++) {
      final a = -math.pi + i * math.pi / 6;
      c.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo(top.dx + math.cos(a) * 9 * k, top.dy - 7 * k, top.dx + math.cos(a) * 17 * k + sway,
                top.dy + math.sin(a).abs() * -3 * k + 8 * k),
          leaf);
    }
  }

  // ----------------------------------------------------------------- people

  /// The back hand of the last worker drawn (holds the seedling bundle ...).
  Offset _backHand = Offset.zero;

  /// A rounded, tapered limb from [a] (width [wa]) to [b] (width [wb]).
  void _limb(Canvas c, Offset a, Offset b, double wa, double wb, Color col, {bool outline = true}) {
    if (outline && col.a > 0.9) _limb(c, a, b, wa + 1.4 * _s, wb + 1.4 * _s, const Color(0x8C342218), outline: false);
    final p = Paint()..color = col;
    final d = b - a;
    final len = d.distance;
    if (len > 0.01) {
      final n = Offset(-d.dy / len, d.dx / len);
      c.drawPath(
          Path()
            ..moveTo(a.dx + n.dx * wa / 2, a.dy + n.dy * wa / 2)
            ..lineTo(b.dx + n.dx * wb / 2, b.dy + n.dy * wb / 2)
            ..lineTo(b.dx - n.dx * wb / 2, b.dy - n.dy * wb / 2)
            ..lineTo(a.dx - n.dx * wa / 2, a.dy - n.dy * wa / 2)
            ..close(),
          p);
    }
    c.drawCircle(a, wa / 2, p);
    c.drawCircle(b, wb / 2, p);
  }

  _Outfit get _defaultOutfit =>
      job.scene == AskodoxWorkScene.field || job.id == 'digging' ? _Outfit.lungi : _Outfit.shirt;

  /// Draws a worker standing on [foot], facing right ([flip] = facing left).
  /// Returns the front hand; the back hand is left in [_backHand].
  Offset _person(Canvas c, Offset foot, _Pose p,
      {Color? shirt,
      Color cap = const Color(0xFFE8C87A),
      bool mask = false,
      double k = 1,
      _Outfit? outfit,
      bool? towel,
      bool hat = true,
      bool flip = false,
      Color? cloth}) {
    final wear = outfit ?? _defaultOutfit;
    if (flip) {
      c.save();
      c.translate(foot.dx, 0);
      c.scale(-1, 1);
      c.translate(-foot.dx, 0);
    }
    final hand = _body(c, foot, p,
        shirt: shirt,
        cap: cap,
        mask: mask,
        k: k,
        outfit: wear,
        towel: towel ?? wear == _Outfit.lungi,
        hat: hat,
        cloth: cloth);
    if (!flip) return hand;
    c.restore();
    _backHand = Offset(2 * foot.dx - _backHand.dx, _backHand.dy);
    return Offset(2 * foot.dx - hand.dx, hand.dy);
  }

  Offset _body(Canvas c, Offset foot, _Pose p,
      {required Color? shirt,
      required Color cap,
      required bool mask,
      required double k,
      required _Outfit outfit,
      required bool towel,
      required bool hat,
      required Color? cloth}) {
    final s = _s * k;
    final top = shirt ??
        switch (outfit) {
          _Outfit.shirt => const Color(0xFF2F6FEB),
          _Outfit.lungi => const Color(0xFFF2EEE6),
          _Outfit.saree => const Color(0xFF2E7D32),
        };
    final wrapCol = cloth ?? (outfit == _Outfit.saree ? const Color(0xFFC2185B) : const Color(0xFF3F6E9E));
    // A resting worker still breathes.
    final bob = p.bob + (active ? 0.0 : _wave(4) * 0.5);
    final down = 1 - 0.38 * p.crouch;
    final hip = foot + Offset(0, -31 * s * down + bob * s);
    (Offset, Offset) legAt(double a) {
      final knee = hip + Offset(math.sin(a) * 15 * s + p.crouch * 8 * s, math.cos(a) * 15 * s * down);
      final ankle = knee + Offset(math.sin(a) * 14 * s - p.crouch * 6 * s, 15 * s * down);
      return (knee, ankle);
    }

    final up = Offset(math.sin(p.lean), -math.cos(p.lean));
    final fwd = Offset(math.cos(p.lean), math.sin(p.lean));
    final shoulder = hip + up * (24 * s);
    (Offset, Offset) armAt(double a) {
      final elbow = shoulder + Offset(math.sin(a) * 11 * s, math.cos(a) * 11 * s);
      final hand = elbow + Offset(math.sin(a + 0.35) * 11 * s, math.cos(a + 0.35) * 11 * s);
      return (elbow, hand);
    }

    final trousers = outfit == _Outfit.shirt;
    final sleeves = outfit != _Outfit.lungi;
    c.drawOval(Rect.fromCenter(center: foot + Offset(2 * s, 2 * s), width: 30 * s, height: 6 * s),
        Paint()..color = Colors.black.withValues(alpha: 0.18));

    // Back arm (behind everything).
    final (eB, hB) = armAt(p.armB);
    _limb(c, shoulder, eB, 4.6 * s, 4 * s, _skinBack);
    _limb(c, eB, hB, 4 * s, 3.4 * s, _skinBack);
    if (sleeves) _limb(c, shoulder, Offset.lerp(shoulder, eB, 0.55)!, 6 * s, 5.2 * s, Color.lerp(top, Colors.black, 0.2)!);
    c.drawCircle(hB, 2.4 * s, Paint()..color = _skinBack);
    _backHand = hB;

    void leg(double a, bool front) {
      final (knee, ankle) = legAt(a);
      final col = trousers ? (front ? _pants : _pantsBack) : (front ? _skin : _skinBack);
      _limb(c, hip, knee, 7.5 * s, 6 * s, col);
      _limb(c, knee, ankle, 5.8 * s, 4.2 * s, col);
      c.drawOval(Rect.fromCenter(center: ankle + Offset(2.6 * s, 1.2 * s), width: 8 * s, height: 3.4 * s),
          Paint()..color = trousers ? const Color(0xFF3B2A20) : col);
    }

    leg(p.legB, false);
    leg(p.legF, true);

    if (!trousers) {
      // Lungi / saree tucked up to the knees for field work.
      final (kB, _) = legAt(p.legB);
      final (kF, _) = legAt(p.legF);
      final side = fwd * (6 * s);
      final hemB = kB + Offset(-3 * s, 2 * s);
      final hemF = kF + Offset(3 * s, 2 * s);
      final waistB = hip - side + Offset(0, -3 * s);
      final waistF = hip + side + Offset(0, -3 * s);
      final wrap = Path()
        ..moveTo(waistB.dx, waistB.dy)
        ..lineTo(waistF.dx, waistF.dy)
        ..quadraticBezierTo(math.max(hemF.dx, hemB.dx) + 3 * s, (waistF.dy + hemF.dy) / 2, hemF.dx + 2 * s, hemF.dy)
        ..lineTo(hemB.dx - 2 * s, hemB.dy)
        ..quadraticBezierTo(math.min(hemF.dx, hemB.dx) - 3 * s, (waistB.dy + hemB.dy) / 2, waistB.dx, waistB.dy)
        ..close();
      c.drawPath(wrap, Paint()..color = wrapCol);
      final fold = _stroke(Colors.black.withValues(alpha: 0.16), 0.8 * s);
      c.drawLine(Offset.lerp(waistB, hemB, 0.5)!, Offset.lerp(waistF, hemF, 0.5)!, fold);
      c.drawLine(hip, Offset.lerp(hemB, hemF, 0.5)!, fold);
      c.drawLine(waistB, waistF, _stroke(Color.lerp(wrapCol, Colors.black, 0.25)!, 1.6 * s));
    }

    // Body with a soft highlight on the sunny side.
    _limb(c, hip, shoulder, 12 * s, 13.5 * s, top);
    _limb(c, hip + fwd * (2.6 * s), shoulder + fwd * (3 * s), 3.6 * s, 4.2 * s, Colors.white.withValues(alpha: 0.2));
    _limb(c, hip - fwd * (3.4 * s), shoulder - fwd * (3.8 * s), 3 * s, 3.4 * s, Colors.black.withValues(alpha: 0.12));
    if (outfit == _Outfit.saree) {
      // Pallu across the body from the back shoulder to the front of the waist.
      final a = shoulder - fwd * (6.5 * s);
      final b = shoulder - fwd * (0.5 * s);
      final cc = hip + fwd * (6 * s);
      final d = hip + fwd * (0.5 * s);
      c.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(cc.dx, cc.dy)
            ..lineTo(d.dx, d.dy)
            ..close(),
          Paint()..color = wrapCol);
      c.drawLine(b, cc, _stroke(const Color(0xFFFFC107), 1 * s));
    }

    // Neck and head.
    final head = shoulder + up * (9 * s) + fwd * (1 * s);
    _limb(c, shoulder, shoulder + up * (4 * s), 4.4 * s, 4.4 * s, _skinBack);
    const hair = Color(0xFF1E1A17);
    c.drawCircle(head - fwd * (1.2 * s) + up * (1 * s), 6.9 * s, Paint()..color = hair);
    c.drawCircle(head + fwd * (1.1 * s) - up * (0.6 * s), 6.3 * s, Paint()..color = _skin);
    c.drawCircle(head + fwd * (6.6 * s) - up * (0.6 * s), 1.4 * s, Paint()..color = _skin); // nose
    c.drawCircle(head - fwd * (0.6 * s), 1.6 * s, Paint()..color = _skinBack); // ear
    if (mask) {
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: head + fwd * (3 * s), width: 10 * s, height: 13 * s),
              Radius.circular(2 * s)),
          Paint()..color = const Color(0xFF263238));
      c.drawRect(Rect.fromCenter(center: head + fwd * (5 * s) + up * (1 * s), width: 5 * s, height: 2.4 * s),
          Paint()..color = const Color(0xFF7CB342));
    } else {
      c.drawCircle(head + fwd * (4 * s) + up * (1 * s), 0.95 * s, Paint()..color = hair); // eye
      if (outfit != _Outfit.saree) {
        c.drawLine(head + fwd * (3.6 * s) - up * (2.4 * s), head + fwd * (6.2 * s) - up * (2.2 * s),
            _stroke(hair, 1.2 * s)); // moustache
      }
    }
    if (outfit == _Outfit.saree) {
      // Hair bun with jasmine.
      final bun = head - fwd * (6.2 * s) + up * (0.5 * s);
      c.drawCircle(bun, 3.3 * s, Paint()..color = hair);
      for (final dy in [-2.4, 0.0, 2.4]) {
        c.drawCircle(bun - fwd * (2.6 * s) + up * (dy * s), 1 * s, Paint()..color = Colors.white);
      }
    } else if (towel) {
      // Towel tied round the head (talapaga), its end hanging at the back.
      const towelCol = Color(0xFFF7F3EA);
      _limb(c, head - fwd * (6.8 * s) + up * (3.2 * s), head + fwd * (5.8 * s) + up * (3.8 * s), 5.4 * s, 4.6 * s, towelCol);
      c.drawLine(head - fwd * (6 * s) + up * (3 * s), head + fwd * (5.2 * s) + up * (3.6 * s),
          _stroke(const Color(0xFFD84343).withValues(alpha: 0.7), 0.8 * s));
      final sway = _wave(3) * 0.8 * s;
      _limb(c, head - fwd * (7 * s) + up * (3 * s), head - fwd * (10.5 * s) - up * (1.5 * s) + Offset(sway, 0), 3 * s,
          2 * s, towelCol);
    } else if (hat && !mask) {
      c.drawPath(
          Path()
            ..moveTo(head.dx - 7.5 * s, head.dy - 1 * s)
            ..quadraticBezierTo(head.dx, head.dy - 14 * s, head.dx + 8 * s, head.dy - 1 * s)
            ..lineTo(head.dx + 10.5 * s, head.dy - 0.5 * s)
            ..close(),
          Paint()..color = cap);
    }

    // Front arm.
    final (eF, hF) = armAt(p.armF);
    _limb(c, shoulder, eF, 4.8 * s, 4.2 * s, _skin);
    _limb(c, eF, hF, 4.2 * s, 3.6 * s, _skin);
    if (sleeves) _limb(c, shoulder, Offset.lerp(shoulder, eF, 0.55)!, 6.2 * s, 5.4 * s, top);
    c.drawCircle(hF, 2.5 * s, Paint()..color = _skin);
    return hF;
  }

  double _ease(double t) => t * t * (3 - 2 * t);

  /// Work rhythm 0 (raised / ready) .. 1 (impact): a slow lift, a quick
  /// strike and a short hold -- like a real tool, not a pendulum.
  double _strike(double period, [double shift = 0]) {
    final p = _saw(period, shift);
    if (p < 0.5) return 1 - _ease(p / 0.5);
    if (p < 0.72) {
      final q = (p - 0.5) / 0.22;
      return q * q;
    }
    return 1.0;
  }

  /// 0..1 during the moments after an impact of [_strike] (dust, splash,
  /// ripple, falling bunch); -1 the rest of the time.
  double _afterImpact(double period, [double shift = 0]) {
    final p = _saw(period, shift);
    if (p >= 0.72) return (p - 0.72) / 0.48;
    if (p < 0.2) return (p + 0.28) / 0.48;
    return -1;
  }

  /// A gust of wind that sweeps across the picture every 10 s (0..1 at x).
  double _gust(double x) {
    final d = (x / _w - (_saw(10) * 1.6 - 0.3)) * 5;
    return math.exp(-d * d);
  }

  _Pose _walk([double speed = 0.75, bool? on]) {
    if (!(on ?? active)) return const _Pose();
    final a = _wave(speed);
    return _Pose(lean: 0.1, legF: a * 0.45, legB: -a * 0.45, armF: -a * 0.5, armB: a * 0.5, bob: _wave(speed / 2).abs() * -1.5);
  }

  /// Bent over, the front hand going down into the soil / mud and back.
  _Pose _bend([double period = 1.0, double shift = 0, bool? on]) {
    if (!(on ?? active)) return const _Pose(lean: 0.35, crouch: 0.2, armF: 0.2, armB: 0.1);
    final t = _strike(period, shift); // 1 = hand in the mud
    return _Pose(lean: 0.95 + t * 0.12, crouch: 0.42 + t * 0.06, armF: 0.05 + t * 0.6, armB: 0.45, legF: 0.15, legB: -0.1, bob: t);
  }

  _Pose _swing([double period = 1.0]) {
    if (!active) return const _Pose(lean: 0.15, armF: 0.4, armB: 0.3);
    final t = _strike(period); // 0 = raised, 1 = struck
    return _Pose(
        lean: 0.25 + t * 0.4, crouch: 0.15 + t * 0.12, armF: -2.3 + t * 2.8, armB: -2.1 + t * 2.6, legF: 0.28, legB: -0.22);
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
    final box = plot.getBounds();
    if (paddy && stageIndex > plough) {
      // Flooded paddy: the sky reflected in the water, small ripples drifting with the breeze.
      c.save();
      c.clipPath(plot);
      c.drawRect(
          box,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFCDEBF8).withValues(alpha: 0.6),
                const Color(0xFF7FB8D6).withValues(alpha: 0.38),
              ],
            ).createShader(box));
      final rnd = math.Random(11);
      for (var i = 0; i < 28; i++) {
        final x = box.left + ((rnd.nextDouble() + _saw(20)) % 1) * box.width;
        final y = box.top + rnd.nextDouble() * box.height;
        final len = (4 + rnd.nextDouble() * 7) * _s;
        c.drawLine(Offset(x, y), Offset(x + len, y),
            _stroke(Colors.white.withValues(alpha: 0.3 + 0.25 * _wave(3, i / 28)), 0.9 * _s));
      }
      c.restore();
    } else if (tilledAll) {
      // Turned soil: clods.
      c.save();
      c.clipPath(plot);
      final rnd = math.Random(5);
      for (var i = 0; i < 46; i++) {
        final x = box.left + rnd.nextDouble() * box.width;
        final y = box.top + rnd.nextDouble() * box.height;
        c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4 * _s, height: 2 * _s),
            Paint()..color = (i.isEven ? const Color(0xFF6E5034) : const Color(0xFFA0805A)).withValues(alpha: 0.8));
      }
      c.restore();
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

    _flyers(c);

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
        // Each worker (you alone, or your team side by side along the row) holds
        // a bundle of seedlings and pushes them into the mud; a ripple spreads
        // where each one goes in and the planter is mirrored in the water.
        final dir = row.isEven ? 1.0 : -1.0;
        final gap = (_rowRight(row) - _rowLeft(row)) / _slots;
        final k = 0.82 + 0.07 * row;
        _egret(c, Offset(_rowLeft(1) + (_rowRight(1) - _rowLeft(1)) * (spot.dx < _w / 2 ? 0.8 : 0.2), _rowY(1)), 0.62, 0.55, dir > 0);
        final members = _crew;
        for (var j = members.length - 1; j >= 0; j--) {
          final m = members[j];
          final x = (spot.dx - dir * j * 2.2 * gap).clamp(_rowLeft(row) + 6, _rowRight(row) - 6);
          final shift = j * 0.33;
          final foot = Offset(x - dir * 10, spot.dy + 6);
          final pose = _bend(1.0, shift, m.active);
          void draw() => _person(c, foot, pose, k: k, flip: dir < 0, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
          if (paddy) {
            // Reflection in the flooded field.
            c.save();
            c.clipRect(Rect.fromLTWH(0, foot.dy, _w, _h - foot.dy));
            c.saveLayer(null, Paint()..color = const Color(0x38000000));
            c.translate(0, 2 * foot.dy);
            c.scale(1, -1);
            draw();
            c.restore();
            c.restore();
          }
          final hand = _person(c, foot, pose, k: k, flip: dir < 0, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
          _seedlingTuft(c, _backHand, 0.9 * k);
          c.drawLine(hand, hand + Offset(dir * 1.5, -6), _stroke(const Color(0xFF5DBB4C), 1.6));
          final after = _afterImpact(1.0, shift);
          if (m.active && after >= 0) {
            final r = (2 + after * 12) * k;
            c.drawOval(Rect.fromCenter(center: Offset(hand.dx, spot.dy + 1), width: r * 2, height: r * 0.7),
                _stroke(Colors.white.withValues(alpha: 0.75 * (1 - after)), 1.0));
          }
          _nameTag(c, foot + Offset(0, -62 * k), m);
        }
        // Seedling bundles waiting on the bund get fewer as the planting goes.
        final bundles = ((1 - fraction) * 6).ceil();
        for (var b = 0; b < bundles; b++) {
          _seedlingTuft(c, Offset(_rowLeft(0) + b * 14, _rowY(0) - 12), 1.3);
        }
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
        // Bent low: one hand gathers a bunch, the sickle cuts it at the base and
        // the cut bunch falls and is laid down. A team works side by side.
        final dir = row.isEven ? 1.0 : -1.0;
        final gap = (_rowRight(row) - _rowLeft(row)) / _slots;
        final k = 0.82 + 0.07 * row;
        final members = _crew;
        for (var j = members.length - 1; j >= 0; j--) {
          final m = members[j];
          final shift = j * 0.4;
          final at = Offset((spot.dx - dir * j * 2.2 * gap).clamp(_rowLeft(row) + 6, _rowRight(row) - 6), spot.dy);
          final t = m.active ? _strike(1.2, shift) : 0.0;
          final pose = m.active
              ? _Pose(lean: 1.0, crouch: 0.45, armB: 0.55 + t * 0.15, armF: -0.2 + t * 1.3, legF: 0.15, legB: -0.1, bob: t)
              : const _Pose(lean: 0.4, crouch: 0.2, armF: 0.3, armB: 0.2);
          final foot = at + Offset(-dir * 12, 6);
          final hand = _person(c, foot, pose, k: k, flip: dir < 0, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
          _sickle(c, hand, dir, k);
          final after = _afterImpact(1.2, shift);
          if (m.active && after >= 0) {
            c.save();
            c.translate(at.dx, at.dy);
            c.rotate(dir * _ease(after) * 1.4);
            for (final dx in [-1.5, 0.0, 1.5]) {
              c.drawLine(Offset(dx, 0), Offset(dx * 1.8, -18 * k), _stroke(const Color(0xFFC9962E), 1.5));
            }
            c.drawOval(Rect.fromCenter(center: Offset(0, -18 * k), width: 4, height: 6), Paint()..color = const Color(0xFFE6B84F));
            c.restore();
            // Chaff in the air.
            for (var i = 0; i < 5; i++) {
              final a = i * 1.3;
              c.drawCircle(at + Offset(math.cos(a) * after * 16, -10 - after * 12 + math.sin(a) * 4), 0.9,
                  Paint()..color = const Color(0xFFE8C468).withValues(alpha: 1 - after));
            }
          }
          _nameTag(c, foot + Offset(0, -58 * k), m);
        }
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
    // A light breeze always, a stronger bend when a gust passes.
    final sway = (0.6 * _wave(3, at.dx / 300) + 2.4 * _gust(at.dx)) * growth * _s;
    final golden = ripe && job.id == 'paddy';
    final stem = golden ? const Color(0xFFC9962E) : const Color(0xFF2F7A32);
    final tip = golden ? const Color(0xFFE8C468) : const Color(0xFF6CC24A);
    for (var b = -2; b <= 2; b++) {
      final base = at + Offset(b * 1.0 * _s * scale, 0);
      final end = at + Offset(b * 2.6 * _s * scale + sway * (1 + b.abs() * 0.2), -hgt * (1 - b.abs() * 0.12));
      final ctrl = Offset((base.dx + end.dx) / 2 + b * 0.8 * _s, base.dy - hgt * 0.6);
      c.drawPath(
          Path()
            ..moveTo(base.dx, base.dy)
            ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy),
          _stroke(b.isEven ? stem : Color.lerp(stem, tip, 0.6)!, 1.4 * _s));
    }
    if (golden) {
      // Heavy grain heads droop with their weight.
      for (final d in [-1.0, 1.0]) {
        final top = at + Offset(d * 2.6 * _s * scale + sway, -hgt);
        final hang = top + Offset(d * 4 * _s + sway * 0.5, 4 * _s);
        c.drawPath(
            Path()
              ..moveTo(top.dx, top.dy)
              ..quadraticBezierTo(top.dx + d * 3 * _s, top.dy - 2 * _s, hang.dx, hang.dy),
            _stroke(const Color(0xFFE6B84F), 2.2 * _s));
      }
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

  /// A bundle of seedlings with mud on the roots, tied in the middle.
  void _seedlingTuft(Canvas c, Offset at, double k) {
    final s = _s * k;
    for (var b = -2; b <= 2; b++) {
      c.drawLine(at, at + Offset(b * 1.6 * s + _wave(3) * 0.4 * s, -7 * s + b.abs() * 1.2 * s),
          _stroke(const Color(0xFF5DBB4C), 1.2 * s));
    }
    c.drawLine(at, at + Offset(0, 3 * s), _stroke(const Color(0xFF6E5034), 1.8 * s));
    c.drawLine(at + Offset(-1.6 * s, -1 * s), at + Offset(1.6 * s, -1 * s), _stroke(const Color(0xFFB08850), 1.2 * s));
  }

  /// A sickle in the hand, the blade curving forward.
  void _sickle(Canvas c, Offset hand, double dir, double k) {
    final s = _s * k;
    c.drawLine(hand, hand + Offset(dir * 3 * s, 1 * s), _stroke(const Color(0xFF6D4C2F), 2.4 * s));
    final ctr = hand + Offset(dir * 7.5 * s, -1 * s);
    c.drawArc(Rect.fromCircle(center: ctr, radius: 5 * s), dir > 0 ? -math.pi / 2 : math.pi / 2, math.pi, false,
        _stroke(const Color(0xFF9AA0A6), 1.8 * s));
    c.drawArc(Rect.fromCircle(center: ctr, radius: 4 * s), dir > 0 ? -math.pi / 3 : math.pi * 2 / 3, math.pi / 2, false,
        _stroke(Colors.white.withValues(alpha: 0.7), 0.7 * s));
  }

  /// Dragonflies over the paddy water, butterflies over the other crops.
  void _flyers(Canvas c) {
    for (var i = 0; i < 2; i++) {
      final x = _w * (0.4 + 0.28 * math.sin(2 * math.pi * (seconds / 12 + i * 0.4)));
      final y = _h * (0.55 + 0.05 * math.sin(2 * math.pi * (seconds / 6 + i * 0.3)));
      final flap = _wave(0.1, i * 0.5);
      if (job.id == 'paddy') {
        c.drawLine(Offset(x - 5 * _s, y), Offset(x + 4 * _s, y), _stroke(const Color(0xFF1565C0), 1.3 * _s));
        final wing = Paint()..color = Colors.white.withValues(alpha: 0.6);
        c.drawOval(Rect.fromCenter(center: Offset(x + 1 * _s, y - 2 * _s - flap * _s), width: 7 * _s, height: 2.2 * _s), wing);
        c.drawOval(Rect.fromCenter(center: Offset(x + 1 * _s, y + 2 * _s + flap * _s), width: 7 * _s, height: 2.2 * _s), wing);
      } else {
        final col = i == 0 ? const Color(0xFFFFB300) : const Color(0xFFE91E63);
        final wy = 3.4 * _s * (0.3 + 0.7 * flap.abs());
        c.drawOval(Rect.fromCenter(center: Offset(x - 2 * _s, y - wy / 2), width: 4 * _s, height: wy), Paint()..color = col);
        c.drawOval(Rect.fromCenter(center: Offset(x + 2 * _s, y - wy / 2), width: 4 * _s, height: wy), Paint()..color = col);
        c.drawLine(Offset(x, y - 2 * _s), Offset(x, y + 1 * _s), _stroke(const Color(0xFF3E2723), 0.9 * _s));
      }
    }
  }

  void _ploughTeam(Canvas c, {required bool withOxen}) {
    final pos = fraction * _rows;
    final row = _ci(pos.floor(), 0, _rows - 1);
    final along = (pos - row).clamp(0.0, 1.0);
    final x = _rowLeft(row) + (_rowRight(row) - _rowLeft(row)) * along;
    final y = _rowY(row) + 4 * _s;
    if (withOxen) {
      _ox(c, Offset(x + 40 * _s, y - 2 * _s), 0.05);
      _ox(c, Offset(x + 46 * _s, y + 4 * _s));
      // Yoke and plough.
      c.drawLine(Offset(x + 20 * _s, y - 14 * _s), Offset(x + 4 * _s, y - 2 * _s), _stroke(const Color(0xFF7A5232), 2.4 * _s));
      c.drawLine(Offset(x + 4 * _s, y - 2 * _s), Offset(x + 8 * _s, y + 3 * _s), _stroke(const Color(0xFF555555), 2.4 * _s));
    }
    // A fresh dark furrow behind the blade, soil thrown aside.
    c.drawLine(Offset(math.max(_rowLeft(row), x - 30 * _s), y + 1 * _s), Offset(x + 4 * _s, y + 1 * _s),
        _stroke(const Color(0xFF4A3220), 2.6 * _s));
    if (active) {
      for (var i = 0; i < 6; i++) {
        final t = _saw(0.75, i / 6);
        c.drawCircle(Offset(x + 2 * _s - t * 12 * _s, y - math.sin(math.pi * t) * 9 * _s), (1.2 + 0.8 * (i % 2)) * _s,
            Paint()..color = const Color(0xFF6B4A2B).withValues(alpha: 1 - t));
      }
    }
    // Egrets follow the plough for the insects it turns up.
    _egret(c, Offset(math.max(4, x - 60), y + 2), 0.7, 0.2, false);
    _egret(c, Offset(math.max(4, x - 92), y - 5), 0.6, 0.7, false);
    final hand = _person(c, Offset(x - 10 * _s, y + 2 * _s), _walk(0.75));
    c.drawLine(hand, Offset(x + 4 * _s, y - 4 * _s), _stroke(const Color(0xFF7A5232), 2 * _s));
  }

  /// A white Ongole-style bullock: hump, dewlap, lowered nodding head, tail swish.
  void _ox(Canvas c, Offset foot, [double shift = 0]) {
    final s = _s;
    final ph = active ? _wave(0.75, shift) : 0.0;
    final nod = active ? _wave(0.375, shift) * 1.2 * s : 0.0;
    const white = Color(0xFFF1ECE2);
    const shade = Color(0xFFD3CABB);
    const dark = Color(0xFF5D4E40);
    final body = foot + Offset(0, -23 * s);
    for (final (dx, sign) in const [(-14.0, 1.0), (-8.0, -1.0), (10.0, -1.0), (16.0, 1.0)]) {
      final top = foot + Offset(dx * s, -18 * s);
      final knee = top + Offset(ph * sign * 2 * s, 9 * s);
      final hoof = foot + Offset(dx * s + ph * sign * 4 * s, 0);
      final col = sign > 0 ? shade : white;
      _limb(c, top, knee, 4.6 * s, 3.6 * s, col);
      _limb(c, knee, hoof, 3.6 * s, 3 * s, col);
      c.drawCircle(hoof + Offset(0, 0.5 * s), 1.8 * s, Paint()..color = dark);
    }
    final trunk = Rect.fromCenter(center: body, width: 44 * s, height: 18 * s);
    c.drawOval(
        trunk,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [white, shade])
              .createShader(trunk));
    c.drawOval(Rect.fromCenter(center: body + Offset(10 * s, -9 * s), width: 13 * s, height: 10 * s), Paint()..color = white);
    final head = body + Offset(25 * s, -1 * s + nod);
    c.drawPath(
        Path()
          ..moveTo(body.dx + 13 * s, body.dy - 8 * s)
          ..lineTo(head.dx - 2 * s, head.dy - 4 * s)
          ..lineTo(head.dx, head.dy + 3 * s)
          ..quadraticBezierTo(body.dx + 20 * s, body.dy + 11 * s, body.dx + 13 * s, body.dy + 6 * s)
          ..close(),
        Paint()..color = white);
    c.drawOval(Rect.fromCenter(center: head + Offset(3 * s, 1 * s), width: 12 * s, height: 8 * s), Paint()..color = white);
    c.drawOval(Rect.fromCenter(center: head + Offset(8 * s, 2.6 * s), width: 4.6 * s, height: 4 * s), Paint()..color = dark);
    c.drawCircle(head + Offset(3 * s, -0.6 * s), 0.9 * s, Paint()..color = dark);
    c.drawOval(Rect.fromCenter(center: head + Offset(-2.5 * s, -1 * s), width: 5 * s, height: 2.4 * s), Paint()..color = shade);
    final horn = _stroke(dark, 2.2 * s);
    for (final dx in [-0.5, 1.8]) {
      c.drawPath(
          Path()
            ..moveTo(head.dx + dx * s, head.dy - 3 * s)
            ..quadraticBezierTo(head.dx - 2 * s + dx * s, head.dy - 10 * s, head.dx - 6 * s + dx * s, head.dy - 9 * s),
          horn);
    }
    final swish = _wave(2, shift) * 4 * s;
    final tailEnd = body + Offset(-25 * s + swish, 14 * s);
    c.drawPath(
        Path()
          ..moveTo(body.dx - 21 * s, body.dy - 4 * s)
          ..quadraticBezierTo(body.dx - 27 * s, body.dy + 4 * s, tailEnd.dx, tailEnd.dy),
        _stroke(shade, 1.6 * s));
    c.drawOval(Rect.fromCenter(center: tailEnd, width: 3 * s, height: 5 * s), Paint()..color = dark);
  }

  // ----------------------------------------------------------------- street

  static const _edge = Color(0x8C342218);
  static const _sareeColors = [Color(0xFF5E35B1), Color(0xFF00897B), Color(0xFFD81B60), Color(0xFF3949AB), Color(0xFFEF6C00)];
  static const _idlePose = _Pose(lean: 0.3, crouch: 0.15, armF: 0.3, armB: 0.15);

  List<double> get _doors => [for (var i = 0; i < 5; i++) _w * (0.13 + 0.17 * i)];

  void _dot(Canvas c, Offset at, double r, Color col) => c.drawCircle(at, r, Paint()..color = col);

  void _text(Canvas c, String s, Offset center, Color col, double size) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// A lane of village houses (with rangoli at the doors) and the road in front.
  void _street(Canvas c) {
    c.drawRect(Rect.fromLTWH(0, 130, _w, 70), Paint()..color = const Color(0xFFD8C7A4));
    const walls = [Color(0xFFF2D7B6), Color(0xFFCFE0F2), Color(0xFFE9C3C3), Color(0xFFD9ECC7), Color(0xFFF5E2A0)];
    const rangoli = [Color(0xFFE91E63), Color(0xFF3F51B5), Color(0xFFFF9800), Color(0xFF009688), Color(0xFF9C27B0)];
    final edge = _stroke(_edge, 0.9);
    final doors = _doors;
    for (var i = 0; i < doors.length; i++) {
      final x = doors[i];
      final body = Rect.fromLTWH(x - 26, 140, 52, 56);
      c.drawRect(body, Paint()..color = walls[i]);
      c.drawRect(body, edge);
      final roof = Path()
        ..moveTo(x - 30, 142)
        ..lineTo(x, 122)
        ..lineTo(x + 30, 142)
        ..close();
      c.drawPath(roof, Paint()..color = const Color(0xFFB5523B));
      c.drawPath(roof, edge);
      c.drawRect(Rect.fromLTWH(x - 7, 168, 14, 28), Paint()..color = const Color(0xFF7A5232));
      final win = Rect.fromLTWH(x + 10, 152, 10, 10);
      c.drawRect(win, Paint()..color = const Color(0xFFFFF3C4));
      c.drawRect(win, edge);
      c.drawOval(Rect.fromCenter(center: Offset(x, 202), width: 14, height: 4.8), _stroke(rangoli[i], 1));
    }
    c.drawRect(Rect.fromLTWH(0, 206, _w, _h - 206), Paint()..color = const Color(0xFF9AA0A6));
    c.drawRect(Rect.fromLTWH(0, 204, _w, 3), Paint()..color = const Color(0xFF7E858C));
    for (var x = 0.0; x < _w; x += 40) {
      c.drawLine(Offset(x, 232), Offset(x + 18, 232), _stroke(Colors.white.withValues(alpha: 0.7), 2));
    }
  }

  /// A bicycle with its rider pedalling; [cargo] draws on the carrier
  /// (given the back wheel and the handlebar).
  void _cycle(Canvas c, Offset ground, double k, bool moving, {void Function(Offset back, Offset bar)? cargo}) {
    final rot = moving ? seconds * 2 * math.pi / 0.6 : 0.0;
    c.save();
    c.translate(ground.dx, ground.dy);
    c.scale(k);
    const r = 9.0;
    const back = Offset(-13, -r);
    const front = Offset(13, -r);
    for (final ctr in [back, front]) {
      c.drawCircle(ctr, r, _stroke(const Color(0xFF2D3E50), 2));
      for (var j = 0; j < 4; j++) {
        final a = rot + j * math.pi / 4;
        final d = Offset(math.cos(a) * r, math.sin(a) * r);
        c.drawLine(ctr + d, ctr - d, _stroke(const Color(0xFF8A929A), 0.6));
      }
    }
    const seat = Offset(-4, -24);
    const bar = Offset(10, -27);
    const crank = Offset(0, -r);
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
        _stroke(const Color(0xFF1F4E79), 2.2));
    cargo?.call(back, bar);
    // Rider: hips on the seat, feet on the turning pedals.
    final hip = seat + const Offset(0, -3);
    for (final (shift, col) in [(math.pi, _skinBack), (0.0, _skin)]) {
      final pedal = crank + Offset(math.cos(rot + shift) * 5, math.sin(rot + shift) * 5);
      final knee = Offset((hip.dx + pedal.dx) / 2 + 6, math.min(hip.dy, pedal.dy) - 2);
      _limb(c, hip, knee, 5, 4.6, col);
      _limb(c, knee, pedal, 4.4, 3.6, col);
    }
    c.drawOval(Rect.fromCenter(center: hip + const Offset(2, 1), width: 14, height: 8), Paint()..color = const Color(0xFF3F6E9E));
    final shoulder = hip + const Offset(9, -20);
    _limb(c, hip, shoulder, 11, 12, const Color(0xFFF2EEE6));
    _limb(c, shoulder, bar + const Offset(2, -2), 4, 3.6, _skin);
    final head = shoulder + const Offset(4, -8);
    _dot(c, head + const Offset(-1, 1), 6.8, const Color(0xFF1E1A17));
    _dot(c, head + const Offset(1, 0), 6.2, _skin);
    _dot(c, head + const Offset(4, -1), 0.9, const Color(0xFF1E1A17));
    _limb(c, head + const Offset(-7, -3), head + const Offset(6, -4), 4.6, 4.2, const Color(0xFFF7F3EA));
    c.restore();
  }

  /// Paper boy / delivery: ride the lane, the paper flies to each door (a
  /// parcel is handed over); doors not reached yet wait and complain.
  void _paperOrParcels(Canvas c) {
    _street(c);
    final parcels = job.id == 'delivery';
    final doors = _doors;
    final members = _crew;
    final working = _anyActive;
    double lapX(int j) => -30 + (_w + 60) * _saw(15, j * 0.33);
    final served = <int>{};
    for (var j = 0; j < members.length; j++) {
      if (!members[j].active) continue;
      for (var i = 0; i < doors.length; i++) {
        if (lapX(j) > doors[i]) served.add(i);
      }
    }
    if (!working) {
      for (var i = 0; i < (fraction * doors.length).floor(); i++) {
        served.add(i);
      }
    }
    // Bundles / parcels pile up at the agent's shop until someone takes them.
    for (var i = 0; i < (working ? 2 : 6); i++) {
      final r = Rect.fromLTWH(4.0 + (i % 3) * 12, 190.0 - (i ~/ 3) * 6, 11, 5.5);
      c.drawRect(r, Paint()..color = parcels ? const Color(0xFFC49A6C) : const Color(0xFFEFE7D6));
      c.drawRect(r, _stroke(const Color(0xFFB0A58F), 0.6));
    }
    for (var i = 0; i < doors.length; i++) {
      final at = Offset(doors[i] + 14, 198);
      final wear = i.isOdd ? _Outfit.saree : _Outfit.shirt;
      if (served.contains(i)) {
        final hand = _person(c, at, const _Pose(lean: 0.05, armF: 1.4, armB: 1.3),
            k: 0.9, outfit: wear, shirt: const Color(0xFF607D8B), cloth: _sareeColors[i], hat: false);
        if (parcels) {
          c.drawRect(Rect.fromCenter(center: hand + const Offset(3, -3), width: 10, height: 8), Paint()..color = const Color(0xFFC49A6C));
        } else {
          final page = Rect.fromLTWH(hand.dx - 1, hand.dy - 9, 12, 11);
          c.drawRect(page, Paint()..color = const Color(0xFFF5F0E6));
          c.drawRect(page, _stroke(const Color(0xFF9E9E9E), 0.6));
        }
      } else if (!working || i.isEven) {
        _person(c, at, _Pose(armF: 0.2, armB: 0.1, bob: _wave(3, i * 0.2)),
            k: 0.9, outfit: wear, shirt: const Color(0xFF607D8B), cloth: _sareeColors[i], hat: false, flip: true);
        if (!working && (seconds ~/ 2 + i) % 3 == 0) {
          if (parcels) {
            _say(c, at + const Offset(0, -58), 'Where is my parcel?', 'నా పార్సిల్ ఇంకా రాలేదు!', angry: true);
          } else {
            _say(c, at + const Offset(0, -58), i.isOdd ? 'No paper yet!' : 'Where is the paper?',
                i.isOdd ? 'పేపర్ ఇంకా రాలేదు!' : 'పేపర్ ఏది బాబూ?',
                angry: true);
          }
        }
      }
    }
    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final x = m.active ? lapX(j) : 30.0 + j * 48;
      final y = 228.0 + j * 6;
      _cycle(c, Offset(x, y), 1.15, m.active, cargo: (back, bar) {
        c.drawRect(Rect.fromLTWH(back.dx - 8, back.dy - 15, 14, 8), Paint()..color = const Color(0xFFB08850));
        c.drawRect(Rect.fromLTWH(back.dx - 7, back.dy - 18, 12, 4),
            Paint()..color = parcels ? const Color(0xFFC49A6C) : const Color(0xFFF5F0E6));
      });
      if (m.active && !parcels) {
        for (final d in doors) {
          final f = (x - (d - 46)) / 40;
          if (f <= 0 || f >= 1) continue;
          final p = Offset.lerp(Offset(x + 10, y - 40), Offset(d + 2, 196), f)! + Offset(0, -math.sin(math.pi * f) * 26);
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(f * 7);
          c.drawRect(Rect.fromCenter(center: Offset.zero, width: 10, height: 4), Paint()..color = const Color(0xFFF5F0E6));
          c.restore();
        }
      }
      _nameTag(c, Offset(x, y - 60), m);
    }
    if (!working) {
      _say(c, const Offset(30, 186), parcels ? 'Parcels have arrived!' : 'The bundles are here!',
          parcels ? 'పార్సిళ్లు వచ్చేశాయి!' : 'బండిల్స్ వచ్చేశాయి!');
    }
  }

  /// Milkman: ride to a door, stop and pour into the vessel held out, ride on.
  void _milk(Canvas c) {
    _street(c);
    final doors = _doors;
    final members = _crew;
    void cans(Offset back, Offset bar) {
      for (final dx in const [-7.0, 3.0]) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(back.dx + dx - 4, back.dy - 18, 8, 14), const Radius.circular(2));
        c.drawRRect(r, Paint()..color = const Color(0xFFCFD8DC));
        c.drawRRect(r, _stroke(const Color(0xFF78909C), 0.7));
      }
    }

    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final q = _saw(20, j * 0.4) * doors.length;
      final i = math.min(q.floor(), doors.length - 1);
      final f = q - i;
      final from = i == 0 ? -30.0 : doors[i - 1] - 22;
      final to = doors[i] - 22;
      final riding = m.active && f < 0.4;
      final pouring = m.active && f >= 0.4;
      final x = m.active ? (riding ? from + (to - from) * _ease(f / 0.4) : to) : 24.0 + j * 48;
      final y = 230.0 + j * 5;
      if (pouring) {
        _cycle(c, Offset(x - 10, y), 1.1, false, cargo: cans);
        final hand = _person(c, Offset(x + 10, y - 6), const _Pose(lean: 0.3, armF: 1.3, armB: 0.8),
            k: 1.1, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
        c.drawRect(Rect.fromLTWH(hand.dx - 2, hand.dy - 3, 7, 6), Paint()..color = const Color(0xFFCFD8DC));
        c.drawPath(
            Path()
              ..moveTo(hand.dx + 5, hand.dy)
              ..quadraticBezierTo(hand.dx + 9, hand.dy + 6, hand.dx + 10, hand.dy + 16),
            _stroke(Colors.white.withValues(alpha: 0.95), 1.8));
        final vessel = _person(c, Offset(doors[i] + 4, 198), const _Pose(lean: -0.05, armF: 1.1, armB: 1),
            k: 0.9, outfit: _Outfit.saree, cloth: _sareeColors[i], flip: true);
        c.drawOval(Rect.fromCenter(center: vessel + const Offset(-3, 0), width: 10, height: 6), Paint()..color = const Color(0xFFB0BEC5));
      } else {
        _cycle(c, Offset(x, y), 1.15, riding, cargo: cans);
      }
      _nameTag(c, Offset(x, y - 60), m);
    }
    if (!_anyActive) {
      for (var i = 0; i < doors.length; i++) {
        final at = Offset(doors[i] + 4, 198);
        _person(c, at, const _Pose(armF: 0.9, armB: 0.2), k: 0.9, outfit: _Outfit.saree, cloth: _sareeColors[i], flip: true);
        if ((seconds ~/ 2 + i) % 3 == 0) {
          _say(c, at + const Offset(0, -58), i.isOdd ? 'No milk yet!' : 'How do I make tea?',
              i.isOdd ? 'పాలు ఇంకా రాలేదు!' : 'టీ ఎలా పెట్టాలి?',
              angry: true);
        }
      }
    }
  }

  /// Vegetable cart: push and call out, stop and weigh for the lady at the door.
  void _vegCart(Canvas c) {
    _street(c);
    final doors = _doors;
    final members = _crew;
    final fresh = _anyActive;
    const freshCols = [Color(0xFFE53935), Color(0xFF6A1B9A), Color(0xFF43A047), Color(0xFF7CB342)];
    const wilted = [Color(0xFFA1887F), Color(0xFF8D7F86), Color(0xFF8D9B74), Color(0xFF9AA37A)];
    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final q = _saw(30, j * 0.45) * doors.length;
      final i = math.min(q.floor(), doors.length - 1);
      final f = q - i;
      final from = i == 0 ? -40.0 : doors[i - 1] + 30;
      final to = doors[i] + 30;
      final moving = m.active && f < 0.45;
      final selling = m.active && f >= 0.45;
      final x = m.active ? (moving ? from + (to - from) * _ease(f / 0.45) : to) : 40.0 + j * 70;
      final y = 238.0 + j * 4;
      final deck = Rect.fromLTWH(x - 4, y - 26, 52, 7);
      c.drawRect(deck, Paint()..color = const Color(0xFF8D6E63));
      c.drawRect(deck, _stroke(_edge, 0.9));
      for (final wx in const [4.0, 40.0]) {
        c.drawCircle(Offset(x + wx, y - 6), 6, _stroke(const Color(0xFF4E342E), 2));
      }
      for (var h = 0; h < 4; h++) {
        for (var b = 0; b < 6; b++) {
          _dot(c, Offset(x + 2 + h * 12 + (b % 3) * 3.5, y - 28 - (b ~/ 3) * 3), 2.2, (fresh ? freshCols : wilted)[h]);
        }
      }
      if (!fresh && j == 0) _say(c, Offset(x + 22, y - 34), 'The vegetables are wilting!', 'కూరలు వాడిపోతున్నాయి!', angry: true);
      final push = _wave(0.75);
      final pose = moving
          ? _Pose(lean: 0.35, legF: push * 0.45, legB: -push * 0.45, armF: 1.2, armB: 1.1, bob: -_wave(0.375).abs() * 1.5)
          : selling
              ? _Pose(lean: 0.1, armF: 1.6 + _strike(1.5) * 0.3, armB: 0.4)
              : _idlePose;
      final hand = _person(c, Offset(x - 10, y), pose, k: 1.1, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
      if (moving && _saw(4) < 0.5) _say(c, Offset(x + 8, y - 78), 'Vegetables! Tomato, brinjal!', 'కూరగాయలూ... టమాటా, వంకాయ!');
      if (selling) {
        // Hand scale, the customer at the cart.
        final tilt = _wave(1.5) * 1.5;
        c.drawLine(hand, hand + const Offset(0, 8), _stroke(const Color(0xFF555555), 0.8));
        c.drawLine(hand + Offset(-6, 8 + tilt), hand + Offset(6, 8 - tilt), _stroke(const Color(0xFF555555), 0.8));
        _person(c, Offset(x + 62, y), const _Pose(lean: -0.05, armF: 1.2, armB: 0.9),
            outfit: _Outfit.saree, cloth: const Color(0xFF00897B), flip: true);
      }
      _nameTag(c, Offset(x, y - 66), m);
    }
  }

  // ----------------------------------------------------------------- cattle

  void _buffalo(Canvas c, Offset foot, double k, double shift, bool graze) {
    c.save();
    c.translate(foot.dx, foot.dy);
    c.scale(k);
    const body = Color(0xFF3E3A39);
    const dark = Color(0xFF2A2726);
    final ph = graze ? 0.0 : _wave(0.9, shift);
    for (final (dx, sign) in const [(-14.0, 1.0), (-8.0, -1.0), (10.0, -1.0), (16.0, 1.0)]) {
      final knee = Offset(dx + ph * sign * 2, -9);
      _limb(c, Offset(dx, -18), knee, 4.6, 3.6, sign > 0 ? dark : body);
      _limb(c, knee, Offset(dx + ph * sign * 4, 0), 3.6, 3, sign > 0 ? dark : body);
    }
    c.drawOval(Rect.fromCenter(center: const Offset(0, -24), width: 46, height: 20), Paint()..color = body);
    final chew = graze ? _wave(0.6, shift) : 0.0;
    final head = Offset(25, graze ? -6 + chew : -26);
    c.drawPath(
        Path()
          ..moveTo(14, -30)
          ..lineTo(head.dx - 3, head.dy - 4)
          ..lineTo(head.dx, head.dy + 4)
          ..lineTo(15, -16)
          ..close(),
        Paint()..color = body);
    c.save();
    c.translate(head.dx + 3, head.dy);
    c.rotate(graze ? 1.1 : 0.2);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 12, height: 9), Paint()..color = body);
    c.restore();
    c.drawPath(
        Path()
          ..moveTo(head.dx - 1, head.dy - 3)
          ..quadraticBezierTo(head.dx - 10, head.dy - 6, head.dx - 8, head.dy + 2),
        _stroke(const Color(0xFF6D6159), 2.2));
    _dot(c, head + const Offset(2, -1), 0.9, const Color(0xFFBBBBBB));
    final swish = _wave(2, shift) * 4;
    c.drawPath(
        Path()
          ..moveTo(-22, -28)
          ..quadraticBezierTo(-28, -18, -26 + swish, -9),
        _stroke(dark, 1.4));
    c.restore();
  }

  /// Grazing: the herd eats together while someone walks behind it; left
  /// alone it drifts into the neighbour's paddy.
  void _cattle(Canvas c) {
    final ground = Rect.fromLTWH(0, 132, _w, _h - 132);
    c.drawRect(
        ground,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFA6CF7A), Color(0xFF6F9E4B)],
          ).createShader(ground));
    c.drawRect(Rect.fromLTWH(0, 138, _w, 8), Paint()..color = const Color(0xFF9FD0E6));
    final fence = _w * 0.82;
    c.drawRect(Rect.fromLTWH(fence, 150, _w - fence, 100), Paint()..color = const Color(0xFF5C9C3D));
    for (var y = 158.0; y < 250; y += 12) {
      for (var x = fence + 6; x < _w; x += 10) {
        _plant(c, Offset(x, y), 0.6, 0.4, false);
      }
    }
    c.drawLine(Offset(fence - 2, 150), Offset(fence - 2, 250), _stroke(const Color(0xFF8B6B4A), 1.5));
    final working = _anyActive;
    const herd = [(0.3, 190.0, 0.95, 0.0), (0.47, 214.0, 1.1, 0.3), (0.62, 182.0, 0.85, 0.6)];
    for (var i = 0; i < herd.length; i++) {
      final (fx, y, k, sh) = herd[i];
      final x = _w * fx;
      final drift = working ? _wave(15, sh) * 10 : math.min(1.0, _saw(20, sh * 0.2) * 1.4) * (fence - x + 10);
      _buffalo(c, Offset(x + drift, y), k, sh, working || i == 0);
    }
    _egret(c, Offset(_w * 0.4, 238), 0.7, 0.4, true);
    final members = _crew;
    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final x = m.active ? 60 + _wave(12, j * 0.3) * 30 + j * 30 : 40.0 + j * 30;
      final foot = Offset(x, 232.0 - j * 16);
      final hand = _person(c, foot, m.active ? _walk(1.0, true) : _idlePose,
          k: 1.15 - j * 0.1, outfit: _outfitOf(m), cloth: _crewCloth[j % 4]);
      c.drawLine(hand, hand + const Offset(6, -26), _stroke(const Color(0xFF7A5232), 1.6));
      _nameTag(c, foot + const Offset(0, -80), m);
    }
    if (!working) {
      _say(c, Offset(fence + 10, 146), 'Your buffaloes are in my field!', 'గేదెలు నా పొలంలోకి వస్తున్నాయి!', angry: true);
    }
  }

  // ---------------------------------------------------------------- fishing

  void _water(Canvas c, double top) {
    final r = Rect.fromLTWH(0, top, _w, _h - top);
    c.save();
    c.clipRect(r);
    c.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFCFE7EE), Color(0xFFA7C7C2), Color(0xFF7E8F6C)],
            stops: [0, 0.35, 1],
          ).createShader(r));
    final glint = Offset(_w * 0.8, top + 10);
    c.drawCircle(
        glint,
        60,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xB3FFF5C8), Color(0x00FFF5C8)])
              .createShader(Rect.fromCircle(center: glint, radius: 60)));
    final rnd = math.Random(4);
    for (var i = 0; i < 40; i++) {
      final x = ((rnd.nextDouble() + _saw(20)) % 1) * _w;
      final y = top + 4 + rnd.nextDouble() * (_h - top - 4);
      final len = 4 + rnd.nextDouble() * 9;
      c.drawLine(Offset(x, y), Offset(x + len, y), _stroke(Colors.white.withValues(alpha: 0.25 + 0.2 * _wave(3, i / 40)), 0.8));
    }
    c.restore();
  }

  void _fishShape(Canvas c, Offset at, double angle, double len) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(angle);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: len, height: len * 0.45), Paint()..color = const Color(0xFFB0BEC5));
    c.restore();
  }

  /// Cast net: wind up, throw (the net opens in the air), let it sink, pull
  /// it in with fish flapping; the basket fills as the work goes on.
  void _fishing(Canvas c) {
    _water(c, 130);
    c.drawPath(
        Path()
          ..moveTo(0, 218)
          ..quadraticBezierTo(_w * 0.35, 206, _w * 0.65, 222)
          ..lineTo(_w, 230)
          ..lineTo(_w, _h)
          ..lineTo(0, _h)
          ..close(),
        Paint()..color = const Color(0xFF8A6A45));
    final b = Offset(_w * 0.75, 236);
    final basket = Path()
      ..moveTo(b.dx - 16, b.dy - 18)
      ..lineTo(b.dx + 16, b.dy - 18)
      ..lineTo(b.dx + 12, b.dy)
      ..lineTo(b.dx - 12, b.dy)
      ..close();
    c.drawPath(basket, Paint()..color = const Color(0xFFB08850));
    c.drawPath(basket, _stroke(_edge, 0.9));
    final fish = (((stageIndex + fraction) / job.stages.length) * 8).round();
    for (var i = 0; i < fish; i++) {
      _fishShape(c, Offset(b.dx - 10 + (i % 4) * 7, b.dy - 19 - (i ~/ 4) * 3), i.isOdd ? 0.3 : -0.3, 8);
    }
    final members = _crew;
    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final x = _w * 0.27 + j * 70;
      final y = 214.0 - j * 6;
      final q = m.active ? _saw(5, j * 0.37) : 0.0;
      final _Pose pose;
      if (!m.active) {
        pose = _idlePose;
      } else if (q < 0.25) {
        pose = _Pose(lean: -0.1 - q * 0.6, armF: 1.6 + q * 2, armB: 1.2, legF: 0.25, legB: -0.2);
      } else if (q < 0.35) {
        pose = _Pose(lean: 0.35, armF: 2.6 - (q - 0.25) * 18, armB: 0.6, legF: 0.3, legB: -0.25);
      } else if (q < 0.7) {
        pose = const _Pose(lean: 0.2, armF: 0.9, armB: 0.5);
      } else {
        pose = _Pose(lean: -0.15 + math.sin((q - 0.7) * 40) * 0.05, armF: 1.3 + _wave(0.5) * 0.2, armB: 1.2);
      }
      final hand = _person(c, Offset(x, y), pose,
          k: 1.2 - j * 0.1, outfit: m.wear == 'saree' ? _Outfit.saree : _Outfit.lungi, cloth: _crewCloth[j % 4]);
      final net = Offset(x + 80 - j * 10, 172.0 - j * 4);
      final cord = _stroke(const Color(0xB3505050), 0.6);
      if (m.active && q >= 0.25 && q < 0.7) {
        final open = q < 0.35 ? (q - 0.25) / 0.1 : 1.0;
        final ctr = Offset.lerp(hand, net, open)! + Offset(0, -math.sin(math.pi * open) * 30);
        final rx = 4 + open * 26;
        final ry = 2 + open * 8;
        c.drawLine(hand, ctr + Offset(0, -ry), cord);
        c.drawOval(Rect.fromCenter(center: ctr, width: rx * 2, height: ry * 2), cord);
        for (var n = 0; n < 10; n++) {
          final a = n * math.pi / 5;
          c.drawLine(ctr + Offset(0, -ry), ctr + Offset(math.cos(a) * rx, math.sin(a) * ry), cord);
        }
        if (q >= 0.35) {
          final rr = (q - 0.35) / 0.35;
          c.drawOval(Rect.fromCenter(center: net, width: 40 + rr * 40, height: 12 + rr * 12),
              _stroke(Colors.white.withValues(alpha: 0.7 * (1 - rr)), 0.8));
        }
      }
      if (m.active && q >= 0.7) {
        final p = Offset.lerp(net, hand + const Offset(6, 10), (q - 0.7) / 0.3)!;
        c.drawLine(hand, p + const Offset(0, -5), _stroke(const Color(0xCC505050), 0.7));
        c.drawOval(Rect.fromCenter(center: p, width: 16, height: 12), Paint()..color = const Color(0x8C5A5A5A));
        for (var f = 0; f < 3; f++) {
          _fishShape(c, p + Offset(-4.0 + f * 4, _wave(0.2, f * 0.3) * 1.5), _wave(0.2, f * 0.3) * 0.5, 6);
        }
      }
      _nameTag(c, Offset(x, y - 86), m);
    }
    // Fish jumping in the open water.
    for (var i = 0; i < 3; i++) {
      final q = _saw(4, i * 0.37);
      if (q >= 0.3) continue;
      final f = q / 0.3;
      _fishShape(c, Offset(_w * 0.55 + i * 50 + f * 14, 160 + i * 10 - math.sin(math.pi * f) * 14), -0.6 + f * 1.2, 8);
    }
    _egret(c, Offset(_w * 0.1, 222), 0.8, 0.2, false);
    if (!_anyActive) {
      _say(c, Offset(_w * 0.6, 140), 'The fish are getting away!', 'చేపలు వలకు దొరక్కుండా పోతున్నాయి!', angry: true);
    }
  }

  /// A white egret (konga) standing in the field, pecking now and then.
  void _egret(Canvas c, Offset foot, double k, double shift, bool flip) {
    final peck = _strike(2.4, shift);
    c.save();
    c.translate(foot.dx, foot.dy);
    c.scale(flip ? -k : k, k);
    final leg = _stroke(const Color(0xFF2B2B2B), 1);
    c.drawLine(const Offset(-1, -9), const Offset(-2, 0), leg);
    c.drawLine(const Offset(2, -9), const Offset(3, 0), leg);
    c.save();
    c.translate(0, -12);
    c.rotate(-0.2);
    final body = Rect.fromCenter(center: Offset.zero, width: 14, height: 8);
    c.drawOval(body, Paint()..color = const Color(0xFFFBFBF7));
    c.drawOval(body, _stroke(const Color(0x40000000), 0.7));
    c.restore();
    final head = Offset(9 + 3 * peck, -24 + 18 * peck);
    c.drawPath(
        Path()
          ..moveTo(5, -14)
          ..cubicTo(10, -16, 4, -22 + 12 * peck, head.dx, head.dy),
        _stroke(const Color(0xFFFBFBF7), 2.2));
    _dot(c, head, 2.2, const Color(0xFFFBFBF7));
    c.drawLine(head + const Offset(1, 0), head + Offset(7, 3 * peck), _stroke(const Color(0xFFF2B632), 1.3));
    c.restore();
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
        // A puff of dust where the blade bites.
        final after = _afterImpact(1.0);
        if (active && after >= 0) {
          for (var i = 0; i < 4; i++) {
            final a = math.pi * (0.15 + 0.23 * i);
            c.drawCircle(hand + Offset(10 * _s + math.cos(a) * after * 12 * _s, 21 * _s - math.sin(a) * after * 8 * _s),
                (2 + after * 5) * _s, Paint()..color = const Color(0xFFB89470).withValues(alpha: 0.4 * (1 - after)));
          }
        }
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
          _person(c, Offset(x, _h * 0.98), _walk(0.75), shirt: i == 0 ? const Color(0xFF8E24AA) : const Color(0xFF00897B), hat: false);
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

  // ------------------------------------------------------------------ hotel

  static const _seats = 5;
  double _seatX(int i) => _w * 0.365 + i * _w * 0.13;
  double _hx(double v) => v * _w / 400;

  /// Each seat runs its own 20 s visit: arrive, order and wait, eat, pay and leave, empty.
  (String, double) _seat(int i) {
    final q = _saw(20, i * 0.21);
    if (q < 0.08) return ('arrive', q / 0.08);
    if (q < 0.32) return ('wait', (q - 0.08) / 0.24);
    if (q < 0.74) return ('eat', (q - 0.32) / 0.42);
    if (q < 0.84) return ('leave', (q - 0.74) / 0.1);
    return ('empty', 0.0);
  }

  /// Where waiter [j] (of [n] working waiters) is: serving at a seat the moment
  /// its wait ends, back to the kitchen for the next plate in between.
  /// Returns x, serving, facing left.
  (double, bool, bool) _waiter(int j, int n) {
    final events = <(double, double)>[
      for (var i = 0; i < _seats; i++)
        if (i % n == j) (((0.32 - i * 0.21) % 1) * 20, _seatX(i) - 4),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final kitchen = _hx(112);
    if (events.isEmpty) return (kitchen, false, false);
    final now = seconds % 20;
    final k = events.lastIndexWhere((e) => e.$1 <= now);
    final prev = k < 0 ? events.last : events[k];
    final next = events[(k + 1) % events.length];
    var since = now - prev.$1;
    if (since < 0) since += 20;
    var gap = next.$1 - prev.$1;
    if (gap <= 0) gap += 20;
    const serve = 1.2;
    if (since < serve) return (prev.$2, true, false);
    final t = (since - serve) / (gap - serve);
    if (t < 0.5) return (prev.$2 + (kitchen - prev.$2) * _ease(t / 0.5), false, true);
    return (kitchen + (next.$2 - kitchen) * _ease((t - 0.5) / 0.5), false, false);
  }

  void _leaf(Canvas c, Offset at) {
    final r = Rect.fromCenter(center: at, width: 32, height: 9);
    c.drawOval(r, Paint()..color = const Color(0xFF3F9A3C));
    c.drawOval(r, _stroke(const Color(0xFF2D6E2B), 0.7));
    c.drawLine(at - const Offset(16, 0), at + const Offset(16, 0), _stroke(const Color(0xFF2D6E2B), 0.7));
  }

  /// Tiffin hotel: customers walk in, order, wait, eat from banana leaves, ask
  /// for the bill and leave; the waiter (or each working team member) hurries
  /// between the kitchen and the customers. With nobody walking the plates pile
  /// up at the hatch and the customers get angry.
  void _hotel(Canvas c) {
    final working = _anyActive;
    final room = Rect.fromLTWH(0, 0, _w, _h);
    c.drawRect(
        room,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6E2C2), Color(0xFFECD0A6)],
          ).createShader(room));
    c.drawRect(Rect.fromLTWH(0, 128, _w, 6), Paint()..color = const Color(0xFFB5753E));
    final board = RRect.fromRectAndRadius(Rect.fromLTWH(_hx(126), 30, _hx(112), 24), const Radius.circular(4));
    c.drawRRect(board, Paint()..color = const Color(0xFF8E2B1C));
    _text(c, te ? 'శ్రీ లక్ష్మీ టిఫిన్స్' : 'Sri Lakshmi Tiffins', board.center, const Color(0xFFFFE9A8), 10);
    // Window with the street outside.
    final win = Rect.fromLTWH(_hx(250), 30, _hx(100), 66);
    c.drawRect(win, Paint()..color = const Color(0xFF9FD3EF));
    c.drawRect(Rect.fromLTWH(win.left, 80, win.width, 16), Paint()..color = const Color(0xFFC9E6C0));
    _palm(c, Offset(win.center.dx, 96), 0.55);
    c.drawRect(win, _stroke(const Color(0xFF7A4A24), 4));
    // Ceiling fan.
    final fan = Offset(_hx(190), 16);
    c.drawLine(Offset(fan.dx, 0), fan, _stroke(const Color(0xFF6B6B6B), 1.5));
    for (var i = 0; i < 3; i++) {
      final a = seconds * 2 * math.pi / 0.5 + i * 2 * math.pi / 3;
      c.drawOval(Rect.fromCenter(center: fan + Offset(math.cos(a) * 20, math.sin(a) * 3), width: 36, height: 5),
          Paint()..color = const Color(0xBF6E6E6E));
    }
    _dot(c, fan, 4, const Color(0xFF555555));
    // Door on the right, floor.
    c.drawRect(Rect.fromLTWH(_w - 30, 92, 30, 106), Paint()..color = const Color(0xFF6D4C41));
    c.drawRect(Rect.fromLTWH(_w - 26, 96, 26, 100), Paint()..color = const Color(0xFFFFE9C4));
    c.drawRect(Rect.fromLTWH(0, 196, _w, _h - 196), Paint()..color = const Color(0xFFC99E6D));
    for (var x = -40.0; x < _w + 40; x += 30) {
      c.drawLine(Offset(x, 196), Offset(x - 30, _h), _stroke(const Color(0x40784828), 1));
    }
    // Kitchen hatch: the cook stirs; ready plates pile up when nobody serves.
    final hatch = Rect.fromLTWH(_hx(14), 60, _hx(82), 64);
    c.drawRect(hatch, Paint()..color = const Color(0xFF5D4037));
    c.drawRect(hatch.deflate(5), Paint()..color = const Color(0xFFFFE0B2));
    _person(c, Offset(hatch.left + _hx(34), 130), _Pose(lean: 0.1, armF: 1.5 + _wave(1.2) * 0.3, armB: 0.9),
        outfit: _Outfit.shirt, shirt: const Color(0xFFFAFAFA), cap: Colors.white);
    final pot = Offset(hatch.left + _hx(58), 112);
    c.drawOval(Rect.fromCenter(center: pot, width: 28, height: 10), Paint()..color = const Color(0xFF6D6D6D));
    c.drawRect(Rect.fromLTWH(pot.dx - 14, pot.dy, 28, 9), Paint()..color = const Color(0xFF8A8A8A));
    for (var i = 0; i < 4; i++) {
      final s = _saw(2.4, i / 4);
      _dot(c, pot + Offset(-6.0 + i * 4 + _wave(1.2, i / 4) * 2, -8 - s * 26), 2 + s * 3,
          Colors.white.withValues(alpha: 0.6 * (1 - s)));
    }
    c.drawRect(Rect.fromLTWH(hatch.left - 4, 120, hatch.width + 8, 6), Paint()..color = const Color(0xFF5D4037));
    for (var i = 0; i < (working ? 1 : 4); i++) {
      final p = Offset(hatch.left + 12 + i * 15, 118);
      _dot(c, p, 6, const Color(0xFFFBFAF3));
      _dot(c, p + const Offset(0, -2), 3, const Color(0xFFE2A32A));
    }
    if (!working) _say(c, Offset(hatch.center.dx, 56), 'Plates ready! Nobody came!', 'ప్లేట్లు రెడీ! ఎవరూ రాలేదు!', angry: true);

    // Customers, each on their own visit; without a waiter they only wait.
    const tableY = 188.0;
    const shirts = [Color(0xFF8E24AA), Color(0xFF00897B), Color(0xFFEF6C00), Color(0xFF3949AB), Color(0xFFC62828)];
    const orders = [
      ('Idli please!', 'ఇడ్లీ ప్లీజ్!'),
      ('One dosa!', 'దోస ఒకటి!'),
      ('Meals!', 'మీల్స్!'),
      ('Tea please!', 'టీ ఇవ్వండి!'),
      ('One vada!', 'వడ ఒకటి!'),
    ];
    final states = [for (var i = 0; i < _seats; i++) _seat(i)];
    if (!working) {
      for (var i = 0; i < _seats; i++) {
        if (states[i].$1 != 'empty') states[i] = ('wait', 1.0);
      }
    }
    for (var i = 0; i < _seats; i++) {
      final (phase, q) = states[i];
      final gx = _seatX(i) - 16;
      final wear = i.isOdd ? _Outfit.saree : _Outfit.shirt;
      if (phase == 'empty') continue;
      if (phase == 'arrive' || phase == 'leave') {
        final from = phase == 'arrive' ? _w - 8 : gx;
        final to = phase == 'arrive' ? gx : _w - 8;
        _person(c, Offset(from + (to - from) * _ease(q), 232), _walk(0.6, true),
            k: 1.1, outfit: wear, shirt: shirts[i], cloth: const Color(0xFFAD1457), hat: false, flip: phase == 'arrive');
        continue;
      }
      final eat = phase == 'eat' ? _wave(2, i * 0.3).abs() : 0.0;
      final angry = phase == 'wait' && q > 0.55;
      _person(
          c,
          Offset(gx, tableY + 20),
          angry
              ? _Pose(crouch: 0.6, lean: 0.05, armB: 0.7, armF: 2.6 + _wave(0.5, i * 0.2) * 0.3)
              : _Pose(crouch: 0.6, lean: 0.15 + eat * 0.1, armB: 0.7, armF: 0.9 + eat * 1.5),
          outfit: wear,
          shirt: shirts[i],
          cloth: const Color(0xFFAD1457),
          hat: false);
      if (phase == 'wait') {
        final show = working || (seconds ~/ 2.5) % _seats == i || (seconds ~/ 2.5 + 2) % _seats == i;
        if (show) {
          if (q < 0.55) {
            _say(c, Offset(gx, tableY - 52), orders[i].$1, orders[i].$2);
          } else if (working) {
            _say(c, Offset(gx, tableY - 52), 'Not yet?', 'ఇంకా రాలేదా?', angry: true);
          } else {
            _say(c, Offset(gx, tableY - 52), 'How long?!', 'ఎంతసేపు?!', angry: true);
          }
        }
      }
      if (phase == 'eat' && q > 0.85) _say(c, Offset(gx, tableY - 52), 'Bill please', 'బిల్లు ప్లీజ్');
    }
    final table = Rect.fromLTWH(_hx(105), tableY - 2, _w - _hx(105) - 34, 7);
    c.drawRect(table, Paint()..color = const Color(0xFF8D6E63));
    c.drawRect(table, _stroke(_edge, 1));
    for (final x in [table.left + 6, table.right - 10]) {
      c.drawRect(Rect.fromLTWH(x, tableY + 5, 5, 26), Paint()..color = const Color(0xFF6D4C41));
    }
    for (var i = 0; i < _seats; i++) {
      final (phase, q) = states[i];
      if (phase == 'empty' || phase == 'arrive') continue;
      final leaf = Offset(_seatX(i), tableY - 3);
      _leaf(c, leaf);
      if (phase != 'eat') continue;
      final left = 1 - q * 0.8;
      _dot(c, leaf + const Offset(-4, -3), 4 * left, const Color(0xFFFBFAF3));
      _dot(c, leaf + const Offset(5, -2), 2.4 * left, const Color(0xFFE2A32A));
      _dot(c, leaf + const Offset(9, -1.5), 1.8 * left, const Color(0xFFB5371C));
      if (q < 0.4) {
        final s = _saw(1.5, i * 0.2);
        c.drawPath(
            Path()
              ..moveTo(leaf.dx - 5, leaf.dy - 8 - s * 6)
              ..quadraticBezierTo(leaf.dx - 2, leaf.dy - 11 - s * 6, leaf.dx - 4, leaf.dy - 14 - s * 8),
            _stroke(Colors.white.withValues(alpha: 0.8 * (1 - s)), 1));
      }
    }

    // Waiters: every working member serves; one who has not walked stands by the kitchen.
    final members = _crew;
    final workingIdx = [for (var j = 0; j < members.length; j++) if (members[j].active) j];
    for (var j = 0; j < members.length; j++) {
      final m = members[j];
      final y = 236.0 + j * 4;
      double x;
      var serving = false;
      var left = false;
      var moving = false;
      if (m.active) {
        final (wx, ws, wl) = _waiter(workingIdx.indexOf(j), workingIdx.length);
        x = wx;
        serving = ws;
        left = wl;
        moving = !ws;
      } else {
        x = _hx(112) + j * 34;
      }
      final ladle = serving ? _strike(0.8, j * 0.3) : 0.0;
      final pose = serving
          ? _Pose(lean: 0.2, armB: 0.9, armF: 0.8 + ladle * 0.9)
          : moving
              ? _walk(0.5, true)
              : _idlePose;
      final hand = _person(c, Offset(x - 6, y), pose,
          k: 1.2, outfit: _Outfit.shirt, shirt: Colors.white, cap: const Color(0xFF263238), flip: left);
      // Steel bucket of rice in the other hand.
      final bh = _backHand;
      final bucket = Path()
        ..moveTo(bh.dx - 6, bh.dy)
        ..lineTo(bh.dx + 6, bh.dy)
        ..lineTo(bh.dx + 5, bh.dy + 10)
        ..lineTo(bh.dx - 5, bh.dy + 10)
        ..close();
      c.drawPath(bucket, Paint()..color = const Color(0xFFB0BEC5));
      c.drawPath(bucket, _stroke(const Color(0xFF78909C), 0.8));
      _dot(c, bh + const Offset(0, 0.5), 5.5, const Color(0xFFFBFAF3));
      if (serving) {
        c.drawLine(hand, hand + const Offset(8, 3), _stroke(const Color(0xFF90A4AE), 1.6));
        _dot(c, hand + const Offset(9, 3), 2.4, const Color(0xFFFBFAF3));
      }
      _nameTag(c, Offset(x - 6, y - 88), m);
    }
  }

  // ---------------------------------------------------------------- waiting

  /// While nobody walks: a thought cloud with a clock -- the work is waiting.
  void _waitingBubble(Canvas c) {
    final center = Offset(_w * 0.5, _h * 0.17);
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.95);
    for (final (dx, dy, r) in const [(-14.0, 2.0, 12.0), (0.0, -4.0, 15.0), (15.0, 2.0, 12.0), (0.0, 7.0, 12.0)]) {
      c.drawCircle(center + Offset(dx * _s, dy * _s), r * _s, cloud);
    }
    c.drawCircle(center + Offset(-22 * _s, 20 * _s), 4 * _s, cloud);
    c.drawCircle(center + Offset(-28 * _s, 28 * _s), 2.5 * _s, cloud);
    final face = center + Offset(0, 1 * _s);
    c.drawCircle(face, 9 * _s, _stroke(const Color(0xFFB45309), 1.8 * _s));
    final a = 2 * math.pi * _saw(4);
    c.drawLine(face, face + Offset(math.sin(a) * 6.5 * _s, -math.cos(a) * 6.5 * _s), _stroke(const Color(0xFFB45309), 1.6 * _s));
    c.drawLine(face, face + Offset(0, -4.5 * _s), _stroke(const Color(0xFFB45309), 1.8 * _s));
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
      old.bubble != bubble ||
      old.images != images;
}
