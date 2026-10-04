import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../services/place_name_service.dart';
import '../../growth/data/growth_repository.dart';

/// Names a map point; injectable so tests never touch the network.
typedef AskodoxPointNamer = Future<String?> Function(double latitude, double longitude);

/// Real map pin selection for any "where" (current place, pickup, drop).
///
/// * Tap the map to drop the pin; the point is named by the backend's
///   reverse geocoding when it can be ("Benz Circle, Vijayawada, AP"),
///   otherwise shown honestly as coordinates.
/// * Search an address/place (Places, India region) to jump there.
/// * "Use this location" returns an [AskodoxPlace] with real coordinates.
class AskodoxMapPinPicker extends ConsumerStatefulWidget {
  const AskodoxMapPinPicker({
    super.key,
    required this.title,
    this.initial,
    this.namer,
    this.showTiles = true,
    this.deviceSearch,
    this.junctionLookup,
  });

  /// Nearest named junction for the pin (injectable for tests).
  final AskodoxJunctionLookup? junctionLookup;

  /// The phone's geocoder (injectable for tests).
  final Future<List<({double latitude, double longitude, String label})>> Function(String query)? deviceSearch;

  final String title;
  final AskodoxPlace? initial;
  final AskodoxPointNamer? namer;

  /// Tests disable network map tiles; the pin/search/confirm logic is the same.
  final bool showTiles;

  static Future<AskodoxPlace?> open(BuildContext context, {required String title, AskodoxPlace? initial}) =>
      Navigator.of(context).push<AskodoxPlace>(MaterialPageRoute(
        builder: (_) => AskodoxMapPinPicker(title: title, initial: initial),
      ));

  @override
  ConsumerState<AskodoxMapPinPicker> createState() => _AskodoxMapPinPickerState();
}

class _AskodoxMapPinPickerState extends ConsumerState<AskodoxMapPinPicker> {
  // No point known yet: show the whole country (no city is assumed) until
  // the user searches or taps a place; nothing is confirmed until pinned.
  static const _fallback = LatLng(22.5, 79.0);
  final _map = MapController();
  final _search = TextEditingController();
  late LatLng _pin = widget.initial == null
      ? _fallback
      : LatLng(widget.initial!.latitude, widget.initial!.longitude);
  String? _label;
  bool _pinned = false;
  bool _naming = false;
  bool _searching = false;
  String? _searchMessage;
  List<AskodoxPlace> _results = const [];
  AskodoxJunction? _junction;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _pinned = true;
      _label = widget.initial!.label;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _dropPin(LatLng point, {String? label}) async {
    setState(() {
      _pin = point;
      _pinned = true;
      _label = label;
      _naming = label == null;
      _results = const [];
      _junction = null;
    });
    unawaited(_findJunction(point));
    if (label != null) return;
    final namer = widget.namer ?? const PlaceNameService().resolve;
    String? name;
    try {
      name = await namer(point.latitude, point.longitude);
    } catch (_) {
      name = null;
    }
    if (!mounted || _pin != point) return;
    setState(() {
      _label = name;
      _naming = false;
    });
  }

  Future<void> _findJunction(LatLng point) async {
    final AskodoxJunctionLookup lookup = widget.junctionLookup ?? ref.read(askodoxJunctionLookupProvider);
    final AskodoxJunction? junction = await lookup(point.latitude, point.longitude);
    if (!mounted || _pin != point) return;
    setState(() => _junction = junction);
  }

  /// Moves the pin onto the junction itself (a clear meeting point).
  void _useJunction() {
    final j = _junction;
    if (j == null) return;
    final point = LatLng(j.latitude, j.longitude);
    setState(() {
      _pin = point;
      _label = j.name;
      _naming = false;
    });
    if (widget.showTiles) _map.move(point, 17);
  }

  /// Search text -> geocode (backend: the typed town first, then nearby
  /// places; phone geocoder when the backend has nothing) -> the map and
  /// pin move to the best result at once; other results stay listed.
  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2 || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    var results = await ref.read(growthRepositoryProvider).searchPlaces(
          query,
          latitude: _pinned ? _pin.latitude : null,
          longitude: _pinned ? _pin.longitude : null,
        );
    if (results.isEmpty) {
      final onDevice = await (widget.deviceSearch ?? const PlaceNameService().searchOnDevice)(query);
      results = [
        for (final p in onDevice)
          AskodoxPlace(latitude: p.latitude, longitude: p.longitude, label: p.label.isEmpty ? query : p.label, kind: 'area'),
      ];
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results.length > 1 ? results.skip(1).toList() : const [];
      _searchMessage = results.isEmpty ? 'No place found for "$query". Check the spelling or tap the map.' : null;
    });
    if (results.isNotEmpty) _choose(results.first, keepAlternatives: true);
  }

  void _choose(AskodoxPlace place, {bool keepAlternatives = false}) {
    final point = LatLng(place.latitude, place.longitude);
    final alternatives = keepAlternatives ? _results : const <AskodoxPlace>[];
    unawaited(_dropPin(point, label: place.label).then((_) {
      if (mounted && keepAlternatives) setState(() => _results = alternatives);
    }));
    if (widget.showTiles) _map.move(point, place.kind == 'area' ? 13 : 16);
  }

  String get _pinText => _label?.trim().isNotEmpty == true
      ? _label!
      : '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const Key('askodoxPlaceSearch'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              hintText: 'Search address, area or landmark',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      key: const Key('askodoxPlaceSearchGo'),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _runSearch,
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_searchMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_searchMessage!, key: const Key('askodoxPlaceSearchMessage'),
                style: const TextStyle(color: Color(0xFFB42318))),
          ),
        if (_results.isNotEmpty)
          SizedBox(
            height: 132,
            child: ListView(children: [
              for (final place in _results)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(place.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _choose(place),
                ),
            ]),
          ),
        Expanded(
          child: widget.showTiles
              ? FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: widget.initial == null ? 4.5 : 16,
                    onTap: (_, point) => _dropPin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.askodox.askodox',
                    ),
                    MarkerLayer(markers: [
                      if (_pinned)
                        Marker(
                          point: _pin,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.location_on_rounded, size: 44, color: Color(0xFFD93025)),
                        ),
                    ]),
                    const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                  ],
                )
              : GestureDetector(
                  key: const Key('askodoxMapSurface'),
                  onTap: () => _dropPin(_pin),
                  child: const SizedBox.expand(child: ColoredBox(color: Color(0xFFE8EEF5))),
                ),
        ),
        if (_pinned && _junction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(children: [
              const Icon(Icons.signpost_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Near ${_junction!.name}${_junction!.distanceM == null ? '' : ' · ${_junction!.distanceM} m'}',
                  key: const Key('askodoxNearestJunction'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_pinText != _junction!.name)
                TextButton(
                  key: const Key('askodoxUseJunction'),
                  onPressed: _useJunction,
                  child: const Text('Pin here'),
                ),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: Text(
                  !_pinned ? 'Tap the map to drop a pin' : (_naming ? 'Finding the place name…' : _pinText),
                  key: const Key('askodoxPinLabel'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('askodoxUsePin'),
                onPressed: !_pinned
                    ? null
                    : () => Navigator.of(context).pop(AskodoxPlace(
                          latitude: _pin.latitude,
                          longitude: _pin.longitude,
                          label: askodoxLabelNearJunction(_pinText, _junction),
                        )),
                child: const Text('Use this location'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
