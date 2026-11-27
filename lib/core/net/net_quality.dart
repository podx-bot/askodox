import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Owner 2026-11-23 (ASKODOX Lite step 2): where 4G is weak or the net is slow the app turns to "Lite mode" by itself --
/// the reply text comes at once and its voice plays after it has downloaded, result photos wait for a tap -- and goes
/// back to normal by itself when the net is good again. The payment voice never depends on this (it speaks from the
/// phone, see `PaymentVoicePack`).
enum AskodoxNet { good, slow, offline }

/// A reading slower than this = slow net.
const askodoxNetSlowMs = 2500;

/// A reading faster than this counts towards "good again".
const askodoxNetGoodMs = 1500;

/// Good readings in a row needed to leave Lite mode (one lucky answer on a weak signal is not "good").
const askodoxNetGoodRun = 2;

/// The next state after ONE reading: [ms] = how long a tiny request took, null = it failed / timed out.
/// [goodRun] = fast readings in a row so far (this one not counted). Pure.
({AskodoxNet state, int goodRun}) askodoxNetAfter(AskodoxNet now, int goodRun, int? ms) {
  if (ms == null) return (state: AskodoxNet.offline, goodRun: 0);
  if (ms >= askodoxNetSlowMs) return (state: AskodoxNet.slow, goodRun: 0);
  if (ms < askodoxNetGoodMs) {
    final run = goodRun + 1;
    if (now == AskodoxNet.good || run >= askodoxNetGoodRun) return (state: AskodoxNet.good, goodRun: run);
    // The request got through, so the phone is not offline any more -- but not good yet either.
    return (state: AskodoxNet.slow, goodRun: run);
  }
  // In between: good stays good, Lite stays Lite (an answer came, so never "offline").
  return (state: now == AskodoxNet.offline ? AskodoxNet.slow : now, goodRun: 0);
}

/// The app's one net watcher. Off until [start] (only `main()` starts it, so tests and previews never probe).
class AskodoxNetQuality {
  AskodoxNetQuality._();
  static final AskodoxNetQuality instance = AskodoxNetQuality._();

  final ValueNotifier<AskodoxNet> state = ValueNotifier(AskodoxNet.good);
  bool get lite => state.value != AskodoxNet.good;

  Future<int?> Function()? _probe;
  Timer? _timer;
  int _goodRun = 0;
  bool _busy = false;

  /// Starts watching with [probe] (ms of one tiny request, null on failure).
  void start(Future<int?> Function() probe) {
    _probe = probe;
    _timer?.cancel();
    // Slow / offline is re-checked often (to leave Lite mode soon); good net only now and then.
    _timer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (lite || t.tick % 6 == 0) unawaited(check());
    });
    unawaited(check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _probe = null;
  }

  /// One reading now (also called when a question is sent and when a request fails).
  Future<void> check() async {
    final probe = _probe;
    if (probe == null || _busy) return;
    _busy = true;
    try {
      int? ms;
      try {
        ms = await probe();
      } catch (_) {
        ms = null;
      }
      take(ms);
    } finally {
      _busy = false;
    }
  }

  /// Applies one reading (tests call this directly).
  void take(int? ms) {
    final next = askodoxNetAfter(state.value, _goodRun, ms);
    _goodRun = next.goodRun;
    state.value = next.state;
  }

  /// Back to "good" with nothing running (tests).
  void reset() {
    stop();
    _goodRun = 0;
    state.value = AskodoxNet.good;
  }
}

/// The real probe: the server's tiny `/health` answer, 6 s limit.
Future<int?> Function() askodoxHealthProbe(Uri base, {http.Client? client}) => () async {
      final watch = Stopwatch()..start();
      final c = client ?? http.Client();
      try {
        final r = await c.get(base.resolve('/health')).timeout(const Duration(seconds: 6));
        return r.statusCode < 500 ? watch.elapsedMilliseconds : null;
      } catch (_) {
        return null;
      } finally {
        if (client == null) c.close();
      }
    };

/// The strip above the chat while Lite mode is on (nothing when the net is good).
class AskodoxLiteBanner extends StatelessWidget {
  const AskodoxLiteBanner({super.key, required this.te});
  final bool te;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AskodoxNet>(
        valueListenable: AskodoxNetQuality.instance.state,
        builder: (context, net, _) {
          if (net == AskodoxNet.good) return const SizedBox.shrink();
          final off = net == AskodoxNet.offline;
          final text = off
              ? (te
                  ? 'Net లేదు · Lite mode — payment sound, బిల్లు ఫోన్‌లోనే పనిచేస్తాయి'
                  : 'No internet · Lite mode — payment sound and bills work on the phone')
              : (te
                  ? 'Net slow · Lite mode — ముందు text, voice తర్వాత వస్తుంది'
                  : 'Slow internet · Lite mode — text first, the voice follows');
          return Semantics(
            liveRegion: true,
            child: Container(
              key: Key('askodoxLiteBanner-${net.name}'),
              width: double.infinity,
              color: const Color(0xFF402804),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(children: [
                Icon(off ? Icons.wifi_off_rounded : Icons.network_check_rounded, size: 18, color: const Color(0xFFFEA56F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      style: const TextStyle(fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w700, color: Color(0xFFFEA56F))),
                ),
              ]),
            ),
          );
        },
      );
}

/// A result photo: loads by itself on a good net; in Lite mode it waits for a tap (saves data, cards come at once).
class AskodoxLiteImage extends StatefulWidget {
  const AskodoxLiteImage(this.url, {super.key, required this.fallback, this.fit = BoxFit.cover});
  final String url;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<AskodoxLiteImage> createState() => _AskodoxLiteImageState();
}

class _AskodoxLiteImageState extends State<AskodoxLiteImage> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AskodoxNet>(
        valueListenable: AskodoxNetQuality.instance.state,
        builder: (context, net, _) {
          if (net == AskodoxNet.good || _asked) {
            return Image.network(widget.url, fit: widget.fit, errorBuilder: (_, __, ___) => widget.fallback);
          }
          return InkWell(
            key: const Key('askodoxLitePhotoTap'),
            onTap: () => setState(() => _asked = true),
            child: Stack(fit: StackFit.expand, children: [
              widget.fallback,
              const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.download_for_offline_rounded, size: 16, color: Color(0xFFADAEFD)),
                ),
              ),
            ]),
          );
        },
      );
}
