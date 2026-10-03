import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_device_location_gateway.dart';

/// Location is permission-based, follows the phone while allowed, is named
/// in human words, never assumes a city, and a hand-picked place always wins.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Names by rounded coordinates so each test place gets its own name.
  Future<String?> namer(double lat, double lon) async => 'Place ${lat.toStringAsFixed(2)}, State';

  test('no place and no built-in city before the user allows or chooses one', () {
    final c = LocationController(null, FakeDeviceLocationGateway());
    expect(c.state.hasPlace, isFalse);
    expect(c.state.headerLocation, isNull);
    expect(c.state.defaultLocation, isNull);
  });

  test('allowed: the header names the place and follows the phone when it moves', () async {
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.restoreAndRefresh();
    expect(c.state.headerLocation, 'Place 16.30');
    expect(gps.watchers, 1, reason: 'following starts once location is allowed');

    // Small jitter (< threshold): same place, no re-naming.
    gps.movements.add(const GeoPoint(16.3005, 80.4003));
    await pumpEventQueue();
    expect(c.state.headerLocation, 'Place 16.30');

    // Travelled ~5 km: new point AND new human-readable name.
    gps.movements.add(const GeoPoint(16.35, 80.40));
    await pumpEventQueue();
    expect(c.state.headerLocation, 'Place 16.35');
    expect(c.state.defaultLocation?.point.latitude, 16.35, reason: 'searches use the new point');
    c.dispose();
  });

  test('a place picked by hand is never overwritten by movement or resume', () async {
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.restoreAndRefresh();
    await c.selectManualLocation(const BuyerSavedLocation(
        id: 'manual', name: 'My shop area', address: 'Market Road, Town', point: GeoPoint(17.0, 81.0), type: SavedLocationType.custom));
    gps.movements.add(const GeoPoint(16.60, 80.40));
    await pumpEventQueue();
    await c.onResume();
    expect(c.state.headerLocation, 'Market Road');
    expect(c.state.defaultLocation?.point.latitude, 17.0);
    expect(c.state.followsDevice, isFalse);

    // "Use my location" again goes back to following the phone.
    await c.requestPermission();
    expect(c.state.followsDevice, isTrue);
    expect(c.state.headerLocation, 'Place 16.30');
    c.dispose();
  });

  test('a hand-picked place survives an app restart and the phone never overrides it', () async {
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final first = LocationController(null, gps, placeNamer: namer);
    await first.restoreAndRefresh();
    await first.selectManualLocation(const BuyerSavedLocation(
        id: 'manual', name: 'My shop area', address: 'Market Road, Town', point: GeoPoint(17.0, 81.0), type: SavedLocationType.custom));
    first.dispose();

    // New process: same storage, the phone is now somewhere else.
    final gps2 = FakeDeviceLocationGateway(
        position: const GeoPoint(16.60, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final second = LocationController(null, gps2, placeNamer: namer);
    await second.restoreAndRefresh();
    expect(second.state.headerLocation, 'Market Road');
    expect(second.state.defaultLocation?.point.latitude, 17.0);
    expect(second.state.followsDevice, isFalse);
    expect(gps2.watchers, 0, reason: 'no movement following over a manual choice');
    second.dispose();
  });

  test('an unnamed place is re-named on the next resume (no stuck "Current location")', () async {
    var online = false;
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final c = LocationController(null, gps, placeNamer: (lat, lon) async => online ? 'Town, State' : null);
    await c.restoreAndRefresh();
    expect(c.state.defaultLocation?.name, 'Current location');
    expect(c.state.unnamed, isTrue);
    online = true;
    await c.onResume();
    expect(c.state.headerLocation, 'Town');
    expect(c.state.unnamed, isFalse);
    c.dispose();
  });

  test('denied / services off: honest message, manual choice still works, nothing invented', () async {
    for (final status in [
      LocationPermissionStatus.denied,
      LocationPermissionStatus.deniedPermanently,
      LocationPermissionStatus.servicesDisabled,
    ]) {
      final gps = FakeDeviceLocationGateway(permissionResult: status, position: const GeoPoint(16.3, 80.4));
      final c = LocationController(null, gps, placeNamer: namer);
      await c.requestPermission();
      expect(c.state.defaultLocation, isNull, reason: '$status');
      expect(c.state.message, askodoxLocationStatusMessage(status), reason: 'a specific, honest reason per status');
      expect(gps.watchers, 0, reason: 'never follows without permission');
      final ok = await c.selectManualLocation(const BuyerSavedLocation(
          id: 'm', name: 'Chosen', address: 'Chosen Area, City', point: GeoPoint(17.1, 80.1), type: SavedLocationType.custom));
      expect(ok, isTrue);
      expect(c.state.headerLocation, 'Chosen Area');
      c.dispose();
    }
  });

  test('stopFollowing (app in background) stops movement updates', () async {
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.restoreAndRefresh();
    await c.stopFollowing();
    gps.movements.add(const GeoPoint(16.80, 80.40));
    await pumpEventQueue();
    expect(c.state.headerLocation, 'Place 16.30');
    c.dispose();
  });
}
