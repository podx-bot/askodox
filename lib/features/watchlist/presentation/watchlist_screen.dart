import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../application/watchlist_providers.dart';
import '../domain/watchlist_models.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(watchlistProvider);
    return Scaffold(
      key: const Key('askodoxWatchlistScreen'),
      appBar: AppBar(title: const Text('Watchlist')),
      body: items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_outline, size: 64),
                  SizedBox(height: 12),
                  Text('Your watchlist is empty'),
                  Text('Watch products to receive smart local alerts.'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) => _WatchlistCard(item: items[index]),
            ),
    );
  }
}

class _WatchlistCard extends ConsumerWidget {
  const _WatchlistCard({required this.item});
  final WatchlistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetLabel = item.targetPrice == null
        ? ''
        : ' · Target ₹${item.targetPrice!.toStringAsFixed(0)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 28,
                child: Text(item.image, style: const TextStyle(fontSize: 28)),
              ),
              title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${item.brand} · ${item.variant}\n'
                '3 nearby sellers · Lowest ₹${(item.targetPrice ?? 499.0).toStringAsFixed(0)}\n'
                'Updated just now',
              ),
              isThreeLine: true,
              trailing: IconButton(
                key: Key('watchlistRemove-${item.productId}'),
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref.read(watchlistProvider.notifier).remove(item.productId),
              ),
              onTap: () => context.push('/product/${item.productId}'),
            ),
            SwitchListTile(
              key: Key('watchlistAlerts-${item.productId}'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart alerts'),
              subtitle: Text(
                '${item.radiusKm.toStringAsFixed(0)} km · ${item.frequency.name}$targetLabel',
              ),
              value: item.alertsEnabled,
              onChanged: (value) => ref
                  .read(watchlistProvider.notifier)
                  .update(item.copyWith(alertsEnabled: value)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('watchlistAlertSettings-${item.productId}'),
                icon: const Icon(Icons.tune),
                label: const Text('Alert settings'),
                onPressed: () => _settings(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings(BuildContext context, WidgetRef ref) async {
    double radius = item.radiusKm;
    double? target = item.targetPrice;
    var frequency = item.frequency;
    var targetInput = target?.toStringAsFixed(0) ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            key: const Key('watchlistAlertSettingsSheet'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Alert settings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  key: const Key('watchlistRadiusField'),
                  initialValue: radius,
                  decoration: const InputDecoration(labelText: 'Preferred radius'),
                  items: [1.0, 2.0, 5.0, 10.0, 25.0]
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('${value.toInt()} km'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => radius = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('watchlistTargetPriceField'),
                  initialValue: targetInput,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Target price (₹)'),
                  onChanged: (value) => targetInput = value,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<AlertFrequency>(
                  key: const Key('watchlistFrequencyField'),
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: AlertFrequency.values
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => frequency = value);
                    }
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('watchlistSavePreferences'),
                    onPressed: () {
                      target = double.tryParse(targetInput.trim());
                      ref.read(watchlistProvider.notifier).update(
                            item.copyWith(
                              radiusKm: radius,
                              targetPrice: target,
                              clearTarget: target == null,
                              frequency: frequency,
                            ),
                          );
                      Navigator.pop(context);
                    },
                    child: const Text('Save preferences'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
