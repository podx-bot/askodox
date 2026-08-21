import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/buyer/presentation/widgets/location_selector.dart';

void main() {
  testWidgets('buyer location sheet is usable on phone size', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LocationSelector()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const Key('buyerLocationSelector'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('buyerLocationSheet')), findsOneWidget);
    expect(find.byKey(const Key('buyerLocationSheetScroll')), findsOneWidget);
    expect(find.byKey(const Key('buyerCustomRadiusSlider')), findsOneWidget);

    final save = find.byKey(const Key('buyerSaveDefaultRadius'));
    await tester.ensureVisible(save);
    await tester.pump();
    expect(save, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
