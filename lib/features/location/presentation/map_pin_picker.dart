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
  });

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
  List<AskodoxPlace> _results = const [];

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
    });
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

  Future<void> _runSearch() async {
    final results = await ref.read(growthRepositoryProvider).searchPlaces(
          _search.text,
          latitude: _pin.latitude,
          longitude: _pin.longitude,
        );
    if (!mounted) return;
    setState(() => _results = results);
  }

  void _choose(AskodoxPlace place) {
    final point = LatLng(place.latitude, place.longitude);
    unawaited(_dropPin(point, label: place.label));
    if (widget.showTiles) _map.move(point, 16);
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
              suffixIcon: IconButton(
                key: const Key('askodoxPlaceSearchGo'),
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _runSearch,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_results.isNotEmpty)
          SizedBox(
            height: 160,
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
                      userAgentPackageName: 'com.askodox.app',
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
                          label: _pinText,
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
