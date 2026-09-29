import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'askodox_companion.dart';
import 'companion_3d.dart';

/// Human-like ASKODOX companions: ONE shared 3D human rig (head, face,
/// hair, neck, torso, jointed arms, hands) rendered by the same lit-mesh
/// engine as the robot, dressed as different personalities. Personas are
/// visual modes of the one universal ASKODOX assistant -- they never change
/// what ASKODOX does, only how the companion looks.
///
/// Everything is generated in code (no model files in the APK). A richer
/// mesh in the same rig format can be downloaded as an optional avatar pack
/// (see companion_avatar_packs.dart); the procedural rig is the instant,
/// offline baseline.
enum AskodoxPersona {
  friendlyAssistant,
  professionalGuide,
  serviceExpert,
  travelGuide,
  financeAdvisor,
  educationMentor,
  wellnessSupport,
  lifestyleFriend,
  techExpert,
}

String askodoxPersonaLabel(AskodoxPersona persona, {bool telugu = false}) => switch (persona) {
      AskodoxPersona.friendlyAssistant => telugu ? 'స్నేహ సహాయకుడు' : 'Friendly Assistant',
      AskodoxPersona.professionalGuide => telugu ? 'ప్రొఫెషనల్ గైడ్' : 'Professional Guide',
      AskodoxPersona.serviceExpert => telugu ? 'సర్వీస్ నిపుణుడు' : 'Service Expert',
      AskodoxPersona.travelGuide => telugu ? 'ట్రావెల్ గైడ్' : 'Travel Guide',
      AskodoxPersona.financeAdvisor => telugu ? 'ఫైనాన్స్ సలహాదారు' : 'Finance Advisor',
      AskodoxPersona.educationMentor => telugu ? 'విద్యా మార్గదర్శి' : 'Education Mentor',
      AskodoxPersona.wellnessSupport => telugu ? 'ఆరోగ్య సహాయం' : 'Health & Wellness',
      AskodoxPersona.lifestyleFriend => telugu ? 'లైఫ్‌స్టైల్ స్నేహితుడు' : 'Lifestyle Friend',
      AskodoxPersona.techExpert => telugu ? 'టెక్ నిపుణుడు' : 'Tech Expert',
    };

/// Automatic mode: the persona follows what the ASKODOX brain decided the
/// conversation is about (its generic domain -- never a product category).
AskodoxPersona askodoxPersonaForDomain(String? domain) => switch ((domain ?? '').toUpperCase()) {
      'SERVICE' || 'APPOINTMENT' => AskodoxPersona.serviceExpert,
      'RIDE' || 'PARCEL' => AskodoxPersona.travelGuide,
      'LEDGER' => AskodoxPersona.financeAdvisor,
      'JOB_SEEKER' || 'STAFFING' => AskodoxPersona.professionalGuide,
      'EVENT' => AskodoxPersona.lifestyleFriend,
      _ => AskodoxPersona.friendlyAssistant,
    };

enum AskodoxHairStyle { short, long, bun, curly, covered }

enum AskodoxAccessory { glasses, tie, collar, cap, hat, headset, badge, earrings, coat }

/// How one persona looks on the shared rig.
class AskodoxHumanStyle {
  const AskodoxHumanStyle({
    required this.skin,
    required this.hair,
    required this.hairStyle,
    required this.outfit,
    this.accent = const Color(0xFFFFFFFF),
    this.shortSleeves = false,
    this.accessories = const {},
  });

  final Color skin, hair, outfit, accent;
  final AskodoxHairStyle hairStyle;
  final bool shortSleeves;
  final Set<AskodoxAccessory> accessories;

