enum SavedLocationType { home, work, currentLocation, custom }
enum LocationPermissionStatus { notRequested, granted, denied, deniedPermanently, servicesDisabled }
enum MapDisplayMode { map, list }

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
  bool get isValid => latitude.isFinite && longitude.isFinite && latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

class BuyerSavedLocation {
  const BuyerSavedLocation({required this.id, required this.name, required this.address, required this.point, required this.type, this.isDefault = false});
  final String id, name, address;
  final GeoPoint point;
  final SavedLocationType type;
  final bool isDefault;
  BuyerSavedLocation copyWith({String? name, bool? isDefault, GeoPoint? point}) => BuyerSavedLocation(id: id, name: name ?? this.name, address: address, point: point ?? this.point, type: type, isDefault: isDefault ?? this.isDefault);
}

class NearbyShop {
  const NearbyShop({required this.id, required this.name, required this.businessName, required this.category, required this.address, required this.point, required this.distanceMetres, required this.verified, required this.trustScore, required this.isOpen, required this.productCount, required this.watchlistMatches, required this.activeOffers});
  final String id, name, businessName, category, address;
  final GeoPoint point;
  final double distanceMetres, trustScore;
  final bool verified, isOpen;
  final int productCount, watchlistMatches, activeOffers;
  NearbyShop withDistance(double value) => NearbyShop(id:id,name:name,businessName:businessName,category:category,address:address,point:point,distanceMetres:value,verified:verified,trustScore:trustScore,isOpen:isOpen,productCount:productCount,watchlistMatches:watchlistMatches,activeOffers:activeOffers);
}

class MapMarkerModel { const MapMarkerModel({required this.id, required this.point, required this.label, this.isBuyer = false}); final String id, label; final GeoPoint point; final bool isBuyer; }
class MapViewport { const MapViewport({required this.centre, this.zoom = 13}); final GeoPoint centre; final double zoom; }
class GeoSearchQuery { const GeoSearchQuery({required this.centre, required this.radiusMetres}); final GeoPoint centre; final double radiusMetres; }
class GeoSearchResult { const GeoSearchResult({required this.query, required this.shops}); final GeoSearchQuery query; final List<NearbyShop> shops; }
class SellerLocationSettings { const SellerLocationSettings({this.point, this.landmark = '', this.serviceRadiusMetres = 5000, this.isConfirmed = false, this.publicLocation = true, this.hideExactLocation = false}); final GeoPoint? point; final String landmark; final double serviceRadiusMetres; final bool isConfirmed, publicLocation, hideExactLocation; }
class BuyerLocationPrivacySettings { const BuyerLocationPrivacySettings({this.allowLocationAccess = false, this.usePreciseLocation = false, this.saveSearchHistory = true, this.saveRecentLocations = true}); final bool allowLocationAccess, usePreciseLocation, saveSearchHistory, saveRecentLocations; }
