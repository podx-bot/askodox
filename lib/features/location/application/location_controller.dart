import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/environment.dart';
import '../../../core/providers/backend_providers.dart';

import '../data/geolocator_location_gateway.dart';
import '../data/mock_geo_repository.dart';
import '../domain/device_location_gateway.dart';
import '../domain/geo_distance_service.dart';
import '../domain/geo_models.dart';
import '../domain/geo_repository.dart';
import '../../../services/place_name_service.dart';

final geoRepositoryProvider = Provider<GeoRepository?>((ref) {
  final config = ref.watch(appConfigProvider);
  // Never expose fictional nearby sellers in a real REST-backed build.
  // Until a real geo seller repository is wired, Nearby intentionally returns
  // no sellers rather than presenting mock shops as live commerce.
  if (config.backendProvider == BackendProvider.rest) return null;
  return MockGeoRepository();
});
final deviceLocationGatewayProvider = Provider<DeviceLocationGateway>(
  (ref) => const GeolocatorLocationGateway(),
);
final locationControllerProvider = StateNotifierProvider<LocationController, LocationState>(
  (ref) => LocationController(
    ref.read(geoRepositoryProvider),
    ref.read(deviceLocationGatewayProvider),
    placeNamer: const PlaceNameService().resolve,
  )..restoreAndRefresh(),
);

class LocationState {
  const LocationState({
    this.permission = LocationPermissionStatus.notRequested,
    this.locations = const [],
    // No city is assumed: (0,0) means "no place chosen yet" (see hasPlace).
    this.centre = const GeoPoint(0, 0),
    this.radiusMetres = 5000,
    this.shops = const [],
    this.mode = MapDisplayMode.map,
    this.loading = false,
    this.offline = false,
    this.selectedShopId,
    this.message,
    this.approximate = false,
  });

  /// The user allowed only approximate location (Android 12+): places are
  /// right to ~1-3 km; the app says so instead of claiming precision.
  final bool approximate;

  final LocationPermissionStatus permission;
  final List<BuyerSavedLocation> locations;
  final GeoPoint centre;
  final double radiusMetres;
  final List<NearbyShop> shops;
  final MapDisplayMode mode;
  final bool loading, offline;
  final String? selectedShopId, message;

  /// A real place is known (chosen, detected or a map area) -- never a
  /// built-in city.
  bool get hasPlace => centre.latitude != 0 || centre.longitude != 0;

  /// The active place follows the phone (not a place picked by hand).
  bool get followsDevice {
    final current = defaultLocation;
    return current == null || current.type == SavedLocationType.currentLocation;
  }

  /// The detected place still has no human-readable name.
  bool get unnamed {
    final current = defaultLocation;
    return current != null && current.type == SavedLocationType.currentLocation && current.address.trim().isEmpty;
  }

  BuyerSavedLocation? get defaultLocation {
    for (final l in locations) {
      if (l.isDefault) return l;
    }
    return null;
  }

  String? get displayLocation {
    final location = defaultLocation;
    if (location == null) return null;
    final address = location.address.trim();
    return address.isNotEmpty ? address : location.name.trim();
  }

  /// Short name for the header ("Vuyyuru" from "Vuyyuru, Andhra Pradesh").
  /// It is the SAME location every search uses (full label + coordinates).
  String? get headerLocation {
    final full = displayLocation;
    if (full == null || full.isEmpty) return null;
    return full.split(',').first.trim();
  }

  LocationState copyWith({
    LocationPermissionStatus? permission,
    List<BuyerSavedLocation>? locations,
    GeoPoint? centre,
    double? radiusMetres,
    List<NearbyShop>? shops,
    MapDisplayMode? mode,
    bool? loading,
    bool? offline,
    String? selectedShopId,
    String? message,
    bool clearMessage = false,
    bool? approximate,
  }) =>
      LocationState(
        approximate: approximate ?? this.approximate,
        permission: permission ?? this.permission,
        locations: locations ?? this.locations,
        centre: centre ?? this.centre,
        radiusMetres: radiusMetres ?? this.radiusMetres,
        shops: shops ?? this.shops,
        mode: mode ?? this.mode,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        selectedShopId: selectedShopId ?? this.selectedShopId,
        message: clearMessage ? null : message ?? this.message,
      );
}

