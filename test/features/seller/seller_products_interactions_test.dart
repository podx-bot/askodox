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

    final menuFinder = find.byKey(const Key('sellerProductMenu-seller-1'));
    expect(menuFinder, findsOneWidget);
    final menu = tester.widget<PopupMenuButton<String>>(menuFinder);
    menu.onSelected?.call('edit');
    await tester.pump(const Duration(milliseconds: 350));

    final sheet = find.byKey(const Key('sellerProductEditSheet'));
    expect(sheet, findsOneWidget);

    final price = find.byKey(const Key('sellerProductPriceField'));
    await tester.scrollUntilVisible(
      price,
      180,
      scrollable: find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.ensureVisible(price);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(price);
    await tester.enterText(price, '399');
    await tester.pump(const Duration(milliseconds: 250));

    final save = find.byKey(const Key('sellerProductSaveChanges'));
    await tester.scrollUntilVisible(
      save,
      180,
      scrollable: find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.ensureVisible(save);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 500));

    expect(sheet, findsNothing);
    expect(find.textContaining('₹399'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
