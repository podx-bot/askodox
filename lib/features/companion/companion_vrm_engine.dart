import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'askodox_companion.dart';

/// The engine only knows its original eight moods; the newer states map to
/// the closest body language it has.
String askodoxVrmMood(AskodoxCompanionMood mood) => switch (mood) {
      AskodoxCompanionMood.understanding => 'thinking',
      AskodoxCompanionMood.suggesting => 'greeting',
      AskodoxCompanionMood.guiding => 'explaining',
      _ => mood.name,
    };

/// Real human avatar engine: a VRM model (VRoid Studio export) rendered by
/// three.js + @pixiv/three-vrm inside Android's system WebView (WebGL). No
/// engine binary is bundled -- the page is one ~700 KB asset
/// (`assets/companion/engine.html`), the model is downloaded lazily.
///
/// Flutter stays the brain: it pushes the mood, lip-sync viseme and mic
/// level; the page only renders. Stats (fps, worst frame, triangles, draw
/// calls, JS heap) come back for measurement and slow-phone fallback.
class AskodoxVrmEngineController {
  AskodoxVrmEngineController({this.onStats});

  final void Function(Map<String, Object?> stats)? onStats;
  late final WebViewController web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.transparent)
    ..addJavaScriptChannel('AskodoxEngineStats', onMessageReceived: (m) {
      try {
        final data = Map<String, Object?>.from(jsonDecode(m.message) as Map);
        if (data['event'] == 'ready') _ready.complete();
        onStats?.call(data);
      } catch (_) {}
    });

  final _ready = Completer<void>();

  Future<void> start() async {
    final html = await rootBundle.loadString('assets/companion/engine.html');
    await web.loadHtmlString(html, baseUrl: 'https://askodox.app/companion/');
  }

  Future<void> _js(String code) async {
    await _ready.future;
    try {
      await web.runJavaScript(code);
    } catch (_) {}
  }

  Future<void> load(String url) => _js('AskodoxEngine.load(${jsonEncode(url)})');
  Future<void> setMood(AskodoxCompanionMood mood) => _js('AskodoxEngine.setMood(${jsonEncode(askodoxVrmMood(mood))})');
  Future<void> setMouth(String viseme, double weight) =>
      _js('AskodoxEngine.setMouth(${jsonEncode(viseme)}, ${weight.clamp(0, 1)})');
  Future<void> setMic(double level) => _js('AskodoxEngine.setMic(${level.clamp(0, 1)})');
  Future<void> pause() => _js('AskodoxEngine.pause()');
  Future<void> resume() => _js('AskodoxEngine.resume()');
}

/// MEASUREMENT ONLY (not a customer feature): loads a stand-in VRM and shows
/// what the engine costs on THIS phone before we adopt it for the Smart
/// Advisor companion.
///
/// Stand-in model: "Seed-san" by VirtualCast, Inc., VRM Public License 1.0
/// (https://vrm.dev/licenses/1.0/) -- downloaded at runtime, not bundled.
class AskodoxCompanionEngineLab extends StatefulWidget {
  const AskodoxCompanionEngineLab({super.key});

  static const standInUrl =
      'https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/Seed-san/vrm/Seed-san.vrm';

  @override
  State<AskodoxCompanionEngineLab> createState() => _AskodoxCompanionEngineLabState();
}

class _AskodoxCompanionEngineLabState extends State<AskodoxCompanionEngineLab> with WidgetsBindingObserver {
  late final AskodoxVrmEngineController _engine = AskodoxVrmEngineController(onStats: _onStats);
  final _log = <String>[];
  Map<String, Object?> _stats = const {};
  final _openedAt = DateTime.now();
  AskodoxCompanionMood _mood = AskodoxCompanionMood.idle;
  Timer? _lips;
  final _fpsSamples = <int>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_engine.start().then((_) => _engine.load(AskodoxCompanionEngineLab.standInUrl)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lips?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    state == AppLifecycleState.resumed ? _engine.resume() : _engine.pause();
  }

  void _onStats(Map<String, Object?> data) {
    if (!mounted) return;
    setState(() {
      final event = data['event'];
      if (event == 'stats') {
        _stats = data;
        final fps = (data['fps'] as num?)?.toInt();
        if (fps != null) _fpsSamples.add(fps);
      } else {
        final ms = DateTime.now().difference(_openedAt).inMilliseconds;
        _log.insert(0, '+${ms}ms $event ${jsonEncode(data..remove('event'))}');
      }
    });
  }

  void _setMood(AskodoxCompanionMood mood) {
    setState(() => _mood = mood);
    _engine.setMood(mood);
    _lips?.cancel();
    if (mood == AskodoxCompanionMood.speaking) {
      // Demo lip-sync: the real app drives this from companion_voice.dart.
      var i = 0;
      const seq = ['aa', 'ih', 'ou', 'ee', 'oh', 'aa', 'oh'];
      _lips = Timer.periodic(const Duration(milliseconds: 110), (_) {
        i++;
        _engine.setMouth(seq[i % seq.length], i % 3 == 0 ? .2 : .9);
      });
    } else {
      _engine.setMouth('aa', 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avg = _fpsSamples.isEmpty ? null : _fpsSamples.reduce((a, b) => a + b) / _fpsSamples.length;
    return Scaffold(
      appBar: AppBar(title: const Text('3D engine lab (measurement)')),
      body: Column(children: [
        SizedBox(height: 320, child: WebViewWidget(controller: _engine.web)),
        Wrap(spacing: 6, children: [
          for (final m in AskodoxCompanionMood.values)
            ChoiceChip(label: Text(m.name), selected: _mood == m, onSelected: (_) => _setMood(m)),
        ]),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            key: const Key('askodoxEngineLabStats'),
            'fps ${_stats['fps'] ?? '-'} (avg ${avg?.toStringAsFixed(1) ?? '-'})  '
            'worst frame ${_stats['worstFrameMs'] ?? '-'} ms\n'
            'triangles ${_stats['triangles'] ?? '-'}  draw calls ${_stats['drawCalls'] ?? '-'}  '
            'JS heap ${_stats['jsHeapMb'] ?? '-'} MB  textures ${_stats['gpuTextures'] ?? '-'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('Stand-in model: Seed-san by VirtualCast, Inc. (VRM Public License 1.0). '
              'Measurement only -- not the ASKODOX character.', style: TextStyle(fontSize: 11)),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [for (final l in _log) Text(l)])),
      ]),
    );
  }
}
