import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/mock_geo_repository.dart';
import '../domain/geo_models.dart';
import '../domain/geo_repository.dart';

final geoRepositoryProvider = Provider<GeoRepository>((ref) => MockGeoRepository());
final locationControllerProvider = StateNotifierProvider<LocationController, LocationState>(
  (ref) => LocationController(ref.read(geoRepositoryProvider))..restoreAndRefresh(),
);

class LocationState {
  const LocationState({
    this.permission = LocationPermissionStatus.notRequested,
    this.locations = const [],
    this.centre = const GeoPoint(17.4156, 78.4347),
    this.radiusMetres = 5000,
    this.shops = const [],
    this.mode = MapDisplayMode.map,
    this.loading = false,
    this.offline = false,
    this.selectedShopId,
    this.message,
  });

  final LocationPermissionStatus permission;
  final List<BuyerSavedLocation> locations;
  final GeoPoint centre;
  final double radiusMetres;
  final List<NearbyShop> shops;
  final MapDisplayMode mode;
  final bool loading, offline;
  final String? selectedShopId, message;

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
  }) =>
      LocationState(
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

class LocationController extends StateNotifier<LocationState> {
  LocationController(this._repository) : super(const LocationState());

  static const _storageKey = 'askodox.selected_location.v1';
  final GeoRepository _repository;

  Future<void> restoreAndRefresh() async {
    await _restore();
    await refresh();
  }

  void requestPermission({LocationPermissionStatus result = LocationPermissionStatus.granted}) {
    state = state.copyWith(
      permission: result,
      message: result == LocationPermissionStatus.granted
          ? 'Location access granted'
          : 'Location access was not granted',
    );
  }

  void retryLocation() => requestPermission();

  Future<bool> selectManualLocation(BuyerSavedLocation location) async {
    if (!location.point.isValid) {
      state = state.copyWith(message: 'Invalid location');
      return false;
    }
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
    if (!state.centre.isValid) {
      state = state.copyWith(message: 'Invalid location', shops: []);
      return;
    }
    if (state.offline) {
      state = state.copyWith(message: 'Offline mode');
      return;
    }
    state = state.copyWith(loading: true);
    final shops = await _repository.getNearbySellers(
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

  Future<void> _persist(BuyerSavedLocation location) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'id': location.id,
          'name': location.name,
          'address': location.address,
          'latitude': location.point.latitude,
          'longitude': location.point.longitude,
          'type': location.type.name,
        }),
      );
    } catch (_) {}
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
