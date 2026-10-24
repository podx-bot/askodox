import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/smart_tools/data/phone_meters.dart';
import 'package:podx/features/smart_tools/data/vehicle_report_pdf.dart';
import 'package:podx/features/smart_tools/data/vision_inspection_repository.dart';
import 'package:podx/features/smart_tools/domain/meter_math.dart';
import 'package:podx/features/smart_tools/domain/photo_measure.dart';
import 'package:podx/features/smart_tools/domain/smart_tool_catalog.dart';
import 'package:podx/features/smart_tools/domain/tool_intent_router.dart';
import 'package:podx/features/smart_tools/presentation/extra_tools_screens.dart';
import 'package:podx/features/smart_tools/presentation/smart_tools_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class _Meters extends AskodoxPhoneMeters {
  const _Meters({this.fail});
  final String? fail;

  @override
  Future<double> lux() async {
    if (fail != null) throw AskodoxMeterException(fail!);
    return 320;
  }

  @override
  Future<AskodoxSoundReading> sound({int millis = 600}) async => const AskodoxSoundReading(dbfs: -42, peakDbfs: -30);
}

Future<void> _pump(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
  await tester.pump();
}

void main() {
  group('meter maths', () {
    test('protractor angle at the vertex', () {
      const v = AskodoxPoint(0, 0);
      expect(askodoxAngleAt(const AskodoxPoint(10, 0), v, const AskodoxPoint(0, 10)), closeTo(90, 1e-9));
      expect(askodoxAngleAt(const AskodoxPoint(10, 0), v, const AskodoxPoint(-10, 0)), closeTo(180, 1e-9));
      expect(askodoxAngleAt(const AskodoxPoint(10, 0), v, const AskodoxPoint(10, 10)), closeTo(45, 1e-9));
      expect(askodoxAngleAt(v, v, const AskodoxPoint(1, 1)), isNull, reason: 'an arm with no length is refused');
      // longer arms -> smaller tap error
      final short = askodoxAngleError(const AskodoxPoint(50, 0), v, const AskodoxPoint(0, 50));
      final long = askodoxAngleError(const AskodoxPoint(500, 0), v, const AskodoxPoint(0, 500));
      expect(long, lessThan(short));
    });

    test('lux bands and sound calibration', () {
      expect(askodoxLuxBand(3).id, 'dark');
      expect(askodoxLuxBand(320).id, 'work');
      expect(askodoxLuxBand(50000).id, 'sun');
      const r = AskodoxSoundReading(dbfs: -42, peakDbfs: -30);
      expect(r.calibrated(null), isNull, reason: 'no dB claim without a calibration');
      final offset = askodoxSoundOffset(-42, 60);
      expect(offset, 102);
      expect(r.calibrated(offset), 60);
      expect(r.relative, 48);
    });

    test('vehicle note names the sides and the user-stated details', () {
      final note = askodoxVehicleInspectionNote(vehicle: 'Maruti Swift 2019', odometer: '45000');
      expect(note, contains('front, rear, left side, right side'));
      expect(note, contains('Maruti Swift 2019'));
      expect(note, contains('not read from the photos'));
      expect(askodoxVehicleSides.length, 4);
    });
  });

  group('registry + chat', () {
    test('the new tools open and have routes', () {
      for (final id in ['protractor', 'magnifier', 'light', 'sound', 'vehicle_report']) {
        final tool = askodoxToolById(id)!;
        expect(tool.opens, isTrue, reason: id);
        expect(tool.readiness, AskodoxToolReadiness.hardwareUnverified, reason: '$id is not phone-verified yet');
        expect(askodoxSmartToolPaths.any((p) => tool.route!.startsWith(p) && p.length > 6), isTrue, reason: id);
      }
    });

    test('named asks open the tool; shopping for one stays commerce', () {
      expect(askodoxToolIntent('open the protractor')?.route, '/tools/protractor');
      expect(askodoxToolIntent('magnifier')?.route, '/tools/magnifier');
      expect(askodoxToolIntent('light meter')?.route, '/tools/light');
      expect(askodoxToolIntent('what is the noise level here')?.route, '/tools/sound');
      expect(askodoxToolIntent('make a vehicle inspection report')?.route, '/tools/vehicle-report');
      expect(askodoxToolIntent('buy a light meter')?.tool.id, isNot('light'));
      expect(askodoxToolIntent('sound meter price')?.tool.id, isNot('sound'));
    });
  });

  testWidgets('light meter: one reading with its band', (tester) async {
    await _pump(tester, const AskodoxLightMeterScreen(),
        overrides: [askodoxPhoneMetersProvider.overrideWithValue(const _Meters())]);
    await tester.tap(find.byKey(const Key('askodoxLightRead')));
    await tester.pump();
    expect(find.text('320 lux'), findsOneWidget);
    expect(find.text('Bright — reading / office work'), findsOneWidget);
  });

  testWidgets('light meter: a missing sensor is said plainly', (tester) async {
    await _pump(tester, const AskodoxLightMeterScreen(),
        overrides: [askodoxPhoneMetersProvider.overrideWithValue(const _Meters(fail: 'no_sensor'))]);
    await tester.tap(find.byKey(const Key('askodoxLightRead')));
    await tester.pump();
    expect(find.text('This phone does not have this sensor.'), findsOneWidget);
  });

  testWidgets('sound meter: dBFS until calibrated, then an approximate dB', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, const AskodoxSoundMeterScreen(),
        overrides: [askodoxPhoneMetersProvider.overrideWithValue(const _Meters())]);
    await tester.tap(find.byKey(const Key('askodoxSoundRead')));
    await tester.pump();
    await tester.pump();
    expect(find.text('-42.0 dBFS'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxSoundCalibration')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '60');
    await tester.tap(find.byKey(const Key('askodoxSoundCalibrate')));
    await tester.pumpAndSettle();
    expect(find.text('≈ 60 dB'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getDouble(askodoxSoundOffsetKey), 102);
  });

  testWidgets('vehicle report PDF carries the photos and the disclaimer', (tester) async {
    const report = AskodoxInspectionReport(
      domain: 'vehicle',
      mode: 'expert',
      status: 'ok',
      subject: 'Hatchback, white',
      observed: [AskodoxInspectionFinding('Dent on the left rear door', detail: 'left side', confidence: 0.8)],
      notVerifiable: ['Engine condition cannot be confirmed from photos.'],
      recommendedChecks: ['Have a mechanic check the brakes.'],
      confidence: 0.7,
    );
    final bytes = (await tester.runAsync(() => askodoxVehicleReportPdf(
          report: report,
          photos: {for (final s in askodoxVehicleSides) s.id: Uint8List.fromList(_png1x1)},
          date: '2026-10-24',
          vehicle: 'Maruti Swift 2019',
          compress: false,
        )))!;
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF-'), isTrue);
    expect(RegExp('/Subtype\\s*/Image').allMatches(text).length, greaterThanOrEqualTo(4), reason: 'four side photos');
    expect(text, contains('roadworthiness'));
    expect(askodoxPdfCanEmbed(Uint8List.fromList([1, 2, 3])), isFalse, reason: 'unknown formats are left out, not crashed on');
  });
}