  static AskodoxHumanStyle of(AskodoxPersona persona) => switch (persona) {
        AskodoxPersona.friendlyAssistant => const AskodoxHumanStyle(
            skin: Color(0xFFB9825A), hair: Color(0xFF1E1612), hairStyle: AskodoxHairStyle.short,
            outfit: Color(0xFF14A38B), shortSleeves: true),
        AskodoxPersona.professionalGuide => const AskodoxHumanStyle(
            skin: Color(0xFFC89470), hair: Color(0xFF231A15), hairStyle: AskodoxHairStyle.bun,
            outfit: Color(0xFF1F2F57), accent: Color(0xFF8E2344),
            accessories: {AskodoxAccessory.collar, AskodoxAccessory.tie}),
        AskodoxPersona.serviceExpert => const AskodoxHumanStyle(
            skin: Color(0xFF9E6A45), hair: Color(0xFF1B1411), hairStyle: AskodoxHairStyle.covered,
            outfit: Color(0xFFE0782A), accent: Color(0xFF2B3A4A),
            accessories: {AskodoxAccessory.cap, AskodoxAccessory.badge}),
        AskodoxPersona.travelGuide => const AskodoxHumanStyle(
            skin: Color(0xFFB57E55), hair: Color(0xFF2A1D14), hairStyle: AskodoxHairStyle.covered,
            outfit: Color(0xFF6B7B3A), accent: Color(0xFFCDB27A),
            accessories: {AskodoxAccessory.hat}),
        AskodoxPersona.financeAdvisor => const AskodoxHumanStyle(
            skin: Color(0xFFD2A07C), hair: Color(0xFF3B3B3B), hairStyle: AskodoxHairStyle.short,
            outfit: Color(0xFF3A3F47), accent: Color(0xFF1F4E8C),
            accessories: {AskodoxAccessory.collar, AskodoxAccessory.tie, AskodoxAccessory.glasses}),
        AskodoxPersona.educationMentor => const AskodoxHumanStyle(
            skin: Color(0xFFAF7852), hair: Color(0xFF1A1310), hairStyle: AskodoxHairStyle.long,
            outfit: Color(0xFFC99A2E), accessories: {AskodoxAccessory.glasses}),
        AskodoxPersona.wellnessSupport => const AskodoxHumanStyle(
            skin: Color(0xFFC08A63), hair: Color(0xFF221812), hairStyle: AskodoxHairStyle.bun,
            outfit: Color(0xFFF4F6F8), accent: Color(0xFF1C9C8C),
            accessories: {AskodoxAccessory.coat, AskodoxAccessory.badge}),
        AskodoxPersona.lifestyleFriend => const AskodoxHumanStyle(
            skin: Color(0xFFB27B57), hair: Color(0xFF3A2317), hairStyle: AskodoxHairStyle.long,
            outfit: Color(0xFFE9665A), shortSleeves: true, accessories: {AskodoxAccessory.earrings}),
        AskodoxPersona.techExpert => const AskodoxHumanStyle(
            skin: Color(0xFF8F5E3D), hair: Color(0xFF15100D), hairStyle: AskodoxHairStyle.curly,
            outfit: Color(0xFF2B2F3A), accent: Color(0xFF3FA7FF),
            accessories: {AskodoxAccessory.headset}),
      };
}

/// Builds the shared human rig for a style. Part names drive animation:
/// `head*`/face parts follow the head, `body*` parts the torso, hands and
/// the posed arms follow gestures.
class AskodoxHumanRig {
  static const headCentre = AskodoxVec3(0, .55, 0);
  static const neckPivot = AskodoxVec3(0, .08, 0);
  static const shoulderL = AskodoxVec3(-.6, -.32, .05);
  static const shoulderR = AskodoxVec3(.6, -.32, .05);
  static const upperArm = .5;
  static const forearm = .48;

