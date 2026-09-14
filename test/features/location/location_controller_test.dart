import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/data/mock_geo_repository.dart';
import 'package:podx/features/location/domain/geo_models.dart';

import 'fakes/fake_device_location_gateway.dart';

void main() {
  late LocationController c;
  setUp(() => c = LocationController(
        MockGeoRepository(),
        FakeDeviceLocationGateway(position: const GeoPoint(17.4156, 78.4347)),
      ));

  test('saved location creation and default change', () {
    const home = BuyerSavedLocation(id: 'h', name: 'Home', address: 'A', point: GeoPoint(17, 78), type: SavedLocationType.home),
        work = BuyerSavedLocation(id: 'w', name: 'Work', address: 'B', point: GeoPoint(18, 79), type: SavedLocationType.work);
    c.saveLocation(home);
    c.saveLocation(work);
    c.setDefault('w');
    expect(c.state.locations.length, 2);
    expect(c.state.defaultLocation?.id, 'w');
  });

  test('permission denied flow', () async {
    final denied = LocationController(
      MockGeoRepository(),
      FakeDeviceLocationGateway(permissionResult: LocationPermissionStatus.denied),
    );
    await denied.requestPermission();
    expect(denied.state.permission, LocationPermissionStatus.denied);
    expect(denied.state.message, contains('not granted'));
  });

  test('granted permission with a real GPS fix sets it as the default location', () async {
    // Point 51/location-gap regression guard: previously requestPermission()
    // only flipped an in-memory flag to "granted" without ever reading a
    // real position, so no default location was ever created and the user
    // was stuck on manual selection forever.
    final withFix = LocationController(
      MockGeoRepository(),
      FakeDeviceLocationGateway(
        permissionResult: LocationPermissionStatus.granted,
        position: const GeoPoint(17.4156, 78.4347),
      ),
    );

    await withFix.requestPermission();

    expect(withFix.state.permission, LocationPermissionStatus.granted);
    expect(withFix.state.defaultLocation, isNotNull);
    expect(withFix.state.defaultLocation!.type, SavedLocationType.currentLocation);
    expect(withFix.state.defaultLocation!.point.latitude, 17.4156);
    expect(withFix.state.defaultLocation!.point.longitude, 78.4347);
  });

  test('granted permission without a GPS fix leaves manual selection available', () async {
    final noFix = LocationController(
      MockGeoRepository(),
      FakeDeviceLocationGateway(
        permissionResult: LocationPermissionStatus.granted,
        position: null,
      ),
    );

    await noFix.requestPermission();

    expect(noFix.state.permission, LocationPermissionStatus.granted);
    expect(noFix.state.defaultLocation, isNull);
    expect(noFix.state.message, contains('could not be read'));
  });

  test('manual location selection refreshes nearby sellers', () async {
    final ok = await c.selectManualLocation(
      const BuyerSavedLocation(id: 'm', name: 'Manual', address: 'Test', point: GeoPoint(17.4156, 78.4347), type: SavedLocationType.custom),
    );
    expect(ok, isTrue);
    expect(c.state.defaultLocation?.id, 'm');
    expect(c.state.shops, isNotEmpty);
  });

  test('search this area uses map centre and refreshes', () async {
    c.moveMap(const GeoPoint(17.4380, 78.4510));
    await c.setRadius(500);
    await c.searchThisArea();
    expect(c.state.centre.latitude, 17.4380);
    expect(c.state.shops.any((s) => s.id == 'metro'), isTrue);
  });

  test('nearby seller refresh responds to radius', () async {
    await c.setRadius(100);
    final short = c.state.shops.length;
    await c.setRadius(5000);
    expect(c.state.shops.length, greaterThan(short));
  });
}
