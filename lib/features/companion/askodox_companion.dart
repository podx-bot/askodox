import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companion_3d.dart';
import 'companion_avatar_packs.dart';
import 'companion_human.dart';
import 'companion_voice.dart';

/// What the ASKODOX friend is doing right now. Driven by the SAME chat /
/// voice / results state as the rest of the app -- the companion is a view
/// of the one conversation, never a second workflow.
///
/// * understanding -- reading what was sent (voice being transcribed, a
///   photo / video / document being analyzed);
/// * suggesting -- ASKODOX asked for the one detail it still needs;
/// * explaining -- real options are on screen (it turns to them);
/// * guiding -- a real action (send request / connect) is in flight;
/// * help -- something failed; recovery is offered.
enum AskodoxCompanionMood {
  idle,
  greeting,
  listening,
  understanding,
  thinking,
  speaking,
  suggesting,
  explaining,
  guiding,
  success,
  help,
}

/// How the friend looks. The ASKODOX robot is the default brand look; other
/// looks are neutral (no gender is ever assumed). New looks/meshes plug into
/// [AskodoxMesh] without touching the chat or actions.
enum AskodoxCompanionLook { robot, friendlyFace, simpleOrb }

class AskodoxCompanionSettings {
  const AskodoxCompanionSettings({
    this.look = AskodoxCompanionLook.robot,
    this.animate = true,
    this.render3d = true,
    this.enabled = true,
    this.companion = automatic,
  });

  static const automatic = 'auto';
  static const robotLite = 'robot';

  /// Which companion: [automatic] (the persona follows what ASKODOX is
  /// helping with), an [AskodoxPersona] name (human 3D), or [robotLite].
  final String companion;

  AskodoxPersona? get persona => AskodoxPersona.values.where((p) => p.name == companion).firstOrNull;

  /// Off = no friend at all (a plain mic button and text status instead).
  final bool enabled;

  final AskodoxCompanionLook look;

  /// Off = a still image (battery saver / low-end phones / motion comfort).
  final bool animate;

  /// The real-time 3D friend (companion_3d.dart). Off = the flat 2D friend
  /// (also used automatically when the phone asks for reduced motion).
  final bool render3d;

  Map<String, Object?> toJson() =>
      {'look': look.name, 'animate': animate, 'render3d': render3d, 'enabled': enabled, 'companion': companion};

  static AskodoxCompanionSettings fromJson(Map<String, Object?> json) => AskodoxCompanionSettings(
        look: AskodoxCompanionLook.values.where((l) => l.name == json['look']).firstOrNull ?? AskodoxCompanionLook.robot,
        animate: json['animate'] != false,
        render3d: json['render3d'] != false,
        enabled: json['enabled'] != false,
        companion: _validCompanion(json['companion']),
      );

  static String _validCompanion(Object? value) {
    final v = '${value ?? automatic}';
    if (v == automatic || v == robotLite || AskodoxPersona.values.any((p) => p.name == v)) return v;
    return automatic;
  }
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