  static AskodoxMesh build(AskodoxHumanStyle style) {
    final e = AskodoxMesh.ellipsoid;
    final skin = style.skin;
    final shade = Color.lerp(skin, Colors.black, .12)!;
    final lip = Color.lerp(skin, const Color(0xFFB0404A), .45)!;
    final blush = Color.lerp(skin, const Color(0xFFE77A86), .25)!;
    const eyeWhite = Color(0xFFF7F4EF);
    const iris = Color(0xFF3B2416);
    final parts = <AskodoxMeshPart>[
      // Body (torso + neck), clothing coloured.
      // Bust torso: wide shoulders, cropped below the chest.
      e('body_torso', const AskodoxVec3(0, -.78, .06), const AskodoxVec3(.74, .56, .42), style.outfit,
          rings: 12, segments: 22, phiTo: math.pi * .78),
      AskodoxMesh.cylinder('body_neck', const AskodoxVec3(0, -.3, .03), .18, .42, shade, segments: 12),
      // Head and face.
      e('head', headCentre, const AskodoxVec3(.43, .53, .46), skin, rings: 16, segments: 22),
      e('head_ear_l', const AskodoxVec3(-.42, .55, .02), const AskodoxVec3(.06, .11, .07), shade, rings: 5, segments: 8),
      e('head_ear_r', const AskodoxVec3(.42, .55, .02), const AskodoxVec3(.06, .11, .07), shade, rings: 5, segments: 8),
      e('face_eye_l', const AskodoxVec3(-.16, .62, -.395), const AskodoxVec3(.08, .052, .04), eyeWhite, rings: 6, segments: 10),
      e('face_eye_r', const AskodoxVec3(.16, .62, -.395), const AskodoxVec3(.08, .052, .04), eyeWhite, rings: 6, segments: 10),
      e('face_iris_l', const AskodoxVec3(-.16, .62, -.43), const AskodoxVec3(.036, .04, .015), iris, rings: 5, segments: 8),
      e('face_iris_r', const AskodoxVec3(.16, .62, -.43), const AskodoxVec3(.036, .04, .015), iris, rings: 5, segments: 8),
      e('face_brow_l', const AskodoxVec3(-.16, .735, -.41), const AskodoxVec3(.095, .02, .03), style.hair, rings: 4, segments: 8),
      e('face_brow_r', const AskodoxVec3(.16, .735, -.41), const AskodoxVec3(.095, .02, .03), style.hair, rings: 4, segments: 8),
      e('face_nose', const AskodoxVec3(0, .5, -.465), const AskodoxVec3(.045, .085, .06), shade, rings: 6, segments: 10),
      e('face_cheek_l', const AskodoxVec3(-.25, .43, -.36), const AskodoxVec3(.09, .06, .05), blush, rings: 5, segments: 8),
      e('face_cheek_r', const AskodoxVec3(.25, .43, -.36), const AskodoxVec3(.09, .06, .05), blush, rings: 5, segments: 8),
      e('face_mouth', const AskodoxVec3(0, .325, -.4), const AskodoxVec3(.085, .022, .03), const Color(0xFF4A1A1E), rings: 5, segments: 10),
      e('face_lip_upper', const AskodoxVec3(0, .345, -.415), const AskodoxVec3(.09, .018, .025), lip, rings: 4, segments: 10),
      e('face_lip_lower', const AskodoxVec3(0, .302, -.41), const AskodoxVec3(.082, .022, .028), lip, rings: 4, segments: 10),
    ];
    // Hair: a cap over the top/back of the head, plus the style.
    // Back of the head (behind the face, so only the sides/back show).
    parts.add(e('head_hair_nape', const AskodoxVec3(0, .56, .14), const AskodoxVec3(.45, .5, .4), style.hair, rings: 8, segments: 16));
    if (style.hairStyle != AskodoxHairStyle.covered) {
      final curly = style.hairStyle == AskodoxHairStyle.curly;
      // Top cap ending at the hairline above the brows.
      parts.add(e('head_hair', const AskodoxVec3(0, .62, .04), AskodoxVec3(.47, curly ? .54 : .5, .5), style.hair,
          rings: 10, segments: 18, phiTo: math.pi * .42));
      if (curly) {
        for (var i = 0; i < 6; i++) {
          final a = -1.1 + i * .44;
          parts.add(e('head_hair_curl$i', AskodoxVec3(.34 * math.sin(a), 1.02 - .05 * (a * a), .05 - .12 * math.cos(a)),
              const AskodoxVec3(.12, .1, .12), style.hair, rings: 5, segments: 8));
        }
      }
      if (style.hairStyle == AskodoxHairStyle.long) {
        parts.add(e('head_hair_back', const AskodoxVec3(0, .22, .24), const AskodoxVec3(.47, .56, .24), style.hair, rings: 8, segments: 14));
      }
      if (style.hairStyle == AskodoxHairStyle.bun) {
        parts.add(e('head_hair_bun', const AskodoxVec3(0, .98, .32), const AskodoxVec3(.16, .15, .15), style.hair, rings: 6, segments: 10));
      }
    }
    final a = style.accessories;
    if (a.contains(AskodoxAccessory.cap)) {
      parts
        ..add(e('head_cap', const AskodoxVec3(0, .78, .03), const AskodoxVec3(.47, .34, .5), style.outfit,
            rings: 8, segments: 18, phiTo: math.pi * .5))
        ..add(e('head_cap_brim', const AskodoxVec3(0, .79, -.42), const AskodoxVec3(.3, .03, .2), style.accent, rings: 4, segments: 12));
    }
    if (a.contains(AskodoxAccessory.hat)) {
      parts
        ..add(e('head_hat', const AskodoxVec3(0, .86, .04), const AskodoxVec3(.44, .32, .46), style.accent,
            rings: 8, segments: 18, phiTo: math.pi * .5))
        ..add(e('head_hat_brim', const AskodoxVec3(0, .86, .03), const AskodoxVec3(.78, .035, .74), Color.lerp(style.accent, Colors.black, .15)!,
            rings: 4, segments: 22));
    }
    if (a.contains(AskodoxAccessory.glasses)) {
      const frame = Color(0xFF1C1C22);
      parts
        ..add(AskodoxMesh.torus('face_glasses_l', const AskodoxVec3(-.16, .62, -.45), .1, .012, frame, yScale: .75))
        ..add(AskodoxMesh.torus('face_glasses_r', const AskodoxVec3(.16, .62, -.45), .1, .012, frame, yScale: .75))
        ..add(e('face_glasses_bridge', const AskodoxVec3(0, .63, -.465), const AskodoxVec3(.05, .01, .01), frame, rings: 3, segments: 6));
    }
    if (a.contains(AskodoxAccessory.headset)) {
      parts
        ..add(e('head_headset_l', const AskodoxVec3(-.45, .56, .02), const AskodoxVec3(.07, .13, .12), const Color(0xFF15181E), rings: 5, segments: 8))
        ..add(e('head_headset_r', const AskodoxVec3(.45, .56, .02), const AskodoxVec3(.07, .13, .12), const Color(0xFF15181E), rings: 5, segments: 8))
        ..add(e('head_headset_band', const AskodoxVec3(0, .97, .02), const AskodoxVec3(.46, .05, .06), const Color(0xFF15181E), rings: 4, segments: 14))
        ..add(e('face_headset_mic', const AskodoxVec3(.22, .33, -.36), const AskodoxVec3(.035, .035, .035), style.accent, rings: 4, segments: 6));
    }
    if (a.contains(AskodoxAccessory.earrings)) {
      parts
        ..add(e('head_earring_l', const AskodoxVec3(-.43, .42, -.02), const AskodoxVec3(.03, .03, .03), const Color(0xFFE8B84A), rings: 4, segments: 6))
        ..add(e('head_earring_r', const AskodoxVec3(.43, .42, -.02), const AskodoxVec3(.03, .03, .03), const Color(0xFFE8B84A), rings: 4, segments: 6));
    }
    if (a.contains(AskodoxAccessory.collar)) {
      parts
        ..add(e('body_collar_l', const AskodoxVec3(-.12, -.42, -.3), const AskodoxVec3(.13, .08, .06), const Color(0xFFF5F5F5), rings: 4, segments: 8))
        ..add(e('body_collar_r', const AskodoxVec3(.12, -.42, -.3), const AskodoxVec3(.13, .08, .06), const Color(0xFFF5F5F5), rings: 4, segments: 8));
    }
    if (a.contains(AskodoxAccessory.tie)) {
      parts.add(e('body_tie', const AskodoxVec3(0, -.72, -.36), const AskodoxVec3(.06, .26, .03), style.accent, rings: 6, segments: 8));
    }
    if (a.contains(AskodoxAccessory.coat)) {
      parts.add(e('body_scrubs', const AskodoxVec3(0, -.62, -.3), const AskodoxVec3(.2, .22, .06), style.accent, rings: 5, segments: 10));
    }
    if (a.contains(AskodoxAccessory.badge)) {
      parts.add(e('body_badge', const AskodoxVec3(.32, -.72, -.33), const AskodoxVec3(.07, .05, .02),
          a.contains(AskodoxAccessory.coat) ? const Color(0xFF2FA84F) : const Color(0xFFF2C94C), rings: 4, segments: 8));
    }
    parts
      ..add(e('hand_l', const AskodoxVec3(0, 0, 0), const AskodoxVec3(.1, .12, .075), skin, rings: 6, segments: 10))
      ..add(e('hand_r', const AskodoxVec3(0, 0, 0), const AskodoxVec3(.1, .12, .075), skin, rings: 6, segments: 10));
    return AskodoxMesh(parts, meta: {
      'rig': 'human',
      'sleeve': style.outfit.toARGB32(),
      'forearm': (style.shortSleeves ? skin : style.outfit).toARGB32(),
    });
  }
}

