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
              itemBuilder: (context, i) => _Card(item: items[i]),
            ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.item});

  final WatchlistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              title: Text(
                item.productName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${item.brand} · ${item.variant}\n'
                '3 nearby sellers · Lowest ₹${(item.targetPrice ?? 499).toStringAsFixed(0)}\n'
                'Updated just now',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref
                    .read(watchlistProvider.notifier)
                    .remove(item.productId),
              ),
              onTap: () => context.push('/product/${item.productId}'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Smart alerts'),
              subtitle: Text(
                '${item.radiusKm.toStringAsFixed(0)} km · ${item.frequency.name}'
                '${item.targetPrice == null ? '' : ' · Target ₹${item.targetPrice!.toStringAsFixed(0)}'}',
              ),
              value: item.alertsEnabled,
              onChanged: (v) => ref
                  .read(watchlistProvider.notifier)
                  .update(item.copyWith(alertsEnabled: v)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
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
    final input = TextEditingController(text: target?.toStringAsFixed(0));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Alert settings', style: Theme.of(context).textTheme.titleLarge),
              DropdownButtonFormField<double>(
                initialValue: radius,
                decoration: const InputDecoration(labelText: 'Preferred radius'),
                items: [1.0, 2.0, 5.0, 10.0, 25.0]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text('${v.toInt()} km'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => radius = v!),
              ),
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target price (₹)'),
              ),
              DropdownButtonFormField<AlertFrequency>(
                initialValue: frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: AlertFrequency.values
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => frequency = v!),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  target = double.tryParse(input.text);
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
            ],
          ),
        ),
      ),
    );
    input.dispose();
  }
}
