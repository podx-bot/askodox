import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/smart_tools/domain/construction_calculators.dart';
import 'package:podx/features/smart_tools/domain/photo_measure.dart';
import 'package:podx/features/smart_tools/domain/tool_intent_router.dart';
import 'package:podx/features/smart_tools/presentation/photo_measure_screen.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';

final _png1x1 = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class _Picker implements AskodoxMediaPicker {
  @override
  Future<List<ChatAttachment>> pick(String source) async =>
      [ChatAttachment(name: 'wall.png', bytes: _png1x1, mimeType: 'image/png')];
}

void main() {
  group('reference-object photo measurement', () {
    test('scales the target by the reference and gives an honest range', () {
      // A4 long side (297 mm) spans 1000 px; the target spans 3000 px -> 891 mm.
      final m = askodoxMeasureFromPhoto(
        referenceA: const AskodoxPoint(100, 100),
        referenceB: const AskodoxPoint(1100, 100),
        referenceMm: 297,
        targetA: const AskodoxPoint(100, 300),
        targetB: const AskodoxPoint(3100, 300),
      );
      expect(m.lengthMm, closeTo(891, 0.5));
      expect(m.lowMm, lessThan(m.lengthMm));
      expect(m.highMm, greaterThan(m.lengthMm));
      expect(m.quality, AskodoxMeasureQuality.good);
      expect(m.warnings.first, contains('same flat surface'));
      expect(m.formatted(), startsWith('89.1 cm'));
    });

    test('tiny reference or a long object lowers quality and warns', () {
      final m = askodoxMeasureFromPhoto(
        referenceA: const AskodoxPoint(0, 0),
        referenceB: const AskodoxPoint(40, 0),
        referenceMm: 85.6,
        targetA: const AskodoxPoint(0, 50),
        targetB: const AskodoxPoint(800, 50),
      );
      expect(m.quality, AskodoxMeasureQuality.poor);
      expect(m.warnings.length, 3);
    });

    test('invalid marks are refused', () {
      expect(
          () => askodoxMeasureFromPhoto(
              referenceA: const AskodoxPoint(0, 0), referenceB: const AskodoxPoint(5, 0), referenceMm: 297,
              targetA: const AskodoxPoint(0, 0), targetB: const AskodoxPoint(100, 0)),
          throwsA(isA<AskodoxCalcException>()));
      expect(
          () => askodoxMeasureFromPhoto(
              referenceA: const AskodoxPoint(0, 0), referenceB: const AskodoxPoint(100, 0), referenceMm: 0,
              targetA: const AskodoxPoint(0, 0), targetB: const AskodoxPoint(100, 0)),
          throwsA(isA<AskodoxCalcException>()));
    });

    test('reference sizes are the published standards', () {
      final byId = {for (final r in askodoxReferenceObjects) r.id: r.lengthMm};
      expect(byId['a4_long'], 297);
      expect(byId['a4_short'], 210);
      expect(byId['card_long'], 85.6);
    });

    test('chat opens it only when asked by name', () {
      expect(askodoxToolIntent('measure from a photo')?.route, '/tools/measure-photo');
      expect(askodoxToolIntent('measure this wall')?.route, '/tools/calc/area');
    });
  });

  testWidgets('photo flow: four taps, a too-small reference is refused (no guess)', (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [askodoxMediaPickerProvider.overrideWithValue(_Picker())],
      child: const MaterialApp(home: AskodoxPhotoMeasureScreen()),
    ));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('askodoxMeasureCamera')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('1. Tap one end of the reference object'), findsOneWidget);
    final image = find.byKey(const Key('askodoxMeasureImage'));
    final box = tester.getRect(image);
    for (final dx in [0.1, 0.12, 0.1, 0.9]) {
      await tester.tapAt(Offset(box.left + box.width * dx, box.top + box.height * 0.5));
      await tester.pump();
    }
    // a 1 x 1 px photo: the reference spans far less than 20 px -> refused
    expect(find.byKey(const Key('askodoxMeasureError')), findsOneWidget);
    expect(find.byKey(const Key('askodoxMeasureResult')), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxMeasureUndo')));
    await tester.pump();
    expect(find.text('4. Tap its other end'), findsOneWidget);
  });
}
