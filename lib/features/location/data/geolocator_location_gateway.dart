import 'package:geolocator/geolocator.dart';

import '../domain/device_location_gateway.dart';
import '../domain/geo_models.dart';

/// Real device GPS implementation of [DeviceLocationGateway], backed by the
/// `geolocator` plugin. This is the only file in the location feature that
/// talks to the OS location APIs; everything else in the feature (including
/// [LocationController]) depends only on the [DeviceLocationGateway]
/// interface so it stays testable without a real device.
class GeolocatorLocationGateway implements DeviceLocationGateway {
  const GeolocatorLocationGateway();

  @override
  Future<LocationPermissionStatus> ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionStatus.servicesDisabled;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          return LocationPermissionStatus.granted;
        case LocationPermission.deniedForever:
          return LocationPermissionStatus.deniedPermanently;
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationPermissionStatus.denied;
      }
    } catch (_) {
      // Any platform/plugin failure (missing plugin on an unsupported
      // platform, OS error, etc.) is treated as a plain denial so the UI
      // falls back to manual location selection instead of crashing.
      return LocationPermissionStatus.denied;
    }
  }

  @override
  Future<GeoPoint?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final point = GeoPoint(position.latitude, position.longitude);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }
}
