/// Deterministic quantity estimates for construction / home work. On-device,
/// no AI call. Every result lists the assumptions it used so the user (and a
/// mason or engineer) can check them. These are material ESTIMATES, never a
/// structural design or engineering approval. Prices are never invented: a
/// cost appears only when the user typed a rate.
library;

import 'dart:math' as math;

enum AskodoxLengthUnit { metre, foot }

const double _feetPerMetre = 3.28084;

double askodoxToMetres(double value, AskodoxLengthUnit unit) =>
    unit == AskodoxLengthUnit.metre ? value : value / _feetPerMetre;

/// Square metres -> square feet.
double askodoxSqmToSqft(double sqm) => sqm * _feetPerMetre * _feetPerMetre;

class AskodoxCalcException implements Exception {
  const AskodoxCalcException(this.en, this.te);
  final String en;
  final String te;
  String message(bool te) => te ? this.te : en;
  @override
  String toString() => en;
}

void _positive(double value, String en, String te) {
  if (value.isNaN || value.isInfinite || value <= 0) {
    throw AskodoxCalcException('$en must be more than 0.', '$te 0 కంటే ఎక్కువ ఉండాలి.');
  }
}

void _nonNegative(double value, String en, String te) {
  if (value.isNaN || value.isInfinite || value < 0) {
    throw AskodoxCalcException('$en cannot be negative.', '$te నెగటివ్ కాకూడదు.');
  }
}

/// Whole units to buy: floating-point noise (30.0000000004) must not add one.
double _wholeUnits(double value) => (value - 1e-6).ceilToDouble();

double _wastage(double percent) {
  _nonNegative(percent, 'Wastage', 'వేస్టేజ్');
  if (percent > 50) {
    throw const AskodoxCalcException('Wastage above 50% is unusual; check the value.',
        '50% కంటే ఎక్కువ వేస్టేజ్ అసాధారణం; విలువ చూడండి.');
  }
  return 1 + percent / 100;
}

/// One line of a result: label + value + unit.
class AskodoxCalcLine {
  const AskodoxCalcLine(this.labelEn, this.labelTe, this.value, this.unit, {this.decimals = 2});
  final String labelEn;
  final String labelTe;
  final double value;
  final String unit;
  final int decimals;

  String formatted() {
    final fixed = value.toStringAsFixed(decimals);
    final trimmed = decimals == 0 ? fixed : fixed.replaceFirst(RegExp(r'\.?0+$'), '');
    if (unit == '₹') return '₹$trimmed';
    return unit.isEmpty ? trimmed : '$trimmed $unit';
  }
}

class AskodoxCalcResult {
  const AskodoxCalcResult({required this.lines, this.assumptions = const [], this.warnings = const []});
  final List<AskodoxCalcLine> lines;
  final List<String> assumptions;
  final List<String> warnings;

  double valueOf(String labelEn) => lines.firstWhere((l) => l.labelEn == labelEn).value;
}

// ------------------------------------------------------------------ area

enum AskodoxShape { rectangle, triangle, circle }

AskodoxCalcResult askodoxArea({
  required AskodoxShape shape,
  required double a,
  double b = 0,
  AskodoxLengthUnit unit = AskodoxLengthUnit.metre,
  double openingsSqm = 0,
}) {
  final x = askodoxToMetres(a, unit);
  final y = askodoxToMetres(b, unit);
  double area;
  double perimeter;
  switch (shape) {
    case AskodoxShape.rectangle:
      _positive(x, 'Length', 'పొడవు');
      _positive(y, 'Width', 'వెడల్పు');
      area = x * y;
      perimeter = 2 * (x + y);
    case AskodoxShape.triangle:
      // a = base, b = height (right triangle perimeter when legs are base/height)
      _positive(x, 'Base', 'బేస్');
      _positive(y, 'Height', 'ఎత్తు');
      area = x * y / 2;
      perimeter = x + y + math.sqrt(x * x + y * y);
    case AskodoxShape.circle:
      _positive(x, 'Diameter', 'వ్యాసం');
      area = math.pi * x * x / 4;
      perimeter = math.pi * x;
  }
  _nonNegative(openingsSqm, 'Openings', 'తలుపులు/కిటికీలు');
  final net = area - openingsSqm;
  if (net <= 0) {
    throw const AskodoxCalcException('Openings are larger than the area.', 'తలుపులు/కిటికీలు వైశాల్యం కంటే ఎక్కువ.');
  }
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Area', 'వైశాల్యం', net, 'm²'),
    AskodoxCalcLine('Area (sq ft)', 'వైశాల్యం (చ.అ.)', askodoxSqmToSqft(net), 'sq ft'),
    AskodoxCalcLine('Perimeter', 'చుట్టుకొలత', perimeter, 'm'),
  ], assumptions: [
    if (shape == AskodoxShape.triangle) 'Triangle perimeter assumes a right angle between base and height.',
    if (openingsSqm > 0) 'Door / window openings subtracted from the area.',
  ]);
}

