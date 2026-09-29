import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'askodox_companion.dart' show AskodoxCompanionMood;

/// The approved ASKODOX companion: ONE natural human identity (the "Smart
/// Advisor" -- see docs/SMART_ADVISOR_VROID_SPEC.md) shown as prepared
/// photographic states. Used everywhere (Home, bottom navigation, chat,
/// floating companion, voice) whenever the experimental 3D renderers are not
/// explicitly picked, and as their fallback -- it never switches to a
/// different face.
///
/// States are image files in assets/companion/human2d/. A state without its
/// own photo uses the neutral one with a state treatment (listening rings,
/// thinking dots, speaking pulse, success glow); drop in the file and add it
/// to [bundled] to upgrade a state -- nothing else changes.
class AskodoxHuman2d extends StatelessWidget {
  const AskodoxHuman2d({super.key, required this.mood, required this.size, this.t = 0, this.level = 0});

  final AskodoxCompanionMood mood;
  final double size;

  /// Animation clock (0..1, repeating while a state is active).
  final double t;

  /// Live microphone level while listening, mouth openness while speaking.
  final double level;

  static const dir = 'assets/companion/human2d';

  /// States that have their own photo in this build.
  static const bundled = {'neutral', 'listening', 'thinking'};

  static String stateOf(AskodoxCompanionMood mood) => switch (mood) {
        AskodoxCompanionMood.listening || AskodoxCompanionMood.understanding => 'listening',
        AskodoxCompanionMood.thinking || AskodoxCompanionMood.help => 'thinking',
        AskodoxCompanionMood.speaking => 'speaking',
        AskodoxCompanionMood.explaining ||
        AskodoxCompanionMood.suggesting ||
        AskodoxCompanionMood.guiding =>
          'explaining',
        AskodoxCompanionMood.success || AskodoxCompanionMood.greeting => 'happy',
        _ => 'neutral',
      };

  static String assetFor(AskodoxCompanionMood mood) {
    final state = stateOf(mood);
    return '$dir/${bundled.contains(state) ? state : 'neutral'}.jpg';
  }

  static const _violet = Color(0xFF6C4DFF);

  Color get _ring => switch (mood) {
        AskodoxCompanionMood.listening || AskodoxCompanionMood.understanding => const Color(0xFF1FA2FF),
        AskodoxCompanionMood.speaking ||
        AskodoxCompanionMood.success ||
        AskodoxCompanionMood.guiding =>
          const Color(0xFF1B8A3B),
        AskodoxCompanionMood.help => const Color(0xFFE08A00),
        _ => _violet,
      };

  @override
  Widget build(BuildContext context) {
    final wave = math.sin(t * 2 * math.pi);
    // Alive, not busy: a slow breath at rest, a small nod while speaking.
    final breathe = 1 + .012 * wave;
    final speakingNod = mood == AskodoxCompanionMood.speaking ? .02 * math.max(level, (wave + 1) / 4) : 0.0;
    final ring = _ring;
    final face = size * .86;
    return SizedBox.square(
      key: const ValueKey('askodoxCompanionHuman2d'),
      dimension: size,
      child: CustomPaint(
        painter: _StatePainter(mood: mood, t: t, level: level, color: ring),
        child: Center(
          child: Transform.scale(
            scale: breathe + speakingNod,
            child: Container(
              width: face,
              height: face,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: math.max(2, size * .025)),
                boxShadow: [BoxShadow(color: ring.withValues(alpha: .25), blurRadius: size * .08)],
              ),
              child: ClipOval(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Image.asset(
                    assetFor(mood),
                    key: ValueKey(assetFor(mood)),
                    width: face,
                    height: face,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.35),
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Image.asset('$dir/neutral.jpg', fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// State treatments around the photo (drawn outside the face).
class _StatePainter extends CustomPainter {
  _StatePainter({required this.mood, required this.t, required this.level, required this.color});

  final AskodoxCompanionMood mood;
  final double t;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    switch (mood) {
      case AskodoxCompanionMood.listening:
      case AskodoxCompanionMood.understanding:
        for (var i = 0; i < 2; i++) {
          final p = (t + i * .5) % 1;
          canvas.drawCircle(
              c,
              r * (.86 + .14 * p) + r * .06 * level,
              Paint()
                ..color = color.withValues(alpha: .4 * (1 - p))
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3);
        }
      case AskodoxCompanionMood.thinking:
      case AskodoxCompanionMood.help:
        for (var i = 0; i < 3; i++) {
          final a = (t + i / 3) * 2 * math.pi;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * .95, r * .045, Paint()..color = color);
        }
      case AskodoxCompanionMood.speaking:
        final pulse = math.max(level, (math.sin(t * 4 * math.pi) + 1) / 2);
        canvas.drawCircle(
            c,
            r * (.9 + .08 * pulse),
            Paint()
              ..color = color.withValues(alpha: .35)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4);
      case AskodoxCompanionMood.success:
      case AskodoxCompanionMood.greeting:
      case AskodoxCompanionMood.explaining:
      case AskodoxCompanionMood.suggesting:
      case AskodoxCompanionMood.guiding:
        final glow = (math.sin(t * 2 * math.pi) + 1) / 2;
        canvas.drawCircle(c, r * .98, Paint()..color = color.withValues(alpha: .10 + .10 * glow));
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_StatePainter old) =>
      old.mood != mood || old.t != t || old.level != level || old.color != color;
}
