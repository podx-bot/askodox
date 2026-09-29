import 'dart:async';

import 'package:podx/features/location/domain/device_location_gateway.dart';
import 'package:podx/features/location/domain/geo_models.dart';

/// Test double for [DeviceLocationGateway]. Never touches real GPS/OS APIs;
/// results are configured explicitly so permission and current-position
/// behaviour can be exercised deterministically in tests.
class FakeDeviceLocationGateway extends DeviceLocationGateway {
  FakeDeviceLocationGateway({
    this.permissionResult = LocationPermissionStatus.granted,
    this.position,
    this.alreadyAllowed = LocationPermissionStatus.notRequested,
    this.lastKnown,
    this.approximate = false,
  });

  final GeoPoint? lastKnown;
  final bool approximate;
  int locationSettingsOpened = 0, appSettingsOpened = 0;

  @override
  Future<GeoPoint?> getLastKnownPosition() async => lastKnown;

  @override
  Future<bool> isApproximate() async => approximate;

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  final LocationPermissionStatus permissionResult;
  final GeoPoint? position;

  /// What the OS reports before the app asks (app start).
  final LocationPermissionStatus alreadyAllowed;
  int prompts = 0;

  @override
  Future<LocationPermissionStatus> ensurePermission() async {
    prompts++;
    return permissionResult;
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async => alreadyAllowed;

  @override
  Future<GeoPoint?> getCurrentPosition() async => position;

  /// Push a new device position (the phone moved).
  StreamController<GeoPoint> movements = StreamController<GeoPoint>.broadcast();
  int watchers = 0;

  @override
  Stream<GeoPoint> watchPosition({int distanceFilterMetres = 300}) {
    watchers++;
    return movements.stream;
  }
}
