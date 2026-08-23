import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/buyer_providers.dart';
import '../../domain/entities/buyer_models.dart';

class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key});
  static const _deviceChannel = MethodChannel('com.askodox.app/device');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(buyerLocationProvider);
    final radius = ref.watch(radiusKmProvider);
    final resolved = !(location.latitude == 0 && location.longitude == 0);
    return Card(
      child: ListTile(
        leading: Icon(resolved ? Icons.my_location : Icons.location_searching),
        title: Text(resolved ? 'Current location' : 'Use current location'),
        subtitle: Text('${location.address} · ${_label(radius)}'),
        trailing: const Icon(Icons.tune),
        onTap: () => _show(context, ref),
      ),
    );
  }

  String _label(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km % 1 == 0 ? 0 : 1)} km';

  Future<void> _resolveLocation(BuildContext context, WidgetRef ref) async {
    try {
      final value = await _deviceChannel.invokeMapMethod<String, dynamic>('getCurrentLocation');
      final lat = (value?['latitude'] as num?)?.toDouble();
      final lng = (value?['longitude'] as num?)?.toDouble();
      final accuracy = (value?['accuracy'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        throw PlatformException(code: 'location_unavailable', message: 'Location unavailable');
      }
      ref.read(buyerLocationProvider.notifier).state = BuyerLocation(
        id: 'device-current',
        label: 'Current location',
        address: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}${accuracy == null ? '' : ' · ±${accuracy.round()} m'}',
        latitude: lat,
        longitude: lng,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current location updated')));
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Turn on location and try again')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to read current location')));
      }
    }
  }

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    var custom = ref.read(radiusKmProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final location = ref.watch(buyerLocationProvider);
        final radius = ref.watch(radiusKmProvider);
        final resolved = !(location.latitude == 0 && location.longitude == 0);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Location & search radius', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _resolveLocation(context, ref),
                    icon: const Icon(Icons.my_location),
                    label: Text(resolved ? 'Refresh current location' : 'Use my current location'),
                  ),
                ),
                if (resolved) ...[
                  const SizedBox(height: 8),
                  Text(location.address, style: Theme.of(context).textTheme.bodySmall),
                ],
                const Divider(height: 28),
                const Text('Search radius', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: SearchRadius.values.map((r) => ChoiceChip(label: Text(r.label), selected: r == SearchRadius.custom ? !SearchRadius.values.where((e) => e != SearchRadius.custom).any((e) => e.kilometres == radius) : r.kilometres == radius, onSelected: (_) { if (r == SearchRadius.custom) { ref.read(radiusKmProvider.notifier).state = custom; } else { ref.read(radiusKmProvider.notifier).state = r.kilometres; } })).toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [const Text('Adjust'), Expanded(child: Slider(min: .1, max: 50, divisions: 499, value: radius.clamp(.1, 50).toDouble(), label: _label(radius), onChanged: (v) { custom = v; ref.read(radiusKmProvider.notifier).state = v; }))]),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
