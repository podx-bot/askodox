import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_device_location_gateway.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<String?> namer(double lat, double lon) async => 'Vuyyuru, Andhra Pradesh';

  test('GPS switched off: a clear message and the phone Location switch is opened (not app settings)', () async {
    final gps = FakeDeviceLocationGateway(permissionResult: LocationPermissionStatus.servicesDisabled);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.requestPermission();
    expect(c.state.message, contains('turned off'));
    expect(c.state.hasPlace, isFalse);
    await c.openFixSettings();
    expect(gps.locationSettingsOpened, 1);
    expect(gps.appSettingsOpened, 0);
  });

  test('blocked permission opens app settings; plain denial offers allow or manual', () async {
    final blocked = FakeDeviceLocationGateway(permissionResult: LocationPermissionStatus.deniedPermanently);
    final c = LocationController(null, blocked);
    await c.requestPermission();
    expect(c.state.message, contains('blocked'));
    await c.openFixSettings();
    expect(blocked.appSettingsOpened, 1);
    expect(askodoxLocationStatusMessage(LocationPermissionStatus.denied), contains('choose a place on the map'));
  });

  test('no fresh fix (indoors): the last known position is used and named; approximate is reported', () async {
    final gps = FakeDeviceLocationGateway(lastKnown: const GeoPoint(16.36, 80.84), approximate: true);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.requestPermission();
    expect(c.state.headerLocation, 'Vuyyuru');
    expect(c.state.approximate, isTrue);
    c.dispose();
  });

  test('when the GPS stream ends, following restarts on the next resume', () async {
    final gps = FakeDeviceLocationGateway(
        position: const GeoPoint(16.30, 80.40), alreadyAllowed: LocationPermissionStatus.granted);
    final c = LocationController(null, gps, placeNamer: namer);
    await c.restoreAndRefresh();
    expect(gps.watchers, 1);
    await gps.movements.close();
    gps.movements = StreamController.broadcast();
    await pumpEventQueue();
    await c.onResume();
    expect(gps.watchers, 2, reason: 'it used to stay "following" a dead stream');
    c.dispose();
  });
}
