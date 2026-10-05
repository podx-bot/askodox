import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'askodox_primary_home_screen.dart' show askodoxVoiceTranscriptionServiceProvider;

/// How many screens with their own question mic are showing (the video Q&A
/// page). While one is, the centre ASKODOX mic records INTO that question
/// instead of closing the page and going back to Main Chat (phone finding).
final askodoxQuestionMicTargetsProvider = StateProvider<int>((ref) => 0);

/// Each increment toggles the visible question mic (start / stop).
final askodoxQuestionMicTriggerProvider = StateProvider<int>((ref) => 0);

/// Records a spoken question in-app (the same native recorder + Sarvam-first
/// transcription as Main Chat) and hands the words to [onText]. Tap to
/// start, tap again to stop; stops by itself after [maxDuration].
class AskodoxQuestionMic extends ConsumerStatefulWidget {
  const AskodoxQuestionMic({super.key, required this.onText, this.lang = 'en',
      this.maxDuration = const Duration(seconds: 45)});

  final ValueChanged<String> onText;
  final String lang;
  final Duration maxDuration;

  @override
  ConsumerState<AskodoxQuestionMic> createState() => _AskodoxQuestionMicState();
}

enum _MicPhase { idle, recording, transcribing }

class _AskodoxQuestionMicState extends ConsumerState<AskodoxQuestionMic> {
  static const _device = MethodChannel('com.askodox.app/device');
  _MicPhase _phase = _MicPhase.idle;
  Timer? _limit;
  late final StateController<int> _targets;

  bool get _te => widget.lang == 'te';

  @override
  void initState() {
    super.initState();
    _targets = ref.read(askodoxQuestionMicTargetsProvider.notifier);
    Future.microtask(() => _targets.state++);
    ref.listenManual<int>(askodoxQuestionMicTriggerProvider, (previous, next) {
      if (previous != null && next != previous && mounted) unawaited(_toggle());
    });
  }

  @override
  void dispose() {
    _limit?.cancel();
    if (_phase == _MicPhase.recording) {
      _device.invokeMethod<Object?>('cancelVoiceRecording').catchError((_) => null);
    }
    final targets = _targets;
    Future.microtask(() {
      try {
        targets.state = targets.state > 0 ? targets.state - 1 : 0;
      } catch (_) {
        // The whole app scope is gone (shutdown): nothing to give back.
      }
    });
    super.dispose();
  }

  void _say(String en, String te) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(_te ? te : en)));
  }

  Future<void> _toggle() async {
    switch (_phase) {
      case _MicPhase.transcribing:
        return;
      case _MicPhase.recording:
        await _stop();
      case _MicPhase.idle:
        await _start();
    }
  }

  Future<void> _start() async {
    setState(() => _phase = _MicPhase.recording);
    bool? started;
    try {
      started = await _device.invokeMethod<bool>('startVoiceRecording', {'languageCode': _te ? 'te' : 'en'});
    } on PlatformException catch (error) {
      started = false;
      if (error.code == 'mic_denied') {
        _say('Microphone permission is off. Allow it in Settings and try again.',
            'మైక్రోఫోన్ అనుమతి లేదు. Settings లో అనుమతించి మళ్లీ ప్రయత్నించండి.');
      }
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    if (started != true) {
      setState(() => _phase = _MicPhase.idle);
      return;
    }
    _limit = Timer(widget.maxDuration, () => unawaited(_stop()));
  }

  Future<void> _stop() async {
    _limit?.cancel();
    if (_phase != _MicPhase.recording) return;
    setState(() => _phase = _MicPhase.transcribing);
    String? path;
    try {
      path = await _device.invokeMethod<String>('stopVoiceRecording');
    } catch (_) {
      path = null;
    }
    String? text;
    if (path != null && path.isNotEmpty) {
      text = await ref.read(askodoxVoiceTranscriptionServiceProvider).transcribeFile(path, locale: widget.lang);
    }
    if (!mounted) return;
    setState(() => _phase = _MicPhase.idle);
    if (text == null || text.trim().isEmpty) {
      _say('I did not catch that. Please try again or type.', 'మీ మాట అర్థం కాలేదు. మళ్లీ ప్రయత్నించండి లేదా టైప్ చేయండి.');
      return;
    }
    widget.onText(text.trim());
  }

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('askodoxQuestionMic'),
        tooltip: _phase == _MicPhase.recording ? (_te ? 'ఆపండి' : 'Stop') : (_te ? 'మాట్లాడండి' : 'Speak'),
        onPressed: _phase == _MicPhase.transcribing ? null : _toggle,
        icon: switch (_phase) {
          _MicPhase.transcribing =>
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          _MicPhase.recording => const Icon(Icons.stop_circle_rounded, color: Color(0xFFE5484D)),
          _MicPhase.idle => const Icon(Icons.mic_rounded),
        },
      );
}