/// Names a GPS point (area / city / state); null when it cannot.
typedef PlaceNamer = Future<String?> Function(double latitude, double longitude);

class LocationController extends StateNotifier<LocationState> {
  LocationController(this._repository, this._deviceLocation, {PlaceNamer? placeNamer})
      : _placeNamer = placeNamer,
        super(const LocationState());

  final PlaceNamer? _placeNamer;

  /// Moving this far from the active point re-reads and re-names the place.
  static const moveThresholdMetres = 300.0;
  StreamSubscription<GeoPoint>? _following;
  bool _updatingFromMove = false;

  static const _storageKey = 'askodox.selected_location.v1';
  // Recently used places (max 5) shown under "Use my location / Search".
  static const _recentKey = 'askodox.recent_locations.v1';
  final GeoRepository? _repository;
  final DeviceLocationGateway _deviceLocation;

  Future<void> restoreAndRefresh() async {
    await _restore();
    // Location already allowed: read where the phone is NOW and name it
    // (no prompt). A place the user picked by hand is kept as chosen.
    if (state.followsDevice && await _deviceLocation.checkPermission() == LocationPermissionStatus.granted) {
      await requestPermission();
      return;
    }
    await refresh();
  }

  /// Follow the phone while the app is open: a new place is detected and
  /// named when the user has moved [moveThresholdMetres]. Never overrides a
  /// place the user picked by hand; stops when they pick one.
  Future<void> startFollowing() async {
    if (_following != null || !state.followsDevice) return;
    if (await _deviceLocation.checkPermission() != LocationPermissionStatus.granted) return;
    if (!mounted || !state.followsDevice) return;
    _following = _deviceLocation
        .watchPosition(distanceFilterMetres: moveThresholdMetres.round())
        .listen((point) => unawaited(onDeviceMoved(point)), onError: (Object _) {}, cancelOnError: false,
            // GPS switched off / stream ended: allow the next resume or
            // refresh to start following again (it used to stay "on").
            onDone: () => _following = null);
  }

  Future<void> stopFollowing() async {
    final following = _following;
    _following = null;
    await following?.cancel();
  }

  /// App came back to the foreground: silently re-read the phone's place
  /// (no prompt) when it follows the device, then keep following.
  Future<void> onResume() async {
    if (!state.followsDevice) return;
    final permission = await _deviceLocation.checkPermission();
    if (permission == LocationPermissionStatus.granted) {
      final point = await _deviceLocation.getCurrentPosition();
      if (point != null) await onDeviceMoved(point);
      await startFollowing();
    } else if (state.permission == LocationPermissionStatus.granted) {
      // Permission was revoked in Settings meanwhile: say so honestly.
      state = state.copyWith(permission: permission, message: 'Location access was not granted');
    }
  }

  /// The device reports a (possibly new) position.
  Future<void> onDeviceMoved(GeoPoint point) async {
    if (!mounted || !point.isValid || !state.followsDevice || _updatingFromMove) return;
    final current = state.defaultLocation;
    final moved = current == null
        ? double.infinity
        : const GeoDistanceService().distanceMetres(current.point, point) ?? double.infinity;
    // Same place and already named: nothing to do (no extra lookups).
    if (moved < moveThresholdMetres && !state.unnamed) return;
    _updatingFromMove = true;
    try {
      await _selectDevicePoint(point);
    } finally {
      _updatingFromMove = false;
    }
  }

  @override
  void dispose() {
    _following?.cancel();
    _following = null;
    super.dispose();
  }

  /// Opens the right settings screen for the current problem: the phone's
  /// Location switch when GPS is off, this app's permissions after "Don't
  /// ask again". Returns false when nothing could be opened.
  Future<bool> openFixSettings() => state.permission == LocationPermissionStatus.servicesDisabled
      ? _deviceLocation.openLocationSettings()
      : _deviceLocation.openAppSettings();

  /// "Refresh my location": re-read GPS and re-name it.
  Future<void> refreshCurrentLocation() => requestPermission();

