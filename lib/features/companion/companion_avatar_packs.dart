import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'companion_3d.dart';
import 'companion_human.dart';

/// Optional downloadable avatar packs: a richer mesh for a persona in the
/// SAME rig format (`AskodoxMesh.fromJson`, `meta.rig = human`, the same
/// part names), fetched lazily once and cached on the phone. Nothing is
/// bundled in the APK; with no pack server configured
/// (`--dart-define=ASKODOX_AVATAR_BASE_URL=...`) or on any failure the
/// procedural rig is used, so the companion always renders.
class AskodoxAvatarPacks {
  static const baseUrl = String.fromEnvironment('ASKODOX_AVATAR_BASE_URL');

  /// Safety limits for a downloaded pack (memory + frame time on phones).
  static const maxBytes = 1500000;
  static const maxTriangles = 12000;
  static const requiredParts = {'head', 'face_mouth', 'hand_l', 'hand_r'};

  /// A valid pack mesh, or null (caller keeps the procedural rig).
  static AskodoxMesh? parse(String body) {
    if (body.length > maxBytes) return null;
    try {
      final mesh = AskodoxMesh.fromJson(Map<String, Object?>.from(jsonDecode(body) as Map));
      final names = mesh.parts.map((p) => p.name).toSet();
      if (!mesh.isHuman || !names.containsAll(requiredParts)) return null;
      if (mesh.triangleCount > maxTriangles) return null;
      for (final part in mesh.parts) {
        if (part.triangles.any((i) => i < 0 || i >= part.vertices.length)) return null;
      }
      return mesh;
    } catch (_) {
      return null;
    }
  }

  static Future<AskodoxMesh?> load(AskodoxPersona persona, {String base = baseUrl, http.Client? client}) async {
    if (base.isEmpty) return null;
    File? cached;
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/askodox_avatars');
      cached = File('${dir.path}/${persona.name}.json');
      if (await cached.exists()) {
        final mesh = parse(await cached.readAsString());
        if (mesh != null) return mesh;
      }
      await dir.create(recursive: true);
    } catch (_) {
      cached = null; // no storage: still try the network, just don't cache
    }
    final http.Client http0 = client ?? http.Client();
    try {
      final uri = Uri.parse('${base.endsWith('/') ? base : '$base/'}${persona.name}.json');
      final response = await http0.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final mesh = parse(response.body);
      if (mesh != null) await cached?.writeAsString(response.body);
      return mesh;
    } catch (_) {
      return null;
    } finally {
      if (client == null) http0.close();
    }
  }
}

final askodoxAvatarPackProvider =
    FutureProvider.family<AskodoxMesh?, AskodoxPersona>((ref, persona) => AskodoxAvatarPacks.load(persona));
