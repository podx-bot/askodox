import 'package:podx/features/location/domain/device_location_gateway.dart';
import 'package:podx/features/location/domain/geo_models.dart';

/// Test double for [DeviceLocationGateway]. Never touches real GPS/OS APIs;
/// results are configured explicitly so permission and current-position
/// behaviour can be exercised deterministically in tests.
class FakeDeviceLocationGateway implements DeviceLocationGateway {
  FakeDeviceLocationGateway({
    this.permissionResult = LocationPermissionStatus.granted,
    this.position,
    this.alreadyAllowed = LocationPermissionStatus.notRequested,
  });

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
}
