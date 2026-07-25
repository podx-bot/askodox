import 'dart:math';
import 'geo_models.dart';

class GeoDistanceService {
  const GeoDistanceService();
  static const _earthRadiusMetres = 6371000.0;
  double? distanceMetres(GeoPoint from, GeoPoint to) {
    if (!from.isValid || !to.isValid) return null;
    final dLat = _radians(to.latitude - from.latitude), dLon = _radians(to.longitude - from.longitude);
    final a = pow(sin(dLat / 2), 2) + cos(_radians(from.latitude)) * cos(_radians(to.latitude)) * pow(sin(dLon / 2), 2);
    return _earthRadiusMetres * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
  double? distanceKilometres(GeoPoint from, GeoPoint to) { final metres = distanceMetres(from, to); return metres == null ? null : metres / 1000; }
  bool isWithinRadius(GeoPoint from, GeoPoint to, double radiusMetres) { final distance = distanceMetres(from, to); return radiusMetres >= 0 && distance != null && distance <= radiusMetres; }
  double _radians(double degrees) => degrees * pi / 180;
}
