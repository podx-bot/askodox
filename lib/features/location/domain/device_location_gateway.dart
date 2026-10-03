import 'geo_models.dart';

/// Abstraction over the device's real GPS/location services.
///
/// [LocationController] talks to the device only through this interface so
/// it never depends on a specific plugin (or any platform channel) directly.
/// Production code is wired to [GeolocatorLocationGateway]; tests inject a
/// fake implementation instead of touching real hardware, mirroring how
/// [GeoRepository]/`MockGeoRepository` are already used in this feature.
abstract class DeviceLocationGateway {
  /// A last-known fix older than this is never used as the current place.
  static const maxLastKnownAge = Duration(minutes: 10);

  const DeviceLocationGateway();

  /// Ensures location services are enabled and permission is granted,
  /// requesting permission from the OS if it has not been decided yet.
  ///
  /// Must never throw: any unexpected platform/plugin failure is mapped to
  /// [LocationPermissionStatus.denied] so the UI can fall back to manual
  /// location selection instead of crashing.
  Future<LocationPermissionStatus> ensurePermission();

  /// The current permission WITHOUT asking the user (used at app start to
  /// refresh an already-allowed location silently). Never throws.
  Future<LocationPermissionStatus> checkPermission();

  /// Reads the device's current GPS position.
  ///
  /// Only meaningful to call after [ensurePermission] has returned
  /// [LocationPermissionStatus.granted]. Returns null (rather than
  /// throwing) if the position could not be read, e.g. no GPS fix within
  /// the allotted time.
  Future<GeoPoint?> getCurrentPosition();

  /// Positions as the phone MOVES, emitted only after it travelled at least
  /// [distanceFilterMetres]. Only listened to while the location follows
  /// the device (never for a place the user picked by hand) and while the
  /// app is in the foreground. Errors end the stream quietly.
  Stream<GeoPoint> watchPosition({int distanceFilterMetres = 300});

  /// The phone's last known fix (used when a fresh fix cannot be read in
  /// time, e.g. indoors). Null when there is none. Never throws.
  Future<GeoPoint?> getLastKnownPosition() async => null;

  /// True when the user allowed only APPROXIMATE location (Android 12+).
  Future<bool> isApproximate() async => false;

  /// Opens the phone's Location (GPS) switch screen. False when unavailable.
  Future<bool> openLocationSettings() async => false;

  /// Opens this app's permission settings (after "Don't ask again").
  Future<bool> openAppSettings() async => false;
}
