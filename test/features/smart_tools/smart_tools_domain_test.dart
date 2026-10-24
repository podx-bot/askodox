import 'package:podx/features/smart_tools/domain/construction_calculators.dart';
import 'package:podx/features/smart_tools/domain/load_planner.dart';
import 'package:podx/features/smart_tools/domain/sensor_math.dart';
import 'package:podx/features/smart_tools/domain/smart_tool_catalog.dart';
import 'package:podx/features/smart_tools/domain/tool_intent_router.dart';
import 'package:podx/features/smart_tools/presentation/calculator_screens.dart';
import 'package:podx/features/smart_tools/presentation/smart_tools_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Construction calculators (deterministic, on-device)', () {
    test('modular bricks: ~500 per m³ of wall plus wastage, with mortar materials', () {
      final unit = askodoxMasonryUnits.firstWhere((u) => u.id == 'modular');
      final r = askodoxBricks(wallLength: 1, wallHeight: 1, wallThicknessMm: 1000, unit: unit);
      expect(r.valueOf('Bricks / blocks'), 525);
      expect(r.valueOf('Cement'), closeTo(1.33, 0.05));
      expect(r.valueOf('Sand'), closeTo(0.276, 0.005));
      expect(r.assumptions.join(' '), contains('1:6'));
      expect(r.warnings.single, contains('not a structural design'));
      expect(r.lines.where((l) => l.unit == '₹'), isEmpty, reason: 'no cost without the user\'s own rate');
    });

    test('feet input and openings are honoured; cost only from the typed rate', () {
      final unit = askodoxMasonryUnits.firstWhere((u) => u.id == 'traditional');
      final metric = askodoxBricks(wallLength: 3.048, wallHeight: 3.048, wallThicknessMm: 230, unit: unit, openingsSqm: 2);
      final feet = askodoxBricks(
          wallLength: 10, wallHeight: 10, wallThicknessMm: 230, unit: unit, openingsSqm: 2,
          lengthUnit: AskodoxLengthUnit.foot, ratePerUnit: 8);
      expect(feet.valueOf('Bricks / blocks'), metric.valueOf('Bricks / blocks'));
      expect(feet.valueOf('Brick / block cost (your rate)'), feet.valueOf('Bricks / blocks') * 8);
    });

    test('concrete 1:1.5:3 needs about 8 bags per m³', () {
      final r = askodoxConcrete(wetVolumeM3: 1, wastagePercent: 0);
      expect(r.valueOf('Cement'), closeTo(8.07, 0.05));
      expect(r.valueOf('Sand'), closeTo(0.42, 0.005));
      expect(r.valueOf('Aggregate'), closeTo(0.84, 0.005));
      expect(r.warnings.single, contains('engineer'));
    });

    test('plaster, tiles, paint, area and volume', () {
      expect(askodoxPlaster(areaSqm: 10, wastagePercent: 0).valueOf('Sand'), closeTo(0.1277, 0.001));
      final tiles = askodoxTiles(areaSqm: 10, tileLengthMm: 600, tileWidthMm: 600, tilesPerBox: 4);
      expect(tiles.valueOf('Tiles'), 30);
      expect(tiles.valueOf('Boxes'), 8);
      final paint = askodoxPaint(areaSqm: 100);
      expect(paint.valueOf('Paint'), closeTo(21, 0.001));
      expect(paint.valueOf('Primer'), closeTo(10.5, 0.001));
      final area = askodoxArea(shape: AskodoxShape.rectangle, a: 10, b: 12, unit: AskodoxLengthUnit.foot);
      expect(area.valueOf('Area (sq ft)'), closeTo(120, 0.01));
      final circle = askodoxArea(shape: AskodoxShape.circle, a: 2);
      expect(circle.valueOf('Area'), closeTo(3.1416, 0.001));
      final drum = askodoxVolume(solid: AskodoxSolid.cylinder, a: 0.6, b: 0.9);
      expect(drum.valueOf('Capacity'), closeTo(254.5, 0.5));
    });

    test('invalid input is refused with a message in both languages', () {
      expect(() => askodoxArea(shape: AskodoxShape.rectangle, a: 0, b: 2), throwsA(isA<AskodoxCalcException>()));
      expect(() => askodoxArea(shape: AskodoxShape.rectangle, a: 1, b: 1, openingsSqm: 2),
          throwsA(isA<AskodoxCalcException>()));
      expect(() => askodoxTiles(areaSqm: 10, tileLengthMm: 600, tileWidthMm: 600, wastagePercent: 70),
          throwsA(isA<AskodoxCalcException>()));
      try {
        askodoxPaint(areaSqm: -1);
        fail('negative area accepted');
      } on AskodoxCalcException catch (e) {
        expect(e.message(true), contains('0'));
        expect(e.message(false), contains('Area'));
      }
    });
  });

  group('Load planner', () {
    const van = AskodoxCargoSpace(lengthCm: 260, widthCm: 150, heightCm: 120, payloadKg: 750);

    test('fits by volume and weight; heaviest loads first', () {
      final plan = askodoxPlanLoad([
        const AskodoxLoadItem(name: 'rice bags', lengthCm: 60, widthCm: 40, heightCm: 20, weightKg: 25, quantity: 10),
        const AskodoxLoadItem(name: 'fridge', lengthCm: 70, widthCm: 65, heightCm: 110, weightKg: 60),
      ], van);
      expect(plan.verdicts, {AskodoxLoadVerdict.fits});
      expect(plan.totalWeightKg, 310);
      expect(plan.loadingOrder.first, 'fridge');
    });

    test('over payload and oversized items are reported (any rotation counts)', () {
      final plan = askodoxPlanLoad([
        const AskodoxLoadItem(name: 'cement', lengthCm: 60, widthCm: 40, heightCm: 12, weightKg: 50, quantity: 20),
        const AskodoxLoadItem(name: 'pipe', lengthCm: 40, widthCm: 255, heightCm: 40, weightKg: 5),
        const AskodoxLoadItem(name: 'ladder', lengthCm: 300, widthCm: 40, heightCm: 10, weightKg: 8),
      ], van);
      expect(plan.verdicts, containsAll([AskodoxLoadVerdict.overWeight, AskodoxLoadVerdict.itemTooLarge]));
      expect(plan.oversizedItems, ['ladder'], reason: 'the 255 cm pipe fits lengthwise when rotated');
      expect(plan.fits, isFalse);
    });

    test('nearly full is "tight", never a plain yes', () {
      final plan = askodoxPlanLoad([
        const AskodoxLoadItem(name: 'boxes', lengthCm: 50, widthCm: 50, heightCm: 50, weightKg: 5, quantity: 32),
      ], van);
      expect(plan.verdicts, {AskodoxLoadVerdict.tight});
    });

    test('bad input refused', () {
      expect(() => askodoxPlanLoad(const [], van), throwsA(isA<AskodoxCalcException>()));
      expect(
          () => askodoxPlanLoad([const AskodoxLoadItem(name: 'x', lengthCm: 0, widthCm: 1, heightCm: 1, weightKg: 1)], van),
          throwsA(isA<AskodoxCalcException>()));
    });
  });

  group('Sensor maths', () {
    test('flat phone, top to magnetic north = 0°, to east = 90°', () {
      const g = AskodoxVec3(0, 0, 9.8);
      expect(askodoxHeading(g, const AskodoxVec3(0, 20, -40)), closeTo(0, 0.01));
      expect(askodoxHeading(g, const AskodoxVec3(-20, 0, -40)), closeTo(90, 0.01));
      expect(askodoxHeading(g, const AskodoxVec3(0, -20, -40)), closeTo(180, 0.01));
      expect(askodoxCardinal(90), 'E');
      expect(askodoxCardinal(0, te: true), 'ఉత్తరం');
    });

    test('heading is tilt-compensated', () {
      // Same field, phone tilted 20° forward: heading must stay ~0.
      const tilted = AskodoxVec3(0, 3.35, 9.21);
      expect(askodoxHeading(tilted, const AskodoxVec3(0, 20, -40)), closeTo(0, 0.5));
      expect(askodoxHeading(const AskodoxVec3(0, 0, 0), const AskodoxVec3(1, 1, 1)), isNull);
    });

    test('level and plumb angles', () {
      expect(askodoxFlatTilt(const AskodoxVec3(0, 0, 9.8)).tiltX, closeTo(0, 0.001));
      expect(askodoxInclination(const AskodoxVec3(0, 9.8, 0)), closeTo(90, 0.001));
      final upright = askodoxEdgeAngle(const AskodoxVec3(0, 9.8, 0));
      expect(upright.fromVertical, closeTo(0, 0.001));
      final leaning = askodoxEdgeAngle(const AskodoxVec3(1.7, 9.65, 0));
      expect(leaning.fromVertical, closeTo(10, 0.1));
      expect(askodoxEdgeAngle(const AskodoxVec3(0, -9.8, 0)).fromVertical, closeTo(0, 0.001),
          reason: 'upside down is still plumb');
    });
  });

  group('Tool router (contextual discovery)', () {
    String? idOf(String text) => askodoxToolIntent(text)?.tool.id;

    test('quantity questions across unrelated materials, English and Telugu', () {
      expect(idOf('How many bricks for a 10 ft by 8 ft wall?'), 'brick');
      expect(idOf('ఈ గోడకు ఎన్ని ఇటుకలు కావాలి?'), 'brick');
      expect(idOf('how many tiles for 120 sq ft'), 'tile');
      expect(idOf('how much paint for two rooms'), 'paint');
      expect(idOf('calculate cement and sand for plastering'), 'cement');
      expect(idOf('will 20 boxes fit in my tata ace, calculate'), 'load');
      expect(idOf('measure this wall'), 'area');
    });

    test('explicit tool names', () {
      expect(askodoxToolIntent('open the compass')?.explicit, isTrue);
      expect(idOf('spirit level'), 'level');
      expect(idOf('దిక్సూచి చూపించు'), 'compass');
      expect(idOf('connect my tv'), 'pairing');
      expect(askodoxToolIntent('connect my tv')?.route, isNull, reason: 'pairing is not built: never opened');
    });

    test('photo inspection picks the domain from the words', () {
      expect(askodoxToolIntent('check this chicken quality')?.route, '/tools/inspect?domain=food');
      expect(askodoxToolIntent('check this tyre')?.route, '/tools/inspect?domain=tyre');
      expect(askodoxToolIntent('ఈ ఆకు చూడు, పంటకు ఏమైంది')?.route, '/tools/inspect?domain=crop');
      expect(askodoxToolIntent('inspect this crack in the wall')?.route, '/tools/inspect?domain=construction');
      expect(idOf('goat weight'), 'animal_weight');
    });

    test('commerce, chat and look-alike words are never taken over', () {
      for (final text in [
        'buy bricks near me',
        'brick price in Vijayawada',
        'how much does paint cost',
        'I want chicken',
        'check this chicken price',
        'need a mason to build a wall',
        'ఇటుకలు కొనాలి',
        'how many days for delivery',
        'what is the capital of France',
        'my card is blocked',
        'tell me about the border',
        '',
      ]) {
        expect(askodoxToolIntent(text), isNull, reason: text);
      }
    });
  });

  group('Registry consistency', () {
    test('ids unique; only built tools open; every route is served', () {
      final ids = askodoxSmartTools.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final tool in askodoxSmartTools) {
        if (tool.readiness == AskodoxToolReadiness.comingSoon ||
            tool.readiness == AskodoxToolReadiness.needsExternalDevice) {
          expect(tool.opens, isFalse, reason: '${tool.id} must not look functional');
        }
        final route = tool.route;
        if (route == null) continue;
        final path = route.split('?').first;
        expect(askodoxSmartToolPaths.any((p) => p.endsWith('/') ? path.startsWith(p) : path == p), isTrue,
            reason: '${tool.id} -> $route');
        if (path.startsWith('/tools/calc/')) {
          final id = path.substring('/tools/calc/'.length);
          expect(id == 'load' || askodoxCalcSpecs.containsKey(id), isTrue, reason: id);
        }
      }
    });

    test('electrical and safety-critical tools carry a safety note', () {
      for (final id in ['electrical', 'inspect', 'crack', 'animal_weight', 'load', 'level']) {
        expect(askodoxToolById(id)?.safetyNote, isNotNull, reason: id);
      }
    });
  });
}
