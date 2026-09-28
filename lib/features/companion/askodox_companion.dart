import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companion_3d.dart';
import 'companion_voice.dart';

/// What the ASKODOX friend is doing right now. Driven by the SAME chat /
/// voice / results state as the rest of the app -- the companion is a view
/// of the one conversation, never a second workflow.
enum AskodoxCompanionMood { idle, greeting, listening, thinking, speaking, explaining, success, help }

/// How the friend looks. The ASKODOX robot is the default brand look; other
/// looks are neutral (no gender is ever assumed). New looks/meshes plug into
/// [AskodoxMesh] without touching the chat or actions.
enum AskodoxCompanionLook { robot, friendlyFace, simpleOrb }

class AskodoxCompanionSettings {
  const AskodoxCompanionSettings(
      {this.look = AskodoxCompanionLook.robot, this.animate = true, this.render3d = true, this.enabled = true});

  /// Off = no friend at all (a plain mic button and text status instead).
  final bool enabled;

  final AskodoxCompanionLook look;

  /// Off = a still image (battery saver / low-end phones / motion comfort).
  final bool animate;

  /// The real-time 3D friend (companion_3d.dart). Off = the flat 2D friend
  /// (also used automatically when the phone asks for reduced motion).
  final bool render3d;

  Map<String, Object?> toJson() => {'look': look.name, 'animate': animate, 'render3d': render3d, 'enabled': enabled};

