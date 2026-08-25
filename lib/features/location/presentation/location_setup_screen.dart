import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/location_controller.dart';
import '../domain/geo_models.dart';

class LocationSetupScreen extends ConsumerWidget {
  const LocationSetupScreen({super.key});

  bool _te(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'te';

  String _t(BuildContext context, String en, String te) =>
      _te(context) ? te : en;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final telugu = _te(context);

    return Scaffold(
      appBar: AppBar(title: Text(_t(context, 'Set your location', 'మీ లొకేషన్ సెట్ చేయండి'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          Text(
            _t(
              context,
              'Find nearby shops, prices and watchlist matches',
              'దగ్గరలోని షాపులు, ధరలు మరియు మీ అవసరాలకు సరిపడే మ్యాచులను కనుగొనండి',
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              context,
              'ASKODOX uses your location only to show relevant nearby results. Your home address is never shared with sellers.',
              'ASKODOX మీకు సంబంధించిన దగ్గరలోని ఫలితాలు చూపించడానికి మాత్రమే లొకేషన్‌ను ఉపయోగిస్తుంది. మీ ఇంటి చిరునామా సెల్లర్లతో షేర్ చేయబడదు.',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(_permission(context, state.permission)),
              subtitle: Text(
                _t(
                  context,
                  'You stay in control and can use a manual location instead.',
                  'నియంత్రణ మీ చేతిలోనే ఉంటుంది. కావాలంటే లొకేషన్‌ను మాన్యువల్‌గా ఎంచుకోవచ్చు.',
                ),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: controller.requestPermission,
            icon: const Icon(Icons.my_location),
            label: Text(_t(context, 'Request location permission', 'లొకేషన్ అనుమతి ఇవ్వండి')),
          ),
          if (state.permission == LocationPermissionStatus.deniedPermanently ||
              state.permission == LocationPermissionStatus.servicesDisabled)
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      context,
                      'Device settings will open here in a future release.',
                      'తదుపరి విడుదలలో ఇక్కడి నుంచి డివైస్ సెట్టింగ్స్ ఓపెన్ అవుతాయి.',
                    ),
                  ),
                ),
              ),
              child: Text(_t(context, 'Open settings', 'సెట్టింగ్స్ ఓపెన్ చేయండి')),
            ),
          if (state.permission != LocationPermissionStatus.notRequested)
            OutlinedButton(
              onPressed: controller.retryLocation,
              child: Text(_t(context, 'Retry location', 'లొకేషన్ మళ్లీ ప్రయత్నించండి')),
            ),
          const Divider(height: 32),
          Text(
            _t(context, 'Choose manually', 'మాన్యువల్‌గా ఎంచుకోండి'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ..._suggestions.map(
            (location) => ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(telugu ? _suggestionName(location.id) : location.name),
              subtitle: Text(location.address),
              onTap: () async {
                await controller.selectManualLocation(location);
                if (context.mounted) context.go('/nearby');
              },
            ),
          ),
          TextButton(
            onPressed: () => _coordinates(context, controller),
            child: Text(
              _t(
                context,
                'Enter latitude and longitude for testing',
                'టెస్టింగ్ కోసం అక్షాంశం మరియు రేఖాంశం నమోదు చేయండి',
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => context.go('/nearby'),
            child: Text(
              _t(
                context,
                'Continue with manual location',
                'మాన్యువల్ లొకేషన్‌తో కొనసాగండి',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _permission(BuildContext context, LocationPermissionStatus permission) =>
      switch (permission) {
        LocationPermissionStatus.notRequested => _t(
            context, 'Location permission not requested', 'లొకేషన్ అనుమతి ఇంకా అడగలేదు'),
        LocationPermissionStatus.granted =>
          _t(context, 'Location permission granted', 'లొకేషన్ అనుమతి ఇచ్చారు'),
        LocationPermissionStatus.denied =>
          _t(context, 'Location permission denied', 'లొకేషన్ అనుమతి నిరాకరించారు'),
        LocationPermissionStatus.deniedPermanently => _t(
            context,
            'Location permission denied permanently',
            'లొకేషన్ అనుమతి శాశ్వతంగా నిరాకరించారు'),
        LocationPermissionStatus.servicesDisabled => _t(
            context, 'Location services disabled', 'లొకేషన్ సర్వీసులు ఆఫ్‌లో ఉన్నాయి'),
      };

  String _suggestionName(String id) => switch (id) {
        'banjara' => 'బంజారా హిల్స్',
        'jubilee' => 'ఇల్లు',
        'work' => 'పని ప్రదేశం',
        _ => 'లొకేషన్',
      };

  Future<void> _coordinates(
    BuildContext context,
    LocationController controller,
  ) async {
    final lat = TextEditingController(text: '17.4156');
    final lng = TextEditingController(text: '78.4347');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t(context, 'Manual coordinates', 'మాన్యువల్ కోఆర్డినేట్స్')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('latitudeField'),
              controller: lat,
              decoration: InputDecoration(labelText: _t(context, 'Latitude', 'అక్షాంశం')),
            ),
            TextField(
              key: const Key('longitudeField'),
              controller: lng,
              decoration: InputDecoration(labelText: _t(context, 'Longitude', 'రేఖాంశం')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t(context, 'Cancel', 'రద్దు చేయండి')),
          ),
          FilledButton(
            onPressed: () {
              final point = GeoPoint(
                double.tryParse(lat.text) ?? double.nan,
                double.tryParse(lng.text) ?? double.nan,
              );
              controller.selectManualLocation(
                BuyerSavedLocation(
                  id: 'manual',
                  name: _t(context, 'Manual location', 'మాన్యువల్ లొకేషన్'),
                  address: _t(context, 'Custom coordinates', 'కస్టమ్ కోఆర్డినేట్స్'),
                  point: point,
                  type: SavedLocationType.custom,
                ),
              );
              Navigator.pop(dialogContext);
            },
            child: Text(_t(context, 'Use location', 'ఈ లొకేషన్ ఉపయోగించండి')),
          ),
        ],
      ),
    );
    lat.dispose();
    lng.dispose();
  }
}

const _suggestions = [
  BuyerSavedLocation(
    id: 'banjara',
    name: 'Banjara Hills',
    address: 'Hyderabad, Telangana',
    point: GeoPoint(17.4156, 78.4347),
    type: SavedLocationType.currentLocation,
  ),
  BuyerSavedLocation(
    id: 'jubilee',
    name: 'Home',
    address: 'Jubilee Hills, Hyderabad',
    point: GeoPoint(17.4326, 78.4071),
    type: SavedLocationType.home,
  ),
  BuyerSavedLocation(
    id: 'work',
    name: 'Work',
    address: 'Somajiguda, Hyderabad',
    point: GeoPoint(17.4239, 78.4738),
    type: SavedLocationType.work,
  ),
];