// ------------------------------------------------------------------ volume

enum AskodoxSolid { cuboid, cylinder }

AskodoxCalcResult askodoxVolume({
  required AskodoxSolid solid,
  required double a,
  required double b,
  double c = 0,
  AskodoxLengthUnit unit = AskodoxLengthUnit.metre,
}) {
  final x = askodoxToMetres(a, unit);
  final y = askodoxToMetres(b, unit);
  final z = askodoxToMetres(c, unit);
  double volume;
  if (solid == AskodoxSolid.cuboid) {
    _positive(x, 'Length', 'పొడవు');
    _positive(y, 'Width', 'వెడల్పు');
    _positive(z, 'Height', 'ఎత్తు');
    volume = x * y * z;
  } else {
    _positive(x, 'Diameter', 'వ్యాసం');
    _positive(y, 'Height', 'ఎత్తు');
    volume = math.pi * x * x / 4 * y;
  }
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Volume', 'ఘనపరిమాణం', volume, 'm³', decimals: 3),
    AskodoxCalcLine('Volume (cu ft)', 'ఘనపరిమాణం (ఘ.అ.)', volume * math.pow(_feetPerMetre, 3), 'cu ft'),
    AskodoxCalcLine('Capacity', 'సామర్థ్యం', volume * 1000, 'litres', decimals: 0),
  ]);
}

// ------------------------------------------------------------------ bricks / blocks

/// Unit sizes in millimetres (L x W x H, actual, without mortar).
class AskodoxMasonryUnit {
  const AskodoxMasonryUnit(this.id, this.nameEn, this.nameTe, this.l, this.w, this.h);
  final String id;
  final String nameEn;
  final String nameTe;
  final double l;
  final double w;
  final double h;
}

const askodoxMasonryUnits = <AskodoxMasonryUnit>[
  AskodoxMasonryUnit('modular', 'Modular brick 190×90×90', 'మాడ్యులర్ ఇటుక 190×90×90', 190, 90, 90),
  AskodoxMasonryUnit('traditional', 'Traditional brick 230×110×75', 'సాధారణ ఇటుక 230×110×75', 230, 110, 75),
  AskodoxMasonryUnit('block4', 'Concrete block 400×100×200', 'కాంక్రీట్ బ్లాక్ 400×100×200', 400, 100, 200),
  AskodoxMasonryUnit('block6', 'Concrete block 400×150×200', 'కాంక్రీట్ బ్లాక్ 400×150×200', 400, 150, 200),
  AskodoxMasonryUnit('block8', 'Concrete block 400×200×200', 'కాంక్రీట్ బ్లాక్ 400×200×200', 400, 200, 200),
];

/// Cement bag: 50 kg at ~1440 kg/m³ loose density = 0.0347 m³.
const double askodoxCementBagM3 = 0.0347;
const double _dryVolumeFactorMortar = 1.33;
const double _dryVolumeFactorConcrete = 1.54;