/// Human pose: head/face values from the shared mood pose (expressions,
/// lip-sync, blink, gaze) + body and hand gestures on the human scale.
class AskodoxHumanPose {
  AskodoxHumanPose(this.face, {required this.handL, required this.handR, this.lean = 0, this.shrug = 0, this.breathe = 0,
      this.smile = 0});
  final AskodoxPose face;
  final AskodoxVec3 handL, handR;
  final double lean, shrug, breathe, smile;
}

AskodoxHumanPose askodoxHumanPoseFor(AskodoxCompanionMood mood, double t,
    [AskodoxCompanionSignals signals = const AskodoxCompanionSignals()]) {
  final face = askodoxPoseFor(mood, t, signals);
  final s = math.sin(t * 2 * math.pi);
  final breathe = .5 + .5 * math.sin(t * 2 * math.pi);
  const restL = AskodoxVec3(-.28, -1.08, -.6), restR = AskodoxVec3(.28, -1.08, -.6);
  // Head motion is gentler on a human than on the robot.
  face
    ..yaw *= .6
    ..pitch *= .7
    ..roll *= .6;
  switch (mood) {
    case AskodoxCompanionMood.idle:
      return AskodoxHumanPose(face, handL: restL, handR: restR, breathe: breathe, smile: .3);
    case AskodoxCompanionMood.greeting:
      final wave = math.sin(t * 6 * math.pi);
      return AskodoxHumanPose(face,
          handL: restL, handR: AskodoxVec3(.82 + .1 * wave, .42, -.42), smile: 1, breathe: breathe);
    case AskodoxCompanionMood.listening:
      return AskodoxHumanPose(face,
          handL: const AskodoxVec3(-.6, .5, -.12), handR: restR, lean: .08 + .05 * signals.micLevel, smile: .2);
    case AskodoxCompanionMood.understanding:
      // Holding what was sent in front, reading it.
      return AskodoxHumanPose(face,
          handL: const AskodoxVec3(-.2, -.62, -.92), handR: const AskodoxVec3(.2, -.62, -.92), lean: .05, smile: .1);
    case AskodoxCompanionMood.suggesting:
      // One more detail, please: an open palm offered toward the customer.
      return AskodoxHumanPose(face,
          handL: restL, handR: AskodoxVec3(.6, -.45 + .03 * s.abs(), -.9), smile: .6, breathe: breathe);
    case AskodoxCompanionMood.guiding:
      // Pointing at the option while the request is sent.
      return AskodoxHumanPose(face,
          handL: restL, handR: AskodoxVec3(1.02 + .04 * s, -.1, -.62), lean: .04, smile: .5);
    case AskodoxCompanionMood.thinking:
      return AskodoxHumanPose(face,
          handL: const AskodoxVec3(-.05, -.8, -.62), handR: AskodoxVec3(.1, .18 + .02 * math.sin(t * 8 * math.pi), -.6), lean: -.03);
    case AskodoxCompanionMood.speaking:
      return AskodoxHumanPose(face,
          handL: AskodoxVec3(-.46, -.72 + .16 * math.max(0, s), -.78),
          handR: AskodoxVec3(.46, -.72 + .16 * math.max(0, -s), -.78),
          lean: .03, smile: .4, breathe: breathe);
    case AskodoxCompanionMood.explaining:
      return AskodoxHumanPose(face,
          handL: const AskodoxVec3(-.42, -.82, -.72), handR: AskodoxVec3(1.02 + .04 * s, -.22, -.62), smile: .5);
    case AskodoxCompanionMood.success:
      final up = .08 * s.abs();
      return AskodoxHumanPose(face,
          handL: AskodoxVec3(-.7, .18 + up, -.5), handR: AskodoxVec3(.7, .18 + up, -.5), smile: 1);
    case AskodoxCompanionMood.help:
      return AskodoxHumanPose(face,
          handL: const AskodoxVec3(-.62, -.62, -.8), handR: const AskodoxVec3(.62, -.62, -.8),
          shrug: .06 + .04 * s.abs(), smile: -.4);
  }
}

