/// Photo measurement with a reference object of known size (no AR): the
/// user marks the reference's two ends and the target's two ends in one
/// photo; the target length = reference length x (target pixels / reference
/// pixels). Valid only when both lie on the same flat plane, roughly facing
/// the camera -- the result says so and is never survey-grade.
library;

import 'dart:math' as math;

import 'construction_calculators.dart' show AskodoxCalcException;

class AskodoxReferenceObject {
  const AskodoxReferenceObject(this.id, this.nameEn, this.nameTe, this.lengthMm);
  final String id;
  final String nameEn;
  final String nameTe;
  final double lengthMm;
}

/// Standard sizes: ISO 216 A4 paper (210 x 297 mm), ISO/IEC 7810 ID-1 card
/// (85.60 x 53.98 mm -- bank / ID / driving-licence cards). "custom" = typed.
const askodoxReferenceObjects = <AskodoxReferenceObject>[
  AskodoxReferenceObject('a4_long', 'A4 sheet — long side (297 mm)', 'A4 పేపర్ — పొడవు వైపు (297 మి.మీ.)', 297),
  AskodoxReferenceObject('a4_short', 'A4 sheet — short side (210 mm)', 'A4 పేపర్ — వెడల్పు వైపు (210 మి.మీ.)', 210),
  AskodoxReferenceObject('card_long', 'Bank / ID card — long side (85.6 mm)', 'బ్యాంక్ / ID కార్డు — పొడవు (85.6 మి.మీ.)', 85.6),
  AskodoxReferenceObject('card_short', 'Bank / ID card — short side (54 mm)', 'బ్యాంక్ / ID కార్డు — వెడల్పు (54 మి.మీ.)', 53.98),
];

class AskodoxPoint {
  const AskodoxPoint(this.x, this.y);
  final double x;
  final double y;
  double distanceTo(AskodoxPoint o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));
}

enum AskodoxMeasureQuality { good, fair, poor }

class AskodoxPhotoMeasurement {
  const AskodoxPhotoMeasurement({
    required this.lengthMm,
    required this.lowMm,
    required this.highMm,
    required this.quality,
    required this.warnings,
  });
  final double lengthMm;
  final double lowMm;
  final double highMm;
  final AskodoxMeasureQuality quality;
  final List<String> warnings;

  String formatted() {
    String f(double mm) => mm >= 1000 ? '${(mm / 1000).toStringAsFixed(2)} m' : '${(mm / 10).toStringAsFixed(1)} cm';
    return '${f(lengthMm)} (${f(lowMm)} – ${f(highMm)})';
  }
}

/// [tapErrorPx]: how far a finger tap can be off on each end, in image pixels.
AskodoxPhotoMeasurement askodoxMeasureFromPhoto({
  required AskodoxPoint referenceA,
  required AskodoxPoint referenceB,
  required double referenceMm,
  required AskodoxPoint targetA,
  required AskodoxPoint targetB,
  double tapErrorPx = 6,
}) {
  if (referenceMm.isNaN || referenceMm <= 0) {
    throw const AskodoxCalcException('Reference length must be more than 0.', 'రిఫరెన్స్ పొడవు 0 కంటే ఎక్కువ ఉండాలి.');
  }
  final refPx = referenceA.distanceTo(referenceB);
  final targetPx = targetA.distanceTo(targetB);
  if (refPx < 20) {
    throw const AskodoxCalcException('Mark the reference object\'s two ends further apart (zoom in or come closer).',
        'రిఫరెన్స్ వస్తువు రెండు చివరలు ఇంకా దూరంగా గుర్తించండి.');
  }
  if (targetPx < 5) {
    throw const AskodoxCalcException('Mark the two ends of what you want to measure.', 'కొలవాల్సిన దాని రెండు చివరలు గుర్తించండి.');
  }
  final scale = referenceMm / refPx;
  final length = targetPx * scale;
  // Tap error on both objects, propagated as a range.
  final low = math.max(targetPx - 2 * tapErrorPx, 0.0) * referenceMm / (refPx + 2 * tapErrorPx);
  final high = (targetPx + 2 * tapErrorPx) * referenceMm / math.max(refPx - 2 * tapErrorPx, 1.0);
  final spread = (high - low) / length;
  final ratio = targetPx / refPx;
  final warnings = <String>[
    'Valid only if the reference and the object are on the same flat surface, facing the camera.',
  ];
  if (ratio > 8) warnings.add('The object is much longer than the reference; use a bigger reference (A4) for better accuracy.');
  if (refPx < 80) warnings.add('The reference looks small in the photo; move closer or zoom.');
  final quality = spread < 0.06 ? AskodoxMeasureQuality.good : spread < 0.15 ? AskodoxMeasureQuality.fair : AskodoxMeasureQuality.poor;
  return AskodoxPhotoMeasurement(lengthMm: length, lowMm: low, highMm: high, quality: quality, warnings: warnings);
}
