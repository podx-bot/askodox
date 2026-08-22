import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/watchlist_providers.dart';
import '../domain/watchlist_models.dart';

class AlertSimulatorScreen extends ConsumerWidget {
  const AlertSimulatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(watchlistProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mock automation')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Developer demo controls', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Text('Local-only events; no push notification or personal data leaves this device.'),
          const SizedBox(height: 20),
          for (final item in items)
            Card(
              child: ListTile(
                leading: Text(item.image, style: const TextStyle(fontSize: 32)),
                title: Text(item.productName),
                subtitle: const Text('Simulate seller 1.2 km away'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    final event = AlertEvent(
                      productId: item.productId,
                      sellerName: 'Nearby Mart',
                      price: value == 'price' ? 99.0 : 199.0,
                      previousPrice: 249.0,
                      inStock: true,
                      wasInStock: value != 'stock',
                      distanceKm: 1.2,
                      hasOffer: value == 'offer',
                    );
                    final alert = ref.read(alertsProvider.notifier).match(event);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(alert == null ? 'No matching alert (or duplicate)' : 'Alert generated'),
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'price', child: Text('Change seller price')),
                    PopupMenuItem(value: 'stock', child: Text('Mark back in stock')),
                    PopupMenuItem(value: 'offer', child: Text('Add mock offer')),
                  ],
                ),
              ),
            ),
          if (items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Add a catalog product to your watchlist first.'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Demand scores recalculated')),
            ),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Recalculate demand score'),
          ),
        ],
      ),
    );
  }
}
