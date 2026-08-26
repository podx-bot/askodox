import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/buyer_providers.dart';
import '../../domain/entities/buyer_models.dart';

class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key});
  static const _deviceChannel = MethodChannel('com.askodox.app/device');

  bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';
  String _t(BuildContext context, String en, String te) => _te(context) ? te : en;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(buyerLocationProvider);
    final radius = ref.watch(radiusKmProvider);
    final resolved = !(location.latitude == 0 && location.longitude == 0);
    return Card(
      child: ListTile(
        leading: Icon(resolved ? Icons.my_location : Icons.location_searching),
        title: Text(resolved
            ? _t(context, 'Current location', 'ప్రస్తుత లొకేషన్')
            : _t(context, 'Use current location', 'ప్రస్తుత లొకేషన్ ఉపయోగించండి')),
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
        label: _t(context, 'Current location', 'ప్రస్తుత లొకేషన్'),
        address: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}${accuracy == null ? '' : ' · ±${accuracy.round()} m'}',
        latitude: lat,
        longitude: lng,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t(context, 'Current location updated', 'ప్రస్తుత లొకేషన్ అప్‌డేట్ అయింది'))),
        );
      }
    } on PlatformException catch (error) {
      if (context.mounted) {
        final fallback = _t(context, 'Turn on location and try again', 'లొకేషన్ ఆన్ చేసి మళ్లీ ప్రయత్నించండి');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? fallback)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t(context, 'Unable to read current location', 'ప్రస్తుత లొకేషన్‌ను చదవలేకపోయాం'))),
        );
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
                Text(
                  _t(context, 'Location & search radius', 'లొకేషన్ & సెర్చ్ పరిధి'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _resolveLocation(context, ref),
                    icon: const Icon(Icons.my_location),
                    label: Text(resolved
                        ? _t(context, 'Refresh current location', 'ప్రస్తుత లొకేషన్‌ను రిఫ్రెష్ చేయండి')
                        : _t(context, 'Use my current location', 'నా ప్రస్తుత లొకేషన్ ఉపయోగించండి')),
                  ),
                ),
                if (resolved) ...[
                  const SizedBox(height: 8),
                  Text(location.address, style: Theme.of(context).textTheme.bodySmall),
                ],
                const Divider(height: 28),
                Text(_t(context, 'Search radius', 'సెర్చ్ పరిధి'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: SearchRadius.values.map((r) {
                    final label = r == SearchRadius.custom ? _t(context, 'Custom', 'కస్టమ్') : r.label;
                    return ChoiceChip(
                      label: Text(label),
                      selected: r == SearchRadius.custom
                          ? !SearchRadius.values.where((e) => e != SearchRadius.custom).any((e) => e.kilometres == radius)
                          : r.kilometres == radius,
                      onSelected: (_) {
                        if (r == SearchRadius.custom) {
                          ref.read(radiusKmProvider.notifier).state = custom;
                        } else {
                          ref.read(radiusKmProvider.notifier).state = r.kilometres;
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text(_t(context, 'Adjust', 'సర్దుబాటు')),
                  Expanded(child: Slider(
                    min: .1,
                    max: 50,
                    divisions: 499,
                    value: radius.clamp(.1, 50).toDouble(),
                    label: _label(radius),
                    onChanged: (v) {
                      custom = v;
                      ref.read(radiusKmProvider.notifier).state = v;
                    },
                  )),
                ]),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_t(context, 'Done', 'పూర్తైంది')),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}
