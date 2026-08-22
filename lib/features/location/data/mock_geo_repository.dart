import '../domain/geo_distance_service.dart';
import '../domain/geo_models.dart';
import '../domain/geo_repository.dart';

class MockGeoRepository implements GeoRepository {
  MockGeoRepository({this.extraShops = const []});

  final List<NearbyShop> extraShops;
  final _distance = const GeoDistanceService();

  List<NearbyShop> get _shops => [...mockNearbyShops, ...extraShops];

  @override
  Future<List<NearbyShop>> getNearbySellers(GeoSearchQuery query) async =>
      getSellersWithinRadius(query.centre, query.radiusMetres);

  @override
  Future<List<NearbyShop>> getSellersWithinRadius(
    GeoPoint centre,
    double radiusMetres,
  ) async =>
      [
        for (final shop in _shops)
          if (_distance.isWithinRadius(centre, shop.point, radiusMetres))
            shop.withDistance(
              _distance.distanceMetres(centre, shop.point)!,
            ),
      ]..sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));

  @override
  Future<List<String>> getNearbyProductListings(GeoSearchQuery query) async =>
      (await getNearbySellers(query))
          .expand(
            (shop) => List.generate(
              shop.productCount.clamp(0, 3).toInt(),
              (index) => '${shop.id}-product-$index',
            ),
          )
          .toList();

  @override
  Future<int> getDemandWithinRadius(GeoSearchQuery query) async {
    final shops = await getNearbySellers(query);
    return shops.fold<int>(
      0,
      (total, shop) => total + shop.watchlistMatches,
    );
  }

  @override
  Future<int> getWatchlistMatchesWithinRadius(GeoSearchQuery query) =>
      getDemandWithinRadius(query);
}

const mockNearbyShops = [
  NearbyShop(
    id: 'fresh',
    name: 'ASKODOX Fresh Mart',
    businessName: 'ASKODOX Retail Pvt Ltd',
    category: 'Supermarket',
    address: 'Road 12, Banjara Hills, Hyderabad',
    point: GeoPoint(17.4170, 78.4370),
    distanceMetres: 0,
    verified: true,
    trustScore: 4.8,
    isOpen: true,
    productCount: 86,
    watchlistMatches: 3,
    activeOffers: 12,
  ),
  NearbyShop(
    id: 'sri',
    name: 'Sri Local Stores',
    businessName: 'Sri Lakshmi Stores',
    category: 'Kirana',
    address: 'Jubilee Hills, Hyderabad',
    point: GeoPoint(17.4260, 78.4430),
    distanceMetres: 0,
    verified: false,
    trustScore: 4.1,
    isOpen: true,
    productCount: 44,
    watchlistMatches: 1,
    activeOffers: 4,
  ),
  NearbyShop(
    id: 'metro',
    name: 'Metro Daily',
    businessName: 'Metro Daily Foods',
    category: 'Supermarket',
    address: 'Somajiguda, Hyderabad',
    point: GeoPoint(17.4380, 78.4510),
    distanceMetres: 0,
    verified: true,
    trustScore: 4.9,
    isOpen: false,
    productCount: 132,
    watchlistMatches: 5,
    activeOffers: 18,
  ),
];
