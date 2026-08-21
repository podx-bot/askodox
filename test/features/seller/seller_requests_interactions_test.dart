import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/seller/presentation/seller_requests_screen.dart';

void main() {
  testWidgets('seller request response works on phone size', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SellerRequestsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final available = find.byKey(
      const Key('sellerRequestAvailable-request-1'),
    );
    expect(available, findsOneWidget);
    await tester.tap(available);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sellerRequestResponseSheet')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('sellerRequestPrice')),
      '160',
    );
    await tester.enterText(
      find.byKey(const Key('sellerRequestStock')),
      '12',
    );
    await tester.enterText(
      find.byKey(const Key('sellerRequestOffer')),
      '150',
    );

    final submit = find.byKey(const Key('sellerRequestSubmit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sellerRequestResponded-request-1')),
      findsOneWidget,
    );
    expect(find.text('Response submitted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid seller response gives feedback', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SellerRequestsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('sellerRequestAvailable-request-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sellerRequestPrice')),
      '0',
    );
    await tester.enterText(
      find.byKey(const Key('sellerRequestStock')),
      '-1',
    );

    final submit = find.byKey(const Key('sellerRequestSubmit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid price and available stock.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