/// Elbow from shoulder [s] to hand [h]: two-bone IK bending outward/down.
AskodoxVec3 askodoxElbow(AskodoxVec3 s, AskodoxVec3 h, {required bool left}) {
  const l1 = AskodoxHumanRig.upperArm, l2 = AskodoxHumanRig.forearm;
  final d = h - s;
  final len = math.sqrt(d.dot(d));
  final dir = d.unit;
  if (len >= l1 + l2 - 1e-3) return s + dir.scale(l1);
  final along = (l1 * l1 - l2 * l2 + len * len) / (2 * len);
  final height = math.sqrt(math.max(0, l1 * l1 - along * along));
  final pref = AskodoxVec3(left ? -1 : 1, -.7, .5);
  var bend = pref - dir.scale(pref.dot(dir));
  if (bend.dot(bend) < 1e-6) bend = const AskodoxVec3(0, -1, 0);
  return s + dir.scale(along) + bend.unit.scale(height);
}

/// A limb (cylinder) between two points, generated per frame.
(List<AskodoxVec3>, List<int>) askodoxLimb(AskodoxVec3 a, AskodoxVec3 b, double radius, {int segments = 8}) {
  final dir = (b - a).unit;
  var u = dir.cross(const AskodoxVec3(0, 0, 1));
  if (u.dot(u) < 1e-4) u = dir.cross(const AskodoxVec3(1, 0, 0));
  u = u.unit;
  final v = dir.cross(u).unit;
  final vs = <AskodoxVec3>[];
  final ts = <int>[];
  for (var j = 0; j <= segments; j++) {
    final t = 2 * math.pi * j / segments;
    final off = u.scale(math.cos(t) * radius) + v.scale(math.sin(t) * radius);
    vs
      ..add(a + off)
      ..add(b + off);
  }
  for (var j = 0; j < segments; j++) {
    final i = j * 2;
    ts.addAll([i, i + 2, i + 1, i + 1, i + 2, i + 3]);
  }
  return (vs, ts);
}

