import 'package:geolocator/geolocator.dart';

import '../domain/device_location_gateway.dart';
import '../domain/geo_models.dart';

/// Real device GPS implementation of [DeviceLocationGateway], backed by the
/// `geolocator` plugin. This is the only file in the location feature that
/// talks to the OS location APIs; everything else in the feature (including
/// [LocationController]) depends only on the [DeviceLocationGateway]
/// interface so it stays testable without a real device.
class GeolocatorLocationGateway extends DeviceLocationGateway {
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
  Future<LocationPermissionStatus> checkPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationPermissionStatus.servicesDisabled;
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.always || LocationPermission.whileInUse => LocationPermissionStatus.granted,
        LocationPermission.deniedForever => LocationPermissionStatus.deniedPermanently,
        LocationPermission.denied => LocationPermissionStatus.notRequested,
        LocationPermission.unableToDetermine => LocationPermissionStatus.notRequested,
      };
    } catch (_) {
      return LocationPermissionStatus.notRequested;
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

  @override
  Future<GeoPoint?> getLastKnownPosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      // An old fix (yesterday, another town) is not "current location".
      if (DateTime.now().difference(position.timestamp) > DeviceLocationGateway.maxLastKnownAge) return null;
      final point = GeoPoint(position.latitude, position.longitude);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isApproximate() async {
    try {
      return await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<GeoPoint> watchPosition({int distanceFilterMetres = 300}) {
    try {
      return Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: distanceFilterMetres,
        ),
      )
          .map((position) => GeoPoint(position.latitude, position.longitude))
          .where((point) => point.isValid)
          .handleError((Object _) {});
    } catch (_) {
      return const Stream<GeoPoint>.empty();
    }
  }
}
