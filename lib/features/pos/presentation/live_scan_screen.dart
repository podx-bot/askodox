import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/pos_hardware.dart';

/// Full-screen live scanner: back camera preview, every frame's brightness is read for a barcode / QR in a background
/// isolate; the first code found closes the screen with its text. Cancel closes with null; a camera that cannot start
/// answers [usePhoto] so the caller falls back to the photo scan.
class AskodoxLiveScanScreen extends StatefulWidget {
  const AskodoxLiveScanScreen({super.key});

  static const usePhoto = 'use_photo';

  @override
  State<AskodoxLiveScanScreen> createState() => _AskodoxLiveScanScreenState();
}

class _AskodoxLiveScanScreenState extends State<AskodoxLiveScanScreen> {
  CameraController? _camera;
  bool _busy = false;
  bool _done = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? cameras.firstOrNull;
      if (back == null) throw StateError('no camera');
      final controller = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      await controller.startImageStream(_onFrame);
      setState(() {});
    } catch (_) {
      if (mounted) Navigator.of(context).pop(AskodoxLiveScanScreen.usePhoto);
    }
  }

  void _onFrame(CameraImage frame) {
    if (_busy || _done) return;
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 250) return;
    _last = now;
    _busy = true;
    final plane = frame.planes.first;
    final image = askodoxScanImageFromLuma(plane.bytes, frame.width, frame.height, plane.bytesPerRow);
    compute(askodoxDecodeBarcodePixels, image).then((code) {
      if (code != null && !_done && mounted) {
        _done = true;
        Navigator.of(context).pop(code);
      }
    }).catchError((_) {}).whenComplete(() => _busy = false);
  }

  @override
  void dispose() {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      unawaited(() async {
        try {
          if (camera.value.isStreamingImages) await camera.stopImageStream();
        } catch (_) {}
        await camera.dispose();
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final camera = _camera;
    return Scaffold(
      key: const Key('askodoxLiveScan'),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: camera != null && camera.value.isInitialized
                ? Center(child: CameraPreview(camera))
                : const Center(child: CircularProgressIndicator()),
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Column(children: [
              Text(te ? 'బార్‌కోడ్ / QR ని ఫ్రేమ్‌లో పెట్టండి' : 'Put the barcode / QR inside the frame',
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('askodoxLiveScanPhoto'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: () => Navigator.of(context).pop(AskodoxLiveScanScreen.usePhoto),
                child: Text(te ? 'ఫోటో తీసి చదువు' : 'Take a photo instead'),
              ),
            ]),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              key: const Key('askodoxLiveScanClose'),
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }
}