AskodoxCalcResult askodoxBricks({
  required double wallLength,
  required double wallHeight,
  required double wallThicknessMm,
  required AskodoxMasonryUnit unit,
  AskodoxLengthUnit lengthUnit = AskodoxLengthUnit.metre,
  double openingsSqm = 0,
  double jointMm = 10,
  double mortarSandParts = 6,
  double wastagePercent = 5,
  double? ratePerUnit,
}) {
  final length = askodoxToMetres(wallLength, lengthUnit);
  final height = askodoxToMetres(wallHeight, lengthUnit);
  _positive(length, 'Wall length', 'గోడ పొడవు');
  _positive(height, 'Wall height', 'గోడ ఎత్తు');
  _positive(wallThicknessMm, 'Wall thickness', 'గోడ మందం');
  _nonNegative(jointMm, 'Mortar joint', 'జాయింట్');
  _positive(mortarSandParts, 'Sand parts', 'ఇసుక భాగాలు');
  _nonNegative(openingsSqm, 'Openings', 'తలుపులు/కిటికీలు');
  if (ratePerUnit != null) _nonNegative(ratePerUnit, 'Rate', 'రేటు');
  final factor = _wastage(wastagePercent);
  final faceArea = length * height - openingsSqm;
  if (faceArea <= 0) {
    throw const AskodoxCalcException('Openings are larger than the wall.', 'తలుపులు/కిటికీలు గోడ కంటే పెద్దవి.');
  }
  final wallVolume = faceArea * wallThicknessMm / 1000;
  final nominal = (unit.l + jointMm) * (unit.w + jointMm) * (unit.h + jointMm) / 1e9;
  final count = wallVolume / nominal;
  final unitsVolume = count * unit.l * unit.w * unit.h / 1e9;
  final wetMortar = math.max(wallVolume - unitsVolume, 0.0);
  final dryMortar = wetMortar * _dryVolumeFactorMortar;
  final cementM3 = dryMortar / (1 + mortarSandParts);
  final sandM3 = dryMortar * mortarSandParts / (1 + mortarSandParts);
  final units = _wholeUnits(count * factor);
  final bags = (cementM3 * factor / askodoxCementBagM3);
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Bricks / blocks', 'ఇటుకలు / బ్లాక్‌లు', units, 'nos', decimals: 0),
    AskodoxCalcLine('Wall volume', 'గోడ ఘనపరిమాణం', wallVolume, 'm³', decimals: 3),
    AskodoxCalcLine('Cement', 'సిమెంట్', bags, 'bags (50 kg)', decimals: 1),
    AskodoxCalcLine('Sand', 'ఇసుక', sandM3 * factor, 'm³', decimals: 3),
    AskodoxCalcLine('Sand (cu ft)', 'ఇసుక (ఘ.అ.)', sandM3 * factor * math.pow(_feetPerMetre, 3), 'cu ft', decimals: 1),
    if (ratePerUnit != null)
      AskodoxCalcLine('Brick / block cost (your rate)', 'ఇటుకల ఖర్చు (మీ రేటు)', units * ratePerUnit, '₹', decimals: 0),
  ], assumptions: [
    '${unit.nameEn} with ${jointMm.toStringAsFixed(0)} mm mortar joints.',
    'Mortar 1:${mortarSandParts.toStringAsFixed(0)} (cement:sand); dry volume = wet × 1.33.',
    'Cement bag 50 kg ≈ 0.0347 m³. Wastage ${wastagePercent.toStringAsFixed(0)}% added.',
  ], warnings: const [
    'Material estimate only -- not a structural design. Load-bearing walls need an engineer.',
  ]);
}

// ------------------------------------------------------------------ concrete / plaster

/// Concrete: mix as cement:sand:aggregate parts (e.g. M20 nominal 1:1.5:3).
AskodoxCalcResult askodoxConcrete({
  required double wetVolumeM3,
  double cementParts = 1,
  double sandParts = 1.5,
  double aggregateParts = 3,
  double wastagePercent = 2,
}) {
  _positive(wetVolumeM3, 'Concrete volume', 'కాంక్రీట్ ఘనపరిమాణం');
  _positive(cementParts, 'Cement parts', 'సిమెంట్ భాగాలు');
  _nonNegative(sandParts, 'Sand parts', 'ఇసుక భాగాలు');
  _nonNegative(aggregateParts, 'Aggregate parts', 'కంకర భాగాలు');
  final factor = _wastage(wastagePercent);
  final total = cementParts + sandParts + aggregateParts;
  final dry = wetVolumeM3 * _dryVolumeFactorConcrete * factor;
  final cement = dry * cementParts / total;
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Cement', 'సిమెంట్', cement / askodoxCementBagM3, 'bags (50 kg)', decimals: 1),
    AskodoxCalcLine('Sand', 'ఇసుక', dry * sandParts / total, 'm³', decimals: 3),
    AskodoxCalcLine('Aggregate', 'కంకర', dry * aggregateParts / total, 'm³', decimals: 3),
  ], assumptions: [
    'Nominal mix 1:${_p(sandParts / cementParts)}:${_p(aggregateParts / cementParts)}; dry volume = wet × 1.54.',
    'Wastage ${wastagePercent.toStringAsFixed(0)}% added. Water not included.',
  ], warnings: const [
    'Structural concrete (slabs, beams, columns) must follow the engineer\'s design mix.',
  ]);
}