  /// Requests real device location permission and, once granted, reads the
  /// device's current GPS position and saves it as the default location.
  ///
  /// Point 51/location-gap fix: this used to just mark `permission` as
  /// granted without ever touching real GPS or the OS permission dialog,
  /// so tapping the button never actually gave the user a default location.
  Future<void> requestPermission() async {
    final status = await _deviceLocation.ensurePermission();
    state = state.copyWith(
      permission: status,
      message: askodoxLocationStatusMessage(status),
      clearMessage: status == LocationPermissionStatus.granted,
    );
    if (status != LocationPermissionStatus.granted) return;

    // A fresh fix first; indoors / weak GPS falls back to the phone's last
    // known fix rather than failing.
    final point = await _deviceLocation.getCurrentPosition() ?? await _deviceLocation.getLastKnownPosition();
    if (await _deviceLocation.isApproximate()) {
      state = state.copyWith(approximate: true);
    }
    if (point == null) {
      state = state.copyWith(
        message: 'Location access granted, but the device position could not be read. '
            'Please retry or choose a location manually.',
      );
      return;
    }

    await _selectDevicePoint(point);
    await startFollowing();
  }

  /// Names [point] and makes it the active place (type currentLocation).
  Future<void> _selectDevicePoint(GeoPoint point) async {
    // A readable place (area, town, state) from the phone's Geocoder or the
    // backend; otherwise honestly "Current location" (retried on the next
    // move or resume).
    String? place;
    try {
      place = await _placeNamer?.call(point.latitude, point.longitude);
    } catch (_) {
      place = null;
    }
    await selectManualLocation(
      BuyerSavedLocation(
        id: 'current-location',
        name: place ?? 'Current location',
        address: place ?? '',
        point: point,
        type: SavedLocationType.currentLocation,
      ),
    );
  }

  Future<void> retryLocation() => requestPermission();

  Future<bool> selectManualLocation(BuyerSavedLocation location) async {
    if (!location.point.isValid) {
      state = state.copyWith(message: 'Invalid location');
      return false;
    }
    // A place picked by hand wins: stop following the phone until the user
    // chooses "Use my location" again.
    if (location.type != SavedLocationType.currentLocation) await stopFollowing();
    final selected = location.copyWith(isDefault: true);
    final nextLocations = [
      for (final l in state.locations.where((l) => l.id != selected.id)) l.copyWith(isDefault: false),
      selected,
    ];
    state = state.copyWith(locations: nextLocations, centre: selected.point);
    await _persist(selected);
    await refresh();
    return true;
  }

  void saveLocation(BuyerSavedLocation location) {
    state = state.copyWith(locations: [...state.locations.where((l) => l.id != location.id), location]);
  }

  void renameLocation(String id, String name) {
    state = state.copyWith(
      locations: [for (final l in state.locations) if (l.id == id) l.copyWith(name: name) else l],
    );
    final selected = state.defaultLocation;
    if (selected != null) _persist(selected);
  }

  void deleteLocation(String id) {
    final wasDefault = state.defaultLocation?.id == id;
    state = state.copyWith(locations: state.locations.where((l) => l.id != id).toList());
    if (wasDefault) _clearPersisted();
  }

  void setDefault(String id) {
    state = state.copyWith(
      locations: [for (final l in state.locations) l.copyWith(isDefault: l.id == id)],
    );
    final selected = state.defaultLocation;
    if (selected != null) {
      state = state.copyWith(centre: selected.point);
      _persist(selected);
    }
  }

  Future<void> setRadius(double metres) async {
    state = state.copyWith(radiusMetres: metres);
    await refresh();
  }

  void moveMap(GeoPoint centre) {
    if (centre.isValid) {
      state = state.copyWith(centre: centre, message: 'Map moved. Search this area to refresh.');
    }
  }

  Future<void> searchThisArea() async {
    state = state.copyWith(clearMessage: true);
    await refresh();
  }

  Future<void> saveSelectedArea() async => selectManualLocation(
        BuyerSavedLocation(
          id: 'area-${DateTime.now().millisecondsSinceEpoch}',
          name: 'Saved area',
          address: 'Map-selected area',
          point: state.centre,
          type: SavedLocationType.custom,
        ),
      );

  void toggleMode(MapDisplayMode mode) => state = state.copyWith(mode: mode);
  void selectShop(String id) => state = state.copyWith(selectedShopId: id);

