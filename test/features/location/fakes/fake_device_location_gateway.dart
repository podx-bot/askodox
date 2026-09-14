import 'package:podx/features/location/domain/device_location_gateway.dart';
import 'package:podx/features/location/domain/geo_models.dart';

/// Test double for [DeviceLocationGateway]. Never touches real GPS/OS APIs;
/// results are configured explicitly so permission and current-position
/// behaviour can be exercised deterministically in tests.
class FakeDeviceLocationGateway implements DeviceLocationGateway {
  FakeDeviceLocationGateway({
    this.permissionResult = LocationPermissionStatus.granted,
    this.position,
  });

  final LocationPermissionStatus permissionResult;
  final GeoPoint? position;

  @override
  Future<LocationPermissionStatus> ensurePermission() async => permissionResult;

  @override
  Future<GeoPoint?> getCurrentPosition() async => position;
}
