import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/buyer_providers.dart';
import '../../domain/entities/buyer_models.dart';

class LocationSelector extends ConsumerWidget {
  const LocationSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(buyerLocationProvider);
    final radius = ref.watch(radiusKmProvider);

    return Card(
      child: ListTile(
        key: const Key('buyerLocationSelector'),
        leading: const Icon(Icons.my_location),
        title: Text(location.label),
        subtitle: Text('${location.address} · ${_label(radius)}'),
        trailing: const Icon(Icons.tune),
        onTap: () => _show(context, ref),
      ),
    );
  }

  String _label(double km) => km < 1
      ? '${(km * 1000).round()} m'
      : '${km.toStringAsFixed(km % 1 == 0 ? 0 : 1)} km';

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    var custom = ref.read(radiusKmProvider);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final selected = ref.watch(buyerLocationProvider);
          final radius = ref.watch(radiusKmProvider);
          final locations = ref.watch(buyerLocationsProvider).valueOrNull ?? const [];

          return FractionallySizedBox(
            key: const Key('buyerLocationSheet'),
            heightFactor: 0.88,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('buyerLocationSheetScroll'),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Location & search radius',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ...locations.map(
                          (location) => RadioListTile<BuyerLocation>(
                            key: Key('buyerLocation-${location.label}'),
                            value: location,
                            groupValue: selected,
                            contentPadding: EdgeInsets.zero,
                            title: Text(location.label),
                            subtitle: Text(location.address),
                            onChanged: (value) {
                              if (value != null) {
                                ref.read(buyerLocationProvider.notifier).state = value;
                              }
                            },
                          ),
                        ),
                        const Divider(),
                        const Text(
                          'Search radius',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: SearchRadius.values.map((item) {
                            final isCustom = item == SearchRadius.custom;
                            final selectedRadius = isCustom
                                ? !SearchRadius.values
                                    .where((entry) => entry != SearchRadius.custom)
                                    .any((entry) => entry.kilometres == radius)
                                : item.kilometres == radius;

                            return ChoiceChip(
                              key: Key('buyerRadius-${item.name}'),
                              label: Text(item.label),
                              selected: selectedRadius,
                              onSelected: (_) {
                                if (isCustom) {
                                  ref.read(radiusKmProvider.notifier).state = custom;
                                } else {
                                  ref.read(radiusKmProvider.notifier).state =
                                      item.kilometres;
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text('Custom radius: ${_label(radius)}'),
                        Slider(
                          key: const Key('buyerCustomRadiusSlider'),
                          min: .1,
                          max: 50,
                          divisions: 499,
                          value: radius.clamp(.1, 50).toDouble(),
                          label: _label(radius),
                          onChanged: (value) {
                            custom = value;
                            ref.read(radiusKmProvider.notifier).state = value;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: const Key('buyerSaveDefaultRadius'),
                            onPressed: () async {
                              await ref
                                  .read(buyerRepositoryProvider)
                                  .saveDefaultRadius(ref.read(radiusKmProvider));
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('Save as default'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
