import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/seller/presentation/request_new_product_screen.dart';

void main() {
  testWidgets('seller new product image reference works on small phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RequestNewProductScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sellerNewProductChooseImage')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sellerNewProductImageReference')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('sellerNewProductImageReference')),
      'https://example.com/item.jpg',
    );
    await tester.tap(find.byKey(const Key('sellerNewProductImageSave')));
    await tester.pumpAndSettle();

    expect(find.text('Image added'), findsOneWidget);
    expect(find.text('https://example.com/item.jpg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