  static AskodoxCompanionSettings fromJson(Map<String, Object?> json) => AskodoxCompanionSettings(
        look: AskodoxCompanionLook.values.where((l) => l.name == json['look']).firstOrNull ?? AskodoxCompanionLook.robot,
        animate: json['animate'] != false,
        render3d: json['render3d'] != false,
        enabled: json['enabled'] != false,
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

  Future<void> update({AskodoxCompanionLook? look, bool? animate, bool? render3d, bool? enabled}) async {
    state = AskodoxCompanionSettings(
        look: look ?? state.look,
        animate: animate ?? state.animate,
        render3d: render3d ?? state.render3d,
        enabled: enabled ?? state.enabled);
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

/// Session-wide guard for low-end phones: when real frames of the 3D friend
/// are too slow, the friend drops to the light 2D drawing for the rest of
/// the session (the user's 3D setting is not changed).
class AskodoxCompanionPerformance {
  static bool lite = false;

  /// Frames slower than this (build+raster) count as janky.
  static const jankMicros = 24000;

  static bool judge(List<int> frameMicros) {
    if (frameMicros.length < 45) return false;
    final sorted = [...frameMicros]..sort();
    return sorted[sorted.length ~/ 2] > jankMicros;
  }
}

/// The ASKODOX friend. 3D by default (lit mesh with expressions, gestures,
/// blinking, gaze, mic-reactive listening and lip-synced speaking); the flat
/// 2D drawing is used when the user turns 3D off, the phone asks for reduced
/// motion, or real frames prove too slow. Tapping it talks to ASKODOX.
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
  final _random = math.Random();
  Timer? _blinkTimer;
  double _blink = 0;
  Offset _gaze = Offset.zero;
  final List<int> _frames = [];
  bool _watchingFrames = false;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _stopFrameWatch();
    _clock.dispose();
    super.dispose();
  }

  /// Natural blinks every 2.5-6 s (and an occasional glance), cheap enough
  /// to run even while the friend is otherwise still.
  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2500 + _random.nextInt(3500)), () {
      if (!mounted) return;
      setState(() {
        _blink = 1;
        if (_random.nextDouble() < .35) {
          _gaze = Offset(_random.nextDouble() * 1.2 - .6, _random.nextDouble() * .6 - .3);
        } else if (_random.nextDouble() < .5) {
          _gaze = Offset.zero;
        }
      });
      _blinkTimer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _blink = 0);
        _scheduleBlink();
      });
    });
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames.add(t.totalSpan.inMicroseconds);
    }
    if (_frames.length > 120) _frames.removeRange(0, _frames.length - 120);
    if (!AskodoxCompanionPerformance.lite && AskodoxCompanionPerformance.judge(_frames)) {
      AskodoxCompanionPerformance.lite = true;
      _stopFrameWatch();
      if (mounted) setState(() {});
    }
  }

  void _startFrameWatch() {
    if (_watchingFrames) return;
    _watchingFrames = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _stopFrameWatch() {
    if (!_watchingFrames) return;
    _watchingFrames = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _syncAnimation(bool animate, bool use3d) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Motion only while ASKODOX is actively doing something; at rest it is
    // a still image (battery friendly, never distracting) that still blinks.
    const active = {
      AskodoxCompanionMood.listening,
      AskodoxCompanionMood.thinking,
      AskodoxCompanionMood.speaking,
      AskodoxCompanionMood.explaining,
    };
    final run = animate && !reduceMotion && active.contains(widget.mood);
    if (run) {
      if (!_clock.isAnimating) _clock.repeat();
    } else if (_clock.isAnimating) {
      _clock.stop();
    }
    if (run && use3d && !AskodoxCompanionPerformance.lite) {
      _startFrameWatch();
    } else {
      _stopFrameWatch();
    }
  }

  AskodoxMesh? _mesh;
  (AskodoxCompanionLook, int)? _meshKey;

  AskodoxMesh _meshFor(AskodoxCompanionLook look) {
    final accent = _CompanionPainter(mood: widget.mood, look: look, t: 0)._accent;
    final key = (look, accent.toARGB32());
    if (_mesh == null || _meshKey != key) {
      _mesh = AskodoxMesh.forLook(look, accent);
      _meshKey = key;
    }
    return _mesh!;
  }

  AskodoxCompanionSignals _signals(AskodoxCompanionVoice voice) => AskodoxCompanionSignals(
        micLevel: widget.mood == AskodoxCompanionMood.listening ? voice.micLevel : 0,
        mouthOpen: widget.mood == AskodoxCompanionMood.speaking && voice.speaking ? voice.mouthOpenness() : null,
        blink: _blink,
        gaze: _gaze,
      );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(askodoxCompanionSettingsProvider);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!settings.enabled) {
      // Friend off: a plain, still mic button with the same tap action.
      return Semantics(
        label: 'ASKODOX ${widget.mood.name}',
        button: widget.onTap != null,
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox.square(
            key: const ValueKey('askodoxCompanionOff'),
            dimension: widget.size,
            child: Center(
              child: CircleAvatar(
                radius: widget.size * .32,
                backgroundColor: const Color(0xFF6C4DFF),
                child: Icon(Icons.mic_rounded, color: Colors.white, size: widget.size * .3),
              ),
            ),
          ),
        ),
      );
    }
    final use3d = settings.render3d && !reduceMotion && !AskodoxCompanionPerformance.lite;
    _syncAnimation(settings.animate, use3d);
    final voice = ref.watch(askodoxCompanionVoiceProvider);
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
              key: ValueKey(use3d ? 'askodoxCompanion3d' : 'askodoxCompanion2d'),
              painter: use3d
                  ? AskodoxCompanion3dPainter(
                      mesh: _meshFor(settings.look), mood: widget.mood, t: _clock.value, signals: _signals(voice))
                  : _CompanionPainter(mood: widget.mood, look: settings.look, t: _clock.value, blinkAmount: _blink),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionPainter extends CustomPainter {
  _CompanionPainter({required this.mood, required this.look, required this.t, this.blinkAmount = 0});

  final double blinkAmount;

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
    final blink = blinkAmount > .5 || ((t % 1) > .94 && mood == AskodoxCompanionMood.idle);
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
  bool shouldRepaint(_CompanionPainter old) =>
      old.t != t || old.mood != mood || old.look != look || old.blinkAmount != blinkAmount;
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
