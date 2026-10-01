import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_device_location_gateway.dart';

/// A phone whose GPS / permission / fix can change during the test.
class _Phone extends FakeDeviceLocationGateway {
  _Phone() : super(alreadyAllowed: LocationPermissionStatus.granted);
  LocationPermissionStatus status = LocationPermissionStatus.granted;
  GeoPoint? fix = const GeoPoint(16.36, 80.84);

  @override
  Future<LocationPermissionStatus> checkPermission() async => status;
  @override
  Future<LocationPermissionStatus> ensurePermission() async => status;
  @override
  Future<GeoPoint?> getCurrentPosition() async => fix;
  @override
  Future<GeoPoint?> getLastKnownPosition() async => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<String?> namer(double lat, double lon) async =>
      lat > 17 ? 'Vijayawada, Andhra Pradesh' : 'Vuyyuru, Andhra Pradesh';

  test('APK 1273: GPS switched off after detection -> the old place is flagged stale, not used silently', () async {
    final phone = _Phone();
    final c = LocationController(null, phone, placeNamer: namer);
    await c.requestPermission();
    expect(c.state.headerLocation, 'Vuyyuru');
    expect(c.state.stale, isFalse);

    phone.status = LocationPermissionStatus.servicesDisabled;
    await c.onResume();
    expect(c.state.stale, isTrue);
    expect(c.state.message, contains('Location is off'));

    // GPS back on and the phone moved: fresh place, stale cleared.
    phone.status = LocationPermissionStatus.granted;
    phone.fix = const GeoPoint(17.5, 80.6);
    await c.onResume();
    expect(c.state.stale, isFalse);
    expect(c.state.headerLocation, 'Vijayawada');
    c.dispose();
  });

  test('permission revoked or no fix: stale with an honest reason; a hand-picked place clears it', () async {
    final phone = _Phone();
    final c = LocationController(null, phone, placeNamer: namer);
    await c.requestPermission();
    phone.fix = null;
    await c.refreshCurrentLocation();
    expect(c.state.stale, isTrue);
    expect(c.state.message, contains('could not be read'));

    phone.status = LocationPermissionStatus.deniedPermanently;
    await c.onResume();
    expect(c.state.message, contains('not allowed'));

    await c.selectManualLocation(const BuyerSavedLocation(
        id: 'home', name: 'Home', address: 'Gudivada', point: GeoPoint(16.43, 80.99), type: SavedLocationType.home));
    expect(c.state.stale, isFalse, reason: 'a place the user picked is current by definition');
    expect(c.state.headerLocation, 'Gudivada');
    c.dispose();
  });

  test('a place detected in an earlier session is stale on restart while GPS is off', () async {
    final phone = _Phone();
    final first = LocationController(null, phone, placeNamer: namer);
    await first.requestPermission();
    first.dispose();
    phone.status = LocationPermissionStatus.servicesDisabled;
    final restarted = LocationController(null, phone, placeNamer: namer);
    await restarted.restoreAndRefresh();
    expect(restarted.state.headerLocation, 'Vuyyuru');
    expect(restarted.state.stale, isTrue);
    restarted.dispose();
  });
}
