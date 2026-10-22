/// Pure sensor maths for the level and compass (unit-tested without a phone).
library;

import 'dart:math' as math;

class AskodoxVec3 {
  const AskodoxVec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  double get length => math.sqrt(x * x + y * y + z * z);

  /// Exponential low-pass: keeps gravity / field, drops hand shake.
  AskodoxVec3 smooth(AskodoxVec3 next, {double alpha = 0.15}) =>
      AskodoxVec3(x + alpha * (next.x - x), y + alpha * (next.y - y), z + alpha * (next.z - z));
}

double _deg(double rad) => rad * 180 / math.pi;

/// Phone lying flat: tilt along the short (x) and long (y) axes in degrees.
/// 0/0 = level. Positive x = right side low... sign only drives the bubble.
({double tiltX, double tiltY}) askodoxFlatTilt(AskodoxVec3 gravity) =>
    (tiltX: _deg(math.atan2(gravity.x, gravity.z)), tiltY: _deg(math.atan2(gravity.y, gravity.z)));

/// Phone standing on its long edge against a surface (portrait): the angle
/// of the phone's long axis from vertical (0 = plumb) and the matching angle
/// from horizontal (90 - that).
({double fromVertical, double fromHorizontal}) askodoxEdgeAngle(AskodoxVec3 gravity) {
  final fromVertical = _deg(math.atan2(gravity.x, gravity.y)).abs();
  final folded = fromVertical > 90 ? 180 - fromVertical : fromVertical;
  return (fromVertical: folded, fromHorizontal: 90 - folded);
}

/// Total inclination of the screen from horizontal (0 = flat, 90 = upright).
double askodoxInclination(AskodoxVec3 gravity) {
  final g = gravity.length;
  if (g == 0) return 0;
  return _deg(math.acos((gravity.z / g).clamp(-1.0, 1.0)));
}

/// Tilt-compensated magnetic heading in degrees (0 = magnetic north,
/// clockwise), the same construction as Android's getRotationMatrix.
/// Null when the phone is in free fall or the field is parallel to gravity.
double? askodoxHeading(AskodoxVec3 gravity, AskodoxVec3 magnetic) {
  final ax = gravity.x, ay = gravity.y, az = gravity.z;
  final ex = magnetic.x, ey = magnetic.y, ez = magnetic.z;
  var hx = ey * az - ez * ay;
  var hy = ez * ax - ex * az;
  var hz = ex * ay - ey * ax;
  final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
  final normA = gravity.length;
  if (normH < 0.1 || normA < 0.1) return null;
  hx /= normH;
  hy /= normH;
  hz /= normH;
  final nx = ax / normA, ny = ay / normA, nz = az / normA;
  final my = nz * hx - nx * hz;
  final heading = _deg(math.atan2(hy, my));
  return (heading + 360) % 360;
}

String askodoxCardinal(double heading, {bool te = false}) {
  const en = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  const tel = ['ఉత్తరం', 'ఈశాన్యం', 'తూర్పు', 'ఆగ్నేయం', 'దక్షిణం', 'నైరుతి', 'పడమర', 'వాయువ్యం'];
  final index = ((heading % 360) / 45).round() % 8;
  return te ? tel[index] : en[index];
}
