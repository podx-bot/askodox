import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the ASKODOX friend is doing right now. Driven by the SAME chat /
/// voice / results state as the rest of the app -- the companion is a view
/// of the one conversation, never a second workflow.
enum AskodoxCompanionMood { idle, greeting, listening, thinking, speaking, explaining, success, help }

/// How the friend looks. The ASKODOX robot is the default brand look; other
/// looks are neutral (no gender is ever assumed). Richer/3D renderers can
/// be added later behind [askodoxCompanion3dEnabled] without touching the
/// chat or actions.
enum AskodoxCompanionLook { robot, friendlyFace, simpleOrb }

/// 3D companion renderer switch (off until a lightweight 3D asset pipeline
/// ships; low-end phones always keep the 2D look).
const askodoxCompanion3dEnabled = bool.fromEnvironment('ASKODOX_COMPANION_3D');

class AskodoxCompanionSettings {
  const AskodoxCompanionSettings({this.look = AskodoxCompanionLook.robot, this.animate = true});

  final AskodoxCompanionLook look;

  /// Off = a still image (battery saver / low-end phones / motion comfort).
  final bool animate;

  Map<String, Object?> toJson() => {'look': look.name, 'animate': animate};

  static AskodoxCompanionSettings fromJson(Map<String, Object?> json) => AskodoxCompanionSettings(
        look: AskodoxCompanionLook.values.where((l) => l.name == json['look']).firstOrNull ?? AskodoxCompanionLook.robot,
        animate: json['animate'] != false,
      );
}

class AskodoxCompanionSettingsController extends StateNotifier<AskodoxCompanionSettings> {
  AskodoxCompanionSettingsController() : super(const AskodoxCompanionSettings()) {
    _load();
  }

