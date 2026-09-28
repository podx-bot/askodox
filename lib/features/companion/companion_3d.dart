import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'askodox_companion.dart';

/// Real-time 3D ASKODOX friend, drawn with Flutter's own canvas: a lit,
/// perspective-projected triangle mesh (back-face culled, depth sorted,
/// one `drawVertices` batch per frame). No 3D engine, no plugin, no asset
/// download -- so it stays light on low-end phones. Per-mood motion (nod,
/// tilt, turn toward results, talk, bounce, shake) is rotation/scale of
/// mesh parts, not a video.
///
/// [AskodoxMesh.fromJson] loads any mesh in the same simple format, so
/// richer avatars (human-like, professional, travel...) can be added as
/// assets later without changing the chat, the actions or this renderer.

class AskodoxVec3 {
  const AskodoxVec3(this.x, this.y, this.z);
  final double x, y, z;
  AskodoxVec3 operator +(AskodoxVec3 o) => AskodoxVec3(x + o.x, y + o.y, z + o.z);
  AskodoxVec3 operator -(AskodoxVec3 o) => AskodoxVec3(x - o.x, y - o.y, z - o.z);
  AskodoxVec3 scale(double s) => AskodoxVec3(x * s, y * s, z * s);
  AskodoxVec3 cross(AskodoxVec3 o) => AskodoxVec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double dot(AskodoxVec3 o) => x * o.x + y * o.y + z * o.z;
  AskodoxVec3 get unit {
    final l = math.sqrt(x * x + y * y + z * z);
    return l == 0 ? this : scale(1 / l);
  }
}

/// A named group of triangles that animates together (head, eyes, mouth...).
class AskodoxMeshPart {
  AskodoxMeshPart(this.name, this.vertices, this.triangles, this.color);

  final String name;
  final List<AskodoxVec3> vertices;
  final List<int> triangles; // 3 indices per triangle, counter-clockwise
  final Color color;