/// Paints a human companion mesh for a mood.
class AskodoxHuman3dPainter extends CustomPainter {
  AskodoxHuman3dPainter({
    required this.mesh,
    required this.mood,
    required this.t,
    this.signals = const AskodoxCompanionSignals(),
    this.onError,
  });

  final AskodoxMesh mesh;
  final AskodoxCompanionMood mood;
  final double t;
  final AskodoxCompanionSignals signals;

  /// Called (once per failing frame) when drawing fails, so the widget can
  /// fall back to the lite robot instead of showing nothing.
  final VoidCallback? onError;

  /// Triangles drawn in the last frame (performance tests / telemetry).
  static int lastTriangles = 0;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paint(canvas, size);
    } catch (_) {
      onError?.call();
    }
  }

  void _paint(Canvas canvas, Size size) {
    final pose = askodoxHumanPoseFor(mood, t, signals);
    final f = pose.face;
    final raster = AskodoxRaster(size, frameHeight: 2.35, frameCenterY: -.24);

    // Body: slight lean (pitch about the hips), breathing, a third of the
    // head's yaw.
    const hip = AskodoxVec3(0, -1.5, 0);
    final by = f.yaw * .35, cby = math.cos(by), sby = math.sin(by);
    final cl = math.cos(pose.lean), sl = math.sin(pose.lean);
    AskodoxVec3 body(AskodoxVec3 v) {
      var x = v.x, y = v.y - hip.y, z = v.z;
      final y2 = y * cl + z * sl, z2 = -y * sl + z * cl; // lean forward
      y = y2;
      z = z2;
      final x3 = x * cby + z * sby, z3 = -x * sby + z * cby;
      return AskodoxVec3(x3, y + hip.y + f.lift * .5, z3);
    }

    // Head: yaw/pitch/roll about the neck, then the body transform.
    final cy = math.cos(f.yaw), sy = math.sin(f.yaw);
    final cp = math.cos(f.pitch), sp = math.sin(f.pitch);
    final cr = math.cos(f.roll), sr = math.sin(f.roll);
    const pivot = AskodoxHumanRig.neckPivot;
    AskodoxVec3 head(AskodoxVec3 v) {
      var x = v.x - pivot.x, y = v.y - pivot.y, z = v.z - pivot.z;
      final x1 = x * cr - y * sr, y1 = x * sr + y * cr;
      x = x1;
      y = y1;
      final x2 = x * cy + z * sy, z2 = -x * sy + z * cy;
      x = x2;
      z = z2;
      final y3 = y * cp - z * sp, z3 = y * sp + z * cp;
      return body(AskodoxVec3(x + pivot.x, y3 + pivot.y, z3 + pivot.z));
    }

    final open = ((f.mouth - 1) / 2.6).clamp(0.0, 1.0);
    for (final part in mesh.parts) {
      final name = part.name;
      if (name.startsWith('hand_')) continue; // drawn with the arms
      final anchor = askodoxCentroid(part.vertices);
      var sx = 1.0, syPart = 1.0, roll = 0.0;
      var offset = const AskodoxVec3(0, 0, 0);
      if (name == 'face_mouth') {
        syPart = .6 + 3.2 * open + (f.mouth < 1 ? 0 : 0);
        sx = f.mouthWidth * (1 + .12 * pose.smile);
      } else if (name == 'face_lip_upper') {
        offset = AskodoxVec3(0, .02 * open, 0);
        sx = f.mouthWidth * (1 + .1 * pose.smile);
      } else if (name == 'face_lip_lower') {
        offset = AskodoxVec3(0, -.055 * open, 0);
        sx = f.mouthWidth * (1 + .1 * pose.smile);
      } else if (name.startsWith('face_eye') || name.startsWith('face_iris')) {
        syPart = f.eyes.clamp(.05, 1.3) * (1 - .15 * pose.smile.clamp(0, 1));
        if (name.startsWith('face_iris')) offset = AskodoxVec3(f.gaze.dx * .03, f.gaze.dy * .022, 0);
      } else if (name.startsWith('face_brow')) {
        final left = name.endsWith('_l');
        offset = AskodoxVec3(0, f.browLift * .5 + (left ? f.browTilt : -f.browTilt) * .05, 0);
        roll = left ? -f.browTilt * .8 : f.browTilt * .8;
      } else if (name.startsWith('face_cheek')) {
        offset = AskodoxVec3(0, .02 * pose.smile.clamp(0, 1), 0);
      }
      final isHead = name.startsWith('head') || name.startsWith('face');
      final bodyPart = name.startsWith('body');
      final world = <AskodoxVec3>[];
      for (final v in part.vertices) {
        var local = AskodoxVec3(anchor.x + (v.x - anchor.x) * sx, anchor.y + (v.y - anchor.y) * syPart, v.z);
        local = askodoxRollAround(local, anchor, roll) + offset;
        if (name == 'body_torso') {
          // Breathing + shrug lift the chest a little.
          local = AskodoxVec3(local.x, local.y + (local.y - anchor.y) * .015 * pose.breathe + pose.shrug * .5, local.z);
        }
        world.add(isHead ? head(local) : (bodyPart ? body(local) : body(local)));
      }
      raster.add(world, part.triangles, part.color, hideBehind: name.startsWith('face'), wound: part.wound);
    }

    // Arms: shoulder -> elbow (IK) -> hand, posed for the gesture.
    final sleeve = Color((mesh.meta['sleeve'] as int?) ?? 0xFF14A38B);
    final forearmColor = Color((mesh.meta['forearm'] as int?) ?? sleeve.toARGB32());
    for (final left in [true, false]) {
      final shoulder = body((left ? AskodoxHumanRig.shoulderL : AskodoxHumanRig.shoulderR) + AskodoxVec3(0, pose.shrug, 0));
      final hand = body(left ? pose.handL : pose.handR);
      final elbow = askodoxElbow(shoulder, hand, left: left);
      final (uv, ut) = askodoxLimb(shoulder, elbow, .12);
      raster.add(uv, ut, sleeve);
      final (fv, ft) = askodoxLimb(elbow, hand, .095);
      raster.add(fv, ft, forearmColor);
      final joint = AskodoxMesh.ellipsoid('joint', elbow, const AskodoxVec3(.11, .11, .11), sleeve, rings: 5, segments: 8);
      raster.add(joint.vertices, joint.triangles, sleeve);
      final shoulderBall = AskodoxMesh.ellipsoid('shoulder', shoulder, const AskodoxVec3(.15, .15, .15), sleeve, rings: 5, segments: 8);
      raster.add(shoulderBall.vertices, shoulderBall.triangles, sleeve);
      final handPart = mesh.parts.where((p) => p.name == (left ? 'hand_l' : 'hand_r')).firstOrNull;
      if (handPart != null) {
        final anchor = askodoxCentroid(handPart.vertices);
        final tilt = left ? f.handTiltL : f.handTiltR;
        final world = [
          for (final v in handPart.vertices) askodoxRollAround(v, anchor, tilt) - anchor + hand,
        ];
        raster.add(world, handPart.triangles, handPart.color);
      }
    }
    lastTriangles = raster.triangleCount;
    raster.draw(canvas, shadowY: 1.18, shadowWidth: 1.5);
  }

  @override
  bool shouldRepaint(AskodoxHuman3dPainter old) =>
      old.t != t || old.mood != mood || old.mesh != mesh || old.signals != signals;
}