  Future<void> refresh() async {
    if (!state.hasPlace) {
      state = state.copyWith(shops: const []);
      return;
    }
    if (!state.centre.isValid) {
      state = state.copyWith(message: 'Invalid location', shops: []);
      return;
    }
    if (state.offline) {
      state = state.copyWith(message: 'Offline mode');
      return;
    }
    final repository = _repository;
    if (repository == null) {
      state = state.copyWith(
        loading: false,
        shops: const [],
        message: 'Nearby sellers are not available yet. Ask ASKODOX to find real local options.',
      );
      return;
    }
    state = state.copyWith(loading: true);
    final shops = await repository.getNearbySellers(
      GeoSearchQuery(centre: state.centre, radiusMetres: state.radiusMetres),
    );
    state = state.copyWith(
      loading: false,
      shops: shops,
      message: shops.isEmpty ? 'No sellers within radius' : '${shops.length} nearby shops',
    );
  }

  void setOffline(bool value) {
    state = state.copyWith(offline: value, message: value ? 'Offline mode' : null, clearMessage: !value);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      final latitude = (json['latitude'] as num?)?.toDouble();
      final longitude = (json['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return;
      final point = GeoPoint(latitude, longitude);
      if (!point.isValid) return;
      final typeName = json['type']?.toString();
      final type = SavedLocationType.values.where((value) => value.name == typeName).firstOrNull ?? SavedLocationType.custom;
      final selected = BuyerSavedLocation(
        id: json['id']?.toString() ?? 'saved-location',
        name: json['name']?.toString() ?? 'Saved location',
        address: json['address']?.toString() ?? '',
        point: point,
        type: type,
        isDefault: true,
      );
      state = state.copyWith(locations: [selected], centre: point);
    } catch (_) {
      await _clearPersisted();
    }
  }

  static Map<String, Object?> _encode(BuyerSavedLocation location) => {
        'id': location.id,
        'name': location.name,
        'address': location.address,
        'latitude': location.point.latitude,
        'longitude': location.point.longitude,
        'type': location.type.name,
      };

  static BuyerSavedLocation? _decode(Object? json, {bool isDefault = false}) {
    if (json is! Map) return null;
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final point = GeoPoint(latitude, longitude);
    if (!point.isValid) return null;
    final typeName = json['type']?.toString();
    return BuyerSavedLocation(
      id: json['id']?.toString() ?? 'saved-location',
      name: json['name']?.toString() ?? 'Saved location',
      address: json['address']?.toString() ?? '',
      point: point,
      type: SavedLocationType.values.where((value) => value.name == typeName).firstOrNull ?? SavedLocationType.custom,
      isDefault: isDefault,
    );
  }

  Future<void> _persist(BuyerSavedLocation location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_encode(location)));
      final label = location.address.isNotEmpty ? location.address : location.name;
      final recents = [
        _encode(location),
        for (final item in (jsonDecode(prefs.getString(_recentKey) ?? '[]') as List))
          if (item is Map && '${item['address']?.toString().isNotEmpty == true ? item['address'] : item['name']}' != label)
            Map<String, Object?>.from(item),
      ].take(5).toList();
      await prefs.setString(_recentKey, jsonEncode(recents));
    } catch (_) {}
  }

  /// Privacy: forget the saved and recent places on this device.
  Future<void> clearSaved() async {
    state = state.copyWith(locations: const []);
    await _clearPersisted();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentKey);
    } catch (_) {}
  }

  /// Recently used places (newest first), for one-tap reuse.
  Future<List<BuyerSavedLocation>> recentPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final item in (jsonDecode(prefs.getString(_recentKey) ?? '[]') as List))
          if (_decode(item) case final place?) place,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}

/// What to tell the user for each permission outcome (null = all good).
String? askodoxLocationStatusMessage(LocationPermissionStatus status) => switch (status) {
      LocationPermissionStatus.granted => null,
      LocationPermissionStatus.servicesDisabled =>
        'Location (GPS) is turned off on this phone. Turn it on, or choose a place on the map.',
      LocationPermissionStatus.deniedPermanently =>
        'Location permission is blocked for ASKODOX. Allow it in app settings, or choose a place on the map.',
      _ => 'Location access was not granted. You can allow it, or choose a place on the map.',
    };
