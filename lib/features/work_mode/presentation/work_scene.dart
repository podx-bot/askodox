import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/work_mode_plan.dart';

/// The animated picture of the job. The work drawn follows the real progress
/// ([overall] 0..1 and the current stage); the small loop (the worker's step,
/// water drops, sparks) only plays while [moving] is true.
class AskodoxWorkSceneView extends StatefulWidget {
  const AskodoxWorkSceneView({
    required this.scene,
    required this.overall,
    required this.stageIndex,
    required this.stageCount,
    this.moving = true,
    this.height = 220,
    super.key,
  });

  final AskodoxWorkScene scene;
  final double overall;
  final int stageIndex;
  final int stageCount;
  final bool moving;
  final double height;

  @override
  State<AskodoxWorkSceneView> createState() => _AskodoxWorkSceneViewState();
}

class _AskodoxWorkSceneViewState extends State<AskodoxWorkSceneView> with SingleTickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.moving) _loop.repeat();
  }

  @override
  void didUpdateWidget(covariant AskodoxWorkSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moving && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!widget.moving && _loop.isAnimating) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
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
            animation: _loop,
            builder: (context, _) => CustomPaint(
              painter: AskodoxWorkScenePainter(
                scene: widget.scene,
                overall: widget.overall.clamp(0.0, 1.0),
                stage: widget.stageCount <= 1 ? 1 : widget.stageIndex / (widget.stageCount - 1),
                tick: _loop.value,
              ),
            ),
          ),
        ),
      );
}

class AskodoxWorkScenePainter extends CustomPainter {
  AskodoxWorkScenePainter({required this.scene, required this.overall, required this.stage, required this.tick});

  final AskodoxWorkScene scene;

  /// 0..1 of the whole job.
  final double overall;

  /// 0..1 position of the current stage among the stages.
  final double stage;

