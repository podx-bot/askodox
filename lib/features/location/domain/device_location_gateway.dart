import 'geo_models.dart';

/// Abstraction over the device's real GPS/location services.
///
/// [LocationController] talks to the device only through this interface so
/// it never depends on a specific plugin (or any platform channel) directly.
/// Production code is wired to [GeolocatorLocationGateway]; tests inject a
/// fake implementation instead of touching real hardware, mirroring how
/// [GeoRepository]/`MockGeoRepository` are already used in this feature.
abstract class DeviceLocationGateway {
  /// Ensures location services are enabled and permission is granted,
  /// requesting permission from the OS if it has not been decided yet.
  ///
  /// Must never throw: any unexpected platform/plugin failure is mapped to
  /// [LocationPermissionStatus.denied] so the UI can fall back to manual
  /// location selection instead of crashing.
  Future<LocationPermissionStatus> ensurePermission();

  /// Reads the device's current GPS position.
  ///
  /// Only meaningful to call after [ensurePermission] has returned
  /// [LocationPermissionStatus.granted]. Returns null (rather than
  /// throwing) if the position could not be read, e.g. no GPS fix within
  /// the allotted time.
  Future<GeoPoint?> getCurrentPosition();
}
