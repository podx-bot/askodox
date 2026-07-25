import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_buyer_repository.dart';
import '../domain/entities/buyer_models.dart';
import '../domain/repositories/buyer_repository.dart';

final buyerRepositoryProvider = Provider<BuyerRepository>((ref) => MockBuyerRepository());
final buyerLocationsProvider = FutureProvider((ref) => ref.watch(buyerRepositoryProvider).locations());
final buyerLocationProvider = StateProvider<BuyerLocation>((ref) => const BuyerLocation(id: 'current', label: 'Current location', address: 'Banjara Hills, Hyderabad', latitude: 17.4156, longitude: 78.4347));
final radiusKmProvider = StateProvider<double>((ref) => 5);
final comparisonSortProvider = StateProvider<SearchSortOption>((ref) => SearchSortOption.lowestPrice);
final searchFilterProvider = StateProvider<SearchFilter>((ref) => const SearchFilter());
final recentSearchesProvider = StateProvider<List<String>>((ref) => const []);
final priceListingsProvider = FutureProvider.family<List<ProductPriceListing>, String>((ref, id) => ref.watch(buyerRepositoryProvider).listings(id));

double distanceKm(BuyerLocation a, double latitude, double longitude) {
  const earth = 6371.0; final dLat = (latitude-a.latitude)*pi/180, dLon=(longitude-a.longitude)*pi/180;
  final x = sin(dLat/2)*sin(dLat/2)+cos(a.latitude*pi/180)*cos(latitude*pi/180)*sin(dLon/2)*sin(dLon/2);
  return earth*2*atan2(sqrt(x),sqrt(1-x));
}

List<NearbySellerResult> matchNearby({required List<ProductPriceListing> listings, required BuyerLocation location, required double radiusKm, required SearchFilter filter, required SearchSortOption sort}) {
  var results = listings.map((e) => NearbySellerResult(listing: e, distanceKm: distanceKm(location,e.latitude,e.longitude))).where((e) => e.distanceKm <= radiusKm && (!filter.inStockOnly || e.listing.inStock) && (!filter.offersOnly || e.listing.offerPrice != null) && (!filter.verifiedOnly || e.listing.verified) && (filter.maximumDistanceKm == null || e.distanceKm <= filter.maximumDistanceKm!) && (filter.minimumPrice == null || e.listing.effectivePrice >= filter.minimumPrice!) && (filter.maximumPrice == null || e.listing.effectivePrice <= filter.maximumPrice!) && (filter.shopCategory == null || e.listing.shopCategory == filter.shopCategory)).toList();
  results.sort((a,b) => switch(sort) { SearchSortOption.lowestPrice => a.listing.effectivePrice.compareTo(b.listing.effectivePrice), SearchSortOption.nearestShop => a.distanceKm.compareTo(b.distanceKm), SearchSortOption.highestTrust => b.listing.trustScore.compareTo(a.listing.trustScore), SearchSortOption.bestOffer => (b.listing.price-b.listing.effectivePrice).compareTo(a.listing.price-a.listing.effectivePrice), SearchSortOption.recentlyUpdated => b.listing.updatedAt.compareTo(a.listing.updatedAt) });
  return results;
}