  /// 0..1 animation loop.
  final double tick;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final evening = overall >= 0.98;
    // Sky.
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: evening ? const [Color(0xFFF6B26B), Color(0xFFFBE3BE)] : const [Color(0xFF9FD3F0), Color(0xFFE8F6FC)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    // Sun rises with the job and sets at the end.
    final sunX = w * (0.15 + 0.7 * overall);
    final sunY = h * (evening ? 0.32 : 0.28 - 0.12 * math.sin(math.pi * overall));
    canvas.drawCircle(Offset(sunX, sunY), h * 0.08,
        Paint()..color = evening ? const Color(0xFFF08A24) : const Color(0xFFFFE08A));
    // Drifting cloud.
    final cloudX = (w * 0.1 + tick * w * 0.25) % (w * 1.1) - w * 0.05;
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawOval(Rect.fromCenter(center: Offset(cloudX, h * 0.18), width: w * 0.16, height: h * 0.07), cloud);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cloudX + w * 0.06, h * 0.15), width: w * 0.12, height: h * 0.07), cloud);
    // Hills.
    final far = Path()
      ..moveTo(0, h * 0.5)
      ..quadraticBezierTo(w * 0.2, h * 0.32, w * 0.42, h * 0.46)
      ..quadraticBezierTo(w * 0.7, h * 0.3, w, h * 0.45)
      ..lineTo(w, h * 0.6)
      ..lineTo(0, h * 0.6)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFB9CDA9));
    final near = Path()
      ..moveTo(0, h * 0.58)
      ..quadraticBezierTo(w * 0.35, h * 0.47, w * 0.6, h * 0.56)
      ..quadraticBezierTo(w * 0.85, h * 0.62, w, h * 0.55)
      ..lineTo(w, h * 0.64)
      ..lineTo(0, h * 0.64)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFFA2BF8C));
    // Ground.
    final ground = Rect.fromLTWH(0, h * 0.62, w, h * 0.38);
    canvas.drawRect(
        ground,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CC97A), Color(0xFF6E9E4F)],
          ).createShader(ground));

    switch (scene) {
      case AskodoxWorkScene.field:
        _field(canvas, size);
      case AskodoxWorkScene.houses:
        _houses(canvas, size);
      case AskodoxWorkScene.building:
        _building(canvas, size);
      case AskodoxWorkScene.workshop:
        _workshop(canvas, size);
    }
    _worker(canvas, size);
  }

  void _field(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const rows = 6;
    final tilled = (overall * rows * 1.6).clamp(0, rows).round();
    for (var i = 0; i < rows; i++) {
      final y = h * 0.68 + i * h * 0.05;
      final inset = w * 0.06 - i * 3;
      final paint = Paint()
        ..color = i < tilled ? const Color(0xFF6B4A2B) : const Color(0xFF8FB070)
        ..strokeWidth = i < tilled ? 4 : 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(inset, y), Offset(w - inset, y), paint);
      // Plants appear after the first quarter and grow with the job.
      if (overall > 0.22 && i < rows - 1) {
        final grow = ((overall - 0.22) / 0.6).clamp(0.15, 1.0);
        final ripe = stage >= 0.99;
        for (var k = 0; k < 10; k++) {
          final x = inset + 14 + k * (w - 2 * inset - 28) / 9;
          final sway = math.sin((tick * 2 * math.pi) + k + i) * 2 * grow;
          final top = Offset(x + sway, y - 20 * grow);
          canvas.drawLine(
              Offset(x, y),
              top,
              Paint()
                ..color = ripe ? const Color(0xFFC9962E) : const Color(0xFF2F6B2C)
                ..strokeWidth = 2);
          canvas.drawOval(Rect.fromCenter(center: top.translate(-3, 4), width: 6, height: 3),
              Paint()..color = ripe ? const Color(0xFFE2B54C) : const Color(0xFF4FA55A));
          canvas.drawOval(Rect.fromCenter(center: top.translate(3, 7), width: 6, height: 3),
              Paint()..color = ripe ? const Color(0xFFE2B54C) : const Color(0xFF4FA55A));
        }
      }
    }
  }

  void _houses(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const count = 6;
    final served = (overall * count * 1.2).clamp(0, count).floor();
    // Lane.
    canvas.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), Paint()..color = const Color(0xFF8A8F96));
    for (var i = 0; i < count; i++) {
      final x = w * 0.04 + i * w * 0.16;
      final body = Rect.fromLTWH(x, h * 0.6, w * 0.12, h * 0.24);
      canvas.drawRect(body, Paint()..color = const [Color(0xFFF2D7B6), Color(0xFFE9C3C3), Color(0xFFCFE0F2)][i % 3]);
      final roof = Path()
        ..moveTo(x - 4, h * 0.6)
        ..lineTo(x + w * 0.06, h * 0.5)
        ..lineTo(x + w * 0.12 + 4, h * 0.6)
        ..close();
      canvas.drawPath(roof, Paint()..color = const Color(0xFFB5523B));
      canvas.drawRect(Rect.fromLTWH(x + w * 0.045, h * 0.72, w * 0.03, h * 0.12), Paint()..color = const Color(0xFF7A5232));
      if (i < served) {
        // Delivered: a rolled paper / parcel at the door.
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + w * 0.08, h * 0.8, w * 0.03, h * 0.04), const Radius.circular(2)),
            Paint()..color = const Color(0xFFF5F0E6));
        canvas.drawCircle(Offset(x + w * 0.1, h * 0.56), 5, Paint()..color = const Color(0xFF1F8A5B));
      }
    }
  }

  void _building(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Pit / foundation line.
    canvas.drawRect(Rect.fromLTWH(w * 0.2, h * 0.86, w * 0.6, h * 0.05), Paint()..color = const Color(0xFF7A5232));
    const courses = 9;
    final built = (overall * courses).clamp(0, courses).round();
    final brick = Paint()..color = const Color(0xFFC0583A);
    final mortar = Paint()
      ..color = const Color(0xFFEDE3D3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 0; r < built; r++) {
      final y = h * 0.84 - r * h * 0.035;
      for (var k = 0; k < 8; k++) {
        final x = w * 0.22 + k * w * 0.07 + (r.isOdd ? w * 0.035 : 0);
        if (x + w * 0.07 > w * 0.8) continue;
        final rect = Rect.fromLTWH(x, y, w * 0.07, h * 0.035);
        canvas.drawRect(rect, brick);
        canvas.drawRect(rect, mortar);
      }
    }
    if (overall > 0.8) {
      // Slab on top.
      final top = h * 0.84 - built * h * 0.035;
      canvas.drawRect(Rect.fromLTWH(w * 0.2, top - 6, w * 0.6, 8), Paint()..color = const Color(0xFF9AA0A6));
    }
    // A small heap of bricks / soil to carry.
    final heap = Path()
      ..moveTo(w * 0.82, h * 0.9)
      ..quadraticBezierTo(w * 0.88, h * 0.78, w * 0.95, h * 0.9)
      ..close();
    canvas.drawPath(heap, Paint()..color = const Color(0xFF9C6B43));
  }

  void _workshop(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Shed.
    canvas.drawRect(Rect.fromLTWH(w * 0.08, h * 0.5, w * 0.84, h * 0.4), Paint()..color = const Color(0xFFE6E1D6));
    final roof = Path()
      ..moveTo(w * 0.04, h * 0.5)
      ..lineTo(w * 0.5, h * 0.36)
      ..lineTo(w * 0.96, h * 0.5)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF5C6B7A));
    // Bench.
    canvas.drawRect(Rect.fromLTWH(w * 0.3, h * 0.74, w * 0.4, h * 0.04), Paint()..color = const Color(0xFF7A5232));
    // The piece being made: it gets longer / more finished with the job.
    final len = w * 0.36 * (0.2 + 0.8 * overall);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.32, h * 0.7, len, h * 0.03),
        Paint()..color = overall > 0.85 ? const Color(0xFF1F6FB2) : const Color(0xFF6D7278));
    // Sparks / activity at the working end.
    final end = Offset(w * 0.32 + len, h * 0.71);
    final rnd = math.Random((tick * 20).floor());
    for (var i = 0; i < 7; i++) {
      final a = rnd.nextDouble() * math.pi;
      final r = 6 + rnd.nextDouble() * 14;
      canvas.drawLine(end, end + Offset(math.cos(a) * r, -math.sin(a) * r),
          Paint()
            ..color = const Color(0xFFFFB84D)
            ..strokeWidth = 1.5);
    }
  }

  void _worker(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final x = w * (0.12 + 0.72 * overall);
    final bob = math.sin(tick * 2 * math.pi) * 2;
    final feet = h * 0.86;
    final step = math.sin(tick * 2 * math.pi) * 5;
    canvas.drawOval(Rect.fromCenter(center: Offset(x, feet + 3), width: 26, height: 6),
        Paint()..color = Colors.black.withValues(alpha: 0.18));
    final leg = Paint()
      ..color = const Color(0xFF2D3E50)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x - 4, feet - 22 + bob), Offset(x - 4 - step, feet), leg);
    canvas.drawLine(Offset(x + 4, feet - 22 + bob), Offset(x + 4 + step, feet), leg);
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(x - 9, feet - 46 + bob, 18, 26), const Radius.circular(6));
    canvas.drawRRect(body, Paint()..color = const Color(0xFF2F6FEB));
    canvas.drawCircle(Offset(x, feet - 54 + bob), 7, Paint()..color = const Color(0xFFC68B59));
    // Hat (towel / cap).
    final hat = Path()
      ..moveTo(x - 10, feet - 56 + bob)
      ..quadraticBezierTo(x, feet - 70 + bob, x + 10, feet - 56 + bob)
      ..close();
    canvas.drawPath(hat, Paint()..color = const Color(0xFFE8C87A));
    if (scene == AskodoxWorkScene.field && overall > 0.2 && overall < 0.9) {
      // Water drops from the can while the field is being watered.
      for (var i = 0; i < 3; i++) {
        final t = (tick + i / 3) % 1;
        canvas.drawCircle(Offset(x + 16, feet - 34 + t * 30), 2.4,
            Paint()..color = const Color(0xFF4AA3E0).withValues(alpha: 1 - t));
      }
    }
  }

  @override
  bool shouldRepaint(covariant AskodoxWorkScenePainter old) =>
      old.tick != tick || old.overall != overall || old.stage != stage || old.scene != scene;
}
