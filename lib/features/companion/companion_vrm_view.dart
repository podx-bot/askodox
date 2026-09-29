import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'askodox_companion.dart';
import 'companion_voice.dart';
import 'companion_vrm_engine.dart';

/// Which VRM model the Human HD companion loads. Default: the stand-in
/// "Seed-san" (VirtualCast, Inc., VRM Public License 1.0), downloaded at
/// runtime and cached by the WebView -- NOT the final ASKODOX character.
/// A VRoid export of our own character replaces it with
/// `--dart-define=ASKODOX_VRM_MODEL_URL=https://.../askodox.vrm`.
const askodoxVrmModelUrl = String.fromEnvironment(
  'ASKODOX_VRM_MODEL_URL',
  defaultValue: AskodoxCompanionEngineLab.standInUrl,
);

/// Builds the Human HD view; replaced in tests (no WebView there).
typedef AskodoxVrmViewBuilder = Widget Function({
  required AskodoxCompanionMood mood,
  required double size,
  required Widget fallback,
  required void Function(String reason) onFallback,
});

final askodoxVrmViewBuilderProvider = Provider<AskodoxVrmViewBuilder>(
  (ref) => ({required mood, required size, required fallback, required onFallback}) =>
      AskodoxVrmCompanionView(mood: mood, size: size, fallback: fallback, onFallback: onFallback),
);

/// A real VRM human (three.js + three-vrm in the system WebView), driven by
/// the SAME conversation mood, lip-sync and mic level as every companion.
/// Until the model is loaded the light procedural companion ([fallback])
/// shows; an engine error, a load timeout or slow frames (< 18 fps median)
/// hand over to [fallback] for the rest of the session.
class AskodoxVrmCompanionView extends ConsumerStatefulWidget {
  const AskodoxVrmCompanionView({
    super.key,
    required this.mood,
    required this.size,
    required this.fallback,
    required this.onFallback,
  });

  final AskodoxCompanionMood mood;
  final double size;
  final Widget fallback;
  final void Function(String reason) onFallback;

  @override
  ConsumerState<AskodoxVrmCompanionView> createState() => _AskodoxVrmCompanionViewState();
}

class _AskodoxVrmCompanionViewState extends ConsumerState<AskodoxVrmCompanionView> with WidgetsBindingObserver {
  late final AskodoxVrmEngineController _engine = AskodoxVrmEngineController(onStats: _onStats);
  final _fps = <int>[];
  bool _loaded = false;
  bool _gaveUp = false;
  Timer? _timeout;
  Timer? _lips;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeout = Timer(const Duration(seconds: 25), () => _giveUp('timeout'));
    unawaited(_engine.start().then((_) => _engine.load(askodoxVrmModelUrl)).catchError((Object _) => _giveUp('error')));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    _lips?.cancel();
    unawaited(_engine.pause());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    state == AppLifecycleState.resumed ? _engine.resume() : _engine.pause();
  }

  void _giveUp(String reason) {
    if (_gaveUp || !mounted) return;
    _gaveUp = true;
    widget.onFallback(reason);
  }

  void _onStats(Map<String, Object?> data) {
    switch (data['event']) {
      case 'loaded':
        _timeout?.cancel();
        if (mounted) setState(() => _loaded = true);
        unawaited(_engine.setMood(_mood));
      case 'error':
        _giveUp('error');
      case 'stats':
        final fps = (data['fps'] as num?)?.toInt();
        if (fps == null || !_loaded) return;
        _fps.add(fps);
        if (_fps.length >= 5) {
          final sorted = [..._fps.skip(_fps.length - 5)]..sort();
          if (sorted[2] < 18) _giveUp('slow');
        }
    }
  }

  AskodoxCompanionMood get _mood => widget.mood;

  @override
  void didUpdateWidget(covariant AskodoxVrmCompanionView old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      unawaited(_engine.setMood(widget.mood));
      _syncLips();
    }
  }

  /// Lip-sync and mic level come from the same voice hooks as the other
  /// companions (device TTS ranges / Sarvam audio position, mic meter).
  void _syncLips() {
    _lips?.cancel();
    if (widget.mood != AskodoxCompanionMood.speaking && widget.mood != AskodoxCompanionMood.listening) {
      unawaited(_engine.setMouth('aa', 0));
      return;
    }
    _lips = Timer.periodic(const Duration(milliseconds: 90), (_) {
      final voice = ref.read(askodoxCompanionVoiceProvider);
      if (widget.mood == AskodoxCompanionMood.speaking) {
        unawaited(_engine.setMouth('aa', voice.speaking ? voice.mouthOpenness() : 0));
      } else {
        unawaited(_engine.setMic(voice.micLevel));
      }
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        key: const ValueKey('askodoxCompanionVrm'),
        dimension: widget.size,
        child: Stack(fit: StackFit.expand, children: [
          if (!_loaded) widget.fallback,
          // Transparent until the model is in; then it covers the fallback.
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.size / 5),
            child: WebViewWidget(controller: _engine.web),
          ),
        ]),
      );
}
