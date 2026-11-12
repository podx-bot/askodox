import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Hand-made pictures for the Work Mode scenes (2D, from ChatGPT).
///
/// Loaded once from the app bundle. If anything fails to load, [load] gives
/// null and the scene keeps drawing the code-made picture, so the game never
/// breaks because of a missing picture.
class AskodoxWorkSceneImages {
  AskodoxWorkSceneImages({required this.paddyBackground, required this.paddyTransplantFrames});

  /// The paddy field background (no people, 3:2).
  final ui.Image paddyBackground;

  /// The planting farmer, nine transparent frames: bend, plant, press, rise, stand.
  final List<ui.Image> paddyTransplantFrames;

  static Future<AskodoxWorkSceneImages?>? _cached;

  /// Loads everything once per app run.
  static Future<AskodoxWorkSceneImages?> load() => _cached ??= _loadAll();

  static Future<AskodoxWorkSceneImages?> _loadAll() async {
    try {
      final background = await _image('assets/work_scenes/paddy_field.jpg');
      final frames = <ui.Image>[];
      for (var i = 1; i <= 9; i++) {
        frames.add(await _image('assets/work_sprites/paddy_plant_${i.toString().padLeft(2, '0')}.png'));
      }
      return AskodoxWorkSceneImages(paddyBackground: background, paddyTransplantFrames: frames);
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _image(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
