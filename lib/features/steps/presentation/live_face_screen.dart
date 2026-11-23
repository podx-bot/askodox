import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../domain/live_face.dart';

/// Owner 2026-11-23: the live face check of attendance. The front camera takes a small picture about twice a second,
/// Google ML Kit (free, on this phone, no internet needed) reads the face, and [AskodoxLiveCheck] decides. Pictures are
/// deleted as soon as they are read; only the last straight one is returned (the still the owner sees, max ~150 KB).
/// Returns null when the person goes back, the camera is not allowed, or the time runs out.
Future<List<int>?> askodoxLiveFaceCheck(BuildContext context, {required bool te}) =>
    Navigator.of(context).push<List<int>>(MaterialPageRoute(builder: (_) => AskodoxLiveFaceScreen(te: te)));

class AskodoxLiveFaceScreen extends StatefulWidget {
  const AskodoxLiveFaceScreen({super.key, required this.te});
  final bool te;

  @override
  State<AskodoxLiveFaceScreen> createState() => _AskodoxLiveFaceScreenState();
}

class _AskodoxLiveFaceScreenState extends State<AskodoxLiveFaceScreen> {
  CameraController? _camera;
  final _detector = FaceDetector(
      options: FaceDetectorOptions(enableClassification: true, enableTracking: true, performanceMode: FaceDetectorMode.fast));
  AskodoxLiveCheck _check = AskodoxLiveCheck(askodoxLiveMoves());
  String? _error;
  bool _running = false;

  bool get _te => widget.te;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _running = false;
    unawaited(_camera?.dispose());
    unawaited(_detector.close());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ?? cameras.firstOrNull;
      if (front == null) throw StateError('no camera');
      final camera = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
      _running = true;
      unawaited(_loop());
    } catch (_) {
      if (mounted) {
        setState(() => _error = _te
            ? 'కెమెరా తెరవలేకపోయా. సెట్టింగ్స్ లో ASKODOX కి కెమెరా అనుమతి ఇవ్వండి.'
            : 'Could not open the camera. Allow the camera for ASKODOX in Settings.');
      }
    }
  }

  Future<void> _loop() async {
    while (_running && mounted) {
      final camera = _camera;
      if (camera == null || !camera.value.isInitialized) return;
      XFile? shot;
      try {
        shot = await camera.takePicture();
        final faces = await _detector.processImage(InputImage.fromFilePath(shot.path));
        final first = faces.isEmpty ? null : faces.first;
        final sample = AskodoxFaceSample(
          faces: faces.length,
          yaw: first?.headEulerAngleY ?? 0,
          pitch: first?.headEulerAngleX ?? 0,
          leftEyeOpen: first?.leftEyeOpenProbability,
          rightEyeOpen: first?.rightEyeOpenProbability,
          trackingId: first?.trackingId,
          widthPx: first?.boundingBox.width ?? 0,
        );
        final keep = _check.feed(sample, DateTime.now());
        if (keep) {
          final bytes = await File(shot.path).readAsBytes();
          _running = false;
          if (mounted) Navigator.of(context).pop(bytes);
          return;
        }
        if (mounted) setState(() {});
        if (_check.state == AskodoxLiveState.failed) {
          _running = false;
          if (mounted) {
            setState(() => _error = _te
                ? 'సమయం అయిపోయింది. మళ్ళీ ప్రయత్నించండి — చెప్పినట్టు తల కదపండి.'
                : 'Time is up. Try again — move your head as asked.');
          }
          return;
        }
      } catch (_) {
        // one bad frame is skipped
      } finally {
        if (shot != null) {
          try {
            await File(shot.path).delete();
          } catch (_) {}
        }
      }
    }
  }

  /// A new try on the same page (new random moves), so the still still goes back to whoever asked.
  void _again() {
    setState(() {
      _error = null;
      _check = AskodoxLiveCheck(askodoxLiveMoves());
    });
    if (_camera == null) {
      unawaited(_start());
    } else {
      _running = true;
      unawaited(_loop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final move = _check.current;
    final hint = askodoxLiveHintWords(_check.hint);
    final ask = _check.state == AskodoxLiveState.lookStraight || move == null
        ? (te ? 'నేరుగా ఫోన్ వైపు చూడండి' : 'Look straight at the phone')
        : (te ? askodoxLiveMoveWords(move).$2 : askodoxLiveMoveWords(move).$1);
    return Scaffold(
      key: const Key('askodoxLiveFace'),
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(te ? 'ముఖం లైవ్ చెక్' : 'Live face check'),
      ),
      body: SafeArea(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_error!,
                      key: const Key('askodoxLiveFaceError'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _again, child: Text(te ? 'మళ్ళీ' : 'Try again')),
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(te ? 'వెనక్కి' : 'Back', style: const TextStyle(color: Colors.white70))),
                ]),
              )
            : Column(children: [
                const SizedBox(height: 12),
                Text(ask,
                    key: const Key('askodoxLiveFaceAsk'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                    hint.$1.isEmpty
                        ? (te ? '${_check.done} / ${_check.moves.length} అయ్యాయి' : '${_check.done} / ${_check.moves.length} done')
                        : (te ? hint.$2 : hint.$1),
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipOval(
                        child: _camera == null
                            ? const ColoredBox(color: Color(0xFF1E293B), child: Center(child: CircularProgressIndicator()))
                            : CameraPreview(_camera!),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                  child: Column(children: [
                    for (var i = 0; i < _check.moves.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(i < _check.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: i < _check.done ? const Color(0xFF22C55E) : const Color(0xFF64748B), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(te ? askodoxLiveMoveWords(_check.moves[i]).$2 : askodoxLiveMoveWords(_check.moves[i]).$1,
                                style: TextStyle(
                                    color: i == _check.done ? Colors.white : const Color(0xFFCBD5E1),
                                    fontWeight: i == _check.done ? FontWeight.w800 : FontWeight.w600)),
                          ),
                        ]),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  child: Text(
                      te
                          ? 'ప్రతిసారీ కదలికలు వేరే వరుసలో — ఫోటో పెట్టి మోసం చేయలేరు. ఫోటో ఉంచం, చివరి ఒక్క చిత్రం ఓనర్ కి మాత్రమే.'
                          : 'A new order every time — a photo cannot do it. Only the last still goes to the owner.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ),
              ]),
      ),
    );
  }
}
