import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/buyer/application/buyer_providers.dart';
import 'package:podx/features/buyer/data/mock_buyer_repository.dart';
import 'package:podx/features/buyer/domain/entities/buyer_models.dart';
import 'package:podx/features/buyer/presentation/widgets/location_selector.dart';
import 'package:podx/features/catalog/presentation/product_not_found_screen.dart';

void main() {
  const buyer = BuyerLocation(id: 'buyer', label: 'Buyer', address: 'Test', latitude: 17.4156, longitude: 78.4347);

  test('nearby matching applies radius and excludes out of stock', () async {
    final listings = await MockBuyerRepository().listings('avocado-box');
    final close = matchNearby(listings: listings, location: buyer, radiusKm: 2, filter: const SearchFilter(), sort: SearchSortOption.nearestShop);
    expect(close, isNotEmpty);
    expect(close.every((item) => item.distanceKm <= 2 && item.listing.inStock), isTrue);
  });

  test('price and distance sorting are deterministic', () async {
    final listings = await MockBuyerRepository().listings('avocado-box');
    final byPrice = matchNearby(listings: listings, location: buyer, radiusKm: 50, filter: const SearchFilter(), sort: SearchSortOption.lowestPrice);
    final byDistance = matchNearby(listings: listings, location: buyer, radiusKm: 50, filter: const SearchFilter(), sort: SearchSortOption.nearestShop);
    expect(byPrice.first.listing.effectivePrice, lessThanOrEqualTo(byPrice.last.listing.effectivePrice));
    expect(byDistance.first.distanceKm, lessThanOrEqualTo(byDistance.last.distanceKm));
  });

  testWidgets('radius selector exposes all preset choices', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: LocationSelector()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use current location'));
    await tester.pumpAndSettle();
    expect(find.text('100 m'), findsOneWidget);
    expect(find.text('50 km'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('product not found provides request and notification flow', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: ProductNotFoundScreen())));
    expect(find.text('This product is not available in the PODX catalog yet.'), findsOneWidget);
    expect(find.text('Request Product'), findsOneWidget);
    expect(find.text('Notify Me'), findsOneWidget);
    await tester.tap(find.text('Request Product'));
    await tester.pump();
    expect(find.text('Product request saved locally.'), findsOneWidget);
  });

  test('wrong price report is stored locally', () async {
    final repository = MockBuyerRepository();
    final report = WrongPriceReport(id: 'r1', listingId: 'l1', reason: 'Different shelf price', createdAt: DateTime(2026));
    await repository.reportWrongPrice(report);
    expect(repository.reports, contains(report));
  });
}
