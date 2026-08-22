import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/location/askodox_location_service.dart';

class AskodoxMapPickerScreen extends StatefulWidget {
  const AskodoxMapPickerScreen({
    super.key,
    this.locationService = const AskodoxLocationService(),
  });

  final AskodoxLocationService locationService;

  @override
  State<AskodoxMapPickerScreen> createState() => _AskodoxMapPickerScreenState();
}

class _AskodoxMapPickerScreenState extends State<AskodoxMapPickerScreen> {
  static const _mapsKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const _indiaCentre = LatLng(20.5937, 78.9629);

  GoogleMapController? _mapController;
  AskodoxLocationPoint? _selected;
  bool _locating = false;
  String? _error;

  bool get _mapEnabled => _mapsKey.trim().isNotEmpty;

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final point = await widget.locationService.currentLocation();
      if (!mounted) return;
      setState(() => _selected = point);
      if (_mapEnabled) {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(point.latitude, point.longitude),
            16,
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _selectPin(LatLng point) {
    setState(() {
      _selected = AskodoxLocationPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        label: 'Map pin',
      );
      _error = null;
    });
  }

  void _confirm() {
    final point = _selected;
    if (point == null) return;
    Navigator.of(context).pop(point);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: Column(
        children: [
          Expanded(
            child: _mapEnabled
                ? GoogleMap(
                    key: const Key('askodoxGoogleMap'),
                    initialCameraPosition: const CameraPosition(
                      target: _indiaCentre,
                      zoom: 5,
                    ),
                    myLocationButtonEnabled: false,
                    myLocationEnabled: selected != null,
                    onMapCreated: (controller) => _mapController = controller,
                    onTap: _selectPin,
                    markers: selected == null
                        ? const <Marker>{}
                        : {
                            Marker(
                              markerId: const MarkerId('askodoxSelectedLocation'),
                              position: LatLng(
                                selected.latitude,
                                selected.longitude,
                              ),
                            ),
                          },
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'Google Maps is wired into ASKODOX. The Android Maps API key is not configured in this build yet. Current GPS location still works.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const Key('askodoxLocationError'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (selected != null) ...[
                    Text(
                      '${selected.label ?? 'Selected'} • ${selected.latitude.toStringAsFixed(6)}, ${selected.longitude.toStringAsFixed(6)}',
                      key: const Key('askodoxSelectedCoordinates'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  OutlinedButton.icon(
                    key: const Key('askodoxUseCurrentLocation'),
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: const Text('Use current location'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('askodoxConfirmLocation'),
                    onPressed: selected == null ? null : _confirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use this location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