  /// `{"parts":[{"name","color":"#RRGGBB","vertices":[[x,y,z]...],"triangles":[i,j,k,...]}]}`
  static AskodoxMeshPart fromJson(Map<String, Object?> json) => AskodoxMeshPart(
        '${json['name'] ?? 'part'}',
        [
          for (final v in (json['vertices'] as List? ?? const []))
            AskodoxVec3((v as List)[0].toDouble(), v[1].toDouble(), v[2].toDouble()),
        ],
        [for (final i in (json['triangles'] as List? ?? const [])) (i as num).toInt()],
        Color(int.parse('${json['color'] ?? '#7A4DFF'}'.replaceFirst('#', 'FF'), radix: 16)),
      );
}

class AskodoxMesh {
  AskodoxMesh(this.parts);
  final List<AskodoxMeshPart> parts;

  int get triangleCount => parts.fold(0, (n, p) => n + p.triangles.length ~/ 3);

  static AskodoxMesh fromJson(Map<String, Object?> json) => AskodoxMesh([
        for (final part in (json['parts'] as List? ?? const []))
          AskodoxMeshPart.fromJson(Map<String, Object?>.from(part as Map)),
      ]);

  // ------------------------------------------------ procedural shapes --

  static AskodoxMeshPart ellipsoid(String name, AskodoxVec3 c, AskodoxVec3 r, Color color, {int rings = 12, int segments = 18}) {
    final vs = <AskodoxVec3>[];
    final ts = <int>[];
    for (var i = 0; i <= rings; i++) {
      final phi = math.pi * i / rings;
      for (var j = 0; j <= segments; j++) {
        final theta = 2 * math.pi * j / segments;
        vs.add(AskodoxVec3(c.x + r.x * math.sin(phi) * math.cos(theta), c.y + r.y * math.cos(phi),
            c.z + r.z * math.sin(phi) * math.sin(theta)));
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < segments; j++) {
        final a = i * (segments + 1) + j, b = a + segments + 1;
        ts.addAll([a, a + 1, b, a + 1, b + 1, b]);
      }
    }
    return AskodoxMeshPart(name, vs, ts, color);
  }

  static AskodoxMeshPart cylinder(String name, AskodoxVec3 base, double r, double h, Color color, {int segments = 10}) {
    final vs = <AskodoxVec3>[];
    final ts = <int>[];
    for (var j = 0; j <= segments; j++) {
      final t = 2 * math.pi * j / segments;
      vs
        ..add(AskodoxVec3(base.x + r * math.cos(t), base.y, base.z + r * math.sin(t)))
        ..add(AskodoxVec3(base.x + r * math.cos(t), base.y + h, base.z + r * math.sin(t)));
    }
    for (var j = 0; j < segments; j++) {
      final a = j * 2;
      ts.addAll([a, a + 2, a + 1, a + 1, a + 2, a + 3]);
    }
    return AskodoxMeshPart(name, vs, ts, color);
  }

  /// The ASKODOX friend, built from primitives for the chosen look.
  static AskodoxMesh forLook(AskodoxCompanionLook look, Color accent) {
    const ink = Color(0xFF10204A);
    final parts = <AskodoxMeshPart>[
      ellipsoid('head', const AskodoxVec3(0, 0, 0), const AskodoxVec3(1, .92, .95), accent),
    ];
    if (look == AskodoxCompanionLook.robot) {
      parts
        ..add(ellipsoid('visor', const AskodoxVec3(0, .08, -.62), const AskodoxVec3(.72, .4, .38), ink))
        ..add(ellipsoid('eye_l', const AskodoxVec3(-.3, .1, -1.0), const AskodoxVec3(.12, .14, .06), const Color(0xFF7FE3FF), rings: 6, segments: 10))
        ..add(ellipsoid('eye_r', const AskodoxVec3(.3, .1, -1.0), const AskodoxVec3(.12, .14, .06), const Color(0xFF7FE3FF), rings: 6, segments: 10))
        ..add(cylinder('antenna', const AskodoxVec3(0, .85, 0), .05, .45, const Color(0xFF1769FF)))
        ..add(ellipsoid('antenna_tip', const AskodoxVec3(0, 1.36, 0), const AskodoxVec3(.12, .12, .12), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('ear_l', const AskodoxVec3(-1.0, 0, 0), const AskodoxVec3(.12, .3, .3), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('ear_r', const AskodoxVec3(1.0, 0, 0), const AskodoxVec3(.12, .3, .3), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('mouth', const AskodoxVec3(0, -.42, -.84), const AskodoxVec3(.22, .05, .05), const Color(0xFF7FE3FF), rings: 4, segments: 10));
    } else if (look == AskodoxCompanionLook.friendlyFace) {
      parts
        ..add(ellipsoid('eye_l', const AskodoxVec3(-.32, .15, -.86), const AskodoxVec3(.1, .13, .06), ink, rings: 6, segments: 10))
        ..add(ellipsoid('eye_r', const AskodoxVec3(.32, .15, -.86), const AskodoxVec3(.1, .13, .06), ink, rings: 6, segments: 10))
        ..add(ellipsoid('cheek_l', const AskodoxVec3(-.55, -.2, -.72), const AskodoxVec3(.14, .08, .05), const Color(0xFFFF9EB5), rings: 4, segments: 8))
        ..add(ellipsoid('cheek_r', const AskodoxVec3(.55, -.2, -.72), const AskodoxVec3(.14, .08, .05), const Color(0xFFFF9EB5), rings: 4, segments: 8))
        ..add(ellipsoid('mouth', const AskodoxVec3(0, -.38, -.86), const AskodoxVec3(.2, .06, .05), ink, rings: 4, segments: 10));
    } else {
      parts.add(ellipsoid('mouth', const AskodoxVec3(0, -.3, -.92), const AskodoxVec3(.18, .05, .04), ink, rings: 4, segments: 10));
    }
    return AskodoxMesh(parts);
  }
}

/// Pose of the friend for a mood at animation time [t] (0..1 loop).
class _Pose {
  _Pose({this.yaw = 0, this.pitch = 0, this.roll = 0, this.lift = 0, this.mouth = 1, this.eyes = 1, this.antenna = 1});
  double yaw, pitch, roll, lift, mouth, eyes, antenna;
}

_Pose _poseFor(AskodoxCompanionMood mood, double t) {
  final s = math.sin(t * 2 * math.pi);
  final c = math.cos(t * 2 * math.pi);
  switch (mood) {
    case AskodoxCompanionMood.idle:
      return _Pose(yaw: .18 * s, pitch: .04 * c);
    case AskodoxCompanionMood.greeting:
      return _Pose(yaw: -.25, pitch: .12 * s.abs(), roll: .1, lift: .05 * s.abs(), eyes: .7);
    case AskodoxCompanionMood.listening:
      return _Pose(roll: .22, pitch: .05, yaw: .08 * s, antenna: 1 + .4 * s.abs());
    case AskodoxCompanionMood.thinking:
      return _Pose(yaw: .5 * s, pitch: -.18, roll: -.08, antenna: 1 + .25 * c.abs());
    case AskodoxCompanionMood.speaking:
      return _Pose(yaw: .12 * s, pitch: .05 * math.sin(t * 8 * math.pi), mouth: 1 + 1.6 * math.sin(t * 12 * math.pi).abs());
    case AskodoxCompanionMood.explaining:
      return _Pose(yaw: .55 + .08 * s, pitch: .08, roll: -.05); // turns toward the results
    case AskodoxCompanionMood.success:
      return _Pose(lift: .08 * s.abs(), pitch: .15 * s.abs(), eyes: .6, mouth: 1.4);
    case AskodoxCompanionMood.help:
      return _Pose(yaw: .3 * math.sin(t * 6 * math.pi), pitch: -.1, mouth: .7);
  }
}

class AskodoxCompanion3dPainter extends CustomPainter {
  AskodoxCompanion3dPainter({required this.mesh, required this.mood, required this.t});

  final AskodoxMesh mesh;
  final AskodoxCompanionMood mood;
  final double t;

  // Key light from the upper-left front (the camera looks along +z, so
  // "towards the viewer" is -z); the halfway vector gives a soft highlight.
  static const _light = AskodoxVec3(-.45, .6, -.65);
  static final _halfway = (_light.unit + const AskodoxVec3(0, 0, -1)).unit;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = _poseFor(mood, t);
    final cy = math.cos(pose.yaw), sy = math.sin(pose.yaw);
    final cp = math.cos(pose.pitch), sp = math.sin(pose.pitch);
    final cr = math.cos(pose.roll), sr = math.sin(pose.roll);
    AskodoxVec3 rotate(AskodoxVec3 v) {
      var x = v.x * cr - v.y * sr, y = v.x * sr + v.y * cr, z = v.z; // roll (z)
      final x2 = x * cy + z * sy, z2 = -x * sy + z * cy; // yaw (y)
      x = x2;
      z = z2;
      final y3 = y * cp - z * sp, z3 = y * sp + z * cp; // pitch (x)
      return AskodoxVec3(x, y3 + pose.lift, z3);
    }

    final scale = size.shortestSide * .36;
    final centre = Offset(size.width / 2, size.height * .56);
    const camera = 4.2;
    Offset project(AskodoxVec3 v) {
      final f = camera / (camera + v.z);
      return centre + Offset(v.x * f * scale, -v.y * f * scale);
    }

    final light = _light.unit;
    final tris = <(double, Offset, Offset, Offset, Color)>[];
    for (final part in mesh.parts) {
      // Part-level animation: talking mouth, blinking eyes, glowing antenna.
      final sx = part.name == 'mouth' ? 1.0 : 1.0;
      final syPart = part.name == 'mouth'
          ? pose.mouth
          : part.name.startsWith('eye')
              ? pose.eyes
              : 1.0;
      final lift = part.name.startsWith('antenna') ? (pose.antenna - 1) * .15 : 0.0;
      final anchor = part.vertices.isEmpty
          ? const AskodoxVec3(0, 0, 0)
          : part.vertices.reduce((a, b) => a + b).scale(1 / part.vertices.length);
      final world = [
        for (final v in part.vertices)
          rotate(AskodoxVec3(anchor.x + (v.x - anchor.x) * sx, anchor.y + (v.y - anchor.y) * syPart + lift, v.z)),
      ];
      final centre3 = world.isEmpty ? const AskodoxVec3(0, 0, 0) : world.reduce((a, b) => a + b).scale(1 / world.length);
      final isHead = part.name == 'head';
      final onTop = part.name.startsWith('antenna');
      for (var i = 0; i + 2 < part.triangles.length; i += 3) {
        final a = world[part.triangles[i]], b = world[part.triangles[i + 1]], c = world[part.triangles[i + 2]];
        final mid = (a + b + c).scale(1 / 3);
        var normal = (b - a).cross(c - a).unit;
        // Outward normal regardless of the mesh's winding order.
        if (normal.dot(mid - centre3) < 0) normal = normal.scale(-1);
        if (normal.z > 0) continue; // faces away from the viewer (camera looks along +z)
        // A face detail that turned to the back of the head is hidden by it.
        if (!isHead && !onTop && mid.z > 0.05) continue;
        final diffuse = math.max(0.0, normal.dot(light));
        final spec = math.pow(math.max(0.0, normal.dot(_halfway)), 24).toDouble();
        final lit = .42 + .7 * diffuse;
        int channel(double v) => (v * 255 * lit + 255 * .45 * spec).clamp(0, 255).round();
        final shade = Color.fromARGB(255, channel(part.color.r), channel(part.color.g), channel(part.color.b));
        // Head first, then details on top of it; each group far-to-near.
        tris.add(((isHead ? 1000.0 : 0.0) + mid.z, project(a), project(b), project(c), shade));
      }
    }
    // Painter's algorithm: far triangles first.
    tris.sort((p, q) => q.$1.compareTo(p.$1));
    final positions = Float32List(tris.length * 6);
    final colors = Int32List(tris.length * 3);
    for (var i = 0; i < tris.length; i++) {
      final (_, p1, p2, p3, color) = tris[i];
      positions.setAll(i * 6, [p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy]);
      final argb = color.toARGB32();
      colors.setAll(i * 3, [argb, argb, argb]);
    }
    // Soft ground shadow for depth.
    canvas.drawOval(
      Rect.fromCenter(center: centre + Offset(0, scale * 1.25), width: scale * 1.5 * (1 - pose.lift), height: scale * .22),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawVertices(
      ui.Vertices.raw(VertexMode.triangles, positions, colors: colors),
      BlendMode.dst,
      Paint(),
    );
  }

  @override
  bool shouldRepaint(AskodoxCompanion3dPainter old) => old.t != t || old.mood != mood || old.mesh != mesh;
}