  static const _key = 'askodox.companion.v1';

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null && mounted) {
        state = AskodoxCompanionSettings.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
      }
    } catch (_) {}
  }

  Future<void> update({AskodoxCompanionLook? look, bool? animate}) async {
    state = AskodoxCompanionSettings(look: look ?? state.look, animate: animate ?? state.animate);
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final askodoxCompanionSettingsProvider =
    StateNotifierProvider<AskodoxCompanionSettingsController, AskodoxCompanionSettings>(
  (ref) => AskodoxCompanionSettingsController(),
);

/// One short, friendly line for the mood (never a lecture).
String askodoxCompanionLine(AskodoxCompanionMood mood, {required bool telugu, int results = 0}) => switch (mood) {
      AskodoxCompanionMood.greeting => telugu ? 'నమస్తే! మీకు ఏం కావాలో చెప్పండి.' : 'Hi! Tell me what you need.',
      AskodoxCompanionMood.listening => telugu ? 'వింటున్నాను…' : 'Listening…',
      AskodoxCompanionMood.thinking => telugu ? 'వెతుకుతున్నాను…' : 'Finding real options…',
      AskodoxCompanionMood.speaking => telugu ? 'చెబుతున్నాను…' : 'Speaking…',
      AskodoxCompanionMood.explaining => telugu ? 'ఇదిగో వివరాలు' : 'Here is what I found',
      AskodoxCompanionMood.success =>
        results > 0 ? (telugu ? '$results ఎంపికలు దొరికాయి' : 'Found $results option${results == 1 ? '' : 's'}') : (telugu ? 'పూర్తయింది' : 'Done'),
      AskodoxCompanionMood.help => telugu ? 'చిన్న సమస్య. మళ్లీ ప్రయత్నిద్దాం.' : 'Something went wrong. Let’s try again.',
      AskodoxCompanionMood.idle => telugu ? 'సిద్ధంగా ఉన్నాను' : 'Ready',
    };

/// The ASKODOX friend: a lightweight animated 2D companion (no assets, no
/// 3D engine -- safe on low-end phones). Tapping it talks to ASKODOX.
class AskodoxCompanion extends ConsumerStatefulWidget {
  const AskodoxCompanion({super.key, this.mood = AskodoxCompanionMood.idle, this.size = 112, this.onTap});

  final AskodoxCompanionMood mood;
  final double size;
  final VoidCallback? onTap;

  @override
  ConsumerState<AskodoxCompanion> createState() => _AskodoxCompanionState();
}

class _AskodoxCompanionState extends ConsumerState<AskodoxCompanion> with SingleTickerProviderStateMixin {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _syncAnimation(bool animate) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Motion only while ASKODOX is actively doing something; at rest it is
    // a still image (battery friendly, never distracting).
    const active = {
      AskodoxCompanionMood.listening,
      AskodoxCompanionMood.thinking,
      AskodoxCompanionMood.speaking,
      AskodoxCompanionMood.explaining,
    };
    if (animate && !reduceMotion && active.contains(widget.mood)) {
      if (!_clock.isAnimating) _clock.repeat();
    } else if (_clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(askodoxCompanionSettingsProvider);
    _syncAnimation(settings.animate);
    return Semantics(
      label: 'ASKODOX ${widget.mood.name}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              painter: _CompanionPainter(mood: widget.mood, look: settings.look, t: _clock.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionPainter extends CustomPainter {
  _CompanionPainter({required this.mood, required this.look, required this.t});

  final AskodoxCompanionMood mood;
  final AskodoxCompanionLook look;
  final double t;

  static const _violet = Color(0xFF713BFF);
  static const _blue = Color(0xFF1769FF);

  Color get _accent => switch (mood) {
        AskodoxCompanionMood.listening => const Color(0xFF1FA2FF),
        AskodoxCompanionMood.speaking || AskodoxCompanionMood.success => const Color(0xFF1B8A3B),
        AskodoxCompanionMood.help => const Color(0xFFE08A00),
        _ => _violet,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final wave = math.sin(t * 2 * math.pi);

    // Listening: soft rings; thinking: orbiting dots.
    if (mood == AskodoxCompanionMood.listening) {
      for (var i = 0; i < 2; i++) {
        final p = (t + i * .5) % 1;
        canvas.drawCircle(c, r * (.62 + .38 * p),
            Paint()..color = _accent.withValues(alpha: .35 * (1 - p))..style = PaintingStyle.stroke..strokeWidth = 3);
      }
    }
    if (mood == AskodoxCompanionMood.thinking) {
      for (var i = 0; i < 3; i++) {
        final a = (t + i / 3) * 2 * math.pi;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * .9, r * .06, Paint()..color = _accent);
      }
    }

    final bob = (mood == AskodoxCompanionMood.idle || mood == AskodoxCompanionMood.greeting) ? wave * r * .03 : 0.0;
    final head = c + Offset(0, bob);
    final headR = r * .62;
    canvas.drawCircle(
      head,
      headR,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, const Color(0xFFE8E1FF), _accent])
            .createShader(Rect.fromCircle(center: head, radius: headR)),
    );

    if (look == AskodoxCompanionLook.simpleOrb) {
      _mouth(canvas, head, headR, wave);
      return;
    }
    if (look == AskodoxCompanionLook.robot) {
      // Antenna + visor: the ASKODOX robot.
      final tip = head + Offset(0, -headR * 1.18);
      canvas.drawLine(head + Offset(0, -headR), tip, Paint()..color = _blue..strokeWidth = r * .05);
      canvas.drawCircle(tip, r * .07, Paint()..color = mood == AskodoxCompanionMood.help ? _accent : _blue);
      final visor = RRect.fromRectAndRadius(
          Rect.fromCenter(center: head + Offset(0, -headR * .08), width: headR * 1.35, height: headR * .62),
          Radius.circular(headR * .3));
      canvas.drawRRect(visor, Paint()..color = const Color(0xFF10204A));
    }
    // Eyes: blink now and then; happy arcs on success/greeting.
    final eyeY = head.dy - headR * .08;
    final blink = (t % 1) > .94 && mood == AskodoxCompanionMood.idle;
    final eyePaint = Paint()
      ..color = look == AskodoxCompanionLook.robot ? const Color(0xFF7FE3FF) : const Color(0xFF10204A)
      ..strokeWidth = r * .07
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final dx in [-headR * .32, headR * .32]) {
      final eye = Offset(head.dx + dx, eyeY);
      if (mood == AskodoxCompanionMood.success || mood == AskodoxCompanionMood.greeting) {
        canvas.drawArc(Rect.fromCenter(center: eye, width: r * .22, height: r * .18), math.pi, math.pi, false, eyePaint);
      } else if (blink) {
        canvas.drawLine(eye - Offset(r * .08, 0), eye + Offset(r * .08, 0), eyePaint);
      } else {
        canvas.drawCircle(eye, r * .075, eyePaint..style = PaintingStyle.fill);
        eyePaint.style = PaintingStyle.stroke;
      }
    }
    _mouth(canvas, head, headR, wave);

    // Explaining: a small pointing hand toward the results (to the right).
    if (mood == AskodoxCompanionMood.explaining) {
      final hand = head + Offset(headR * 1.05 + wave * r * .04, headR * .45);
      canvas.drawCircle(hand, r * .12, Paint()..color = _accent);
    }
  }

  void _mouth(Canvas canvas, Offset head, double headR, double wave) {
    final y = head.dy + headR * .38;
    final paint = Paint()
      ..color = const Color(0xFF10204A)
      ..strokeWidth = headR * .08
      ..strokeCap = StrokeCap.round;
    if (mood == AskodoxCompanionMood.speaking) {
      // Talking bars.
      for (var i = -1; i <= 1; i++) {
        final h = headR * (.08 + .1 * (math.sin(t * 12 + i) + 1) / 2);
        canvas.drawLine(Offset(head.dx + i * headR * .18, y - h), Offset(head.dx + i * headR * .18, y + h), paint);
      }
      return;
    }
    final smile = mood == AskodoxCompanionMood.help ? -.12 : .18;
    final path = Path()
      ..moveTo(head.dx - headR * .25, y)
      ..quadraticBezierTo(head.dx, y + headR * smile, head.dx + headR * .25, y);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_CompanionPainter old) => old.t != t || old.mood != mood || old.look != look;
}

/// Compact "friend" bar shown above the input while ASKODOX works: the
/// companion + one short line. Hidden when idle so it never takes space.
class AskodoxCompanionBar extends StatelessWidget {
  const AskodoxCompanionBar({super.key, required this.mood, required this.telugu, this.results = 0, this.onTap});

  final AskodoxCompanionMood mood;
  final bool telugu;
  final int results;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (mood == AskodoxCompanionMood.idle) return const SizedBox.shrink();
    return Padding(
      key: const Key('askodoxCompanionBar'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Row(children: [
        AskodoxCompanion(mood: mood, size: 40, onTap: onTap),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            askodoxCompanionLine(mood, telugu: telugu, results: results),
            key: const Key('askodoxCompanionLine'),
            style: const TextStyle(color: Color(0xFF10204A), fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}
