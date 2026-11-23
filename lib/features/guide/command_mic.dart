import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voice_endpointing.dart';
import '../home/presentation/askodox_primary_home_screen.dart' show askodoxVoiceTranscriptionServiceProvider;

/// "చెప్పు" (owner 2026-11-24): the guide's second tap = a mic that takes a COMMAND. It stops by itself after
/// 2 s of quiet once you spoke (6 s if nothing was said), shows the words, and sends them after 3 s unless you
/// tap Stop or Change. No send button needed. The words go to the ASKODOX chat, which opens the page / does the job
/// (risky jobs still ask for a ✓ there).
AskodoxVoiceEndpointer askodoxCommandEndpointer() => AskodoxVoiceEndpointer(
      calibration: const Duration(milliseconds: 400),
      silenceAfterSpeech: const Duration(seconds: 2),
      noSpeechTimeout: const Duration(seconds: 6),
      maxDuration: const Duration(seconds: 45),
      minimumSpeech: const Duration(milliseconds: 500),
    );

/// Seconds before the heard words are sent by themselves.
const askodoxCommandSendAfter = 3;

enum _Phase { idle, listening, reading, counting, editing }

class AskodoxCommandMic extends ConsumerStatefulWidget {
  const AskodoxCommandMic({super.key, required this.lang, required this.onSend, this.autoStart = false});

  final String lang;
  final ValueChanged<String> onSend;

  /// Start listening as soon as it shows.
  final bool autoStart;

  @override
  ConsumerState<AskodoxCommandMic> createState() => _AskodoxCommandMicState();
}

class _AskodoxCommandMicState extends ConsumerState<AskodoxCommandMic> {
  static const _device = MethodChannel('com.askodox.app/device');
  _Phase _phase = _Phase.idle;
  Timer? _poll;
  Timer? _count;
  int _left = askodoxCommandSendAfter;
  final _words = TextEditingController();
  final _clock = Stopwatch();
  AskodoxVoiceEndpointer _ear = askodoxCommandEndpointer();
  double _level = 0;

  bool get _te => widget.lang == 'te';

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_listen()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _count?.cancel();
    if (_phase == _Phase.listening) {
      _device.invokeMethod<Object?>('cancelVoiceRecording').catchError((_) => null);
    }
    _words.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_phase == _Phase.listening || _phase == _Phase.reading) return;
    _count?.cancel();
    setState(() => _phase = _Phase.listening);
    bool? started;
    try {
      started = await _device.invokeMethod<bool>('startVoiceRecording', {'languageCode': widget.lang});
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    if (started != true) {
      setState(() => _phase = _Phase.idle);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(_te ? 'మైక్ ఆన్ కాలేదు. అనుమతి చూసి మళ్ళీ నొక్కండి.' : 'The mic did not start. Check permission and try again.')));
      return;
    }
    _ear = askodoxCommandEndpointer();
    _clock
      ..reset()
      ..start();
    _poll = Timer.periodic(const Duration(milliseconds: 150), (_) => unawaited(_sample()));
  }

  Future<void> _sample() async {
    int? amplitude;
    try {
      amplitude = await _device.invokeMethod<int>('voiceRecordingLevel');
    } catch (_) {
      amplitude = null;
    }
    if (!mounted || _phase != _Phase.listening) return;
    final level = amplitude ?? 0;
    setState(() => _level = (level / 12000).clamp(0, 1).toDouble());
    if (amplitude == null) return; // no levels on this phone: the person taps to stop
    if (_ear.add(level, _clock.elapsed) != VoiceEndpointDecision.keepRecording) unawaited(_stop());
  }

  Future<void> _stop() async {
    _poll?.cancel();
    _clock.stop();
    if (_phase != _Phase.listening) return;
    setState(() => _phase = _Phase.reading);
    String? path;
    try {
      path = await _device.invokeMethod<String>('stopVoiceRecording');
    } catch (_) {
      path = null;
    }
    String? text;
    if (path != null && path.isNotEmpty && _ear.heardSpeech) {
      text = await ref.read(askodoxVoiceTranscriptionServiceProvider).transcribeFile(path, locale: widget.lang);
    }
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _phase = _Phase.idle);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(_te ? 'మాట వినపడలేదు. మళ్ళీ నొక్కి చెప్పండి.' : "Didn't catch that. Tap and say it again.")));
      return;
    }
    _words.text = text.trim();
    _startCount();
  }

  void _startCount() {
    _count?.cancel();
    setState(() {
      _phase = _Phase.counting;
      _left = askodoxCommandSendAfter;
    });
    _count = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_left <= 1) {
        t.cancel();
        _send();
      } else {
        setState(() => _left--);
      }
    });
  }

  void _send() {
    final text = _words.text.trim();
    _count?.cancel();
    if (text.isEmpty) return;
    setState(() => _phase = _Phase.idle);
    widget.onSend(text);
  }

  void _halt() {
    _count?.cancel();
    setState(() => _phase = _Phase.idle);
  }

  void _edit() {
    _count?.cancel();
    setState(() => _phase = _Phase.editing);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final scheme = Theme.of(context).colorScheme;
    switch (_phase) {
      case _Phase.counting:
      case _Phase.editing:
        final editing = _phase == _Phase.editing;
        return Card(
          key: const Key('askodoxCommandHeard'),
          color: const Color(0xFFEFF6FF),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (editing)
                TextField(
                  key: const Key('askodoxCommandWords'),
                  controller: _words,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => _send(),
                )
              else
                Text('"${_words.text}"', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Row(children: [
                if (!editing)
                  Expanded(
                    child: Text(te ? '$_left సెకన్లలో పంపుతాను…' : 'Sending in $_left s…',
                        key: const Key('askodoxCommandCountdown')),
                  )
                else
                  const Spacer(),
                TextButton(key: const Key('askodoxCommandStop'), onPressed: _halt, child: Text(te ? 'ఆపు' : 'Stop')),
                if (!editing)
                  TextButton(key: const Key('askodoxCommandChange'), onPressed: _edit, child: Text(te ? 'మార్చు' : 'Change'))
                else
                  FilledButton(key: const Key('askodoxCommandSend'), onPressed: _send, child: Text(te ? 'పంపు' : 'Send')),
              ]),
            ]),
          ),
        );
      case _Phase.idle:
      case _Phase.listening:
      case _Phase.reading:
        final listening = _phase == _Phase.listening;
        final reading = _phase == _Phase.reading;
        return FilledButton.icon(
          key: const Key('askodoxCommandMic'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: listening ? const Color(0xFFDC2626) : scheme.primary,
          ),
          onPressed: reading ? null : (listening ? () => unawaited(_stop()) : () => unawaited(_listen())),
          icon: reading
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: 18 + 10 * _level),
          label: Text(listening
              ? (te ? 'వింటున్నాను… ఆపేస్తే పంపుతాను' : 'Listening… stop talking and I send it')
              : reading
                  ? (te ? 'అర్థం చేసుకుంటున్నాను…' : 'Understanding…')
                  : (te ? 'చెప్పు — చెప్పండి, చేస్తాను' : 'Tell — say it, I will do it')),
        );
    }
  }
}