  Future<void> update({AskodoxCompanionLook? look, bool? animate, bool? render3d, bool? enabled, String? companion}) async {
    // An explicit choice always applies (a session step-down never hides it).
    if (companion != null || render3d == true) AskodoxCompanionPerformance.reset();
    state = AskodoxCompanionSettings(
        look: look ?? state.look,
        animate: animate ?? state.animate,
        render3d: render3d ?? state.render3d,
        enabled: enabled ?? state.enabled,
        companion: companion == null ? state.companion : AskodoxCompanionSettings._validCompanion(companion));
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final askodoxCompanionSettingsProvider =
    StateNotifierProvider<AskodoxCompanionSettingsController, AskodoxCompanionSettings>(
  (ref) => AskodoxCompanionSettingsController(),
);

/// What the ASKODOX brain last decided the conversation is about (its
/// generic domain). Automatic mode dresses the companion for it; behaviour
/// (moods, gestures, lip-sync) is the same for every persona.
final askodoxCompanionDomainProvider = StateProvider<String?>((ref) => null);

/// One short, friendly line for the mood (never a lecture), in the
/// conversation language ([lang] wins over [telugu]; Hindi lines avoid
/// gendered first-person verbs -- the companion never assumes a gender).
/// [subject] is what ASKODOX understood (only used when it asks for more).
String askodoxCompanionLine(AskodoxCompanionMood mood,
    {required bool telugu, int results = 0, String? lang, String? subject}) {
  final code = lang ?? (telugu ? 'te' : 'en');
  final about = (subject ?? '').trim();
  final plural = results == 1 ? '' : 's';
  final lines = switch (code) {
    'te' => {
        AskodoxCompanionMood.greeting: 'నమస్తే! మీకు ఏం కావాలో చెప్పండి.',
        AskodoxCompanionMood.listening: 'వింటున్నాను…',
        AskodoxCompanionMood.understanding: 'మీరు పంపింది చదువుతున్నాను…',
        AskodoxCompanionMood.thinking: 'వెతుకుతున్నాను…',
        AskodoxCompanionMood.speaking: 'చెబుతున్నాను…',
        AskodoxCompanionMood.suggesting: about.isEmpty
            ? 'ఇంకో వివరం చెబితే వెతుకుతాను.'
            : '"$about" అర్థమైంది. ఇంకో వివరం చెబితే వెతుకుతాను.',
        AskodoxCompanionMood.explaining:
            results > 0 ? '$results ఎంపికలు దొరికాయి — ఒకటి ఎంచుకోండి' : 'ఇదిగో వివరాలు',
        AskodoxCompanionMood.guiding: 'మీ అభ్యర్థన పంపుతున్నాను…',
        AskodoxCompanionMood.success:
            results > 0 ? '$results ఎంపికలు దొరికాయి' : 'పూర్తయింది! అప్‌డేట్స్‌లో తెలియజేస్తాను.',
        AskodoxCompanionMood.help: 'చిన్న సమస్య. మళ్లీ ప్రయత్నిద్దాం.',
        AskodoxCompanionMood.idle: 'సిద్ధంగా ఉన్నాను',
      },
    'hi' => {
        AskodoxCompanionMood.greeting: 'नमस्ते! बताइए, आपको क्या चाहिए।',
        AskodoxCompanionMood.listening: 'बोलिए…',
        AskodoxCompanionMood.understanding: 'आपका भेजा हुआ पढ़ा जा रहा है…',
        AskodoxCompanionMood.thinking: 'असली विकल्प खोजे जा रहे हैं…',
        AskodoxCompanionMood.speaking: 'जवाब…',
        AskodoxCompanionMood.suggesting: about.isEmpty
            ? 'एक और जानकारी दीजिए, फिर खोज शुरू होगी।'
            : '"$about" समझ आ गया। एक और जानकारी दीजिए, फिर खोज शुरू होगी।',
        AskodoxCompanionMood.explaining: results > 0 ? '$results विकल्प मिले — एक चुनें' : 'यह रहा जो मिला',
        AskodoxCompanionMood.guiding: 'आपका अनुरोध भेजा जा रहा है…',
        AskodoxCompanionMood.success: results > 0 ? '$results विकल्प मिले' : 'हो गया! अपडेट्स में बताया जाएगा।',
        AskodoxCompanionMood.help: 'कुछ गड़बड़ हुई। फिर कोशिश करें।',
        AskodoxCompanionMood.idle: 'तैयार',
      },
    _ => {
        AskodoxCompanionMood.greeting: 'Hi! Tell me what you need.',
        AskodoxCompanionMood.listening: 'Listening…',
        AskodoxCompanionMood.understanding: 'Reading what you sent…',
        AskodoxCompanionMood.thinking: 'Finding real options…',
        AskodoxCompanionMood.speaking: 'Speaking…',
        AskodoxCompanionMood.suggesting: about.isEmpty
            ? 'One more detail and I can search.'
            : 'Got it: "$about". One more detail and I can search.',
        AskodoxCompanionMood.explaining:
            results > 0 ? 'Found $results option$plural — pick one to continue' : 'Here is what I found',
        AskodoxCompanionMood.guiding: 'Sending your request…',
        AskodoxCompanionMood.success:
            results > 0 ? 'Found $results option$plural' : 'Done! I’ll keep you posted in Updates.',
        AskodoxCompanionMood.help: 'Something went wrong. Let’s try again.',
        AskodoxCompanionMood.idle: 'Ready',
      },
  };
  return lines[mood]!;
}

/// Session-wide guard for low-end phones: when real frames of the 3D friend
/// are too slow, the friend drops to the light 2D drawing for the rest of
/// the session (the user's 3D setting is not changed).
class AskodoxCompanionPerformance {
  /// 0 = human 3D allowed, 1 = robot lite, 2 = flat 2D (this session only).
  static int level = 0;

  static bool get lite => level >= 2;
  static set lite(bool value) => level = value ? 2 : 0;

  /// Step down only when the MEDIAN frame is slower than ~30 fps.
  static const jankMicros = 34000;

  /// Frames ignored after the companion starts animating (shader warm-up,
  /// first layout) -- they are slow on every phone and prove nothing.
  static const warmupFrames = 30;

  static bool judge(List<int> frameMicros) {
    if (frameMicros.length < warmupFrames + 60) return false;
    final sorted = frameMicros.sublist(warmupFrames)..sort();
    return sorted[sorted.length ~/ 2] > jankMicros;
  }

  /// The user picked a companion: give 3D a fresh chance this session.
  static void reset() => level = 0;
}

/// Which renderer the companion actually uses right now.
enum AskodoxCompanionRender { human3d, robot3d, flat2d, off }

/// The ASKODOX friend. By default a human-like 3D companion (persona chosen
/// in Profile or Automatic), with expressions, gestures, blinking, gaze,
/// mic-reactive listening and lip-synced speaking -- all driven by the one
/// ASKODOX conversation state. Fallbacks, in order: the lightweight robot
/// (Lite mode: chosen, slow phone, or a 3D failure), the flat 2D friend
/// (3D off, reduced motion, very slow phone), and a plain mic button
/// (friend off). Tapping it talks to ASKODOX.
class AskodoxCompanion extends ConsumerStatefulWidget {
  const AskodoxCompanion({super.key, this.mood = AskodoxCompanionMood.idle, this.size = 112, this.onTap});

  final AskodoxCompanionMood mood;
  final double size;
  final VoidCallback? onTap;

  @override
  ConsumerState<AskodoxCompanion> createState() => _AskodoxCompanionState();
}

/// Meshes are built once per look/persona and shared by every companion on
/// screen; at most a few are kept (memory-safe).
class _MeshCache {
  static final _items = <String, AskodoxMesh>{};

  static AskodoxMesh get(String key, AskodoxMesh Function() build) {
    final hit = _items.remove(key);
    if (hit != null) return _items[key] = hit; // most recently used last
    final mesh = build();
    _items[key] = mesh;
    while (_items.length > 4) {
      _items.remove(_items.keys.first);
    }
    return mesh;
  }
}

class _AskodoxCompanionState extends ConsumerState<AskodoxCompanion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  final _random = math.Random();
  Timer? _blinkTimer;
  double _blink = 0;
  Offset _gaze = Offset.zero;
  final List<int> _frames = [];
  bool _watchingFrames = false;
  bool _humanFailed = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleBlink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blinkTimer?.cancel();
    _stopFrameWatch();
    _clock.dispose();
    super.dispose();
  }

