import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/pos/data/pos_printer.dart';
import 'package:podx/features/steps/presentation/printer_steps_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-24: the bill printer in 3 pieces (made-up devices only).
class _Native extends AskodoxNativePrinters {
  _Native();

  @override
  Future<List<AskodoxNativePrinter>> paired() async =>
      const [AskodoxNativePrinter(id: 'classic:66:22:AA:01:02:03', name: 'Test-Printer', kind: 'classic', hint: true)];

  @override
  Future<List<AskodoxNativePrinter>> usb() async => const [];

  @override
  Future<void> send(String id, Uint8List bytes) async {}
}

class _Transport implements AskodoxPrinterTransport {
  final sent = <String>[];
  @override
  Future<void> write(String deviceId, Uint8List bytes) async => sent.add(deviceId);
}

Future<void> _pump(WidgetTester tester, _Transport transport) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      askodoxNativePrintersProvider.overrideWithValue(_Native()),
      askodoxPrinterTransportProvider.overrideWithValue(transport),
    ],
    child: const MaterialApp(home: AskodoxPrinterStepsScreen(businessId: 'b1')),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('printer: none -> find paired -> pick -> saved -> test print', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final transport = _Transport();
    await _pump(tester, transport);
    expect(find.byKey(const Key('askodoxPrinterSteps')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPrinterStepsStart')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPrinterSteps1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPrinterStepsPaired')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPrinterSteps2')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxPrinterStepsFound-classic:66:22:AA:01:02:03')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxPrinterSteps3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPrinterStepsTest3')));
    await tester.pumpAndSettle();
    expect(transport.sent, ['classic:66:22:AA:01:02:03']);
  });

  testWidgets('printer: a saved printer shows on top with a Test print button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await const AskodoxSavedPrinter(id: 'classic:66:22:AA:01:02:03', name: 'Saved-One', paperMm: 80).save();
    final transport = _Transport();
    await _pump(tester, transport);
    await tester.pumpAndSettle();
    expect(find.text('Saved-One'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxPrinterStepsTest')));
    await tester.pumpAndSettle();
    expect(transport.sent, ['classic:66:22:AA:01:02:03']);
  });
}
