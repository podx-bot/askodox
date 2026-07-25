import 'geo_models.dart';
abstract class GeoRepository {
  Future<List<NearbyShop>> getNearbySellers(GeoSearchQuery query);
  Future<List<String>> getNearbyProductListings(GeoSearchQuery query);
  Future<List<NearbyShop>> getSellersWithinRadius(GeoPoint centre, double radiusMetres);
  Future<int> getDemandWithinRadius(GeoSearchQuery query);
  Future<int> getWatchlistMatchesWithinRadius(GeoSearchQuery query);
}
