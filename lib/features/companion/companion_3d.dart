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
  AskodoxMeshPart(this.name, this.vertices, this.triangles, this.color, {this.wound = false});

  final String name;

  /// Triangles are wound outward (rings/tori): trust the winding instead of
  /// the part-centroid rule used for convex parts.
  final bool wound;
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
  AskodoxMesh(this.parts, {this.meta = const {}});
  final List<AskodoxMeshPart> parts;

  /// Rig facts the painter needs beyond triangles (e.g. `rig: human`,
  /// sleeve/skin colours for the procedurally posed arms).
  final Map<String, Object?> meta;

  bool get isHuman => meta['rig'] == 'human';

  int get triangleCount => parts.fold(0, (n, p) => n + p.triangles.length ~/ 3);

  static AskodoxMesh fromJson(Map<String, Object?> json) => AskodoxMesh([
        for (final part in (json['parts'] as List? ?? const []))
          AskodoxMeshPart.fromJson(Map<String, Object?>.from(part as Map)),
      ], meta: Map<String, Object?>.from(json['meta'] as Map? ?? const {}));

  // ------------------------------------------------ procedural shapes --

  /// Ellipsoid (or a band of it: [phiFrom]..[phiTo] in 0..pi from the top,
  /// e.g. a hair cap or a hat crown).
  static AskodoxMeshPart ellipsoid(String name, AskodoxVec3 c, AskodoxVec3 r, Color color,
      {int rings = 12, int segments = 18, double phiFrom = 0, double phiTo = math.pi}) {
    final vs = <AskodoxVec3>[];
    final ts = <int>[];
    for (var i = 0; i <= rings; i++) {
      final phi = phiFrom + (phiTo - phiFrom) * i / rings;
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

  /// Ring in the x/y plane facing the viewer (glasses frames).
  static AskodoxMeshPart torus(String name, AskodoxVec3 c, double major, double minor, Color color,
      {int segments = 16, int sides = 6, double yScale = 1}) {
    final vs = <AskodoxVec3>[];
    final ts = <int>[];
    for (var i = 0; i <= segments; i++) {
      final u = 2 * math.pi * i / segments;
      for (var j = 0; j <= sides; j++) {
        final v = 2 * math.pi * j / sides;
        final rr = major + minor * math.cos(v);
        vs.add(AskodoxVec3(c.x + rr * math.cos(u), c.y + rr * math.sin(u) * yScale, c.z + minor * math.sin(v)));
      }
    }
    for (var i = 0; i < segments; i++) {
      for (var j = 0; j < sides; j++) {
        final a = i * (sides + 1) + j, b = a + sides + 1;
        ts.addAll([a, a + 1, b, a + 1, b + 1, b]);
      }
    }
    return AskodoxMeshPart(name, vs, ts, color, wound: true);
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

  /// The ASKODOX friend, built from primitives for the chosen look: head,
  /// face details, brows (expressions) and two floating hands (gestures).
  static AskodoxMesh forLook(AskodoxCompanionLook look, Color accent) {
    const ink = Color(0xFF10204A);
    final hand = Color.lerp(accent, Colors.white, .25)!;
    final parts = <AskodoxMeshPart>[
      ellipsoid('head', const AskodoxVec3(0, 0, 0), const AskodoxVec3(1, .92, .95), accent),
    ];
    if (look == AskodoxCompanionLook.robot) {
      parts
        ..add(ellipsoid('visor', const AskodoxVec3(0, .08, -.62), const AskodoxVec3(.72, .4, .38), ink))
        ..add(ellipsoid('eye_l', const AskodoxVec3(-.3, .1, -1.0), const AskodoxVec3(.12, .14, .06), const Color(0xFF7FE3FF), rings: 6, segments: 10))
        ..add(ellipsoid('eye_r', const AskodoxVec3(.3, .1, -1.0), const AskodoxVec3(.12, .14, .06), const Color(0xFF7FE3FF), rings: 6, segments: 10))
        ..add(ellipsoid('brow_l', const AskodoxVec3(-.3, .42, -.96), const AskodoxVec3(.16, .035, .04), const Color(0xFF7FE3FF), rings: 4, segments: 8))
        ..add(ellipsoid('brow_r', const AskodoxVec3(.3, .42, -.96), const AskodoxVec3(.16, .035, .04), const Color(0xFF7FE3FF), rings: 4, segments: 8))
        ..add(cylinder('antenna', const AskodoxVec3(0, .85, 0), .05, .45, const Color(0xFF1769FF)))
        ..add(ellipsoid('antenna_tip', const AskodoxVec3(0, 1.36, 0), const AskodoxVec3(.12, .12, .12), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('ear_l', const AskodoxVec3(-1.0, 0, 0), const AskodoxVec3(.12, .3, .3), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('ear_r', const AskodoxVec3(1.0, 0, 0), const AskodoxVec3(.12, .3, .3), const Color(0xFF1769FF), rings: 6, segments: 10))
        ..add(ellipsoid('mouth', const AskodoxVec3(0, -.42, -.84), const AskodoxVec3(.22, .05, .05), const Color(0xFF7FE3FF), rings: 4, segments: 10));
    } else if (look == AskodoxCompanionLook.friendlyFace) {
      parts
        ..add(ellipsoid('eye_l', const AskodoxVec3(-.32, .15, -.86), const AskodoxVec3(.1, .13, .06), ink, rings: 6, segments: 10))
        ..add(ellipsoid('eye_r', const AskodoxVec3(.32, .15, -.86), const AskodoxVec3(.1, .13, .06), ink, rings: 6, segments: 10))
        ..add(ellipsoid('brow_l', const AskodoxVec3(-.32, .42, -.84), const AskodoxVec3(.14, .03, .04), ink, rings: 4, segments: 8))
        ..add(ellipsoid('brow_r', const AskodoxVec3(.32, .42, -.84), const AskodoxVec3(.14, .03, .04), ink, rings: 4, segments: 8))
        ..add(ellipsoid('cheek_l', const AskodoxVec3(-.55, -.2, -.72), const AskodoxVec3(.14, .08, .05), const Color(0xFFFF9EB5), rings: 4, segments: 8))
        ..add(ellipsoid('cheek_r', const AskodoxVec3(.55, -.2, -.72), const AskodoxVec3(.14, .08, .05), const Color(0xFFFF9EB5), rings: 4, segments: 8))
        ..add(ellipsoid('mouth', const AskodoxVec3(0, -.38, -.86), const AskodoxVec3(.2, .06, .05), ink, rings: 4, segments: 10));
    } else {
      parts.add(ellipsoid('mouth', const AskodoxVec3(0, -.3, -.92), const AskodoxVec3(.18, .05, .04), ink, rings: 4, segments: 10));
    }
    // Hands are modelled at the origin; the pose places them per gesture.
    parts
      ..add(ellipsoid('hand_l', const AskodoxVec3(0, 0, 0), const AskodoxVec3(.2, .22, .14), hand, rings: 6, segments: 10))
      ..add(ellipsoid('hand_r', const AskodoxVec3(0, 0, 0), const AskodoxVec3(.2, .22, .14), hand, rings: 6, segments: 10));
    return AskodoxMesh(parts);
  }
}

/// Live signals that shape the friend beyond its mood: the microphone level
/// (listening), lip-sync openness (speaking), a natural blink and where the
/// eyes look. All optional -- without them the mood pose alone is used.
class AskodoxCompanionSignals {
  const AskodoxCompanionSignals({this.micLevel = 0, this.mouthOpen, this.blink = 0, this.gaze = Offset.zero});

  final double micLevel; // 0..1
  final double? mouthOpen; // 0..1 while lip-syncing, else null
  final double blink; // 0 open .. 1 closed
  final Offset gaze; // -1..1 each axis

  @override
  bool operator ==(Object other) =>
      other is AskodoxCompanionSignals &&
      other.micLevel == micLevel &&
      other.mouthOpen == mouthOpen &&
      other.blink == blink &&
      other.gaze == gaze;

  @override
  int get hashCode => Object.hash(micLevel, mouthOpen, blink, gaze);
}

/// Pose of the friend for a mood at animation time [t] (0..1 loop):
/// head rotation, expression (eyes, brows, mouth) and the hands' gesture.
class AskodoxPose {
  AskodoxPose({
    this.yaw = 0,
    this.pitch = 0,
    this.roll = 0,
    this.lift = 0,
    this.mouth = 1,
    this.mouthWidth = 1,
    this.eyes = 1,
    this.antenna = 1,
    this.browLift = 0,
    this.browTilt = 0,
    this.gaze = Offset.zero,
    this.handL = const AskodoxVec3(-1.22, -.85, -.35),
    this.handR = const AskodoxVec3(1.22, -.85, -.35),
    this.handTiltL = 0,
    this.handTiltR = 0,
  });

  double yaw, pitch, roll, lift, mouth, mouthWidth, eyes, antenna, browLift, browTilt, handTiltL, handTiltR;
  Offset gaze;
  AskodoxVec3 handL, handR;
}

/// Mood -> expression + gesture, then live [signals] layered on top.
AskodoxPose askodoxPoseFor(AskodoxCompanionMood mood, double t, [AskodoxCompanionSignals signals = const AskodoxCompanionSignals()]) {
  final s = math.sin(t * 2 * math.pi);
  final c = math.cos(t * 2 * math.pi);
  final float = .04 * math.sin(t * 4 * math.pi);
  AskodoxPose pose;
  switch (mood) {
    case AskodoxCompanionMood.idle:
      pose = AskodoxPose(yaw: .18 * s, pitch: .04 * c);
      pose.handL = AskodoxVec3(-1.22, -.85 + float, -.35);
      pose.handR = AskodoxVec3(1.22, -.85 - float, -.35);
    case AskodoxCompanionMood.greeting:
      // Friendly head tilt, raised brows, happy squint and a waving hand.
      pose = AskodoxPose(yaw: -.25, pitch: .12 * s.abs(), roll: .1, lift: .05 * s.abs(), eyes: .7, browLift: .08, mouth: 1.3);
      pose.handR = AskodoxVec3(1.3 + .12 * math.sin(t * 6 * math.pi), .25, -.45);
      pose.handTiltR = .45 * math.sin(t * 6 * math.pi);
    case AskodoxCompanionMood.listening:
      // Head tilted toward the speaker, attentive brows, hand cupped at the ear.
      pose = AskodoxPose(roll: .22, pitch: .05, yaw: .08 * s, antenna: 1 + .4 * s.abs(), browLift: .06, eyes: 1.1);
      pose.handL = const AskodoxVec3(-1.28, .08, -.2);
      pose.handTiltL = -.5;
    case AskodoxCompanionMood.thinking:
      // Looks up and around, one brow raised, hand at the chin tapping.
      pose = AskodoxPose(yaw: .5 * s, pitch: -.18, roll: -.08, antenna: 1 + .25 * c.abs(), browTilt: .18, gaze: const Offset(-.6, .7), mouth: .7, mouthWidth: .7);
      pose.handR = AskodoxVec3(.45, -.95 + .05 * math.sin(t * 8 * math.pi), -1.0);
      pose.handTiltR = .3;
    case AskodoxCompanionMood.speaking:
      // Talking: small nods, lively brows, hands gesturing in turn.
      pose = AskodoxPose(yaw: .12 * s, pitch: .05 * math.sin(t * 8 * math.pi), mouth: 1 + 1.6 * math.sin(t * 12 * math.pi).abs(), browLift: .04 * s.abs());
      pose.handL = AskodoxVec3(-1.2, -.75 + .18 * math.max(0, s), -.6);
      pose.handR = AskodoxVec3(1.2, -.75 + .18 * math.max(0, -s), -.6);
      pose.handTiltL = .3 * s;
      pose.handTiltR = -.3 * s;
    case AskodoxCompanionMood.explaining:
      // Turns toward the results and points at them.
      pose = AskodoxPose(yaw: .55 + .08 * s, pitch: .08, roll: -.05, gaze: const Offset(.8, -.2), browLift: .03);
      pose.handR = AskodoxVec3(1.55 + .06 * s, -.35, -.75);
      pose.handTiltR = -1.2;
    case AskodoxCompanionMood.success:
      // Happy bounce with both hands up.
      pose = AskodoxPose(lift: .08 * s.abs(), pitch: .15 * s.abs(), eyes: .6, mouth: 1.4, mouthWidth: 1.15, browLift: .1);
      pose.handL = AskodoxVec3(-1.15, .35 + .1 * s.abs(), -.4);
      pose.handR = AskodoxVec3(1.15, .35 + .1 * s.abs(), -.4);
      pose.handTiltL = -.3;
      pose.handTiltR = .3;
    case AskodoxCompanionMood.help:
      // Gentle "no worries" shake, concerned brows, open palms.
      pose = AskodoxPose(yaw: .3 * math.sin(t * 6 * math.pi), pitch: -.1, mouth: .7, browTilt: -.2);
      pose.handL = const AskodoxVec3(-1.1, -.55, -.75);
      pose.handR = const AskodoxVec3(1.1, -.55, -.75);
      pose.handTiltL = .6;
      pose.handTiltR = -.6;
  }
  // Live signals: the mic level makes the friend lean in, glow and widen its
  // eyes; lip-sync replaces the canned talk loop; blinks and gaze are real.
  final mic = signals.micLevel.clamp(0.0, 1.0);
  if (mic > 0) {
    pose
      ..roll += .12 * mic
      ..antenna += .8 * mic
      ..eyes *= 1 + .15 * mic
      ..browLift += .05 * mic;
  }
  final lips = signals.mouthOpen;
  if (lips != null) {
    pose
      ..mouth = .5 + 2.6 * lips.clamp(0.0, 1.0)
      ..mouthWidth = 1.05 - .25 * lips.clamp(0.0, 1.0);
  }
  pose.eyes *= 1 - .92 * signals.blink.clamp(0.0, 1.0);
  if (signals.gaze != Offset.zero) pose.gaze = signals.gaze;
  return pose;
}

/// The one lit-mesh rasterizer every ASKODOX companion uses (robot lite and
/// human personas): perspective projection, outward normals, back-face
/// culling, Lambert + specular light, painter's-algorithm depth sort and a
/// single `drawVertices` batch.
class AskodoxRaster {
  AskodoxRaster(Size size, {double frameHeight = 1 / .3, double frameCenterY = 0})
      : scale = size.shortestSide / frameHeight,
        centre = Offset(size.width / 2, size.height * .5),
        _centerY = frameCenterY;

  final double scale;
  final Offset centre;
  final double _centerY;
  static const camera = 4.2;

  // Key light from the upper-left front (the camera looks along +z, so
  // "towards the viewer" is -z); the halfway vector gives a soft highlight.
  static final light = const AskodoxVec3(-.45, .6, -.65).unit;
  static final _halfway = (light + const AskodoxVec3(0, 0, -1)).unit;

  final _tris = <(double, Offset, Offset, Offset, int)>[];

  int get triangleCount => _tris.length;

  Offset project(AskodoxVec3 v) {
    final f = camera / (camera + v.z);
    return centre + Offset(v.x * f * scale, -(v.y - _centerY) * f * scale);
  }

  /// Adds one part's triangles. [bucket] groups draw order (higher = drawn
  /// earlier); [hideBehind] hides faces that turned to the back (face
  /// details on a head).
  void add(List<AskodoxVec3> world, List<int> triangles, Color color,
      {double bucket = 0, bool hideBehind = false, bool wound = false}) {
    if (world.isEmpty) return;
    final centre3 = world.reduce((a, b) => a + b).scale(1 / world.length);
    final r = color.r, g = color.g, b = color.b;
    for (var i = 0; i + 2 < triangles.length; i += 3) {
      final p1 = world[triangles[i]], p2 = world[triangles[i + 1]], p3 = world[triangles[i + 2]];
      final mid = (p1 + p2 + p3).scale(1 / 3);
      var normal = (p2 - p1).cross(p3 - p1).unit;
      // Outward normal regardless of the mesh's winding order.
      if (!wound && normal.dot(mid - centre3) < 0) normal = normal.scale(-1);
      if (normal.z > 0) continue; // faces away from the viewer
      if (hideBehind && mid.z > 0.05) continue;
      final diffuse = math.max(0.0, normal.dot(light));
      final spec = math.pow(math.max(0.0, normal.dot(_halfway)), 24).toDouble();
      final lit = .42 + .7 * diffuse;
      int channel(double v) => (v * 255 * lit + 255 * .45 * spec).clamp(0, 255).round();
      final argb = (255 << 24) | (channel(r) << 16) | (channel(g) << 8) | channel(b);
      _tris.add((bucket + mid.z, project(p1), project(p2), project(p3), argb));
    }
  }

  void draw(Canvas canvas, {double shadowY = 1.45, double shadowWidth = 1.6}) {
    _tris.sort((p, q) => q.$1.compareTo(p.$1)); // far triangles first
    final positions = Float32List(_tris.length * 6);
    final colors = Int32List(_tris.length * 3);
    for (var i = 0; i < _tris.length; i++) {
      final (_, a, b, c, argb) = _tris[i];
      positions.setAll(i * 6, [a.dx, a.dy, b.dx, b.dy, c.dx, c.dy]);
      colors.setAll(i * 3, [argb, argb, argb]);
    }
    // Soft ground shadow for depth.
    canvas.drawOval(
      Rect.fromCenter(
          center: centre + Offset(0, scale * shadowY), width: scale * shadowWidth, height: scale * .22),
      Paint()..color = const Color(0x22000000),
    );
    canvas.drawVertices(ui.Vertices.raw(VertexMode.triangles, positions, colors: colors), BlendMode.dst, Paint());
  }
}

AskodoxVec3 askodoxRollAround(AskodoxVec3 v, AskodoxVec3 anchor, double angle) {
  if (angle == 0) return v;
  final ca = math.cos(angle), sa = math.sin(angle);
  final dx = v.x - anchor.x, dy = v.y - anchor.y;
  return AskodoxVec3(anchor.x + dx * ca - dy * sa, anchor.y + dx * sa + dy * ca, v.z);
}

AskodoxVec3 askodoxCentroid(List<AskodoxVec3> vs) =>
    vs.isEmpty ? const AskodoxVec3(0, 0, 0) : vs.reduce((a, b) => a + b).scale(1 / vs.length);

/// The lightweight robot friend (Lite mode / fallback).
class AskodoxCompanion3dPainter extends CustomPainter {
  AskodoxCompanion3dPainter({
    required this.mesh,
    required this.mood,
    required this.t,
    this.signals = const AskodoxCompanionSignals(),
  });

  final AskodoxMesh mesh;
  final AskodoxCompanionMood mood;
  final double t;
  final AskodoxCompanionSignals signals;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = askodoxPoseFor(mood, t, signals);
    final cy = math.cos(pose.yaw), sy = math.sin(pose.yaw);
    final cp = math.cos(pose.pitch), sp = math.sin(pose.pitch);
    final cr = math.cos(pose.roll), sr = math.sin(pose.roll);
    AskodoxVec3 rotateHead(AskodoxVec3 v) {
      var x = v.x * cr - v.y * sr, y = v.x * sr + v.y * cr, z = v.z; // roll (z)
      final x2 = x * cy + z * sy, z2 = -x * sy + z * cy; // yaw (y)
      x = x2;
      z = z2;
      final y3 = y * cp - z * sp, z3 = y * sp + z * cp; // pitch (x)
      return AskodoxVec3(x, y3 + pose.lift, z3);
    }

    // Hands follow the body only loosely (a third of the head's yaw).
    final by = pose.yaw * .33;
    final cby = math.cos(by), sby = math.sin(by);
    AskodoxVec3 rotateBody(AskodoxVec3 v) => AskodoxVec3(v.x * cby + v.z * sby, v.y + pose.lift, -v.x * sby + v.z * cby);

    final raster = AskodoxRaster(size);
    for (final part in mesh.parts) {
      final name = part.name;
      final isHand = name.startsWith('hand_');
      final anchor = askodoxCentroid(part.vertices);
      // Part-level animation: lip-synced mouth, blinking/looking eyes,
      // expressive brows, glowing antenna, gesturing hands.
      var sx = 1.0, syPart = 1.0, roll = 0.0;
      var offset = const AskodoxVec3(0, 0, 0);
      if (name == 'mouth') {
        syPart = pose.mouth;
        sx = pose.mouthWidth;
      } else if (name.startsWith('eye')) {
        syPart = pose.eyes;
        offset = AskodoxVec3(pose.gaze.dx * .06, pose.gaze.dy * .05, 0);
      } else if (name.startsWith('brow')) {
        final left = name.endsWith('_l');
        offset = AskodoxVec3(0, pose.browLift + (left ? pose.browTilt : -pose.browTilt) * .12, 0);
        roll = left ? -pose.browTilt : pose.browTilt;
      } else if (name.startsWith('antenna')) {
        offset = AskodoxVec3(0, (pose.antenna - 1) * .15, 0);
      } else if (isHand) {
        final left = name.endsWith('_l');
        final target = left ? pose.handL : pose.handR;
        offset = target - anchor;
        roll = left ? pose.handTiltL : pose.handTiltR;
      }
      final world = <AskodoxVec3>[];
      for (final v in part.vertices) {
        var local = AskodoxVec3(anchor.x + (v.x - anchor.x) * sx, anchor.y + (v.y - anchor.y) * syPart, v.z);
        local = askodoxRollAround(local, anchor, roll) + offset;
        world.add(isHand ? rotateBody(local) : rotateHead(local));
      }
      final isHead = name == 'head';
      final onTop = name.startsWith('antenna') || isHand;
      // Head first, then details on top of it; a hand behind the head is
      // drawn before it; each group far-to-near.
      final behindHand = isHand && askodoxCentroid(world).z > .2;
      raster.add(world, part.triangles, part.color,
          bucket: isHead ? 1000.0 : (behindHand ? 2000.0 : 0.0), hideBehind: !isHead && !onTop);
    }
    raster.draw(canvas, shadowWidth: 1.6 * (1 - pose.lift));
  }

  @override
  bool shouldRepaint(AskodoxCompanion3dPainter old) =>
      old.t != t || old.mood != mood || old.mesh != mesh || old.signals != signals;
}
