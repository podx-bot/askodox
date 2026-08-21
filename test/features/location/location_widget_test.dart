import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/data/mock_geo_repository.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:podx/features/location/presentation/location_setup_screen.dart';
import 'package:podx/features/location/presentation/nearby_shops_screen.dart';
import 'package:podx/features/location/presentation/shop_details_screen.dart';

void main() {
  testWidgets('manual location selection is available', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LocationSetupScreen())),
    );
    expect(find.text('Choose manually'), findsOneWidget);
    expect(find.text('Banjara Hills'), findsOneWidget);
  });

  testWidgets('map and list view toggle', (tester) async {
    final c = LocationController(MockGeoRepository());
    await c.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [locationControllerProvider.overrideWith((ref) => c)],
        child: const MaterialApp(home: NearbyShopsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mockMap')), findsOneWidget);
    await tester.tap(find.text('List'));
    await tester.pump();
    expect(c.state.mode, MapDisplayMode.list);
    expect(find.byKey(const Key('mockMap')), findsNothing);
  });

  testWidgets('nearby filters and view-on-map actions work', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = LocationController(MockGeoRepository());
    await c.refresh();
    c.toggleMode(MapDisplayMode.list);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [locationControllerProvider.overrideWith((ref) => c)],
        child: const MaterialApp(home: NearbyShopsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearbyFilters')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nearbyFilters')));
    await tester.pumpAndSettle();
    expect(find.text('Nearby filters'), findsOneWidget);
    expect(find.byKey(const Key('nearbyFilterViewMode')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nearbyFilterRadius-5000')));
    await tester.pump();
    expect(c.state.radiusMetres, 5000);
    await tester.tap(find.byKey(const Key('nearbyApplyFilters')));
    await tester.pumpAndSettle();

    expect(c.state.shops, isNotEmpty);
    final shop = c.state.shops.first;
    final action = find.byKey(Key('nearbyViewOnMap-${shop.id}'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(c.state.mode, MapDisplayMode.map);
    expect(c.state.selectedShopId, shop.id);
    expect(find.byKey(const Key('mockMap')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shop details sorting changes product order on phone size', (tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shopId = mockNearbyShops.first.id;
    await tester.pumpWidget(
      MaterialApp(home: ShopDetailsScreen(shopId: shopId)),
    );
    await tester.pumpAndSettle();

    final sort = find.byKey(const Key('shopProductSort'));
    await tester.ensureVisible(sort);
    await tester.tap(sort);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highest price').last);
    await tester.pumpAndSettle();

    final product4 = find.byKey(const Key('shopProduct-Mock product 4'));
    final product1 = find.byKey(const Key('shopProduct-Mock product 1'));
    expect(product4, findsOneWidget);
    expect(product1, findsOneWidget);
    expect(tester.getTopLeft(product4).dy, lessThan(tester.getTopLeft(product1).dy));

    final call = find.byKey(const Key('shopDetailsCall'));
    await tester.ensureVisible(call);
    await tester.tap(call);
    await tester.pump();
    expect(find.text('Shop contact is not published yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
