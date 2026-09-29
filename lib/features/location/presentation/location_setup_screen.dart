import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../growth/data/growth_repository.dart';
import '../../notifications/application/askodox_notifications.dart';
import '../application/location_controller.dart';
import '../domain/geo_models.dart';
import 'map_pin_picker.dart';

/// Location in one step: "Use my location" OR search a place. Done -- the
/// chat uses it for every nearby request. Recently used places are one tap
/// away; the map is optional ("Pick on map"). No radius/area pages.
class LocationSetupScreen extends ConsumerStatefulWidget {
  const LocationSetupScreen({super.key});

  @override
  ConsumerState<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

class _LocationSetupScreenState extends ConsumerState<LocationSetupScreen> {
  final _search = TextEditingController();
  List<AskodoxPlace> _results = const [];
  List<BuyerSavedLocation> _recent = const [];
  bool _searching = false;
  bool _locating = false;
  String? _searchMessage;

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecent());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final recent = await ref.read(locationControllerProvider.notifier).recentPlaces();
    if (mounted) setState(() => _recent = recent);
  }

  void _done() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    await ref.read(locationControllerProvider.notifier).requestPermission();
    if (!mounted) return;
    setState(() => _locating = false);
    final state = ref.read(locationControllerProvider);
    if (state.permission == LocationPermissionStatus.granted && state.defaultLocation != null) _done();
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2) return;
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    final centre = ref.read(locationControllerProvider).defaultLocation?.point;
    List<AskodoxPlace> results;
    try {
      results = await ref
          .read(growthRepositoryProvider)
          .searchPlaces(query, latitude: centre?.latitude, longitude: centre?.longitude);
    } catch (_) {
      results = const [];
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
      _searchMessage = results.isEmpty ? _t('No place found. Try an area or landmark name.', 'ప్రాంతం కనిపించలేదు. ప్రాంతం లేదా ల్యాండ్‌మార్క్ పేరు ప్రయత్నించండి.') : null;
    });
  }

  Future<void> _choose(String label, double latitude, double longitude, {String? id}) async {
    final ok = await ref.read(locationControllerProvider.notifier).selectManualLocation(BuyerSavedLocation(
          id: id ?? 'place-${label.hashCode}',
          name: label,
          address: label,
          point: GeoPoint(latitude, longitude),
          type: SavedLocationType.custom,
        ));
    if (ok && mounted) _done();
  }

  Future<void> _pickOnMap() async {
    final current = ref.read(locationControllerProvider).defaultLocation;
    final place = await AskodoxMapPinPicker.open(
      context,
      title: _t('Pick on map', 'మ్యాప్‌లో ఎంచుకోండి'),
      initial: current == null
          ? null
          : AskodoxPlace(
              latitude: current.point.latitude,
              longitude: current.point.longitude,
              label: current.address.isNotEmpty ? current.address : current.name,
            ),
    );
    if (place != null) await _choose(place.label, place.latitude, place.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(locationControllerProvider);
    final denied = state.permission == LocationPermissionStatus.denied ||
        state.permission == LocationPermissionStatus.deniedPermanently ||
        state.permission == LocationPermissionStatus.servicesDisabled;
    final current = state.displayLocation;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Your location', 'మీ లొకేషన్'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (current != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('${_t('Now', 'ఇప్పుడు')}: $current',
                  key: const Key('askodoxCurrentLocation'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (state.approximate)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  _t('Approximate location allowed -- nearby results are right to about 1-3 km. Allow "Precise" for exact distances.',
                      'సుమారు లొకేషన్ మాత్రమే అనుమతించారు -- దగ్గరి ఫలితాలు 1-3 కి.మీ. వరకు సరిగ్గా ఉంటాయి. ఖచ్చితమైన దూరానికి "Precise" అనుమతించండి.'),
                  key: const Key('askodoxApproximateLocation'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ),
          FilledButton.icon(
            key: const Key('askodoxUseMyLocation'),
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
            label: Text(_t('Use my location', 'నా లొకేషన్ వాడండి')),
          ),
          if (denied) ...[
            const SizedBox(height: 8),
            Card(
              key: const Key('askodoxLocationDenied'),
              color: const Color(0xFFFFF4E5),
              child: ListTile(
                leading: const Icon(Icons.location_off_outlined),
                title: Text(switch (state.permission) {
                  LocationPermissionStatus.servicesDisabled => _t(
                      'Location (GPS) is turned off on this phone. Turn it on, or search your area below.',
                      'ఫోన్‌లో లొకేషన్ (GPS) ఆఫ్‌లో ఉంది. ఆన్ చేయండి, లేదా కింద మీ ప్రాంతం వెతకండి.'),
                  LocationPermissionStatus.deniedPermanently => _t(
                      'Location permission is blocked for ASKODOX. Allow it in settings, or search your area below.',
                      'ASKODOX కి లొకేషన్ అనుమతి బ్లాక్ అయింది. సెట్టింగ్స్‌లో అనుమతించండి, లేదా కింద వెతకండి.'),
                  _ => _t('Location access was not allowed. Tap "Use my location" to allow, or search your area below.',
                      'లొకేషన్ అనుమతి ఇవ్వలేదు. అనుమతికి "నా లొకేషన్ వాడండి" నొక్కండి, లేదా కింద వెతకండి.'),
                }),
                trailing: state.permission == LocationPermissionStatus.deniedPermanently ||
                        state.permission == LocationPermissionStatus.servicesDisabled
                    ? TextButton(
                        key: const Key('askodoxOpenLocationSettings'),
                        // GPS off -> the phone's Location switch; blocked ->
                        // this app's permission page.
                        onPressed: () async {
                          final opened = await ref.read(locationControllerProvider.notifier).openFixSettings();
                          if (!opened) await ref.read(askodoxDeviceNotificationsProvider).openAppSettings();
                        },
                        child: Text(_t(
                            state.permission == LocationPermissionStatus.servicesDisabled ? 'Turn on' : 'Settings',
                            state.permission == LocationPermissionStatus.servicesDisabled ? 'ఆన్ చేయండి' : 'సెట్టింగ్స్')),
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('askodoxLocationSearch'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _runSearch(),
            decoration: InputDecoration(
              hintText: _t('Search area, address or landmark', 'ప్రాంతం, చిరునామా లేదా ల్యాండ్‌మార్క్ వెతకండి'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      key: const Key('askodoxLocationSearchGo'),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: _runSearch,
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_searchMessage != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_searchMessage!)),
          for (final place in _results)
            ListTile(
              key: ValueKey('askodoxPlaceResult-${place.label}'),
              leading: const Icon(Icons.place_outlined),
              title: Text(place.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => _choose(place.label, place.latitude, place.longitude),
            ),
          if (_results.isEmpty && _recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_t('Recent places', 'ఇటీవలి ప్రాంతాలు'), style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final place in _recent)
              ListTile(
                key: ValueKey('askodoxRecentPlace-${place.id}'),
                leading: const Icon(Icons.history_rounded),
                title: Text(place.address.isNotEmpty ? place.address : place.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _choose(place.address.isNotEmpty ? place.address : place.name, place.point.latitude,
                    place.point.longitude, id: place.id),
              ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('askodoxPickOnMap'),
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_outlined),
              label: Text(_t('Pick on map', 'మ్యాప్‌లో ఎంచుకోండి')),
            ),
          ),
        ],
      ),
    );
  }
}