/// Plaster: area x thickness, mortar 1:sandParts.
AskodoxCalcResult askodoxPlaster({
  required double areaSqm,
  double thicknessMm = 12,
  double sandParts = 4,
  double wastagePercent = 10,
}) {
  _positive(areaSqm, 'Area', 'వైశాల్యం');
  _positive(thicknessMm, 'Thickness', 'మందం');
  _positive(sandParts, 'Sand parts', 'ఇసుక భాగాలు');
  final factor = _wastage(wastagePercent);
  final dry = areaSqm * thicknessMm / 1000 * _dryVolumeFactorMortar * factor;
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Cement', 'సిమెంట్', dry / (1 + sandParts) / askodoxCementBagM3, 'bags (50 kg)', decimals: 1),
    AskodoxCalcLine('Sand', 'ఇసుక', dry * sandParts / (1 + sandParts), 'm³', decimals: 3),
  ], assumptions: [
    'Plaster ${thicknessMm.toStringAsFixed(0)} mm, mortar 1:${sandParts.toStringAsFixed(0)}; dry volume = wet × 1.33.',
    'Wastage ${wastagePercent.toStringAsFixed(0)}% added for uneven surfaces.',
  ]);
}

String _p(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

// ------------------------------------------------------------------ tiles / flooring

AskodoxCalcResult askodoxTiles({
  required double areaSqm,
  required double tileLengthMm,
  required double tileWidthMm,
  double wastagePercent = 8,
  int? tilesPerBox,
  double? ratePerSqft,
  double? labourPerSqft,
}) {
  _positive(areaSqm, 'Area', 'వైశాల్యం');
  _positive(tileLengthMm, 'Tile length', 'టైల్ పొడవు');
  _positive(tileWidthMm, 'Tile width', 'టైల్ వెడల్పు');
  if (tilesPerBox != null && tilesPerBox <= 0) {
    throw const AskodoxCalcException('Tiles per box must be more than 0.', 'బాక్స్‌కు టైల్స్ 0 కంటే ఎక్కువ ఉండాలి.');
  }
  final factor = _wastage(wastagePercent);
  final tileArea = tileLengthMm * tileWidthMm / 1e6;
  final tiles = _wholeUnits(areaSqm * factor / tileArea);
  final sqft = askodoxSqmToSqft(areaSqm);
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Tiles', 'టైల్స్', tiles, 'nos', decimals: 0),
    if (tilesPerBox != null) AskodoxCalcLine('Boxes', 'బాక్సులు', _wholeUnits(tiles / tilesPerBox), 'boxes', decimals: 0),
    AskodoxCalcLine('Floor area', 'నేల వైశాల్యం', sqft, 'sq ft', decimals: 1),
    if (ratePerSqft != null)
      AskodoxCalcLine('Tile cost (your rate)', 'టైల్స్ ఖర్చు (మీ రేటు)', sqft * factor * ratePerSqft, '₹', decimals: 0),
    if (labourPerSqft != null)
      AskodoxCalcLine('Labour (your rate)', 'కూలీ (మీ రేటు)', sqft * labourPerSqft, '₹', decimals: 0),
  ], assumptions: [
    'Tile ${tileLengthMm.toStringAsFixed(0)}×${tileWidthMm.toStringAsFixed(0)} mm; '
        '${wastagePercent.toStringAsFixed(0)}% extra for cutting and breakage.',
    'Adhesive / grout / skirting not included.',
  ]);
}

// ------------------------------------------------------------------ paint

AskodoxCalcResult askodoxPaint({
  required double areaSqm,
  int coats = 2,
  double coverageSqmPerLitre = 10,
  bool primer = true,
  double primerCoverageSqmPerLitre = 10,
  double wastagePercent = 5,
  double? ratePerLitre,
}) {
  _positive(areaSqm, 'Area', 'వైశాల్యం');
  if (coats < 1 || coats > 5) {
    throw const AskodoxCalcException('Coats should be between 1 and 5.', 'కోట్లు 1 నుండి 5 మధ్య ఉండాలి.');
  }
  _positive(coverageSqmPerLitre, 'Coverage', 'కవరేజ్');
  _positive(primerCoverageSqmPerLitre, 'Primer coverage', 'ప్రైమర్ కవరేజ్');
  final factor = _wastage(wastagePercent);
  final litres = areaSqm * coats / coverageSqmPerLitre * factor;
  return AskodoxCalcResult(lines: [
    AskodoxCalcLine('Paint', 'పెయింట్', litres, 'litres', decimals: 1),
    if (primer)
      AskodoxCalcLine('Primer', 'ప్రైమర్', areaSqm / primerCoverageSqmPerLitre * factor, 'litres', decimals: 1),
    if (ratePerLitre != null) AskodoxCalcLine('Paint cost (your rate)', 'పెయింట్ ఖర్చు (మీ రేటు)', litres * ratePerLitre, '₹', decimals: 0),
  ], assumptions: [
    '$coats coat(s) at ${coverageSqmPerLitre.toStringAsFixed(0)} m² per litre per coat -- check the can; '
        'rough or porous walls use more.',
  ]);
}
