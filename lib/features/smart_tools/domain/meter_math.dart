/// Pure maths for the protractor, light meter, sound meter and the guided
/// vehicle report (unit-tested without a phone).
library;

import 'dart:math' as math;

import 'photo_measure.dart' show AskodoxPoint;

/// The angle at [vertex] between the arms to [a] and [b], in degrees (0..180).
/// Null when an arm has no length (two taps on the same spot).
double? askodoxAngleAt(AskodoxPoint a, AskodoxPoint vertex, AskodoxPoint b) {
  final ax = a.x - vertex.x, ay = a.y - vertex.y;
  final bx = b.x - vertex.x, by = b.y - vertex.y;
  final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
  if (la < 1e-6 || lb < 1e-6) return null;
  final cos = ((ax * bx + ay * by) / (la * lb)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// Rough angular error (degrees) from a tap error of [tapErrorPx] on arms of the
/// given lengths: each arm's direction can move by atan(err / length).
double askodoxAngleError(AskodoxPoint a, AskodoxPoint vertex, AskodoxPoint b, {double tapErrorPx = 6}) {
  double arm(AskodoxPoint p) => math.sqrt(math.pow(p.x - vertex.x, 2) + math.pow(p.y - vertex.y, 2));
  double dir(double len) => len < 1e-6 ? 90 : math.atan(tapErrorPx / len) * 180 / math.pi;
  return dir(arm(a)) + dir(arm(b));
}

/// Typical light levels (approximate ranges; phone light sensors are not calibrated).
class AskodoxLuxBand {
  const AskodoxLuxBand(this.id, this.en, this.te, this.below);
  final String id;
  final String en;
  final String te;

  /// Upper bound (exclusive) in lux.
  final double below;
}

const askodoxLuxBands = <AskodoxLuxBand>[
  AskodoxLuxBand('dark', 'Dark', 'చీకటి', 10),
  AskodoxLuxBand('dim', 'Dim room', 'మసక వెలుతురు', 100),
  AskodoxLuxBand('indoor', 'Normal indoor light', 'సాధారణ ఇంటి వెలుతురు', 300),
  AskodoxLuxBand('work', 'Bright — reading / office work', 'చదవడానికి / ఆఫీస్ పనికి సరిపడా', 1000),
  AskodoxLuxBand('very_bright', 'Very bright (overcast daylight)', 'చాలా వెలుతురు (మేఘాల పగలు)', 10000),
  AskodoxLuxBand('sun', 'Daylight / direct sun', 'పగటి ఎండ', double.infinity),
];

AskodoxLuxBand askodoxLuxBand(double lux) => askodoxLuxBands.firstWhere((b) => lux < b.below);

/// A microphone reading. Phones report digital full-scale level (dBFS, 0 = loudest
/// the mic can record); it becomes an approximate dB value only with an offset the
/// user measured against a real sound-level meter.
class AskodoxSoundReading {
  const AskodoxSoundReading({required this.dbfs, required this.peakDbfs});
  final double dbfs;
  final double peakDbfs;

  /// Relative level 0..90 (90 = the mic's maximum), for the bar.
  double get relative => (dbfs + 90).clamp(0, 90).toDouble();

  /// Approximate dB(SPL) only when [offsetDb] (from a calibration) is given.
  double? calibrated(double? offsetDb) => offsetDb == null ? null : dbfs + offsetDb;
}

/// Offset that makes this phone's reading match a reference meter's [meterDb].
double askodoxSoundOffset(double phoneDbfs, double meterDb) => meterDb - phoneDbfs;

/// The four sides of the guided vehicle walk-around, in shooting order.
class AskodoxVehicleSide {
  const AskodoxVehicleSide(this.id, this.en, this.te, this.tipEn, this.tipTe);
  final String id;
  final String en;
  final String te;
  final String tipEn;
  final String tipTe;
}

const askodoxVehicleSides = <AskodoxVehicleSide>[
  AskodoxVehicleSide('front', 'Front', 'ముందు', 'Whole front in frame: bumper, lights, number plate, windscreen.',
      'ముందు భాగం మొత్తం: బంపర్, లైట్లు, నంబర్ ప్లేట్, అద్దం.'),
  AskodoxVehicleSide('rear', 'Rear', 'వెనుక', 'Whole rear: bumper, tail lights, number plate.', 'వెనుక భాగం మొత్తం: బంపర్, టెయిల్ లైట్లు, నంబర్ ప్లేట్.'),
  AskodoxVehicleSide('left', 'Left side', 'ఎడమ వైపు', 'Step back so both wheels and all doors show.', 'రెండు చక్రాలు, అన్ని డోర్లు కనిపించేలా వెనక్కి జరగండి.'),
  AskodoxVehicleSide('right', 'Right side', 'కుడి వైపు', 'Step back so both wheels and all doors show.', 'రెండు చక్రాలు, అన్ని డోర్లు కనిపించేలా వెనక్కి జరగండి.'),
];

/// The note sent with the four photos so the model knows which photo is which side.
String askodoxVehicleInspectionNote({String vehicle = '', String odometer = ''}) {
  final parts = [
    'Guided walk-around of one vehicle. Photos in order: ${askodoxVehicleSides.map((s) => s.en.toLowerCase()).join(', ')}.',
    if (vehicle.trim().isNotEmpty) 'Vehicle as stated by the user: ${vehicle.trim()}.',
    if (odometer.trim().isNotEmpty) 'Odometer as stated by the user: ${odometer.trim()} km (not read from the photos).',
    'Name the side for each visible finding.',
  ];
  return parts.join(' ');
}
