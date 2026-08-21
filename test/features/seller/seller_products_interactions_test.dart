import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/seller/presentation/seller_products_screen.dart';

void main() {
  testWidgets('seller product edit survives keyboard and saves', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SellerProductsScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sellerProductMenu-seller-1')));
    await tester.pump(const Duration(milliseconds: 250));
    final edit = find.byKey(const Key('sellerProductEdit-seller-1'));
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byKey(const Key('sellerProductEditSheet')), findsOneWidget);

    final price = find.byKey(const Key('sellerProductPriceField'));
    await tester.tap(price);
    await tester.enterText(price, '399');
    await tester.pump(const Duration(milliseconds: 250));

    final save = find.byKey(const Key('sellerProductSaveChanges'));
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byKey(const Key('sellerProductEditSheet')), findsNothing);
    expect(find.textContaining('₹399'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