  /// App in the background: no timers, no animation, no frame watching.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    if (paused == _paused) return;
    _paused = paused;
    if (paused) {
      _blinkTimer?.cancel();
      _clock.stop();
      _stopFrameWatch();
    } else {
      _scheduleBlink();
      if (mounted) setState(() {});
    }
  }

  /// Natural blinks every 2.5-6 s (and an occasional glance), cheap enough
  /// to run even while the friend is otherwise still.
  void _scheduleBlink() {
    _blinkTimer?.cancel();
    if (_paused) return;
    _blinkTimer = Timer(Duration(milliseconds: 2500 + _random.nextInt(3500)), () {
      if (!mounted || _paused) return;
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
    if (_frames.length > 150) _frames.removeRange(AskodoxCompanionPerformance.warmupFrames, _frames.length - 120);
    if (AskodoxCompanionPerformance.level < 2 && AskodoxCompanionPerformance.judge(_frames)) {
      // Too slow on this phone: step down one level (human -> robot lite ->
      // flat) for this session; the user's choice is kept for next time.
      AskodoxCompanionPerformance.level++;
      _frames.clear();
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

  AskodoxCompanionMood? _burstMood;

  void _syncAnimation(bool animate, bool is3d) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Continuous motion only while ASKODOX is actively working (listening,
    // thinking, speaking). Guiding toward results and happy confirmation are
    // a short gesture burst that then settles; at rest it is a still image
    // (battery friendly, never distracting) that still blinks.
    const continuous = {
      AskodoxCompanionMood.listening,
      AskodoxCompanionMood.understanding,
      AskodoxCompanionMood.thinking,
      AskodoxCompanionMood.speaking,
      AskodoxCompanionMood.guiding,
    };
    const burst = {
      AskodoxCompanionMood.suggesting,
      AskodoxCompanionMood.explaining,
      AskodoxCompanionMood.success,
    };
    final allowed = animate && !reduceMotion && !_paused;
    if (allowed && continuous.contains(widget.mood)) {
      _burstMood = null;
      if (!_clock.isAnimating) _clock.repeat();
    } else if (allowed && burst.contains(widget.mood)) {
      if (_burstMood != widget.mood) {
        _burstMood = widget.mood;
        _clock
          ..stop()
          ..value = 0
          ..repeat(count: 2);
      }
    } else {
      if (!burst.contains(widget.mood)) _burstMood = null;
      if (_clock.isAnimating) _clock.stop();
    }
    if (allowed && _clock.isAnimating && is3d && AskodoxCompanionPerformance.level < 2) {
      _startFrameWatch();
    } else {
      _stopFrameWatch();
    }
  }

  AskodoxMesh _robotMesh(AskodoxCompanionLook look) {
    final accent = _CompanionPainter(mood: widget.mood, look: look, t: 0)._accent;
    return _MeshCache.get('robot:${look.name}:${accent.toARGB32()}', () => AskodoxMesh.forLook(look, accent));
  }

  AskodoxMesh _humanMesh(AskodoxPersona persona) {
    // A downloaded avatar pack (same rig) wins once it is ready; until then
    // (or without one) the procedural rig renders instantly.
    final pack = AskodoxAvatarPacks.baseUrl.isEmpty ? null : ref.watch(askodoxAvatarPackProvider(persona)).valueOrNull;
    return pack ?? _MeshCache.get('human:${persona.name}', () => AskodoxHumanRig.build(AskodoxHumanStyle.of(persona)));
  }

  AskodoxCompanionSignals _signals(AskodoxCompanionVoice voice) => AskodoxCompanionSignals(
        micLevel: widget.mood == AskodoxCompanionMood.listening ? voice.micLevel : 0,
        mouthOpen: widget.mood == AskodoxCompanionMood.speaking && voice.speaking ? voice.mouthOpenness() : null,
        blink: _blink,
        gaze: _gaze,
      );

  AskodoxCompanionRender _renderFor(AskodoxCompanionSettings settings, bool reduceMotion) {
    if (!settings.enabled) return AskodoxCompanionRender.off;
    if (!settings.render3d || reduceMotion || AskodoxCompanionPerformance.level >= 2) {
      return AskodoxCompanionRender.flat2d;
    }
    if (settings.companion == AskodoxCompanionSettings.robotLite ||
        AskodoxCompanionPerformance.level == 1 ||
        _humanFailed) {
      return AskodoxCompanionRender.robot3d;
    }
    return AskodoxCompanionRender.human3d;
  }

  void _humanError() {
    if (_humanFailed) return;
    _humanFailed = true;
    // Never paint-time setState: switch to the robot on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(askodoxCompanionSettingsProvider);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final render = _renderFor(settings, reduceMotion);
    if (render == AskodoxCompanionRender.off) {
      _syncAnimation(false, false);
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
    _syncAnimation(settings.animate, render != AskodoxCompanionRender.flat2d);
    final voice = ref.watch(askodoxCompanionVoiceProvider);
    final persona = render == AskodoxCompanionRender.human3d
        ? (settings.persona ?? askodoxPersonaForDomain(ref.watch(askodoxCompanionDomainProvider)))
        : null;
    final human = persona == null ? null : _humanMesh(persona);
    final robot = render == AskodoxCompanionRender.robot3d ? _robotMesh(settings.look) : null;
    return Semantics(
      label: 'ASKODOX ${persona == null ? '' : '${askodoxPersonaLabel(persona)} '}${widget.mood.name}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(
              key: ValueKey(switch (render) {
                AskodoxCompanionRender.human3d => 'askodoxCompanionHuman3d',
                AskodoxCompanionRender.robot3d => 'askodoxCompanion3d',
                _ => 'askodoxCompanion2d',
              }),
              painter: switch (render) {
                AskodoxCompanionRender.human3d => AskodoxHuman3dPainter(
                    mesh: human!, mood: widget.mood, t: _clock.value, signals: _signals(voice), onError: _humanError),
                AskodoxCompanionRender.robot3d =>
                  AskodoxCompanion3dPainter(mesh: robot!, mood: widget.mood, t: _clock.value, signals: _signals(voice)),
                _ => _CompanionPainter(mood: widget.mood, look: settings.look, t: _clock.value, blinkAmount: _blink),
              },
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
        AskodoxCompanionMood.listening || AskodoxCompanionMood.understanding => const Color(0xFF1FA2FF),
        AskodoxCompanionMood.speaking || AskodoxCompanionMood.success || AskodoxCompanionMood.guiding =>
          const Color(0xFF1B8A3B),
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
    if (mood == AskodoxCompanionMood.thinking || mood == AskodoxCompanionMood.understanding) {
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

    // Explaining / guiding: a small pointing hand toward the results (to
    // the right); suggesting: an open palm offered below.
    if (mood == AskodoxCompanionMood.explaining || mood == AskodoxCompanionMood.guiding) {
      final hand = head + Offset(headR * 1.05 + wave * r * .04, headR * .45);
      canvas.drawCircle(hand, r * .12, Paint()..color = _accent);
    }
    if (mood == AskodoxCompanionMood.suggesting) {
      final palm = head + Offset(headR * .8, headR * .95 - wave.abs() * r * .03);
      canvas.drawOval(Rect.fromCenter(center: palm, width: r * .3, height: r * .14), Paint()..color = _accent);
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

/// The companion docked above the input for the WHOLE conversation
/// (listening, thinking, speaking, results, follow-ups, idle) -- it never
/// disappears. [showLine] is off while the voice panel already says the
/// same status.
class AskodoxCompanionBar extends StatelessWidget {
  const AskodoxCompanionBar({
    super.key,
    required this.mood,
    required this.telugu,
    this.results = 0,
    this.onTap,
    this.showLine = true,
    this.size = 64,
    this.foundLabel,
    this.lang,
    this.subject,
  });

  /// Conversation language code (te / en / hi ...); null = [telugu].
  final String? lang;

  /// What ASKODOX understood so far (shown when it asks for one more detail).
  final String? subject;

  /// "Found N options" in the conversation language when it is not te/en.
  final String? foundLabel;

  final AskodoxCompanionMood mood;
  final bool telugu;
  final int results;
  final VoidCallback? onTap;
  final bool showLine;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('askodoxCompanionBar'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(children: [
          AskodoxCompanion(mood: mood, size: size, onTap: onTap),
          const SizedBox(width: 8),
          if (showLine)
            Expanded(
              child: Text(
                mood == AskodoxCompanionMood.idle
                    ? switch (lang ?? (telugu ? 'te' : 'en')) {
                        'te' => 'ఇంకా ఏమైనా కావాలా? అడగండి.',
                        'hi' => 'और कुछ चाहिए? बस पूछिए।',
                        _ => 'Anything else? Just ask.',
                      }
                    : (foundLabel != null && results > 0 && mood == AskodoxCompanionMood.explaining)
                        ? foundLabel!
                        : askodoxCompanionLine(mood, telugu: telugu, results: results, lang: lang, subject: subject),
                key: const Key('askodoxCompanionLine'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF10204A), fontWeight: FontWeight.w700),
              ),
            ),
        ]),
      );
}
